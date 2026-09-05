/// Creating a family, inviting and joining.
///
/// The family is the isolation boundary: every query is scoped to the caller's
/// own family, not just at join time. See docs/ARCHITECTURE.md §4.

import { hashSecret, randomCode, type Session } from './auth'
import type { Env } from './worker'

/// How long an invite link stays valid. A week is enough for a grandchild to
/// show grandmother the phone on a visit, while an old link in a leaked message
/// thread stops working on its own.
const INVITE_DAYS = 7

const now = () => Math.floor(Date.now() / 1000)

/// Fallback display names, in both languages the app speaks.
///
/// These are not error strings — they are written straight into the UI and sit
/// there for years, on the family screen and beside every memory. They exist
/// because the ordinary case on a phone handed to a grandparent is that nobody
/// typed anything, not that somebody skipped a field.
///
/// Which language is chosen follows the client's own, sent with the request.
/// A family is shared and its members may not share a language, so this is a
/// starting name rather than a translation: whoever renames the family renames
/// it for everybody, which is the same as it has always been.
const DEFAULTS = {
	fi: { family: 'Perhe', owner: 'Minä', member: 'Perheenjäsen' },
	en: { family: 'Family', owner: 'Me', member: 'Family member' },
} as const

export type CreateFamilyInput = {
	memberID: string
	secret: string
	displayName: string
	familyName: string
	/// The client's language, for the fallback names only. Absent means Finnish,
	/// so a client built before this existed keeps the names it always got.
	lang?: 'fi' | 'en'
}

/// Creates a family and its owner in one go.
///
/// A member cannot exist without a family: that prevents orphan rows and makes
/// authentication unambiguous — every id always has a family.
export async function createFamily(env: Env, input: CreateFamilyInput) {
	const existing = await env.DB.prepare('SELECT id FROM member WHERE id = ?')
		.bind(input.memberID)
		.first()
	if (existing) return { error: 'member_exists' as const }

	const familyID = crypto.randomUUID()
	const timestamp = now()

	await env.DB.batch([
		env.DB.prepare('INSERT INTO family (id, name, created_at) VALUES (?, ?, ?)').bind(
			familyID,
			input.familyName.trim() || DEFAULTS[input.lang ?? 'fi'].family,
			timestamp,
		),
		env.DB.prepare(
			`INSERT INTO member (id, family_id, display_name, secret_hash, role, created_at, last_seen_at)
			 VALUES (?, ?, ?, ?, 'owner', ?, ?)`,
		).bind(
			input.memberID,
			familyID,
			input.displayName.trim() || DEFAULTS[input.lang ?? 'fi'].owner,
			await hashSecret(input.secret),
			timestamp,
			timestamp,
		),
	])

	return { familyID, role: 'owner' as const }
}

export type JoinInput = {
	memberID: string
	secret: string
	displayName: string
	code: string
	/// The joiner's language, for the fallback name only. See DEFAULTS.
	lang?: 'fi' | 'en'
}

export async function joinFamily(env: Env, input: JoinInput) {
	const invite = await env.DB.prepare(
		'SELECT code, family_id, expires_at, revoked_at, display_name FROM invite WHERE code = ?',
	)
		.bind(input.code.trim())
		.first<{
			code: string
			family_id: string
			expires_at: number
			revoked_at: number | null
			display_name: string | null
		}>()

	// The same answer in all three cases: a wrong, an expired and a revoked code
	// must be indistinguishable, or the existence of a valid code could be
	// inferred by guessing.
	if (!invite || invite.revoked_at || invite.expires_at < now()) {
		return { error: 'invalid_invite' as const }
	}

	// The joiner's own typing wins; the invitation's name is what stands when
	// they typed nothing, which on a phone handed to a grandparent is the
	// ordinary case rather than the exception.
	const displayName =
		input.displayName.trim() || invite.display_name?.trim() || DEFAULTS[input.lang ?? 'fi'].member

	const existing = await env.DB.prepare('SELECT id, family_id, left_at FROM member WHERE id = ?')
		.bind(input.memberID)
		.first<{ id: string; family_id: string; left_at: number | null }>()

	if (existing && existing.family_id !== invite.family_id) {
		return { error: 'member_exists' as const }
	}
	if (existing && !existing.left_at) {
		// The same device rejoining the same family: not an error but a
		// reinstall or an iCloud restore. Let it through — and through the
		// code it came in by, which is why this stands before the claim below.
		return { familyID: invite.family_id, role: 'member' as const }
	}

	// A code admits one person. `used_count` was recorded and compared to
	// nothing, so a link forwarded on through a group chat was a week-long key
	// for everybody in it — and passing one link around was the natural way
	// for a family of eight to share the app (founder's-eye review, 3 Sep 2026,
	// finding #33). The invitation already asks who it is for; now it is for
	// exactly that person, and the family view lists only the codes nobody has
	// used yet.
	//
	// Claimed with a conditional UPDATE rather than a read and a write, so two
	// phones opening the same link in the same second cannot both get in. A
	// used code answers in the same words as a wrong one, for the reason a
	// revoked one does: a different answer would tell a guesser the code was
	// real. If the write below then fails, the code stays claimed — a burned
	// code is refused, which is the safe side, and the owner makes another.
	const claim = await env.DB.prepare(
		'UPDATE invite SET used_count = used_count + 1 WHERE code = ? AND used_count = 0',
	)
		.bind(invite.code)
		.run()
	if ((claim.meta.changes ?? 0) === 0) return { error: 'invalid_invite' as const }

	// Somebody who left and was invited back. The row was kept so that the
	// names on their memories still resolve, so coming back is undoing the
	// mark rather than creating anything — and the name they just typed
	// wins, because they typed it.
	if (existing?.left_at) {
		await env.DB.prepare(
			'UPDATE member SET left_at = NULL, display_name = ?, last_seen_at = ? WHERE id = ?',
		)
			.bind(displayName, now(), input.memberID)
			.run()
		return { familyID: invite.family_id, role: 'member' as const }
	}

	const timestamp = now()
	await env.DB.prepare(
		`INSERT INTO member (id, family_id, display_name, secret_hash, role, created_at, last_seen_at)
		 VALUES (?, ?, ?, ?, 'member', ?, ?)`,
	)
		.bind(
			input.memberID,
			invite.family_id,
			displayName,
			await hashSecret(input.secret),
			timestamp,
			timestamp,
		)
		.run()

	return { familyID: invite.family_id, role: 'member' as const }
}

