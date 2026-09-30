#!/usr/bin/env node
// When the webhook may take the family's paid tier away.
//
// The payer is not the beneficiary (PLAN.md §9), which cuts both ways: the
// person who flips auto-renew off is not the person whose telling stops
// working. The rule is RevenueCat's, not ours, and it was assumed wrong once —
// a plain CANCELLATION (auto-renew off, the single most common subscriber act)
// revoked the family's tier immediately, in the middle of a period somebody
// had paid for. The set also waited for a REFUND event that does not exist:
// a refund arrives as CANCELLATION with `cancel_reason: CUSTOMER_SUPPORT`,
// and that is the only cancellation that ends access at once.
//
// This drives the real `handleWebhook` from backend/src/entitlement.ts — Node
// runs TypeScript as it is — against the real schema.sql in an in-memory
// SQLite, behind a shim with D1's prepare/bind/first/run shape. No Worker, no
// network, no RevenueCat secret: the webhook's revocation branch is logic and
// database, which is exactly the half that can be proved on this machine. The
// other half — a real event arriving with a real signature — waits for the
// deployed Worker like the rest of the purchase arc (ARCHITECTURE §1).
//
//   node scripts/webhook-revocation-check.mjs
//
// Costs nothing. Run it after touching entitlement.ts or the family table.

import { DatabaseSync } from 'node:sqlite'
import { readFileSync } from 'node:fs'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const schema = readFileSync(join(root, 'backend', 'schema.sql'), 'utf8')
const { handleWebhook, isAuthorizedWebhook } = await import(
	pathToFileURL(join(root, 'backend', 'src', 'entitlement.ts')).href
)

let failures = 0

function check(what, condition, detail = '') {
	if (condition) {
		console.log(`  ok   ${what}`)
	} else {
		failures += 1
		console.log(`  FAIL ${what}${detail ? ` — ${detail}` : ''}`)
	}
}

/// D1's statement shape over node:sqlite — just enough of it for
/// entitlement.ts, which uses prepare().bind().first() and .run().
function d1(db) {
	return {
		prepare(sql) {
			const statement = db.prepare(sql)
			let args = []
			const bound = {
				bind(...values) {
					args = values
					return bound
				},
				async first() {
					return statement.get(...args) ?? null
				},
				async run() {
					statement.run(...args)
					return {}
				},
				async all() {
					return { results: statement.all(...args) }
				},
			}
			return bound
		},
	}
}

const now = Math.floor(Date.now() / 1000)
const paidThrough = now + 30 * 86_400

/// A family in the middle of a paid month, with the payer bound the way
/// /entitlement/sync binds them — the state every event below arrives into.
function paidFamily() {
	const db = new DatabaseSync(':memory:')
	db.exec(schema)
	db.prepare(
		`INSERT INTO family (id, name, created_at, entitlement, payer_id, entitlement_expires_at)
		 VALUES ('perhe', 'Perhe', 0, 'archive', 'maksaja', ?)`,
	).run(paidThrough)
	// The payer's own date on the payer's own row, which is where
	// `applyEntitlement` reads it from since 10 Sep 2026. The family row
	// beside it is the answer it derives, not the source — seeding only the
	// family row is precisely the half-migrated state the ALTER in
	// schema.sql carries a backfill for.
	db.prepare(
		`INSERT INTO member (id, family_id, display_name, secret_hash, role, created_at,
		                     rc_app_user_id, entitlement_expires_at)
		 VALUES ('maksaja', 'perhe', 'Ville', 'x', 'owner', 0, 'cust-1', ?)`,
	).run(paidThrough)
	const family = () =>
		db
			.prepare('SELECT entitlement, entitlement_expires_at, payer_id FROM family WHERE id = ?')
			.get('perhe')
	const join = (id, customer, expires) =>
		db
			.prepare(
				`INSERT INTO member (id, family_id, display_name, secret_hash, role, created_at,
				                     rc_app_user_id, entitlement_expires_at)
				 VALUES (?, 'perhe', 'Toinen', 'x', 'member', 0, ?, ?)`,
			)
			.run(id, customer, expires)
	return { env: { DB: d1(db) }, family, join }
}

const event = (type, extra = {}) => ({ type, app_user_id: 'cust-1', ...extra })

/// RevenueCat's own sample TRANSFER event, with this file's App User IDs in
/// its two arrays (revenuecat.com/docs/integrations/webhooks/sample-events).
/// It has no `app_user_id`: the common fields and those arrays are the whole
/// event, and RevenueCat sends it once, for the receiving customer.
const transfer = (from, to) => ({
	app_id: '1234567890',
	event_timestamp_ms: 78789789798798,
	id: 'CD489E0E-5D52-4E03-966B-A7F17788E432',
	store: 'APP_STORE',
	transferred_from: from,
	transferred_to: to,
	type: 'TRANSFER',
	environment: 'PRODUCTION',
})

