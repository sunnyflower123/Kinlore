#!/usr/bin/env node
// A question asked of one person, and the two notifications it can cause.
//
// `prompt_question.target_member` sat in the schema from the first day and
// was read by nothing until 25 Sep 2026. Now the asker aims a question at a
// member, that member's Kerro tab offers it first, and two things ring a
// phone: "somebody asked you something" to the member it is aimed at, and
// "your question was answered" to its asker. Every rule here is silent when
// broken:
//
//   * an aim that does not resolve — a member who has left, another family's
//     member, an id that never existed — must be stored as nothing, because D1
//     enforces foreign keys and one bad reference fails the WHOLE batch: every
//     row of that push, on every retry, for ever. The phone would look like it
//     had lost its network.
//   * only the asker aims, and only once. Anybody else aiming it would send a
//     notification carrying the asker's name on a request the asker never
//     made.
//   * a notification fires on a change and never on a re-send, because the
//     outbox retries. Nobody is told about their own push.
//   * the notification carries no content — the Worker has none, the words
//     are sealed on the phone — and the log carries neither a token nor a
//     name (rule 9).
//   * the text is a loc-key, looked up on the phone. A key missing from a
//     table shows the phone the raw Finnish key, and localisation-check.mjs
//     cannot see it: it reads the Swift source, and these keys live only in a
//     push payload.
//
// Same technique as `entitlement-sync-check.mjs`: the real `push`, `pull` and
// `notify` are imported straight out of `backend/src` — Node runs TypeScript
// as it is — over the shipping `schema.sql` in an in-memory SQLite behind a
// D1-shaped shim, with foreign keys on as D1 has them, and `fetch` replaced by
// something that answers like APNs and keeps the request. The provider token
// is signed with a P-256 key made for the run and verified with its public
// half. Nothing leaves the machine: APNs speaks only HTTP/2 and `wrangler dev`
// on macOS cannot, so the wire itself is checked once, deployed.
//
//   node scripts/targeted-question-check.mjs
//
// Costs nothing: no Worker, no network, no key. Run it after touching sync.ts's
// question rows, apns.ts or the push_token table.
//
// The D1 shim and `check` are copied rather than shared, like the ones in the
// entitlement checks, for the reason given there.

import { DatabaseSync } from 'node:sqlite'
import { readFileSync } from 'node:fs'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const schema = readFileSync(join(root, 'backend', 'schema.sql'), 'utf8')
const src = (file) => pathToFileURL(join(root, 'backend', 'src', file)).href
const { push, pull } = await import(src('sync.ts'))
const { notify, payload, registerToken, unregisterToken } = await import(src('apns.ts'))

let failures = 0

function check(what, condition, detail = '') {
	if (condition) {
		console.log(`  ok   ${what}`)
	} else {
		failures += 1
		console.log(`  FAIL ${what}${detail ? ` — ${detail}` : ''}`)
	}
}

/// D1's statement shape over node:sqlite, with `batch` as one transaction —
/// which is the property the foreign-key rule above is about.
function d1(db) {
	const wrap = (sql) => {
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
			runNow() {
				statement.run(...args)
			},
		}
		return bound
	}
	return {
		prepare: wrap,
		async batch(statements) {
			db.exec('BEGIN')
			try {
				for (const statement of statements) statement.runNow()
				db.exec('COMMIT')
			} catch (err) {
				db.exec('ROLLBACK')
				throw err
			}
			return []
		},
	}
}

const now = () => Math.floor(Date.now() / 1000)

