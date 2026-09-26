#!/usr/bin/env node
// What a stranger can spend in a day, and what must still save once it is
// spent.
//
// The free tier is metered per family, and a family costs nothing: POST
// /family asks for no invitation, the rate limit is five a minute per
// address, and addresses are not scarce. So every limit written against an
// identity is a limit on nothing. Read from the code on 26 Sep 2026, two days
// before the repository and the production URL in it were due to go public: a
// fresh family could transcribe up to 25 MiB on its first call, any number of
// calls passed together because the meter was checked before the model and
// written after it, `/extract` had no meter and no length cap at all, and
// colouring was five rounds a family — 36 000 rounds a day from one address.
// Nothing bounded a day's spend but the credit limit on the OpenRouter
// account.
//
// The ceiling is one pool per route per UTC day for the whole free tier,
// reserved in one statement before the model is asked (`quota.ts`). What that
// has to keep true, each of them silent when broken:
//
//   1. **Many new families share one day.** A pool per family would be
//      another limit on nothing.
//   2. **Ten at once get what one at a time gets.** A check-then-record meter
//      lets every concurrent call through; a reservation that decides and
//      counts in one statement cannot.
//   3. **The refusal is 429 in the rate limiter's shape, never the meter's
//      402**, and nothing goes upstream. A 402 carrying `ai_seconds` would
//      tell the family its month was spent and offer to sell it one; the app
//      reads 429 as a fact about the moment (`DeferredMemory.isAboutTheMoment`,
//      pinned by `transcription-catchup-check.swift`), keeps the audio and
//      asks again later.
//   4. **A call is charged by what it sends, never by what it claims, and a
//      failed one is not given back.** A recording pays for the longest audio
//      its bytes can hold whatever `seconds` says, because the model is paid
//      for what it hears; a telling pays for its length, corrections
//      included; and a reply cut off at its budget cost what a kept one does.
//      `/extract` and `/colourise` have days of their own.
//   5. **A paid family is neither refused nor counted.**
//   6. **Rule 2.** Once every pool is spent, a typed memory and a recording's
//      audio still save and still reach the family.
//   7. **A new UTC day is a new pool**, so a spent day defers and never
//      retires.
//   8. **The shipped values admit the largest recording the route accepts and
//      the longest telling the app can make**, on a day nobody has touched. A
//      pool smaller than that would refuse one honest telling every day, for
//      ever, and look exactly like a busy day.
//   9. **Rules 8 and 9 on every path here**: every request upstream says
//      `data_collection: deny`, and a refusal logs the pool and the limit and
//      not the family, the member or a word of what was told.
//
// Drives the real Worker's handler over the shipping schema.sql in in-memory
// SQLite, with the global `fetch` replaced by something that answers like
// OpenRouter and counts what it was asked. No wrangler, no key, no network,
// nothing spent.
//
//   node scripts/free-tier-ceiling-check.mjs
//
// After touching quota.ts, budget.ts, the three AI routes in worker.ts, or the
// FREE_TIER_* values in wrangler.jsonc.

import { AsyncLocalStorage } from 'node:async_hooks'
import { DatabaseSync } from 'node:sqlite'
import { readFileSync } from 'node:fs'
import { randomBytes, randomUUID } from 'node:crypto'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const schema = readFileSync(join(root, 'backend', 'schema.sql'), 'utf8')
const wrangler = readFileSync(join(root, 'backend', 'wrangler.jsonc'), 'utf8')

/// The clock, movable, so that "tomorrow" can be asked for without waiting a
/// day. Everything the Worker reads the time through — `new Date()` and
/// `Date.now()` — goes through this.
const RealDate = Date
let shift = 0
globalThis.Date = class extends RealDate {
	constructor(...args) {
		if (args.length === 0) super(RealDate.now() + shift)
		else super(...args)
	}
	static now() {
		return RealDate.now() + shift
	}
}