try {
	console.log('— what keeps the month that was paid for —')
	{
		const { env, family } = paidFamily()
		await handleWebhook(env, event('CANCELLATION', {
			cancel_reason: 'UNSUBSCRIBE',
			expiration_at_ms: paidThrough * 1000,
		}))
		const row = family()
		check(
			'auto-renew going off keeps the tier until the paid-through date',
			row.entitlement === 'archive' && row.entitlement_expires_at === paidThrough,
			JSON.stringify(row),
		)
	}
	{
		const { env, family } = paidFamily()
		await handleWebhook(env, event('SUBSCRIPTION_PAUSED', {
			expiration_at_ms: paidThrough * 1000,
		}))
		check(
			'a paused subscription waits for its EXPIRATION',
			family().entitlement === 'archive',
			JSON.stringify(family()),
		)
	}
	{
		const { env, family } = paidFamily()
		const result = await handleWebhook(env, event('RENEWAL'))
		check(
			'an event with no paid-through date changes nothing',
			result.ignored === 'no_expiration' && family().entitlement === 'archive',
			JSON.stringify({ result, family: family() }),
		)
	}
	{
		const { env, family } = paidFamily()
		await handleWebhook(env, transfer(['cust-9'], ['cust-1']))
		check(
			'a transfer to the payer takes nothing away',
			family().entitlement === 'archive',
			JSON.stringify(family()),
		)
	}

	console.log('— and what ends it at once —')
	{
		const { env, family } = paidFamily()
		await handleWebhook(env, event('CANCELLATION', { cancel_reason: 'CUSTOMER_SUPPORT' }))
		check('a refund drops the tier immediately', family().entitlement === 'free',
			JSON.stringify(family()))
	}
	{
		const { env, family } = paidFamily()
		await handleWebhook(env, event('EXPIRATION'))
		check('so does the expiration itself', family().entitlement === 'free',
			JSON.stringify(family()))
	}
	{
		// Sent as `event('TRANSFER')` until 28 Sep 2026, with an
		// `app_user_id` no TRANSFER carries — so this passed while the
		// Worker answered every real one `missing_app_user_id`.
		const { env, family } = paidFamily()
		const result = await handleWebhook(env, transfer(['cust-1'], ['cust-9']))
		check('and a transfer away from the payer', family().entitlement === 'free',
			JSON.stringify({ result, family: family() }))
	}

	console.log('— and a second payer is not forgotten —')
	{
		// One grandchild on an annual plan, one on a monthly. The comment on
		// `applyEntitlement` has always said the longest expiry wins and the
		// family must not lose the right when one member cancels earlier —
		// and until 10 Sep 2026 only the winner was stored, so the monthly
		// renewals were compared, found nearer, and dropped. Eleven of them.
		// Then the annual one expired, `payer_id` matched, and the family
		// went free with a live subscription still being charged for.
		//
		// The sequence below is that year in four events.
		const annual = now + 300 * 86_400
		const monthly = now + 30 * 86_400
		const { env, family, join } = paidFamily()
		// The annual payer is 'maksaja'; give them their real date.
		await handleWebhook(env, event('RENEWAL', { expiration_at_ms: annual * 1000 }))
		join('kuukausittain', 'cust-2', null)

		// The monthly payer renews. The family's date must not move nearer.
		await handleWebhook(env, {
			type: 'RENEWAL',
			app_user_id: 'cust-2',
			expiration_at_ms: monthly * 1000,
		})
		check(
			'a nearer renewal does not shorten the family’s right',
			family().entitlement_expires_at === annual,
			JSON.stringify(family()),
		)

		// ...but it must not be thrown away either, which is the whole bug.
		await handleWebhook(env, event('EXPIRATION'))
		const after = family()
		check(
			'and when the further subscription ends, the nearer one holds the family',
			after.entitlement === 'archive' && after.entitlement_expires_at === monthly,
			JSON.stringify(after),
		)
		check(
			'with the paying member named as the payer',
			after.payer_id === 'kuukausittain',
			JSON.stringify(after),
		)

		// The last one out does turn the light off.
		await handleWebhook(env, {
			type: 'EXPIRATION',
			app_user_id: 'cust-2',
		})
		check(
			'and when the last one ends, the family really does go free',
			family().entitlement === 'free' && family().payer_id === null,
			JSON.stringify(family()),
		)
	}

	// Since 30 Sep 2026 an event is only the cue, when RevenueCat can be
	// asked: the webhook takes the customer's active entitlements from the
	// REST API, as /entitlement/sync does, so an event that arrives late or
	// twice cannot write an older answer over a newer one. Everything above
	// runs without the keys, which is the fallback: the event decides when
	// RevenueCat cannot be asked. RevenueCat is replaced here by a fetch that
	// answers what `owns` holds.
	console.log('— RevenueCat asked, not the event believed —')
	{
		const realFetch = globalThis.fetch
		let owns = []
		let reachable = true
		let asked = 0
		globalThis.fetch = async () => {
			asked += 1
			if (!reachable) return new Response('{"code": 7110}', { status: 500 })
			return new Response(JSON.stringify({ items: owns }), { status: 200 })
		}
		const keyed = (env) => ({ ...env, RC_SECRET_KEY: 'sk_test', RC_PROJECT_ID: 'proj' })
		const renewedThrough = now + 60 * 86_400
		try {
			{
				const { env, family } = paidFamily()
				owns = [{ entitlement_id: 'entl1', expires_at: renewedThrough * 1000 }]
				await handleWebhook(keyed(env), event('RENEWAL', { expiration_at_ms: renewedThrough * 1000 }))
				// The EXPIRATION of the period before, delivered after the renewal.
				await handleWebhook(keyed(env), event('EXPIRATION', { expiration_at_ms: paidThrough * 1000 }))
				check(
					'an EXPIRATION that arrives after the renewal ends nothing',
					family().entitlement === 'archive' && family().entitlement_expires_at === renewedThrough,
					JSON.stringify(family()),
				)
				check('because RevenueCat was asked each time', asked === 2, `${asked} requests`)
				await handleWebhook(keyed(env), event('RENEWAL', { expiration_at_ms: paidThrough * 1000 }))
				check(
					'and a renewal sent again, with its older date, shortens nothing',
					family().entitlement_expires_at === renewedThrough,
					JSON.stringify(family()),
				)
			}
			{
				const { env, family } = paidFamily()
				owns = []
				await handleWebhook(keyed(env), event('CANCELLATION', { cancel_reason: 'CUSTOMER_SUPPORT' }))
				check(
					'a refund RevenueCat confirms still ends the tier at once',
					family().entitlement === 'free',
					JSON.stringify(family()),
				)
			}
			{
				const { env, family } = paidFamily()
				owns = [{ entitlement_id: 'entl1', expires_at: paidThrough * 1000 }]
				await handleWebhook(keyed(env), event('CANCELLATION', { cancel_reason: 'UNSUBSCRIBE' }))
				check(
					'auto-renew switched off still keeps the month paid for',
					family().entitlement === 'archive' && family().entitlement_expires_at === paidThrough,
					JSON.stringify(family()),
				)
			}
			{
				const { env, family } = paidFamily()
				reachable = false
				await handleWebhook(keyed(env), event('EXPIRATION'))
				reachable = true
				check(
					'and when RevenueCat cannot be asked, the event decides as before',
					family().entitlement === 'free',
					JSON.stringify(family()),
				)
			}
			{
				// A second payer with the later date, who has since left.
				const { env, family, join } = paidFamily()
				join('lahtenyt', 'cust-2', renewedThrough)
				env.DB.prepare('UPDATE member SET left_at = ? WHERE id = ?').bind(now, 'lahtenyt').run()
				owns = [{ entitlement_id: 'entl1', expires_at: paidThrough * 1000 }]
				await handleWebhook(keyed(env), event('RENEWAL', { expiration_at_ms: paidThrough * 1000 }))
				check(
					'a payer who has left no longer pays for the family',
					family().entitlement_expires_at === paidThrough && family().payer_id === 'maksaja',
					JSON.stringify(family()),
				)
			}
		} finally {
			globalThis.fetch = realFetch
		}
	}

	console.log('— and the door itself —')
	{
		const { env } = paidFamily()
		const result = await handleWebhook(env, { type: 'RENEWAL', app_user_id: 'tuntematon' })
		check('an unknown customer is ignored, not an error', result.ignored === 'unknown_customer',
			JSON.stringify(result))
	}
	{
		const env = { RC_WEBHOOK_SECRET: 'oikea-salaisuus' }
		const right = new Request('http://x/webhook/revenuecat', {
			headers: { Authorization: 'oikea-salaisuus' },
		})
		const wrong = new Request('http://x/webhook/revenuecat', {
			headers: { Authorization: 'vaara-salaisuus!' },
		})
		check(
			'the webhook secret is checked, in constant time',
			isAuthorizedWebhook(env, right) && !isAuthorizedWebhook(env, wrong),
		)
	}
} catch (error) {
	failures += 1
	console.log(`  FAIL ${error.message}`)
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