/// Two families. `mummo`, `sanna` and `mikko` are one; `vieras` is somebody
/// else's grandmother; `lahtenyt` was in the first family and has left.
function archive() {
	const db = new DatabaseSync(':memory:')
	db.exec(schema)
	const family = (id) =>
		db.prepare('INSERT INTO family (id, name, created_at) VALUES (?, ?, 0)').run(id, id)
	const member = (id, familyID, name, leftAt = null) =>
		db
			.prepare(
				`INSERT INTO member (id, family_id, display_name, secret_hash, role, created_at, left_at)
				 VALUES (?, ?, ?, 'x', 'member', 0, ?)`,
			)
			.run(id, familyID, name, leftAt)
	family('F1')
	family('F2')
	member('mummo', 'F1', 'Aili')
	member('sanna', 'F1', 'Sanna')
	member('mikko', 'F1', 'Mikko')
	member('lahtenyt', 'F1', 'Lähtenyt', 1)
	member('vieras', 'F2', 'Vieras')
	member('nimeton', 'F1', '')
	db.prepare(
		`INSERT INTO subject (id, family_id, kind, created_at) VALUES ('photo1', 'F1', 'photo', 0)`,
	).run()
	db.prepare(
		`INSERT INTO subject (id, family_id, kind, created_at) VALUES ('photo2', 'F2', 'photo', 0)`,
	).run()
	db.prepare(
		`INSERT INTO memory (id, family_id, subject_id, author_id, body, source, created_at)
		 VALUES ('memF2', 'F2', 'photo2', 'vieras', 'sealed', 'typed', 0)`,
	).run()
	const env = { DB: d1(db) }
	const as = (memberID, familyID = 'F1') => ({
		memberID,
		familyID,
		role: 'member',
		displayName: memberID,
	})
	const row = (id) => db.prepare('SELECT * FROM prompt_question WHERE id = ?').get(id)
	return { db, env, as, row }
}

const question = (id, fields) => ({
	id,
	subject_id: 'photo1',
	text: 'sealed-question-text',
	status: 'open',
	created_at: now(),
	...fields,
})

// ------------------------------------------------------------------ aiming

console.log('aiming')
{
	const { env, as, row } = archive()
	const sanna = as('sanna')
	const reply = await push(env, sanna, {
		questions: [question('q1', { author_id: 'sanna', target_member: 'mummo' })],
	})
	check('the asker aims a question at a member of the family', row('q1').target_member === 'mummo')
	check(
		'the aimed member is told, by the asker’s name',
		reply.notices.length === 1 &&
			reply.notices[0].memberID === 'mummo' &&
			reply.notices[0].kind === 'asked' &&
			reply.notices[0].askerName === 'Sanna',
		JSON.stringify(reply.notices),
	)

	const pulled = await pull(env, as('mikko'), 0)
	const q1 = pulled.questions.find((q) => q.id === 'q1')
	check(
		'a pull carries the aim and the aimed member’s name',
		q1?.target_member === 'mummo' && q1?.target_name === 'Aili',
		JSON.stringify(q1),
	)
	check(
		'every member pulls it, not only the one it is aimed at',
		pulled.questions.some((q) => q.id === 'q1'),
	)

	const again = await push(env, sanna, {
		questions: [question('q1', { author_id: 'sanna', target_member: 'mummo' })],
	})
	check('a re-send tells nobody again', again.notices.length === 0, JSON.stringify(again.notices))

	await push(env, sanna, { questions: [question('q1', { author_id: 'sanna' })] })
	check('an older device re-pushing without an aim does not take it away', row('q1').target_member === 'mummo')

	await push(env, sanna, {
		questions: [question('q1', { author_id: 'sanna', target_member: 'mikko' })],
	})
	check('the aim is set once: a second aim does not move it', row('q1').target_member === 'mummo')

	await push(env, sanna, { questions: [question('q2', { author_id: 'sanna' })] })
	const hijack = await push(env, as('mikko'), {
		questions: [question('q2', { author_id: 'mikko', target_member: 'mummo' })],
	})
	check(
		'nobody but the asker aims a question',
		row('q2').target_member === null && row('q2').author_id === 'sanna',
		JSON.stringify(row('q2')),
	)
	check('…and so nobody is told in the asker’s name', hijack.notices.length === 0)

	const machine = await push(env, as('mikko'), {
		questions: [question('q3', { author_id: null, target_member: 'mummo' })],
	})
	check(
		'a question without an asker carries no aim',
		row('q3').target_member === null && machine.notices.length === 0,
	)

	const self = await push(env, sanna, {
		questions: [question('q4', { author_id: 'sanna', target_member: 'sanna' })],
	})
	check('a question aimed at oneself tells nobody', self.notices.length === 0)

	const open = await push(env, sanna, { questions: [question('q5', { author_id: 'sanna' })] })
	check('a question for the whole family rings nobody’s phone', open.notices.length === 0)

	const deleted = await push(env, sanna, {
		questions: [question('q6', { author_id: 'sanna', target_member: 'mikko', deleted_at: now() })],
	})
	check('a deleted question tells nobody', deleted.notices.length === 0)
}

