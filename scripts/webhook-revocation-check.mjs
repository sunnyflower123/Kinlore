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
		const { env, family } = paidFamily()
		await handleWebhook(env, event('TRANSFER'))
		check('and a transfer away', family().entitlement === 'free',
			JSON.stringify(family()))
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
