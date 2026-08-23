/// RevenueCat: the payer is not the beneficiary.
///
/// The grandchild buys the subscription and the whole family channel opens for
/// every member. RevenueCat grants the right to the buyer; the backend spreads
/// it to the family.
///
/// This is not a contest trick but the only model that works for this audience:
/// the ability to pay sits in a different person than the one producing the
/// value. An 80-year-old does not buy a subscription, but she is the one who
/// tells the memories.

import type { Session } from './auth'
import type { Env } from './worker'

const now = () => Math.floor(Date.now() / 1000)

// ---------------------------------------------------------------- core

/// Sets the family's entitlement. The only place that writes
/// `family.entitlement`.
///
/// **A downgrade never deletes anything.** When the subscription ends the family
/// returns to the free tier: existing photos and audio remain and stay readable,
/// the limits apply only to new content. A family that loses memories when the
/// payment ends never comes back, and that is not a product worth building.
export async function applyEntitlement(
	env: Env,
	familyID: string,
	payerID: string | null,
	expiresAt: number | null,
): Promise<{ entitlement: string; expiresAt: number | null }> {
	const current = await env.DB.prepare(
		'SELECT payer_id, entitlement_expires_at FROM family WHERE id = ?',
	)
		.bind(familyID)
		.first<{ payer_id: string | null; entitlement_expires_at: number | null }>()

	// Two payers: the longest expiry wins. The family must not lose the right
	// because one member cancels theirs earlier.
	const existing = current?.entitlement_expires_at ?? null
	const keepExisting =
		existing !== null &&
		existing > now() &&
		(expiresAt === null || existing > expiresAt) &&
		current?.payer_id !== payerID

	const winner = keepExisting
		? { payer: current?.payer_id ?? null, expires: existing }
		: { payer: payerID, expires: expiresAt }

	const active = winner.expires !== null && winner.expires > now()
	const entitlement = active ? 'archive' : 'free'

	await env.DB.prepare(
		`UPDATE family SET entitlement = ?, payer_id = ?, entitlement_expires_at = ? WHERE id = ?`,
	)
		.bind(entitlement, active ? winner.payer : null, winner.expires, familyID)
		.run()

	return { entitlement, expiresAt: winner.expires }
}

// ---------------------------------------------------------------- verification

type ActiveEntitlement = { entitlement_id: string; expires_at: number | null }

/// Asks RevenueCat what the customer actually owns.
///
/// The client's word is not trusted: the app can claim anything, and the
/// entitlement is what unlocks the paid tier for the entire family.
async function fetchActiveEntitlements(env: Env, customerID: string): Promise<ActiveEntitlement[]> {
	const url =
		`https://api.revenuecat.com/v2/projects/${env.RC_PROJECT_ID}` +
		`/customers/${encodeURIComponent(customerID)}/active_entitlements`

	const res = await fetch(url, {
		headers: { Authorization: `Bearer ${env.RC_SECRET_KEY}` },
	})

	if (!res.ok) {
		// Status and RevenueCat's own error code, never the body.
		//
		// This was the fourth site logging an upstream response verbatim, and it
		// outlived the sweep that closed the other three (`extract.ts`,
		// `openrouter.ts`, `worker.ts`) because it is not a memory — it is the
		// payer's account. PLAN.md §10 says what makes that matter anyway: the
		// log is the one place a family cannot export, cannot empty with
		// "Tyhjennä tämä laite", and never agreed to. A subscriber's identifiers
		// do not belong in it either, and rule 9 does not have a second tier for
		// data that is only somebody's payment details.
		//
		// The code is the part worth having: RevenueCat answers `{"code": 7638,
		// "message": …}`, and the number says what went wrong without quoting
		// anything back.
		const body = await res.text().catch(() => '')
		let code: number | string = 'none'
		try {
			const parsed = JSON.parse(body) as { code?: number }
			if (typeof parsed.code === 'number') code = parsed.code
		} catch {
			code = `unparsed ${body.length} chars`
		}
		console.error(`[entitlement] RevenueCat HTTP ${res.status}, code ${code}`)
		throw new Error(`RevenueCat HTTP ${res.status}`)
	}

	const data = (await res.json()) as { items?: ActiveEntitlement[] }
	return data.items ?? []
}