// ------------------------------------------------ references that do not resolve

console.log('references that do not resolve')
{
	const { env, as, row, db } = archive()
	const sanna = as('sanna')
	for (const [id, target, what] of [
		['r1', 'vieras', 'another family’s member'],
		['r2', 'lahtenyt', 'a member who has left'],
		['r3', 'nobody-at-all', 'an id that never existed'],
	]) {
		let threw = null
		let reply = null
		try {
			reply = await push(env, sanna, {
				subjects: [{ id: `s-${id}`, kind: 'person', created_at: now() }],
				questions: [question(id, { author_id: 'sanna', target_member: target })],
			})
		} catch (err) {
			threw = err
		}
		check(
			`aimed at ${what}: stored as nobody, and the rest of the push lands`,
			!threw &&
				row(id)?.target_member === null &&
				db.prepare('SELECT 1 AS ok FROM subject WHERE id = ?').get(`s-${id}`)?.ok === 1,
			threw ? String(threw.message) : JSON.stringify(row(id)),
		)
		check(`…and nobody is told`, reply !== null && reply.notices.length === 0)
	}

	let threw = null
	try {
		await push(env, sanna, {
			questions: [
				question('r4', { author_id: 'sanna', status: 'answered', answered_memory_id: 'memF2' }),
				question('r5', { author_id: 'sanna', status: 'answered', answered_memory_id: 'no-such' }),
			],
		})
	} catch (err) {
		threw = err
	}
	check(
		'an answer naming a telling of another family, or none at all, is stored as nothing',
		!threw && row('r4')?.answered_memory_id === null && row('r5')?.answered_memory_id === null,
		threw ? String(threw.message) : '',
	)
}

// ---------------------------------------------------------------- answers

console.log('answers')
{
	const { env, as, row } = archive()
	await push(env, as('sanna'), {
		questions: [question('a1', { author_id: 'sanna', target_member: 'mummo' })],
	})
	const answer = await push(env, as('mummo'), {
		memories: [
			{
				id: 'm1',
				subject_id: 'photo1',
				author_id: 'mummo',
				body: 'sealed-telling',
				source: 'voice',
				created_at: now(),
			},
		],
		questions: [question('a1', { author_id: null, status: 'answered', answered_memory_id: 'm1' })],
	})
	check(
		'the telling pushed with the answer is recorded as the answer',
		row('a1').answered_memory_id === 'm1' && row('a1').status === 'answered',
		JSON.stringify(row('a1')),
	)
	check(
		'the asker is told, and the notice names nobody',
		answer.notices.length === 1 &&
			answer.notices[0].memberID === 'sanna' &&
			answer.notices[0].kind === 'answered' &&
			answer.notices[0].askerName === null,
		JSON.stringify(answer.notices),
	)
	check('an answer leaves the aim where it was', row('a1').target_member === 'mummo')

	const pulled = await pull(env, as('sanna'), 0)
	check(
		'a pull carries which telling answered it',
		pulled.questions.find((q) => q.id === 'a1')?.answered_memory_id === 'm1',
	)

	const again = await push(env, as('mummo'), {
		questions: [question('a1', { status: 'answered', answered_memory_id: 'm1' })],
	})
	check('a re-sent answer tells nobody again', again.notices.length === 0)

	await push(env, as('mikko'), {
		memories: [
			{ id: 'm2', subject_id: 'photo1', author_id: 'mikko', body: 's', source: 'typed', created_at: now() },
		],
		questions: [question('a1', { status: 'answered', answered_memory_id: 'm2' })],
	})
	check('the first answer stays the answer', row('a1').answered_memory_id === 'm1')

	await push(env, as('sanna'), { questions: [question('a2', { author_id: 'sanna' })] })
	const own = await push(env, as('sanna'), {
		questions: [question('a2', { author_id: 'sanna', status: 'answered' })],
	})
	check('answering one’s own question tells nobody', own.notices.length === 0)

	await push(env, as('mikko'), { questions: [question('a3', { author_id: null })] })
	const machine = await push(env, as('mummo'), {
		questions: [question('a3', { status: 'answered' })],
	})
	check('a question nobody asked has nobody to tell', machine.notices.length === 0)
}

