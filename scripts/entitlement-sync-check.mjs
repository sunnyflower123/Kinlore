#!/usr/bin/env node
// The half of the purchase arc that says the client is not to be believed.
//
// `/entitlement/sync` does not accept a state, it accepts a hint: the app says
// "this customer bought something" and the server asks RevenueCat's REST API
// what is actually true. That sentence is the whole reason the endpoint exists,
// and until now nothing checked it. ARCHITECTURE §1 says so in the row that
// reads "the REST verification and the webhook need keys and are unrun" — the
// webhook half stopped being true when `webhook-revocation-check.mjs` was
// written; this is the other half.
//
// It is the most expensive thing in the app to get wrong in both directions.
// Believe the client and anyone unlocks the paid tier by sending a string.
// Disbelieve a real purchase and somebody who has been charged watches the
// family stay on the free tier — and ARCHITECTURE §6 records what that looked
// like the first time, a sheet dismissing itself over a family view still
// reading "Ilmainen".
//
// Same technique as `data-collection-check.mjs` and for the same reason: the
// real `syncEntitlement` is imported straight out of `backend/src/entitlement.ts`
// — Node runs TypeScript as it is — the schema is the shipping `schema.sql` in
// an in-memory SQLite behind a D1-shaped shim, and `fetch` is replaced with
// something that answers like RevenueCat and keeps the request. Nothing leaves
// this machine, which matters twice here: the request that proves the payer's
// account is protected must not be the request that sends it anywhere.
//
// So this needs no RC_SECRET_KEY, and that is the point rather than a
// concession. The key is the reason the row above has been unrun since it was
// written, and the logic underneath it does not need one.
//
//   node scripts/entitlement-sync-check.mjs
//
// Costs nothing: no Worker, no network, no D1, no RevenueCat. Run it after
// touching entitlement.ts, the member table or the family table.
//
// The D1 shim and `check` are copied rather than shared, like the ones in
// `webhook-revocation-check.mjs` and `entitlement-binding-check.mjs`. Each
// check in this directory runs on its own with one import of the code under
// test, and a helper module between them would be a fourth thing to keep true.

