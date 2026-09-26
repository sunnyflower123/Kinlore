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
import type { Lang } from './extract'
import { extractionBudget, mostSeconds } from './budget.ts'
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

/// The day in UTC, for the free tier's day below.
function day(): string {
	return new Date().toISOString().slice(0, 10)
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

// ---------------------------------------------------------------- the free tier's day

/// What the whole free tier may spend upstream in one UTC day, per route —
/// every free family together, and nobody's in particular.
///
/// Every limit above belongs to a family, and a family costs nothing: POST
/// /family asks for no invitation, and its rate limit is five a minute per
/// address. Read from the code on 26 Sep 2026, two days before the repository
/// — and with it this Worker's URL — was due to go public, one address could
/// found 7 200 families a day. The first transcription of each passed whatever
/// its length, up to 25 MiB and about $0.88 upstream; any number from one
/// family passed together, because the month is checked before the model and
/// written after it; up to 20 kB of audio that claims no duration rounds to
/// nothing and is never written at all; `/extract` had no meter and no length
/// cap; and five colourings a family came to 36 000 rounds, about $1 220, a day
/// from one address. Nothing bounded a day but the credit limit on the
/// OpenRouter account.
///
/// So the ceiling is the tier's and not an identity's, because identities are
/// the thing that is free. It is **reserved before the call, in the statement
/// that decides**: a check and then a write would let every concurrent request
/// through the check together, which is the month's own hole. And it is **not
/// given back when a call fails**, because a failed call has usually been paid
/// for — a reply cut off at its budget, or a transcript the hallucination guard
/// threw away, cost what a kept one does.
///
/// Each route is charged the most its call can cost, in the unit that grows
/// with it, and the pools are priced in wrangler.jsonc. A paid family never
/// meets any of it. Nor does a memory: `/sync` and `/media` never come here,
/// and the refusal is the rate limiter's 429, which the app reads as a fact
/// about the moment (`DeferredMemory.isAboutTheMoment`) — the audio is kept
/// and transcribed on a later day, a telling lands in its teller's own words
/// instead of structured, and a photograph stays as it was. Never the meter's
/// 402, which would tell the family its month was spent and offer to sell it
/// one.
///
/// What it costs, stated: one stranger can spend the free tier's day for every
/// free family until midnight UTC. A bounded bill for a day of deferral is the
/// trade, and `free-tier-ceiling-check.mjs` pins both halves of it.
async function reserveFreeTierDay(
	env: Env,
	session: Session,
	route: 'transcribe' | 'extract' | 'colourise',
	charge: number,
	limit: number,
): Promise<boolean> {
	if (await isPaid(env, session.familyID)) return true

	// One statement, so D1 decides and counts in the same breath. The SELECT
	// refuses a first charge that is over the limit on its own, the WHERE on
	// the update one that would carry the day past it, and either way no row
	// comes back.
	const row = await env.DB.prepare(
		`INSERT INTO free_tier_day (day, route, used)
		 SELECT ?1, ?2, ?3 WHERE ?3 <= ?4
		 ON CONFLICT(day, route) DO UPDATE SET used = used + excluded.used
		 WHERE used + excluded.used <= ?4
		 RETURNING used`,
	)
		.bind(day(), route, Math.ceil(charge), limit)
		.first<{ used: number }>()
	if (row) return true

	// The pool and its limit, never who asked (rule 9).
	console.warn(`[quota] the free tier's ${route} pool for today is spent (limit ${limit}) — refused`)
	return false
}

/// A transcription is charged the longest recording its bytes can hold
/// (`mostSeconds`), because the model is paid by the second it hears — 32
/// tokens a second at $0.75 a million, 24 µ$ — and never less than five
/// minutes, because a call costs its thinking whatever its length: up to 5 120
/// tokens of reasoning and answer on the shortest clip, 1.9 c at $3.75 a
/// million. Priced from OpenRouter's /models on 26 Sep 2026, the dearest
/// charged second is then a 300-second clip whose reply fills its whole budget,
/// 127 µ$ — so 36 000 s a day is at most $4.56, $2.22 for clips the model
/// answers normally, and under a dollar spent by the app's own recordings,
/// which are 4.5 kB/s and so charged four and a half times what they last.
/// That margin is the price of charging the one thing a caller cannot lie
/// about.
const TRANSCRIPTION_FLOOR_SECONDS = 300

export function reserveTranscription(env: Env, session: Session, base64Length: number): Promise<boolean> {
	const charge = Math.max(mostSeconds(base64Length), TRANSCRIPTION_FLOOR_SECONDS)
	const limit = Number(env.FREE_TIER_AI_SECONDS_PER_DAY) || 36_000
	return reserveFreeTierDay(env, session, 'transcribe', charge, limit)
}

/// A structuring is charged every token it may write — its own `max_tokens`,
/// which grows with the telling — plus every token it may read of what the
/// client sent: the transcript and the corrections, in UTF-8 bytes, which no
/// tokeniser exceeds. The corrections count because they reach the prompt
/// unshortened (`correctionInstruction`), and leaving them out would let a
/// call's size ride in beside a two-word telling for free.
///
/// The rest of the prompt rides uncharged: the archive context is capped by
/// `normaliseContext` and a photograph costs the same 1 140 tokens at any size,
/// so they are a constant, and the price carries it. Measured, the fullest
/// request is 18 184 bytes before its picture, and the dearest charged token a
/// floor-sized call that carries all of that and fails twice before the
/// fallback answers, 18 µ$ — so 300 000 a day is at most $5.54, in 97 calls,
/// while 62 tellings of the 126 words measured at $0.0045 a round come to
/// $0.28. The day also has to hold the longest telling the app can make, which
/// is what keeps it this high: the 35 233 English words that 25 MiB of the
/// app's audio can hold are charged 283 979.
export function reserveExtraction(
	env: Env,
	session: Session,
	transcript: string,
	corrections: { from: string; to: string }[],
	lang: Lang,
): Promise<boolean> {
	const utf8 = new TextEncoder()
	const read = [transcript, ...corrections.flatMap((c) => [c.from, c.to])].reduce(
		(sum, text) => sum + utf8.encode(text).length,
		0,
	)
	const charge = extractionBudget(transcript, lang, env.MODEL_EXTRACT) + read
	const limit = Number(env.FREE_TIER_EXTRACTION_TOKENS_PER_DAY) || 300_000
	return reserveFreeTierDay(env, session, 'extract', charge, limit)
}

/// A colouring is one round, as it is for the month: each costs the same image
/// upstream, 3.39 c measured, and the longest told text adds 0.6 c of input.
/// Twenty a day is at most $0.80.
export function reserveColourisation(env: Env, session: Session): Promise<boolean> {
	const limit = Number(env.FREE_TIER_COLOURISATIONS_PER_DAY) || 20
	return reserveFreeTierDay(env, session, 'colourise', 1, limit)
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