// ------------------------------------------------------------------ tokens

console.log('tokens')
{
	const { env, as, db } = archive()
	const token = 'ab'.repeat(32)
	check(
		'a token that is not hex is refused',
		'error' in (await registerToken(env, as('mummo'), 'not a token', 'sandbox')),
	)
	check(
		'an environment that is not APNs’s is refused',
		'error' in (await registerToken(env, as('mummo'), token, 'staging')),
	)
	await registerToken(env, as('mummo'), token.toUpperCase(), 'sandbox')
	const stored = db.prepare('SELECT * FROM push_token').all()
	check(
		'a token is stored once, lower-cased, with its endpoint',
		stored.length === 1 && stored[0].token === token && stored[0].environment === 'sandbox',
		JSON.stringify(stored),
	)
	await registerToken(env, as('mikko'), token, 'production')
	const moved = db.prepare('SELECT * FROM push_token').all()
	check(
		'a phone that changes hands moves with its token',
		moved.length === 1 && moved[0].member_id === 'mikko' && moved[0].environment === 'production',
	)
	await unregisterToken(env, as('sanna'), token)
	check('a member cannot remove another member’s token', db.prepare('SELECT * FROM push_token').all().length === 1)
	await unregisterToken(env, as('mikko'), token)
	check('the owner of a token removes it', db.prepare('SELECT * FROM push_token').all().length === 0)
}

// -------------------------------------------------------------------- APNs

