#!/usr/bin/env node
// When the stored tier cannot be believed, and what must never happen while
// finding out.
//
// `quota.isPaid` gated the paid archive on one word for most of this project's
// life, and only an event can change that word: the device's
// `syncEntitlementIfPurchased` guards on `hasActivePurchase`, which goes false
// the moment a subscription lapses, so the app stops reporting exactly when the
// news matters. The webhook was therefore the only path that could ever take
// the tier away — and a webhook that never arrives leaves a family paid for
// ever over a date months in the past. Measured 12 Sep 2026, recorded in
// ARCHITECTURE §6.
//
// The reconciliation added for it has two properties and they pull against each
// other, which is why this file exists rather than a reading of the source:
//
//   1. **It must fire only in a state that cannot be true** — the word says
//      `archive` and the date has passed. A working webhook never produces
//      that, so the ordinary path must cost no upstream request at all. A
//      reconciliation that phones RevenueCat on every quota check is a new
//      failure mode, not a fix.
//   2. **It must never end a month somebody paid for.** Missing keys, a payer
//      with no bound customer, an unreachable RevenueCat: each of those is
//      "could not ask", and the stored answer stands — which is *paid*. This
//      file already made the opposite mistake once, with the CANCELLATION set
//      that `webhook-revocation-check.mjs` pins, and it cost a family a month
//      it had paid for. A reconciliation able to repeat that is worse than none.
//
// Both are silent when broken. A reconciliation that never fires looks exactly
// like one that had nothing to do, and one that downgrades on a timeout looks
// exactly like a subscription that ended.
//
// Drives the real `reconcileStaleEntitlement` and the real `usage` over the
// shipping schema.sql in in-memory SQLite, with `fetch` replaced. No Worker, no
// D1, no RevenueCat secret, nothing spent.
//
//   node scripts/entitlement-reconcile-check.mjs
//
// After touching entitlement.ts or quota.ts.

import { DatabaseSync } from 'node:sqlite'
import { readFileSync } from 'node:fs'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const schema = readFileSync(join(root, 'backend', 'schema.sql'), 'utf8')
const { reconcileStaleEntitlement } = await import(
	pathToFileURL(join(root, 'backend', 'src', 'entitlement.ts')).href
)
const { usage } = await import(pathToFileURL(join(root, 'backend', 'src', 'quota.ts')).href)

let failures = 0

function check(what, condition, detail = '') {
	if (condition) console.log(`  ok   ${what}`)
	else {
		failures += 1
		console.log(`  FAIL ${what}${detail ? ` — ${detail}` : ''}`)
	}
}

async function scenario(what, run) {
	try {
		await run()
	} catch (error) {
		failures += 1
		console.log(`  FAIL ${what} threw — ${error.message}`)
	}
}

/// D1's statement shape over node:sqlite — prepare().bind().first()/.run()/.all(),
/// which is all entitlement.ts and quota.ts use.
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

const now = () => Math.floor(Date.now() / 1000)
const inDays = (days) => (now() + days * 86_400) * 1000

/// A paying family, with the date placed by the caller. `stale` is the state
/// this whole file is about: the word still says paid, the date has passed.
function archive({ expires, entitlement = 'archive', customers = { maksaja: 'cust-1' } } = {}) {
	const db = new DatabaseSync(':memory:')
	db.exec(schema)
	db.prepare(
		`INSERT INTO family (id, name, created_at, entitlement, payer_id, entitlement_expires_at)
		 VALUES ('perhe', 'Perhe', 0, ?, 'maksaja', ?)`,
	).run(entitlement, expires)
	for (const [id, customer] of Object.entries({ maksaja: null, mummo: null, ...customers })) {
		db.prepare(
			`INSERT INTO member (id, family_id, display_name, secret_hash, role, created_at,
			                     rc_app_user_id, entitlement_expires_at)
			 VALUES (?, 'perhe', ?, 'x', 'member', 0, ?, ?)`,
		).run(id, id, customer, id === 'maksaja' ? expires : null)
	}
	return {
		db,
		env: {
			DB: d1(db),
			RC_SECRET_KEY: 'sk-jota-ei-ole',
			RC_PROJECT_ID: 'proj087f04ef',
			FREE_AI_SECONDS_PER_MONTH: '600',
			FREE_PHOTO_LIMIT: '20',
		},
		family: () =>
			db.prepare('SELECT entitlement, entitlement_expires_at, payer_id FROM family').get(),
	}
}

const session = { memberID: 'maksaja', familyID: 'perhe', role: 'owner', displayName: 'Ville' }

/// RevenueCat, replaced. `answer` is the items array, or a function for a failure.
function revenueCat(answer) {
	const calls = []
	globalThis.fetch = async (url, init) => {
		calls.push(String(url))
		if (typeof answer === 'function') return answer()
		return new Response(JSON.stringify({ items: answer }), {
			status: 200,
			headers: { 'content-type': 'application/json' },
		})
	}
	return calls
}

function captureLog(run) {
	const lines = []
	const real = console.log
	console.log = (...a) => lines.push(a.join(' '))
	return run()
		.then(
			(value) => ({ lines, value, threw: null }),
			(error) => ({ lines, value: null, threw: error }),
		)
		.finally(() => {
			console.log = real
		})
}

const entitled = (ms) => [{ entitlement_id: 'entl_arkisto', expires_at: ms }]

