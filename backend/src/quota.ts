/// Free tier limits.
///
/// Two principles govern this file:
///
/// 1. **Telling is never paywalled.** The quota limits photos and AI minutes,
///    not the act of writing a memory. A typed memory always goes through.
/// 2. **The original audio is always kept.** Hitting the quota does not reject a
///    recording, it defers its transcription — the audio is the product, not an
///    intermediate step.
///
/// The counters live on the server, because a client-side counter can be edited.

import type { Session } from './auth'
import type { Env } from './worker'

export type QuotaDenial = {
	error: 'quota_exceeded'
	kind: 'ai_seconds' | 'photos'
	used: number
	limit: number
}

/// The month in UTC. For a Finnish family the exact moment the limit resets
/// means nothing, and handling the time zone would only add a source of error.
function period(): string {
	const now = new Date()
	return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`
}

async function isPaid(env: Env, familyID: string): Promise<boolean> {
	const row = await env.DB.prepare('SELECT entitlement FROM family WHERE id = ?')
		.bind(familyID)
		.first<{ entitlement: string }>()
	return row?.entitlement === 'archive'
}

// ---------------------------------------------------------------- AI minutes

/// Checked BEFORE the expensive call. Returns null when it is fine to proceed.
export async function checkAISeconds(
	env: Env,
	session: Session,
	seconds: number,
): Promise<QuotaDenial | null> {
	if (await isPaid(env, session.familyID)) return null

	const limit = Number(env.FREE_AI_SECONDS_PER_MONTH) || 600
	const row = await env.DB.prepare(
		'SELECT ai_seconds FROM usage_counter WHERE family_id = ? AND period = ?',
	)
		.bind(session.familyID, period())
		.first<{ ai_seconds: number }>()

	const used = row?.ai_seconds ?? 0
	// The check uses the amount already consumed rather than consumed + incoming:
	// a recording that has started is not cut off because it happened to be long.
	// The limit is exceeded slightly, and that is cheaper than a rejected memory.
	if (used >= limit) {
		return { error: 'quota_exceeded', kind: 'ai_seconds', used, limit }
	}
	return null
}

/// Recorded after the call. A successful transcription has already cost money,
/// so it counts even if extraction fails afterwards.
export async function recordAISeconds(env: Env, session: Session, seconds: number): Promise<void> {
	const rounded = Math.max(0, Math.round(seconds))
	if (rounded === 0) return

	await env.DB.prepare(
		`INSERT INTO usage_counter (family_id, period, ai_seconds)
		 VALUES (?, ?, ?)
		 ON CONFLICT(family_id, period) DO UPDATE SET ai_seconds = ai_seconds + excluded.ai_seconds`,
	)
		.bind(session.familyID, period(), rounded)
		.run()
}

// ---------------------------------------------------------------- photos

/// The photo count is derived straight from the `subject` table rather than a
/// separate counter.
///
/// The limit is a total rather than monthly, and a deleted photo frees its slot.
/// A separate counter would inevitably drift out of step with reality, and a
/// family archive holds hundreds of rows — counting is free.
export async function checkPhotoCount(env: Env, session: Session): Promise<QuotaDenial | null> {
	if (await isPaid(env, session.familyID)) return null

	const limit = Number(env.FREE_PHOTO_LIMIT) || 20
	const row = await env.DB.prepare(
		`SELECT count(*) AS n FROM subject
		 WHERE family_id = ? AND kind = 'photo' AND deleted_at IS NULL`,
	)
		.bind(session.familyID)
		.first<{ n: number }>()

	const used = row?.n ?? 0
	if (used >= limit) {
		return { error: 'quota_exceeded', kind: 'photos', used, limit }
	}
	return null
}

// ---------------------------------------------------------------- status

/// The family's usage for the app. The paywall needs this so it can show what is
/// left before the limit is reached.
export async function usage(env: Env, session: Session) {
	const paid = await isPaid(env, session.familyID)
	const seconds = await env.DB.prepare(
		'SELECT ai_seconds FROM usage_counter WHERE family_id = ? AND period = ?',
	)
		.bind(session.familyID, period())
		.first<{ ai_seconds: number }>()
	const photos = await env.DB.prepare(
		`SELECT count(*) AS n FROM subject
		 WHERE family_id = ? AND kind = 'photo' AND deleted_at IS NULL`,
	)
		.bind(session.familyID)
		.first<{ n: number }>()

	return {
		entitlement: paid ? 'archive' : 'free',
		period: period(),
		aiSeconds: { used: seconds?.ai_seconds ?? 0, limit: paid ? null : Number(env.FREE_AI_SECONDS_PER_MONTH) || 600 },
		photos: { used: photos?.n ?? 0, limit: paid ? null : Number(env.FREE_PHOTO_LIMIT) || 20 },
	}
}