console.log('APNs')
{
	const keys = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
		'sign',
		'verify',
	])
	const der = Buffer.from(await crypto.subtle.exportKey('pkcs8', keys.privateKey)).toString('base64')
	const pem = `-----BEGIN PRIVATE KEY-----\n${der.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`

	const { env, as, db } = archive()
	const sandboxToken = '11'.repeat(32)
	const productionToken = '22'.repeat(32)
	const goneToken = '33'.repeat(32)
	const leaverToken = '44'.repeat(32)
	await registerToken(env, as('mummo'), sandboxToken, 'sandbox')
	await registerToken(env, as('mummo'), productionToken, 'production')
	await registerToken(env, as('sanna'), goneToken, 'sandbox')
	db.prepare(
		`INSERT INTO push_token (token, member_id, environment, created_at, updated_at)
		 VALUES (?, 'lahtenyt', 'sandbox', 0, 0)`,
	).run(leaverToken)

	const requests = []
	const answers = new Map([[goneToken, { status: 410, reason: 'Unregistered' }]])
	const realFetch = globalThis.fetch
	globalThis.fetch = async (url, init) => {
		requests.push({ url: String(url), init })
		const token = String(url).split('/').pop()
		const answer = answers.get(token) ?? { status: 200 }
		return new Response(answer.status === 200 ? '' : JSON.stringify({ reason: answer.reason }), {
			status: answer.status,
		})
	}
	const logged = []
	const realLog = console.log
	const realError = console.error
	console.log = (...args) => logged.push(args.join(' '))
	console.error = (...args) => logged.push(args.join(' '))

	const asked = { memberID: 'mummo', kind: 'asked', questionID: 'q1', askerName: 'Sanna' }
	const answered = { memberID: 'sanna', kind: 'answered', questionID: 'q1', askerName: null }
	const leaver = { memberID: 'lahtenyt', kind: 'answered', questionID: 'q9', askerName: null }

	await notify(env, 'F1', [asked])
	const withoutKey = requests.length

	const keyed = { ...env, APNS_KEY_P8: pem, APNS_KEY_ID: 'KEY1234567', APNS_TEAM_ID: 'TEAM123456' }
	await notify(keyed, 'F1', [asked, answered, leaver])

	console.log = realLog
	console.error = realError
	globalThis.fetch = realFetch

	check('without the three secrets nothing is sent', withoutKey === 0)
	const hosts = requests.map((request) => new URL(request.url).host).sort()
	check(
		'each phone is sent to its own endpoint, and a member who has left is sent nothing',
		JSON.stringify(hosts) ===
			JSON.stringify(['api.push.apple.com', 'api.sandbox.push.apple.com', 'api.sandbox.push.apple.com']),
		JSON.stringify(hosts),
	)
	const toMummo = requests.find((request) => request.url.endsWith(sandboxToken))
	const headers = toMummo?.init.headers ?? {}
	check(
		'the request names the app, an alert, and replaces an earlier copy of itself',
		headers['apns-topic'] === 'com.kinlore.app' &&
			headers['apns-push-type'] === 'alert' &&
			headers['apns-priority'] === '10' &&
			headers['apns-collapse-id'] === 'asked-q1' &&
			Number(headers['apns-expiration']) > now(),
		JSON.stringify(headers),
	)

	const [head, claims, signature] = String(headers.authorization ?? '').replace('bearer ', '').split('.')
	const decode = (part) => JSON.parse(Buffer.from(part ?? '', 'base64url').toString('utf8') || 'null')
	const verified =
		Boolean(signature) &&
		(await crypto.subtle.verify(
			{ name: 'ECDSA', hash: 'SHA-256' },
			keys.publicKey,
			Buffer.from(signature, 'base64url'),
			new TextEncoder().encode(`${head}.${claims}`),
		))
	check(
		'the provider token is ES256 under the key id and team, and its signature verifies',
		verified &&
			decode(head)?.alg === 'ES256' &&
			decode(head)?.kid === 'KEY1234567' &&
			decode(claims)?.iss === 'TEAM123456' &&
			Math.abs(decode(claims)?.iat - now()) < 60,
		JSON.stringify({ head: decode(head), claims: decode(claims), verified }),
	)
	check(
		'one signature serves every send in the run',
		new Set(requests.map((request) => request.init.headers.authorization)).size === 1,
	)

	const body = JSON.parse(toMummo?.init.body ?? '{}')
	check(
		'"asked" is a loc-key filled with the asker’s name, and a tap knows the question',
		body.aps?.alert?.['loc-key'] === '%@ kysyi sinulta jotain.' &&
			JSON.stringify(body.aps?.alert?.['loc-args']) === '["Sanna"]' &&
			body.kinlore?.question === 'q1' &&
			body.kinlore?.kind === 'asked',
		JSON.stringify(body),
	)
	const toSanna = requests.find((request) => request.url.endsWith(goneToken))
	const answeredBody = JSON.parse(toSanna?.init.body ?? '{}')
	check(
		'"answered" names nobody',
		answeredBody.aps?.alert?.['loc-key'] === 'Kysymykseesi tuli vastaus.' &&
			!('loc-args' in (answeredBody.aps?.alert ?? {})),
		JSON.stringify(answeredBody),
	)
	check(
		'an asker with no display name gets a sentence without a hole in it',
		payload({ ...asked, askerName: '  ' }).aps.alert['loc-key'] === 'Sinulle on uusi kysymys.',
	)
	check(
		'no request carries a question or a telling',
		requests.every(
			(request) =>
				!request.init.body.includes('sealed-question-text') && !request.init.body.includes('sealed-telling'),
		),
	)
	check(
		'a token APNs calls Unregistered is forgotten, and the others are kept',
		db.prepare('SELECT token FROM push_token WHERE token = ?').get(goneToken) === undefined &&
			db.prepare('SELECT COUNT(*) AS n FROM push_token').get().n === 3,
	)
	const log = logged.join('\n')
	check(
		'the log says what happened in counts and codes',
		/\[apns\] 3 notices, 3 sends: .*2× 200.*1× 410 Unregistered/.test(log) &&
			log.includes('1 tokens dropped'),
		log,
	)
	check(
		'…and carries no token and no name',
		![sandboxToken, productionToken, goneToken, 'Sanna', 'Aili'].some((secret) => log.includes(secret)),
		log,
	)
}

// ------------------------------------------------------------- the tables

console.log('the words on the phone')
{
	const keys = ['%@ kysyi sinulta jotain.', 'Kysymykseesi tuli vastaus.', 'Sinulle on uusi kysymys.']
	for (const lang of ['fi', 'en']) {
		const table = readFileSync(join(root, 'ios', 'Kinlore', `${lang}.lproj`, 'Localizable.strings'), 'utf8')
		const missing = keys.filter((key) => !table.includes(`"${key}" =`))
		check(`${lang}.lproj carries every key a notification uses`, missing.length === 0, missing.join(', '))
	}
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
