/// Perheen luonti, kutsuminen ja liittyminen.
///
/// Perhe on eristysraja: jokainen kysely rajataan pyytäjän omaan perheeseen,
/// eikä vain liittymishetkellä. Ks. docs/ARKKITEHTUURI.md §4.

import { hashSecret, randomCode, type Session } from './auth'
import type { Env } from './worker'

/// Kutsulinkin voimassaolo. Viikko riittää siihen että lapsenlapsi ehtii
/// näyttää puhelinta isoäidille käydessään kylässä, mutta vanha linkki
/// vuotaneessa viestiketjussa lakkaa toimimasta itsestään.
const INVITE_DAYS = 7

const now = () => Math.floor(Date.now() / 1000)

export type CreateFamilyInput = {
	memberID: string
	secret: string
	displayName: string
	familyName: string
}

/// Luo perheen ja sen omistajan yhdellä kertaa.
///
/// Jäsentä ei voi olla ilman perhettä: se estää orvot rivit ja tekee
/// tunnistautumisesta yksiselitteisen — jokaisella tunnisteella on aina perhe.
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
			input.familyName.trim() || 'Perhe',
			timestamp,
		),
		env.DB.prepare(
			`INSERT INTO member (id, family_id, display_name, secret_hash, role, created_at, last_seen_at)
			 VALUES (?, ?, ?, ?, 'owner', ?, ?)`,
		).bind(
			input.memberID,
			familyID,
			input.displayName.trim() || 'Minä',
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

	// Sama vastaus kaikissa kolmessa tapauksessa: väärä, umpeutunut ja
	// mitätöity koodi eivät saa erottua toisistaan, muuten kelvollisen koodin
	// olemassaolon voi päätellä arvaamalla.
	if (!invite || invite.revoked_at || invite.expires_at < now()) {
		return { error: 'invalid_invite' as const }
	}

	const existing = await env.DB.prepare('SELECT id, family_id FROM member WHERE id = ?')
		.bind(input.memberID)
		.first<{ id: string; family_id: string }>()

	if (existing) {
		// Sama laite liittyy uudelleen samaan perheeseen: ei virhe vaan
		// uudelleenasennus tai iCloud-palautus. Päästetään läpi.
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
			input.displayName.trim() || 'Perheenjäsen',
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
	// Perhe tarkistetaan ehdossa: toisen perheen kutsua ei voi mitätöidä
	// vaikka koodi tiedettäisiin.
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

	// Vain voimassa olevat kutsut. Omistaja näkee onko linkki elossa ja
	// kuinka moni on sitä käyttänyt — se on ainoa näkyvyys turvallisuusrajaan.
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
