/// Tunnistautuminen ilman kirjautumisruutua.
///
/// Identiteetti on laitteen Keychainissa oleva UUID ja satunnainen salaisuus.
/// 80-vuotias ei näe tästä mitään: hän saa kutsulinkin lapsenlapselta ja on
/// sisällä. Ks. docs/ARKKITEHTUURI.md §4.

import type { Env } from './worker'

export type Session = {
	memberID: string
	familyID: string
	role: 'owner' | 'member'
	displayName: string
}

/// Salaisuus on 32 satunnaista tavua, ei salasana. Arvattavuutta ei ole, joten
/// hidas tiiviste ei toisi turvaa — se vain hidastaisi jokaista pyyntöä.
/// Tiivistetään silti, jottei kannan vuoto anna suoraa pääsyä.
export async function hashSecret(secret: string): Promise<string> {
	const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(secret))
	return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

/// Vakioaikainen vertailu. Ilman tätä vastausaika vuotaisi tiivisteen tavu
/// kerrallaan — teoreettinen hyökkäys, mutta korjaus maksaa kolme riviä.
function equals(a: string, b: string): boolean {
	if (a.length !== b.length) return false
	let diff = 0
	for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
	return diff === 0
}

/// Lukee `Authorization: Bearer <member_id>.<secret>` ja varmistaa jäsenen.
/// Palauttaa null jos tunnistus epäonnistuu — kutsuja päättää mitä siitä seuraa.
export async function authenticate(request: Request, env: Env): Promise<Session | null> {
	const header = request.headers.get('Authorization') ?? ''
	if (!header.startsWith('Bearer ')) return null

	const token = header.slice('Bearer '.length)
	const separator = token.indexOf('.')
	if (separator <= 0) return null

	const memberID = token.slice(0, separator)
	const secret = token.slice(separator + 1)
	if (!memberID || !secret) return null

	const row = await env.DB.prepare(
		'SELECT id, family_id, role, display_name, secret_hash FROM member WHERE id = ?',
	)
		.bind(memberID)
		.first<{
			id: string
			family_id: string
			role: string
			display_name: string
			secret_hash: string
		}>()

	if (!row) return null
	if (!equals(row.secret_hash, await hashSecret(secret))) return null

	return {
		memberID: row.id,
		familyID: row.family_id,
		role: row.role === 'owner' ? 'owner' : 'member',
		displayName: row.display_name,
	}
}

/// Satunnainen base64url-merkkijono. Käytetään kutsukoodeihin.
export function randomCode(bytes = 16): string {
	const raw = crypto.getRandomValues(new Uint8Array(bytes))
	return btoa(String.fromCharCode(...raw))
		.replace(/\+/g, '-')
		.replace(/\//g, '_')
		.replace(/=+$/, '')
}