/// `displayName` is who the invitation is for, and it is optional: an
/// invitation with nobody's name on it is the shape this had before and stays
/// valid. See the column's comment in schema.sql for why it is never read back
/// out before joining.
export async function createInvite(env: Env, session: Session, displayName?: string) {
	const code = randomCode()
	const timestamp = now()
	await env.DB.prepare(
		`INSERT INTO invite (code, family_id, created_by, expires_at, created_at, display_name)
		 VALUES (?, ?, ?, ?, ?, ?)`,
	)
		.bind(
			code,
			session.familyID,
			session.memberID,
			timestamp + INVITE_DAYS * 86_400,
			timestamp,
			displayName?.trim() || null,
		)
		.run()

	return { code, expiresAt: timestamp + INVITE_DAYS * 86_400 }
}

export async function revokeInvite(env: Env, session: Session, code: string) {
	// The family is checked in the condition: another family's invite cannot be
	// revoked even if the code is known.
	const result = await env.DB.prepare(
		'UPDATE invite SET revoked_at = ? WHERE code = ? AND family_id = ? AND revoked_at IS NULL',
	)
		.bind(now(), code, session.familyID)
		.run()
	return { revoked: (result.meta.changes ?? 0) > 0 }
}

/// Ends a membership. **The memories stay.**
///
/// A family archive exists so that what was told outlives the teller, so leaving
/// is not deletion: the rows keep their `author_id`, and the name on them still
/// resolves through `member.display_name` for everybody who is still here — see
/// docs/ARCHITECTURE.md §14.
///
/// Two rules make the family survive the departure:
///
///   - The last member cannot leave. There would be nothing to leave, and the
///     archive would become unreachable rather than deleted.
///   - An owner hands ownership to the longest-standing remaining member. An
///     ownerless family could never invite anyone again.
export async function leaveFamily(env: Env, session: Session) {
	const remaining = await env.DB.prepare(
		`SELECT id, role FROM member
		 WHERE family_id = ? AND id != ? AND left_at IS NULL
		 ORDER BY created_at LIMIT 1`,
	)
		.bind(session.familyID, session.memberID)
		.first<{ id: string; role: string }>()

	if (!remaining) return { error: 'last_member' as const }

	const timestamp = now()
	const statements = [
		// Invites created by the departing member go with them: the link is the
		// entire security boundary, and nobody left would know to revoke it.
		env.DB.prepare(
			'UPDATE invite SET revoked_at = ? WHERE created_by = ? AND revoked_at IS NULL',
		).bind(timestamp, session.memberID),
		// Marked, never deleted. `memory.author_id` references this row, and the
		// name on every memory they told is read from it — a DELETE fails on the
		// foreign key, and if it did not it would strip their name off their own
		// memories. Verified against a local D1: the first version of this route
		// deleted the row, and only a member who had never told anything could
		// leave.
		//
		// The role goes with the membership. Handing ownership on without
		// taking it off the leaver left the family with two owners, and an
		// invited-back founder walked straight back in as one.
		env.DB.prepare(
			`UPDATE member SET left_at = ?, role = 'member' WHERE id = ? AND family_id = ?`,
		).bind(timestamp, session.memberID, session.familyID),
	]

	if (session.role === 'owner') {
		statements.push(
			env.DB.prepare('UPDATE member SET role = ? WHERE id = ?').bind('owner', remaining.id),
		)
	}

	await env.DB.batch(statements)
	return { left: true as const, newOwner: session.role === 'owner' ? remaining.id : null }
}