const { default: worker } = await import(pathToFileURL(join(root, 'backend', 'src', 'worker.ts')).href)

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

/// What the Worker writes to the console is kept with the request that wrote
/// it rather than printed: the rate limiter warns on every family created
/// without its binding, and rule 9 is a claim about exactly these lines. Per
/// request and not per moment, because ten of them run at once below.
const logs = new AsyncLocalStorage()
for (const level of ['log', 'warn', 'error']) {
	const real = console[level].bind(console)
	console[level] = (...a) => {
		const sink = logs.getStore()
		if (sink) sink.push(a.join(' '))
		else real(...a)
	}
}

/// D1's statement shape over node:sqlite, with `batch` as one transaction.
///
/// Every statement reaches the database on a later turn of the event loop, as
/// D1's do across the network. node:sqlite answers in the same breath, and
/// without the turn a request ran from its first statement to its last before
/// the next one moved: a meter that checked and then wrote in two statements
/// passed "ten at once" here, measured, while production would let all ten
/// through.
const turn = () => new Promise((resolve) => setImmediate(resolve))
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
				await turn()
				return statement.get(...args) ?? null
			},
			async run() {
				await turn()
				return { meta: { changes: Number(statement.run(...args).changes) } }
			},
			async all() {
				await turn()
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
			await turn()
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

/// A value as wrangler.jsonc ships it, or undefined.
const shipped = (name) => wrangler.match(new RegExp(`"${name}":\\s*"([^"]*)"`))?.[1]

/// OpenRouter, replaced. Answers each request in the shape its route expects
/// and keeps the request, so a test can count what reached the model. With
/// `cutOff` set, every reply stops at its token budget, the way a paid-for
/// call fails.
const upstream = []
let cutOff = false
const EXTRACTED = {
	body: 'Äiti leipoi pullaa joka lauantai.',
	mentions: [],
	date: { start_year: null, end_year: null, precision: 'unknown' },
	questions: [],
}
globalThis.fetch = async (url, init) => {
	if (!String(url).startsWith('https://openrouter.ai/')) throw new Error(`unexpected fetch to ${url}`)
	const body = JSON.parse(init.body)
	upstream.push(body)
	const message = body.modalities?.includes('image')
		? { content: null, images: [{ image_url: { url: 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQ' } }] }
		: { content: body.response_format ? JSON.stringify(EXTRACTED) : 'Äiti leipoi pullaa.' }
	return new Response(JSON.stringify({ choices: [{ message, finish_reason: cutOff ? 'length' : 'stop' }] }), {
		status: 200,
		headers: { 'content-type': 'application/json' },
	})
}

/// A fresh production in miniature: the shipping schema, an R2 that keeps what
/// it is given, the shipped models, and whatever pools the scenario sets.
function world(pools = {}) {
	const db = new DatabaseSync(':memory:')
	db.exec(schema)
	const stored = new Map()
	const env = {
		DB: d1(db),
		MEDIA: {
			async put(key, value) {
				stored.set(key, value)
			},
			async get(key) {
				return stored.has(key) ? { body: stored.get(key) } : null
			},
		},
		OPENROUTER_API_KEY: 'not-a-key',
		MODEL_EXTRACT: shipped('MODEL_EXTRACT'),
		MODEL_EXTRACT_FALLBACK: shipped('MODEL_EXTRACT_FALLBACK'),
		MODEL_TRANSCRIBE: shipped('MODEL_TRANSCRIBE'),
		MODEL_COLOURISE: shipped('MODEL_COLOURISE'),
		FREE_PHOTO_LIMIT: '20',
		FREE_AI_SECONDS_PER_MONTH: '600',
		FREE_COLOURISATIONS_PER_MONTH: '5',
		...pools,
	}
	return { db, env }
}

const ctx = { waitUntil: (promise) => promise?.catch?.(() => {}), passThroughOnException() {} }

/// One request through the real handler. What the Worker logged on the way
/// comes back with the answer instead of being printed.
async function call(env, method, path, body, auth) {
	const raw = body instanceof Uint8Array
	const request = new Request(`http://localhost${path}`, {
		method,
		headers: {
			...(raw ? {} : { 'content-type': 'application/json' }),
			...(auth ? { Authorization: auth } : {}),
		},
		body: body === undefined ? undefined : raw ? body : JSON.stringify(body),
	})
	const lines = []
	const response = await logs.run(lines, () => worker.fetch(request, env, ctx))
	return { status: response.status, body: await response.json().catch(() => null), lines }
}

/// A new identity and the family it founds, the way a stranger gets one.
async function stranger(env) {
	const memberID = randomUUID()
	const secret = randomBytes(32).toString('hex')
	const created = await call(env, 'POST', '/family', { memberID, secret, displayName: 'Vieras' })
	if (created.status !== 200) throw new Error(`POST /family answered ${created.status}`)
	return { memberID, familyID: created.body.familyID, auth: `Bearer ${memberID}.${secret}` }
}

/// A short recording, in base64: about 1.5 kB, so a second and a half at the
/// app's own bitrate. Charged the floor a call costs whatever its length.
const CLIP = 'A'.repeat(2000)
const transcribe = (env, who, audio = CLIP) =>
	call(env, 'POST', '/transcribe', { audio, format: 'm4a', seconds: 1, lang: 'fi' }, who.auth)

const SHORT = 'Äiti leipoi pullaa joka lauantai.'
const structure = (env, who, transcript = SHORT, extra = {}) =>
	call(env, 'POST', '/extract', { transcript, lang: 'fi', ...extra }, who.auth)

const colourise = (env, who) =>
	call(env, 'POST', '/colourise', { image: '/9j/4AAQSkZJRgABAQ', told: ['Äidin mekko oli tummanvihreä'], aspect: '4:3' }, who.auth)

const refused = (reply) =>
	reply.status === 429 && JSON.stringify(reply.body) === JSON.stringify({ error: 'too_many_requests' })
const statuses = (replies) => replies.map((r) => r.status).join(' ')

try {
	// The pools below are small on purpose, so a scenario spends one in a few
	// calls. A clip is charged 300 s (the floor in quota.ts), so a thousand-
	// second day holds three; a five-word telling is charged its output budget
	// plus its bytes, 3 136 tokens, so a ten-thousand-token day holds three.
	const SMALL = {
		FREE_TIER_AI_SECONDS_PER_DAY: '1000',
		FREE_TIER_EXTRACTION_TOKENS_PER_DAY: '10000',
		FREE_TIER_COLOURISATIONS_PER_DAY: '2',
	}

	console.log('— many new families share one day —')
	await scenario('six strangers', async () => {
		const { env } = world(SMALL)
		const before = upstream.length
		const replies = []
		for (let i = 0; i < 6; i += 1) replies.push(await transcribe(env, await stranger(env)))
		check('three clips spend a thousand-second day', replies.slice(0, 3).every((r) => r.status === 200), statuses(replies))
		check('and every family after them is refused', replies.slice(3).every(refused), statuses(replies))
		check('only the three reached the model', upstream.length - before === 3, `${upstream.length - before} calls`)
	})

	console.log('— ten at once get what one at a time gets —')
	await scenario('one family, ten together', async () => {
		const { env } = world(SMALL)
		const who = await stranger(env)
		const before = upstream.length
		const replies = await Promise.all(Array.from({ length: 10 }, () => transcribe(env, who)))
		check('three go through', replies.filter((r) => r.status === 200).length === 3, statuses(replies))
		check('seven are refused', replies.filter(refused).length === 7, statuses(replies))
		check('and three reached the model, not ten', upstream.length - before === 3, `${upstream.length - before} calls`)
	})

	console.log('— the refusal says busy, asks nothing upstream, and leaves the month alone —')
	await scenario('a spent day', async () => {
		const { env } = world(SMALL)
		const who = await stranger(env)
		for (let i = 0; i < 3; i += 1) await transcribe(env, who)
		const month = (await call(env, 'GET', '/usage', undefined, who.auth)).body.aiSeconds.used
		const before = upstream.length
		const reply = await transcribe(env, who)
		check('the answer is 429 in the rate limiter\'s own shape', refused(reply), JSON.stringify(reply))
		check('not the meter\'s 402, which would offer to sell a month', reply.status !== 402)
		check('nothing was asked of the model', upstream.length === before, `${upstream.length - before} calls`)
		const after = (await call(env, 'GET', '/usage', undefined, who.auth)).body.aiSeconds.used
		check('and the family\'s month did not move', after === month, `${month} → ${after}`)
	})

	console.log('— a call is charged by what it sends, and a failed one is not given back —')
	await scenario('a recording that says one second', async () => {
		// 1 001 s of audio at the 1 kB/s the charge assumes, claiming one. The
		// month clamps that claim up to the bytes' shortest reading, 25 s; the
		// model would hear all of it.
		const { env } = world(SMALL)
		const who = await stranger(env)
		const before = upstream.length
		const long = await transcribe(env, who, 'A'.repeat(Math.ceil(1001 * 1000 * 1.37)))
		check('is charged the audio it carries, more than a fresh day holds', refused(long), `${long.status}`)
		const short = await transcribe(env, who)
		check('while a short clip on the same day still goes', short.status === 200, `${short.status}`)
		check('one call reached the model', upstream.length - before === 1, `${upstream.length - before} calls`)
	})
	await scenario('replies cut off at their budget', async () => {
		const { env } = world(SMALL)
		const who = await stranger(env)
		cutOff = true
		const failed = []
		try {
			for (let i = 0; i < 3; i += 1) failed.push(await transcribe(env, who))
		} finally {
			cutOff = false
		}
		check('three calls fail upstream', failed.every((r) => r.status >= 500), statuses(failed))
		const next = await transcribe(env, who)
		check('and what they spent stays spent', refused(next), `${next.status}`)
	})

	console.log('— /extract and /colourise have days too —')
	await scenario('structuring', async () => {
		const { env } = world(SMALL)
		const before = upstream.length
		const replies = []
		for (let i = 0; i < 4; i += 1) replies.push(await structure(env, await stranger(env)))
		check('three short tellings spend a ten-thousand-token day', replies.slice(0, 3).every((r) => r.status === 200), statuses(replies))
		check('and the fourth is refused', refused(replies[3]), statuses(replies))
		check('three reached the model', upstream.length - before === 3, `${upstream.length - before} calls`)
	})
	await scenario('a long telling', async () => {
		const { env } = world(SMALL)
		const who = await stranger(env)
		const before = upstream.length
		const long = await structure(env, who, 'sana '.repeat(1000))
		check('a thousand words cost more than a fresh day holds', refused(long), `${long.status}`)
		const short = await structure(env, who)
		check('while a short telling on the same day still goes', short.status === 200, `${short.status}`)
		check('one call reached the model', upstream.length - before === 1, `${upstream.length - before} calls`)
	})
	await scenario('corrections are what is read, too', async () => {
		// They go into the prompt unshortened (`correctionInstruction`), so a
		// charge that counted the transcript alone would let the size of a call
		// ride in beside it for free.
		const { env } = world(SMALL)
		const who = await stranger(env)
		const padded = await structure(env, who, SHORT, {
			corrections: [{ from: 'Skotlanti', to: `Sotkamo ${'sana '.repeat(2000)}` }],
		})
		check('a short telling with a long correction is charged the correction', refused(padded), `${padded.status}`)
	})
	await scenario('colouring', async () => {
		const { env } = world(SMALL)
		const before = upstream.length
		const replies = []
		for (let i = 0; i < 3; i += 1) replies.push(await colourise(env, await stranger(env)))
		check('two rounds spend a two-round day', replies.slice(0, 2).every((r) => r.status === 200), statuses(replies))
		check('and the third family is refused', refused(replies[2]), statuses(replies))
		check('two reached the model', upstream.length - before === 2, `${upstream.length - before} calls`)
	})

	console.log('— a paid family is neither refused nor counted —')
	await scenario('an archive family', async () => {
		const { db, env } = world(SMALL)
		const payer = await stranger(env)
		db.prepare("UPDATE family SET entitlement = 'archive', entitlement_expires_at = NULL WHERE id = ?").run(payer.familyID)
		const paid = []
		for (let i = 0; i < 5; i += 1) paid.push(await transcribe(env, payer))
		check('five clips, past what the free day holds', paid.every((r) => r.status === 200), statuses(paid))
		const free = []
		const who = await stranger(env)
		for (let i = 0; i < 4; i += 1) free.push(await transcribe(env, who))
		check('and the free tier\'s day is still whole after them', free.slice(0, 3).every((r) => r.status === 200) && refused(free[3]), statuses(free))
		const late = await transcribe(env, payer)
		check('the paid family goes on once it is spent', late.status === 200, `${late.status}`)
		const coloured = await colourise(env, payer)
		const structured = await structure(env, payer, 'sana '.repeat(1000))
		check('in the other two routes as well', coloured.status === 200 && structured.status === 200, `${coloured.status} ${structured.status}`)
	})

	console.log('— rule 2: a spent day costs structure, never the telling —')
	await scenario('telling after every pool is spent', async () => {
		const { env } = world({
			FREE_TIER_AI_SECONDS_PER_DAY: '300',
			FREE_TIER_EXTRACTION_TOKENS_PER_DAY: '3200',
			FREE_TIER_COLOURISATIONS_PER_DAY: '1',
		})
		const who = await stranger(env)
		await transcribe(env, who)
		await structure(env, who)
		await colourise(env, who)
		const spent = [await transcribe(env, who), await structure(env, who), await colourise(env, who)]
		check('all three pools are spent', spent.every(refused), statuses(spent))

		const audio = await call(env, 'POST', '/media?kind=audio', new Uint8Array(4500).fill(7), who.auth)
		check('the recording\'s audio still uploads', audio.status === 200 && typeof audio.body?.key === 'string', `${audio.status}`)
		const photo = randomUUID()
		const typed = randomUUID()
		const spoken = randomUUID()
		const now = Math.floor(Date.now() / 1000)
		const pushed = await call(env, 'POST', '/sync', {
			subjects: [{ id: photo, kind: 'photo', title: 'Mökin ranta', confirmed: 1, created_at: now }],
			memories: [
				{ id: typed, subject_id: photo, body: 'Sauna lämpisi joka lauantai.', source: 'typed', created_at: now },
				{ id: spoken, subject_id: photo, body: '', audio_r2_key: audio.body?.key, audio_seconds: 1, source: 'voice', created_at: now },
			],
		}, who.auth)
		check('a typed memory and an untranscribed one both sync', pushed.status === 200, `${pushed.status}`)
		const pulled = await call(env, 'GET', '/sync?since=0', undefined, who.auth)
		const rows = new Map((pulled.body?.memories ?? []).map((m) => [m.id, m]))
		check('the typed words reach the family', rows.get(typed)?.body === 'Sauna lämpisi joka lauantai.')
		check('and so does the voice, waiting for its text', rows.get(spoken)?.audio_r2_key === audio.body?.key)
	})

	console.log('— a new UTC day is a new pool —')
	await scenario('tomorrow', async () => {
		const { env } = world(SMALL)
		const who = await stranger(env)
		for (let i = 0; i < 3; i += 1) await transcribe(env, who)
		check('today is spent', refused(await transcribe(env, who)))
		shift = 86_400_000
		try {
			const tomorrow = await transcribe(env, who)
			check('and the same family is heard again tomorrow', tomorrow.status === 200, `${tomorrow.status}`)
		} finally {
			shift = 0
		}
	})

	console.log('— the shipped values admit the longest honest input —')
	await scenario('wrangler.jsonc', async () => {
		const pools = Object.fromEntries(
			['FREE_TIER_AI_SECONDS_PER_DAY', 'FREE_TIER_EXTRACTION_TOKENS_PER_DAY', 'FREE_TIER_COLOURISATIONS_PER_DAY'].map(
				(name) => [name, shipped(name)],
			),
		)
		check('all three pools are set in wrangler.jsonc', Object.values(pools).every((v) => Number(v) > 0), JSON.stringify(pools))
		/// Each input on a day of its own, since the claim is about one of them.
		const emptyDay = async () => {
			const { env } = world(pools)
			return { env, who: await stranger(env) }
		}

		// The largest body `/transcribe` accepts; one character more is a 413.
		// At the 1 kB/s the charge assumes, that is 26 214.4 s, charged 26 215.
		const largest = 'A'.repeat(Math.floor(25 * 1024 * 1024 * 1.37))
		const day1 = await emptyDay()
		const recording = await transcribe(day1.env, day1.who, largest)
		check('the largest recording the route accepts, on an empty day', recording.status === 200, `${recording.status}`)

		// The longest transcript that recording can come back as, from the app:
		// 25 MiB at its own 4.5 kB/s (268 kB a minute, ARCHITECTURE §5) is
		// 5 869 s, and the hallucination guard lets through four Finnish words a
		// second and six English ones, plus twenty (`budget.ts`) — 23 495 and
		// 35 233 words, charged 222 169 and 283 979.
		const seconds = (25 * 1024 * 1024) / (268_000 / 60)
		const words = (sentence, perSecond) => {
			const each = sentence.split(' ')
			const n = Math.floor(seconds * perSecond) + 20
			return Array.from({ length: n }, (_, i) => each[i % each.length]).join(' ')
		}
		const day2 = await emptyDay()
		const fi = await structure(day2.env, day2.who, words('Äiti leipoi pullaa joka lauantai ja isä lämmitti saunan.', 4))
		check('the longest Finnish telling the app can make', fi.status === 200, `${fi.status}`)
		const day3 = await emptyDay()
		const en = await call(day3.env, 'POST', '/extract', {
			transcript: words('Mother baked buns every Saturday and father heated the sauna.', 6),
			lang: 'en',
		}, day3.who.auth)
		check('and the longest English one', en.status === 200, `${en.status}`)
	})

	console.log('— rules 8 and 9 —')
	await scenario('the log', async () => {
		const { env } = world(SMALL)
		const who = await stranger(env)
		for (let i = 0; i < 3; i += 1) await transcribe(env, who)
		const replies = [
			await transcribe(env, who),
			await structure(env, who, `Mummon salainen piparkakkuresepti ${'sana '.repeat(1000)}`),
		]
		check('both are refused', replies.every(refused), statuses(replies))
		const logged = replies.flatMap((r) => r.lines).join('\n')
		check('a refusal is logged as the pool it came from', /\[quota\]/.test(logged), logged || '(nothing logged)')
		check(
			'without the family, the member or a word of what was told',
			!logged.includes(who.familyID) && !logged.includes(who.memberID) && !logged.includes('salainen'),
			logged,
		)
	})
	check(
		'every request that reached the model said data_collection: deny',
		upstream.length > 0 && upstream.every((body) => body.provider?.data_collection === 'deny'),
		`${upstream.filter((body) => body.provider?.data_collection !== 'deny').length} of ${upstream.length} did not`,
	)
} catch (error) {
	failures += 1
	console.log(`  FAIL the run itself threw — ${error.message}`)
}

console.log()
console.log(
	failures === 0
		? 'A stranger\'s day is bounded, and a spent day costs structure, never the telling.'
		: `${failures} failed.`,
)
process.exit(failures === 0 ? 0 : 1)