try {
	console.log('— the tripwire costs nothing while the state is sound —')
	await scenario('a fresh paid family', async () => {
		const { env, family } = archive({ expires: now() + 30 * 86_400 })
		const calls = revenueCat(entitled(inDays(30)))
		const u = await usage(env, session)
		check('a date still in the future is not reconciled', calls.length === 0, `${calls.length} calls`)
		check('and the family reads paid', u.entitlement === 'archive', u.entitlement)
		check('unchanged on disk', family().entitlement === 'archive')
	})
	await scenario('a perpetual entitlement', async () => {
		// null is perpetual, not absent. Read the other way round this asks
		// RevenueCat about a lifetime purchase on every single quota check.
		const { env } = archive({ expires: null })
		const calls = revenueCat(entitled(null))
		const u = await usage(env, session)
		check('a null date is forever, not stale', calls.length === 0, `${calls.length} calls`)
		check('and reads paid', u.entitlement === 'archive', u.entitlement)
	})
	await scenario('a free family', async () => {
		const { env } = archive({ expires: null, entitlement: 'free' })
		const calls = revenueCat(entitled(inDays(30)))
		const u = await usage(env, session)
		check('a free family is never reconciled', calls.length === 0, `${calls.length} calls`)
		check('and reads free', u.entitlement === 'free', u.entitlement)
	})

	console.log('— the state that cannot be true —')
	await scenario('the subscription really had ended', async () => {
		const { env, family } = archive({ expires: now() - 3600 })
		const calls = revenueCat([])
		const u = await usage(env, session)
		check('RevenueCat saying nothing is active ends the tier', family().entitlement === 'free',
			family().entitlement)
		check('and the caller is told so in the same breath', u.entitlement === 'free', u.entitlement)
		check('it asked exactly once', calls.length === 1, `${calls.length} calls`)
		check('the payer is released', family().payer_id === null, String(family().payer_id))
	})
	await scenario('the webhook was merely missed', async () => {
		// The case that makes this worth having: she renewed, the event never
		// arrived, and the old behaviour would have kept a stale date for ever
		// while the new one must not read a missed event as an ended
		// subscription.
		const { env, family } = archive({ expires: now() - 3600 })
		const until = inDays(30)
		revenueCat(entitled(until))
		const u = await usage(env, session)
		check('a renewal RevenueCat knows about keeps the tier', family().entitlement === 'archive',
			family().entitlement)
		check('with the fresh date written', family().entitlement_expires_at === Math.floor(until / 1000),
			`${family().entitlement_expires_at}`)
		check('and reads paid', u.entitlement === 'archive', u.entitlement)
	})
	await scenario('two holders, one of them renewed', async () => {
		// applyEntitlement takes the MAX across the family, so every member
		// holding a customer id has to be asked — not only family.payer_id.
		const { env, family } = archive({
			expires: now() - 3600,
			customers: { maksaja: 'cust-1', mummo: 'cust-2' },
		})
		const far = inDays(60)
		let n = 0
		globalThis.fetch = async () => {
			n += 1
			const items = n === 1 ? [] : entitled(far)
			return new Response(JSON.stringify({ items }), { status: 200 })
		}
		await usage(env, session)
		check('both holders are asked', n === 2, `${n} calls`)
		check('and the furthest date wins', family().entitlement_expires_at === Math.floor(far / 1000),
			`${family().entitlement_expires_at}`)
		check('the family stays paid', family().entitlement === 'archive')
	})

	console.log('— and a failure never ends a month somebody paid for —')
	await scenario('RevenueCat unreachable', async () => {
		const { env, family } = archive({ expires: now() - 3600 })
		revenueCat(() => new Response('{"code":7638}', { status: 503 }))
		const u = await usage(env, session)
		check('the stored answer stands', family().entitlement === 'archive', family().entitlement)
		check('and the caller is told paid, not free', u.entitlement === 'archive', u.entitlement)
	})
	await scenario('no secret key configured', async () => {
		const { db, family } = archive({ expires: now() - 3600 })
		const calls = revenueCat(entitled(inDays(30)))
		const answer = await reconcileStaleEntitlement({ DB: d1(db) }, 'perhe')
		check('it answers null rather than guessing', answer === null, String(answer))
		check('asks nobody anything', calls.length === 0, `${calls.length} calls`)
		check('and leaves the family paid', family().entitlement === 'archive')
	})
	await scenario('nobody holds a customer id', async () => {
		const { env, family } = archive({ expires: now() - 3600, customers: {} })
		const calls = revenueCat(entitled(inDays(30)))
		const answer = await reconcileStaleEntitlement(env, 'perhe')
		check('there is nothing to ask about, so it answers null', answer === null, String(answer))
		check('asks nobody anything', calls.length === 0, `${calls.length} calls`)
		check('and leaves the family paid', family().entitlement === 'archive')
	})

	console.log('— rule 9 on the path whose upstream body is somebody\'s account —')
	await scenario('the log', async () => {
		const { env } = archive({ expires: now() - 3600 })
		revenueCat([])
		const { lines } = await captureLog(() => reconcileStaleEntitlement(env, 'perhe'))
		const logged = lines.join('\n')
		check('the reconciliation is logged as a fact', /reconcil/i.test(logged), logged)
		check(
			'without the family, the member or the customer in it',
			!logged.includes('perhe') && !logged.includes('maksaja') && !logged.includes('cust-1'),
			logged,
		)
	})
} catch (error) {
	failures += 1
	console.log(`  FAIL the run itself threw — ${error.message}`)
}

console.log()
console.log(
	failures === 0
		? 'A stale tier is re-asked, and a failure keeps the month that was paid for.'
		: `${failures} failed.`,
)
process.exit(failures === 0 ? 0 : 1)