/// The owner ends somebody else's membership. **The memories stay**, exactly
/// as when a member leaves on their own (`leaveFamily` above): the row is
/// marked, never deleted, and the name on what they told keeps resolving.
///
/// This is the remedy for the invitation that reached the wrong person. Until
/// 5 Sep 2026 there was none — the only way out of a family was one's own, so
/// whoever tapped a forwarded link was in for good, reading every memory past
/// and future (founder's-eye review, 3 Sep 2026, finding #32).
///
/// Two rules, and the reason there is no third:
///
///   - Every open invitation of the family goes with them. The invite text
///     carries the family key, and the person being removed may hold any live
///     link — being forwarded one is how the wrong person got in. The owner
///     makes a fresh code for whoever was meant to have it, and the dialog on
///     the phone says so.
///   - Only the owner, and never the owner's own row: leaving is
///     `leaveFamily`, which knows how to hand ownership on.
///
/// **The family key is not rotated, and that is a decision rather than a
/// gap.** `authenticate` refuses a departed member on every route, so nothing
/// sealed under the key reaches them again — and what is already on their
/// phone no rotation could take back. Rotation would defend against a removed
/// member obtaining ciphertext by some other road, and the only other road is
/// a live invitation, which this revokes.
export async function removeMember(env: Env, session: Session, memberID: string) {
	if (session.role !== 'owner') return { error: 'not_owner' as const }
	if (memberID === session.memberID) return { error: 'not_found' as const }

	// Looked up first so that removing somebody who has already gone does not
	// close the family's open invitations for nothing.
	const target = await env.DB.prepare(
		'SELECT id FROM member WHERE id = ? AND family_id = ? AND left_at IS NULL',
	)
		.bind(memberID, session.familyID)
		.first<{ id: string }>()
	if (!target) return { removed: false as const }

	const timestamp = now()
	await env.DB.batch([
		env.DB.prepare(
			`UPDATE member SET left_at = ?, role = 'member' WHERE id = ? AND family_id = ?`,
		).bind(timestamp, memberID, session.familyID),
		env.DB.prepare(
			'UPDATE invite SET revoked_at = ? WHERE family_id = ? AND revoked_at IS NULL',
		).bind(timestamp, session.familyID),
	])
	return { removed: true as const }
}

export async function getFamily(env: Env, session: Session) {
	const family = await env.DB.prepare(
		'SELECT id, name, entitlement, sync_seq FROM family WHERE id = ?',
	)
		.bind(session.familyID)
		.first<{ id: string; name: string; entitlement: string; sync_seq: number }>()

	if (!family) return { error: 'not_found' as const }

	// Only the people who are still here. A departed member's row stays behind so
	// that the name on their memories keeps resolving, but the family view is a
	// list of who is in the family — see `leaveFamily`.
	const members = await env.DB.prepare(
		`SELECT id, display_name, role, created_at FROM member
		 WHERE family_id = ? AND left_at IS NULL ORDER BY created_at`,
	)
		.bind(session.familyID)
		.all<{ id: string; display_name: string; role: string; created_at: number }>()

	// The invitations that still open the door: alive, and not yet used by
	// the one person each admits. With the name it was made for, so the owner
	// can tell two open codes apart — read back by the family that wrote it,
	// which is not the unauthenticated lookup §4 refuses.
	const invites = await env.DB.prepare(
		`SELECT code, expires_at, used_count, display_name FROM invite
		 WHERE family_id = ? AND revoked_at IS NULL AND expires_at > ? AND used_count = 0
		 ORDER BY created_at DESC`,
	)
		.bind(session.familyID, now())
		.all<{ code: string; expires_at: number; used_count: number; display_name: string | null }>()

	return {
		id: family.id,
		name: family.name,
		entitlement: family.entitlement,
		syncSeq: family.sync_seq,
		you: { id: session.memberID, role: session.role, displayName: session.displayName },
		members: (members.results ?? []).map((m) => ({
			id: m.id,
			displayName: m.display_name,
			role: m.role,
			joinedAt: m.created_at,
		})),
		invites: (invites.results ?? []).map((i) => ({
			code: i.code,
			expiresAt: i.expires_at,
			// Always 0 now, and still sent: an app built before 5 Sep 2026
			// decodes it as a required field and would fail to read its own
			// family without it.
			usedCount: i.used_count,
			displayName: i.display_name,
		})),
	}
}