import { DatabaseSync } from 'node:sqlite'
import { readFileSync } from 'node:fs'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const schema = readFileSync(join(root, 'backend', 'schema.sql'), 'utf8')
const { syncEntitlement } = await import(
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

const now = () => Math.floor(Date.now() / 1000)
const inDays = (days) => (now() + days * 86_400) * 1000

/// Two families, because half of what this file checks is that a purchase
/// belongs to exactly one of them. `mummo` is in the paying family and has
/// bought nothing, which is the ordinary case: the payer is not the beneficiary.
function archive() {
	const db = new DatabaseSync(':memory:')
	db.exec(schema)
	const family = (id, name) =>
		db.prepare('INSERT INTO family (id, name, created_at) VALUES (?, ?, 0)').run(id, name)
	const member = (id, familyID, name, customer = null) =>
		db
			.prepare(
				`INSERT INTO member (id, family_id, display_name, secret_hash, role, created_at, rc_app_user_id)
				 VALUES (?, ?, ?, 'x', 'member', 0, ?)`,
			)
			.run(id, familyID, name, customer)
	family('perhe', 'Perhe')
	family('toinen', 'Toinen perhe')
	member('lapsenlapsi', 'perhe', 'Ville')
	member('mummo', 'perhe', 'Aino')
	member('vieras', 'toinen', 'Sanni')

	return {
		db,
		env: {
			DB: d1(db),
			RC_SECRET_KEY: 'sk-jota-ei-ole',
			// The real one, out of wrangler.jsonc: it is a public var and not a
			// secret, and the URL is asserted below.
			RC_PROJECT_ID: 'proj087f04ef',
		},
		family: (id = 'perhe') =>
			db
				.prepare('SELECT entitlement, payer_id, entitlement_expires_at FROM family WHERE id = ?')
				.get(id),
		customerOf: (id) => db.prepare('SELECT rc_app_user_id FROM member WHERE id = ?').get(id)
			.rc_app_user_id,
		bind: (memberID, customerID) =>
			db.prepare('UPDATE member SET rc_app_user_id = ? WHERE id = ?').run(customerID, memberID),
		paidThrough: (payer, seconds) =>
			db
				.prepare(
					`UPDATE family SET entitlement = 'archive', payer_id = ?, entitlement_expires_at = ?
					 WHERE id = 'perhe'`,
				)
				.run(payer, seconds),
	}
}

const session = (memberID, familyID = 'perhe') => ({
	memberID,
	familyID,
	role: 'member',
	displayName: memberID,
})

/// RevenueCat's REST API, replaced by something that answers and remembers.
///
/// `answer` is either the `items` array RevenueCat would return, or a function
/// given the URL so a case can answer with a failure instead.
function revenueCat(answer) {
	const calls = []
	globalThis.fetch = async (url, init) => {
		calls.push({ url: String(url), init })
		if (typeof answer === 'function') return answer(String(url), init)
		return new Response(JSON.stringify({ items: answer }), {
			status: 200,
			headers: { 'content-type': 'application/json' },
		})
	}
	return calls
}

/// One case, and what happens when it does not merely fail but throws.
///
/// The first version of this file had bare blocks and one try/finally around
/// all of them, and a mutation found what that costs: breaking the restore's
/// binding release makes the UPDATE violate the unique index, so the case threw
/// — and the run printed every earlier `ok`, then the closing line "The
/// purchase is verified rather than believed", and only then a stack trace.
/// A green sentence over a failed run is the exact thing every check in this
/// directory exists to prevent, so a throw is a failure of the case that threw
/// and is named as one.
async function scenario(what, run) {
	try {
		await run()
	} catch (error) {
		failures += 1
		console.log(`  FAIL ${what} threw — ${error.message}`)
	}
}

/// console.error, kept rather than printed. Rule 9's second half is that the
/// log is not somewhere to leak the cause into either, and on this path the
/// upstream body is the payer's account.
function captureLog(run) {
	const lines = []
	const real = console.error
	console.error = (...args) => lines.push(args.join(' '))
	return run()
		.then(
			(value) => ({ lines, value, threw: null }),
			(error) => ({ lines, value: null, threw: error }),
		)
		.finally(() => {
			console.error = real
		})
}

const entitled = (expiresAtMs) => [{ entitlement_id: 'entl_arkisto', expires_at: expiresAtMs }]

try {
	console.log('— the client says, RevenueCat decides —')
	await scenario('a purchase RevenueCat has never heard of', async () => {
		// The claim with nothing behind it. This is the request an attacker
		// makes, and it is also the request a confused app makes.
		const { env, family } = archive()
		revenueCat([])
		const result = await syncEntitlement(env, session('lapsenlapsi'), 'cust-1')
		check(
			'a purchase RevenueCat has never heard of unlocks nothing',
			result.entitlement === 'free' && family().entitlement === 'free',
			`answered ${result.entitlement}, family is ${family().entitlement}`,
		)
		check('and the server says it verified rather than believed', result.verified === true)
	})
	await scenario('a real purchase', async () => {
		const { env, family } = archive()
		const until = inDays(30)
		revenueCat(entitled(until))
		const result = await syncEntitlement(env, session('lapsenlapsi'), 'cust-1')
		check(
			'a real purchase opens the archive for the whole family',
			result.entitlement === 'archive' && family().entitlement === 'archive',
			`answered ${result.entitlement}`,
		)
		check(
			'through to the second RevenueCat gave, not a rounded one',
			family().entitlement_expires_at === Math.floor(until / 1000),
			`stored ${family().entitlement_expires_at}, expected ${Math.floor(until / 1000)}`,
		)
		check('and the payer is recorded', family().payer_id === 'lapsenlapsi')
	})
	await scenario('an entitlement that has run out', async () => {
		// RevenueCat can return an entitlement whose period has already ended.
		// `> now()` is the only thing standing between that and a free archive.
		const { env, family } = archive()
		revenueCat(entitled(inDays(-1)))
		const result = await syncEntitlement(env, session('lapsenlapsi'), 'cust-1')
		check(
			'an entitlement that has already run out opens nothing',
			result.entitlement === 'free' && family().entitlement === 'free',
			`answered ${result.entitlement}`,
		)
	})
	await scenario('a perpetual entitlement', async () => {
		// `expires_at: null` is RevenueCat for a perpetual entitlement, and the
		// reduce turns it into MAX_SAFE_INTEGER. Read the wrong way round it is
		// the opposite of what it means — null is also what "no date" looks
		// like — and the family would be told the purchase did not exist.
		const { env, family } = archive()
		revenueCat(entitled(null))
		const result = await syncEntitlement(env, session('lapsenlapsi'), 'cust-1')
		check(
			'a perpetual entitlement is forever and not nothing',
			result.entitlement === 'archive' && family().entitlement === 'archive',
			`answered ${result.entitlement}`,
		)
	})

	console.log('— whose purchase it is —')
	await scenario("another family's purchase", async () => {
		// The 409. `entitlement-binding-check.mjs` proves the database refuses
		// the second binding; this is the guard above it, and the part worth
		// checking here is that it answers BEFORE asking RevenueCat anything.
		const { env, family, bind } = archive()
		bind('vieras', 'cust-1')
		const calls = revenueCat(entitled(inDays(30)))
		const { lines, value: result } = await captureLog(() =>
			syncEntitlement(env, session('lapsenlapsi'), 'cust-1'),
		)
		check(
			"another family's purchase is refused, not applied",
			result.error === 'customer_belongs_to_another_family',
			`answered ${JSON.stringify(result)}`,
		)
		check('the refusal costs no upstream request', calls.length === 0, `${calls.length} calls`)
		check('and this family is left exactly as it was', family().entitlement === 'free')
		// The refusal is logged, and this file's own rule applies to it: the
		// customer id is the payer's member UUID, and a subscriber's
		// identifiers do not belong in a store the family cannot empty.
		const logged = lines.join('\n')
		check('the refusal is logged as a fact', logged.includes('another family'), logged)
		check(
			'without the ids it is about',
			!logged.includes('cust-1') && !logged.includes('lapsenlapsi') && !logged.includes('toinen'),
			logged,
		)
	})
	await scenario('a restore inside the family', async () => {
		// The restore, which must keep working: the buyer changed phone, or
		// another member of the same family restored the purchase.
		// `onRestoreCompleted` exists for this, and the unique index means the
		// binding has to MOVE rather than be added.
		const { env, family, bind, customerOf } = archive()
		bind('mummo', 'cust-1')
		revenueCat(entitled(inDays(30)))
		const result = await syncEntitlement(env, session('lapsenlapsi'), 'cust-1')
		check(
			'a restore inside the family moves the binding',
			customerOf('lapsenlapsi') === 'cust-1' && customerOf('mummo') === null,
			`lapsenlapsi ${customerOf('lapsenlapsi')}, mummo ${customerOf('mummo')}`,
		)
		check(
			'and the archive stays open through it',
			result.entitlement === 'archive' && family().entitlement === 'archive',
		)
	})
	await scenario('two payers', async () => {
		// Two payers, the rule ARCHITECTURE §6 states and only the webhook has
		// ever exercised: the longest expiry wins. A second member buying must
		// never shorten a month the family already has.
		const { env, family, paidThrough } = archive()
		const far = now() + 60 * 86_400
		paidThrough('mummo', far)
		revenueCat(entitled(inDays(30)))
		const result = await syncEntitlement(env, session('lapsenlapsi'), 'cust-1')
		check(
			'a second payer with a nearer date does not shorten the family month',
			family().entitlement_expires_at === far && family().payer_id === 'mummo',
			`stored ${family().entitlement_expires_at}, expected ${far}`,
		)
		check('and the archive stays open', result.entitlement === 'archive')
	})

	console.log('— what must not travel, and what must not be written down —')
	await scenario('the key and the request', async () => {
		// Rule 7's shape on this path. The secret is a Worker secret, and the
		// one place it may appear is the Authorization header — never the URL,
		// which is the field that ends up in somebody's access log.
		const { env } = archive()
		const calls = revenueCat(entitled(inDays(30)))
		await syncEntitlement(env, session('lapsenlapsi'), 'cust-1')
		const [call] = calls
		check('the request is made at all', calls.length === 1, `${calls.length} calls`)
		check('over https, to RevenueCat', call?.url.startsWith('https://api.revenuecat.com/'))
		check(
			'the key travels in the Authorization header',
			call?.init?.headers?.Authorization === 'Bearer sk-jota-ei-ole',
		)
		check(
			'and nowhere in the URL',
			!call?.url.includes('sk-jota-ei-ole'),
			call?.url,
		)
		check(
			'the customer is asked about by id, and nothing else is sent',
			call?.url.includes('/customers/cust-1/active_entitlements') && !call?.init?.body,
		)
	})
	await scenario('an upstream failure', async () => {
		// Rule 9 on the path where the upstream body is a subscriber's account.
		// The status and RevenueCat's own numeric code are the useful part; the
		// message is not, and Workers Logs is a store the family cannot empty.
		const { env, family } = archive()
		const secret = 'Customer not found: lapsenlapsen-oma-tunniste'
		revenueCat(
			() =>
				new Response(JSON.stringify({ code: 7638, message: secret }), {
					status: 404,
					headers: { 'content-type': 'application/json' },
				}),
		)
		const { lines, threw } = await captureLog(() =>
			syncEntitlement(env, session('lapsenlapsi'), 'cust-1'),
		)
		const logged = lines.join('\n')
		check(
			'an upstream failure throws rather than answering free',
			threw !== null,
			'a swallowed failure would revoke a paid family on a bad afternoon',
		)
		check('the family is not downgraded by it', family().entitlement === 'free')
		check('the log keeps the status', logged.includes('404'), logged)
		check("and RevenueCat's own code", logged.includes('7638'), logged)
		check(
			'and nothing of the body',
			!logged.includes(secret) && !logged.includes('lapsenlapsen-oma-tunniste'),
			logged,
		)
		check(
			'nor the message a thrown error carries to the log',
			!String(threw?.message ?? '').includes('lapsenlapsen-oma-tunniste'),
			String(threw?.message),
		)
	})
	await scenario('no key configured', async () => {
		// Today's production state until a Test Store key exists, and the answer
		// has to be this one rather than a crash: `paywallSheet` renders nothing
		// without a key, so this is the branch a real install takes.
		const { db } = archive()
		const calls = revenueCat(entitled(inDays(30)))
		const result = await syncEntitlement(
			{ DB: d1(db) },
			session('lapsenlapsi'),
			'cust-1',
		)
		check(
			'without a key the server says so instead of guessing',
			result.error === 'revenuecat_not_configured',
			JSON.stringify(result),
		)
		check('and asks nobody anything', calls.length === 0, `${calls.length} calls`)
	})
} catch (error) {
	// Anything thrown outside a case — a fixture, an import, the schema. The
	// closing line below is only allowed to be the green one when nothing at
	// all went wrong, which was not true of the first version of this file.
	failures += 1
	console.log(`  FAIL the run itself threw — ${error.message}`)
}

console.log()
console.log(
	failures === 0 ? 'The purchase is verified rather than believed.' : `${failures} failed.`,
)
process.exit(failures === 0 ? 0 : 1)
