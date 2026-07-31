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

/// Fallback display names are Finnish on purpose: they are written straight into
/// the app's UI, which is Finnish. See the language rule in CLAUDE.md.
const DEFAULT_FAMILY_NAME = 'Perhe'
const DEFAULT_OWNER_NAME = 'Minä'
const DEFAULT_MEMBER_NAME = 'Perheenjäsen'

export type CreateFamilyInput = {
	memberID: string
	secret: string
	displayName: string
	familyName: string
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
			input.familyName.trim() || DEFAULT_FAMILY_NAME,
			timestamp,
		),
		env.DB.prepare(
			`INSERT INTO member (id, family_id, display_name, secret_hash, role, created_at, last_seen_at)
			 VALUES (?, ?, ?, ?, 'owner', ?, ?)`,
		).bind(
			input.memberID,
			familyID,
			input.displayName.trim() || DEFAULT_OWNER_NAME,
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
}

export async function joinFamily(env: Env, input: JoinInput) {
	const invite = await env.DB.prepare(
		'SELECT code, family_id, expires_at, revoked_at FROM invite WHERE code = ?',
	)
		.bind(input.code.trim())
		.first<{ code: string; family_id: string; expires_at: number; revoked_at: number | null }>()

	// The same answer in all three cases: a wrong, an expired and a revoked code
	// must be indistinguishable, or the existence of a valid code could be
	// inferred by guessing.
	if (!invite || invite.revoked_at || invite.expires_at < now()) {
		return { error: 'invalid_invite' as const }
	}

	const existing = await env.DB.prepare('SELECT id, family_id FROM member WHERE id = ?')
		.bind(input.memberID)
		.first<{ id: string; family_id: string }>()

	if (existing) {
		// The same device rejoining the same family: not an error but a
		// reinstall or an iCloud restore. Let it through.
		if (existing.family_id === invite.family_id) {
			return { familyID: invite.family_id, role: 'member' as const }
		}
		return { error: 'member_exists' as const }
	}

	const timestamp = now()
	await env.DB.batch([
		env.DB.prepare(
			`INSERT INTO member (id, family_id, display_name, secret_hash, role, created_at, last_seen_at)
			 VALUES (?, ?, ?, ?, 'member', ?, ?)`,
		).bind(
			input.memberID,
			invite.family_id,
			input.displayName.trim() || DEFAULT_MEMBER_NAME,
			await hashSecret(input.secret),
			timestamp,
			timestamp,
		),
		env.DB.prepare('UPDATE invite SET used_count = used_count + 1 WHERE code = ?').bind(invite.code),
	])

	return { familyID: invite.family_id, role: 'member' as const }
}

export async function createInvite(env: Env, session: Session) {
	const code = randomCode()
	const timestamp = now()
	await env.DB.prepare(
		`INSERT INTO invite (code, family_id, created_by, expires_at, created_at)
		 VALUES (?, ?, ?, ?, ?)`,
	)
		.bind(code, session.familyID, session.memberID, timestamp + INVITE_DAYS * 86_400, timestamp)
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

export async function getFamily(env: Env, session: Session) {
	const family = await env.DB.prepare(
		'SELECT id, name, entitlement, sync_seq FROM family WHERE id = ?',
	)
		.bind(session.familyID)
		.first<{ id: string; name: string; entitlement: string; sync_seq: number }>()

	if (!family) return { error: 'not_found' as const }

	const members = await env.DB.prepare(
		'SELECT id, display_name, role, created_at FROM member WHERE family_id = ? ORDER BY created_at',
	)
		.bind(session.familyID)
		.all<{ id: string; display_name: string; role: string; created_at: number }>()

	// Valid invites only. The owner sees whether a link is alive and how many
	// people have used it — that is the only visibility into the security
	// boundary.
	const invites = await env.DB.prepare(
		`SELECT code, expires_at, used_count FROM invite
		 WHERE family_id = ? AND revoked_at IS NULL AND expires_at > ?
		 ORDER BY created_at DESC`,
	)
		.bind(session.familyID, now())
		.all<{ code: string; expires_at: number; used_count: number }>()

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
			usedCount: i.used_count,
		})),
	}
}
