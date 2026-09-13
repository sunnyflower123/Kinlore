/// Free tier limits.
///
/// Two principles govern this file:
///
/// 1. **Telling is never paywalled.** The quota limits photos, AI minutes and
///    colourisations, not the act of writing a memory. A typed memory always
///    goes through.
/// 2. **The original audio is always kept.** Hitting the quota does not reject a
///    recording, it defers its transcription — the audio is the product, not an
///    intermediate step.
///
/// The counters live on the server, because a client-side counter can be edited.

import type { Session } from './auth'
import type { Env } from './worker'
import { reconcileStaleEntitlement } from './entitlement.ts'

export type QuotaDenial = {
	error: 'quota_exceeded'
	kind: 'ai_seconds' | 'photos' | 'colourisations'
	used: number
	limit: number
}

/// The month in UTC. For a Finnish family the exact moment the limit resets
/// means nothing, and handling the time zone would only add a source of error.
function period(): string {
	const now = new Date()
	return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`
}

/// Whether the family has the paid archive.
///
/// One word decides it, and for most of this project's life only that word was
/// read. The date beside it was written and never compared, which is safe
/// exactly as long as the webhook always arrives — and when it does not, the
/// word says `archive` for ever over a date months in the past (ARCHITECTURE
/// §6). So the date is read here too, as a **tripwire and not as the answer**:
/// a stored state that cannot be true is the one case where the word is not
/// evidence, and the fix is to ask RevenueCat rather than to guess in either
/// direction.
///
/// `reconcileStaleEntitlement` answers null when it could not ask, and null
/// means *keep what you had*. That is deliberate and it is the whole safety
/// property: an unreachable RevenueCat must not end a month somebody paid for.
async function isPaid(env: Env, familyID: string): Promise<boolean> {
	const row = await env.DB.prepare(
		'SELECT entitlement, entitlement_expires_at FROM family WHERE id = ?',
	)
		.bind(familyID)
		.first<{ entitlement: string; entitlement_expires_at: number | null }>()

	if (row?.entitlement !== 'archive') return false

	// Null is perpetual, not absent — there is nothing stale about it.
	const expires = row.entitlement_expires_at
	if (expires === null || expires > Math.floor(Date.now() / 1000)) return true

	return (await reconcileStaleEntitlement(env, familyID)) ?? true
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

// ---------------------------------------------------------------- colourisations

/// Photographs coloured by the telling, per month, on a counter of their own.
///
/// Never out of the telling minutes: the payer is not the teller (PLAN.md §9),
/// and a grandchild colouring photographs must not use up the time a
/// grandmother has to talk. Every round counts, a "not quite" included — each
/// one is a whole new image upstream and costs the same, 3.4 c on the lite model
/// and 6.8 c on the flash one (measured 13 Sep 2026).
export async function checkColourisations(env: Env, session: Session): Promise<QuotaDenial | null> {
	if (await isPaid(env, session.familyID)) return null

	const limit = Number(env.FREE_COLOURISATIONS_PER_MONTH) || 5
	const row = await env.DB.prepare(
		'SELECT colourisations FROM usage_counter WHERE family_id = ? AND period = ?',
	)
		.bind(session.familyID, period())
		.first<{ colourisations: number }>()

	const used = row?.colourisations ?? 0
	if (used >= limit) {
		return { error: 'quota_exceeded', kind: 'colourisations', used, limit }
	}
	return null
}

/// Recorded once the image has come back, like the minutes: a round that failed
/// upstream delivered nothing, and the family is not charged for it.
export async function recordColourisation(env: Env, session: Session): Promise<void> {
	await env.DB.prepare(
		`INSERT INTO usage_counter (family_id, period, colourisations)
		 VALUES (?, ?, 1)
		 ON CONFLICT(family_id, period) DO UPDATE SET colourisations = colourisations + 1`,
	)
		.bind(session.familyID, period())
		.run()
}

// ---------------------------------------------------------------- status

/// The family's usage for the app. The paywall needs this so it can show what is
/// left before the limit is reached.
export async function usage(env: Env, session: Session) {
	const paid = await isPaid(env, session.familyID)
	const counter = await env.DB.prepare(
		'SELECT ai_seconds, colourisations FROM usage_counter WHERE family_id = ? AND period = ?',
	)
		.bind(session.familyID, period())
		.first<{ ai_seconds: number; colourisations: number }>()
	const photos = await env.DB.prepare(
		`SELECT count(*) AS n FROM subject
		 WHERE family_id = ? AND kind = 'photo' AND deleted_at IS NULL`,
	)
		.bind(session.familyID)
		.first<{ n: number }>()

	return {
		entitlement: paid ? 'archive' : 'free',
		period: period(),
		aiSeconds: { used: counter?.ai_seconds ?? 0, limit: paid ? null : Number(env.FREE_AI_SECONDS_PER_MONTH) || 600 },
		photos: { used: photos?.n ?? 0, limit: paid ? null : Number(env.FREE_PHOTO_LIMIT) || 20 },
		colourisations: {
			used: counter?.colourisations ?? 0,
			limit: paid ? null : Number(env.FREE_COLOURISATIONS_PER_MONTH) || 5,
		},
	}
}