/// A purchase reported by the app is verified and spread to the family.
export async function syncEntitlement(env: Env, session: Session, customerID: string) {
	if (!env.RC_SECRET_KEY || !env.RC_PROJECT_ID) {
		return { error: 'revenuecat_not_configured' as const }
	}

	// Whose customer id this is, before anything is written. The client sends it
	// and the client can send anything: without this check the same purchase
	// reported from two families unlocks both, and a later refund revokes only
	// whichever member row the webhook happens to find first. The unique index
	// on `member.rc_app_user_id` refuses the write in any case — this turns that
	// into an answer instead of a constraint violation.
	const bound = await env.DB.prepare(
		'SELECT id, family_id FROM member WHERE rc_app_user_id = ?',
	)
		.bind(customerID)
		.first<{ id: string; family_id: string }>()

	if (bound && bound.family_id !== session.familyID) {
		// The fact without the ids: the customer id is the payer's member UUID,
		// and this file's own rule says a subscriber's identifiers do not
		// belong in the log. The ids are in D1 when actually needed.
		console.error('[entitlement] customer already bound to another family')
		return { error: 'customer_belongs_to_another_family' as const }
	}

	const items = await fetchActiveEntitlements(env, customerID)

	// Any active entitlement unlocks the archive. The app has a single paid
	// tier, so it is not worth binding to the shape of the identifier —
	// RevenueCat v2 returns an internal id rather than the lookup key.
	const furthest = items.reduce<number | null>((max, item) => {
		// expires_at is in milliseconds, and null means a perpetual entitlement.
		if (item.expires_at === null) return Number.MAX_SAFE_INTEGER
		const seconds = Math.floor(item.expires_at / 1000)
		return max === null ? seconds : Math.max(max, seconds)
	}, null)

	// The same family, a different member: the buyer reinstalled, changed phone,
	// or somebody else restored the purchase — the case `onRestoreCompleted`
	// exists for. The binding moves rather than being refused, because the
	// family is the same and the index allows only one holder.
	if (bound && bound.id !== session.memberID) {
		await env.DB.prepare('UPDATE member SET rc_app_user_id = NULL WHERE id = ?')
			.bind(bound.id)
			.run()
	}

	// The payer is bound to the member so the webhook can find the family
	// without the app.
	await env.DB.prepare('UPDATE member SET rc_app_user_id = ? WHERE id = ?')
		.bind(customerID, session.memberID)
		.run()

	const result = await applyEntitlement(env, session.familyID, session.memberID, furthest)
	return { ...result, verified: true }
}

// ---------------------------------------------------------------- webhook

type WebhookEvent = {
	type?: string
	app_user_id?: string
	expiration_at_ms?: number | null
	product_id?: string
	/// Why a CANCELLATION happened. UNSUBSCRIBE is auto-renew going off;
	/// CUSTOMER_SUPPORT is a refund. The distinction is the whole event.
	cancel_reason?: string
}

/// Whether an event ends the entitlement immediately, regardless of the
/// stored expiry. Measured against RevenueCat's event semantics rather than
/// assumed — the assumed version cost a family its paid month:
///
/// - There is no REFUND event type. A refund arrives as CANCELLATION with
///   `cancel_reason: CUSTOMER_SUPPORT`, and it is the only CANCELLATION that
///   revokes. The common one — UNSUBSCRIBE, auto-renew switched off — means
///   the payer keeps what they paid for until EXPIRATION arrives, and this
///   used to be a set that locked the whole family out of a period already
///   paid for the moment anybody toggled the switch.
/// - SUBSCRIPTION_PAUSED does not end access either; RevenueCat's guidance
///   is to revoke on the EXPIRATION that follows the pause.
/// - EXPIRATION, and a TRANSFER away, end it at once.
function revokes(event: WebhookEvent): boolean {
	if (event.type === 'EXPIRATION' || event.type === 'TRANSFER') return true
	return event.type === 'CANCELLATION' && event.cancel_reason === 'CUSTOMER_SUPPORT'
}

/// Keeps the entitlement current without the app being opened.
///
/// Without the webhook, a renewed subscription would only show up when the payer
/// next launches the app — and they are not the one who uses it most.
export async function handleWebhook(env: Env, event: WebhookEvent) {
	const customerID = event.app_user_id
	if (!customerID) return { ignored: 'missing_app_user_id' as const }

	const member = await env.DB.prepare(
		'SELECT id, family_id FROM member WHERE rc_app_user_id = ?',
	)
		.bind(customerID)
		.first<{ id: string; family_id: string }>()

	// Unknown customer: the purchase happened before the app got to report the
	// id. Not an error — the next /entitlement/sync fixes it.
	if (!member) return { ignored: 'unknown_customer' as const }

	const revoking = revokes(event)
	const expires = revoking
		? null
		: event.expiration_at_ms
			? Math.floor(event.expiration_at_ms / 1000)
			: null

	// An event that neither revokes nor carries a paid-through date has
	// nothing to say about the entitlement — applying its null would end one
	// the event was not about.
	if (!revoking && expires === null) return { ignored: 'no_expiration' as const }

	const result = await applyEntitlement(env, member.family_id, member.id, expires)
	// The event type and the outcome; never the family or customer ids, for
	// the reason the HTTP-error path above spells out.
	console.log(`[entitlement] ${event.type} → ${result.entitlement}`)
	return result
}

/// Webhook authentication is an Authorization header configured in RevenueCat's
/// dashboard. Without the check, anyone could unlock a family's paid tier by
/// sending a forged event.
export function isAuthorizedWebhook(env: Env, request: Request): boolean {
	if (!env.RC_WEBHOOK_SECRET) return false
	const header = request.headers.get('Authorization') ?? ''
	if (header.length !== env.RC_WEBHOOK_SECRET.length) return false
	let diff = 0
	for (let i = 0; i < header.length; i++) {
		diff |= header.charCodeAt(i) ^ env.RC_WEBHOOK_SECRET.charCodeAt(i)
	}
	return diff === 0
}
