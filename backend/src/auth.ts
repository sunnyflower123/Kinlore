/// Authentication without a login screen.
///
/// The identity is a UUID and a random secret in the device's Keychain. An
/// 80-year-old sees none of it: she gets an invite link from a grandchild and
/// she is in. See docs/ARCHITECTURE.md §4.

import type { Env } from './worker'

export type Session = {
	memberID: string
	familyID: string
	role: 'owner' | 'member'
	displayName: string
}

/// The secret is 32 random bytes, not a password. There is no guessability, so a
/// slow hash would add no security — it would only slow down every request. It
/// is hashed anyway so that a database leak grants no direct access.
export async function hashSecret(secret: string): Promise<string> {
	const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(secret))
	return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

/// Constant-time comparison. Without it the response time would leak the hash one
/// byte at a time — a theoretical attack, but the fix costs three lines.
function equals(a: string, b: string): boolean {
	if (a.length !== b.length) return false
	let diff = 0
	for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
	return diff === 0
}

/// Reads `Authorization: Bearer <member_id>.<secret>` and verifies the member.
/// Returns null if authentication fails — the caller decides what follows.
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
		'SELECT id, family_id, role, display_name, secret_hash, left_at FROM member WHERE id = ?',
	)
		.bind(memberID)
		.first<{
			id: string
			family_id: string
			role: string
			display_name: string
			secret_hash: string
			left_at: number | null
		}>()

	if (!row) return null
	// The row outlives the membership so that the names on their memories keep
	// resolving, but a departed member is no longer in the family: no reads, no
	// writes. See `leaveFamily`.
	if (row.left_at) return null
	if (!equals(row.secret_hash, await hashSecret(secret))) return null

	return {
		memberID: row.id,
		familyID: row.family_id,
		role: row.role === 'owner' ? 'owner' : 'member',
		displayName: row.display_name,
	}
}

/// A random base64url string. Used for invite codes.
export function randomCode(bytes = 16): string {
	const raw = crypto.getRandomValues(new Uint8Array(bytes))
	return btoa(String.fromCharCode(...raw))
		.replace(/\+/g, '-')
		.replace(/\//g, '_')
		.replace(/=+$/, '')
}
