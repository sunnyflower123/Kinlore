#!/usr/bin/env node
// Checks the pull cursor, which is the family's delivery guarantee.
//
// The rule is one sentence — the cursor moves only through pull replies — and
// it exists because every way of moving it anywhere else was measured to lose
// rows, silently, on 23 Aug 2026. Three defects lived in one mechanism:
//
//   1. The client advanced its cursor to the push reply's seq. That number is
//      the family-global counter, so any rows other members committed between
//      this device's last pull and its own push fell below the cursor and
//      were never fetched again. A two-device family hit this by merely
//      taking turns — no race, no offline window.
//   2. The server reserved seq with an UPDATE followed by a separate SELECT,
//      so two pushes arriving together could share one number and give each
//      device the same blind spot against the other.
//   3. A reply's cursor was the maximum seq across four separately-capped
//      tables, so when one table filled its cap while another returned
//      higher numbers, the capped table's tail was skipped forever.
//
// Every one of these leaves a working app: pushes succeed, pulls succeed,
// screens fill — and one phone's telling simply never draws on another. That
// is the exact promise the product makes, failing in the one way nobody can
// see. This script drives the interleavings that showed each defect.
//
// What it does NOT cover: the Swift half of rule 1 (SyncEngine no longer
// advances on push). That lives in the app and is out of a Node script's
// reach — this pins the server contract the rule depends on: a pull from the
// pre-push cursor returns the missed rows, so a client that only trusts
// pulls cannot lose them.
//
// One honesty note: local wrangler runs on SQLite, which does not enforce
// D1's 100-bound-parameter limit — the limit that made an unbatched mention
// lookup fail on any archive past a hundred memories. The batching cannot be
// proven here to satisfy D1; what is checked is that the batched lookup still
// attaches every mention to the right memory across the batch boundary.
//
// Costs nothing: no AI, no upstream call, only D1 writes into the local
// database. Each run leaves two throwaway members and ~600 rows behind.
//
// Requires a running Worker:
//   cd backend && npx wrangler dev
//
// Usage (from any directory):
//   node scripts/sync-cursor-check.mjs
//   node scripts/sync-cursor-check.mjs http://localhost:8787

import { randomUUID, randomBytes } from 'node:crypto'

const API = process.argv[2] ?? 'http://localhost:8787'
// Each run knocks from an address of its own, so the checks do not spend each
// other's rate-limit allowance. See family-sync-check.mjs for the argument.
//
// Local Workers only: the real Cloudflare edge answers 403 to any request
// that tries to bring its own CF-Connecting-IP, so against production the
// header stays home and the run spends the machine's real allowance — one
// family per run, well under the five a minute the Worker permits.
const household = `10.${(Math.random() * 254) | 0}.${(Math.random() * 254) | 0}.1`
const json = {
	'content-type': 'application/json',
	...(new URL(API).hostname === 'localhost' || new URL(API).hostname === '127.0.0.1'
		? { 'CF-Connecting-IP': household }
		: {}),
}

let failures = 0

function check(what, condition, detail = '') {
	if (condition) {
		console.log(`  ok   ${what}`)
	} else {
		failures += 1
		console.log(`  FAIL ${what}${detail ? ` — ${detail}` : ''}`)
	}
}

function device(name) {
	const memberID = randomUUID()
	const secret = randomBytes(32).toString('hex')
	return { name, memberID, secret, auth: { Authorization: `Bearer ${memberID}.${secret}` } }
}

async function post(path, body, headers = {}) {
	const response = await fetch(`${API}${path}`, {
		method: 'POST',
		headers: { ...json, ...headers },
		body: JSON.stringify(body),
	})
	if (!response.ok) throw new Error(`POST ${path} → ${response.status}`)
	return response.json()
}

async function pullOnce(auth, since) {
	const response = await fetch(`${API}/sync?since=${since}`, { headers: auth })
	if (!response.ok) throw new Error(`GET /sync → ${response.status}`)
	return response.json()
}

/// The client's loop, as the app runs it: pull from the cursor, apply, advance
/// to the reply's cursor, repeat while the server says there is more. The
/// rounds are capped so a cursor that stops making progress fails loudly here
/// instead of spinning.
async function pullAll(auth, since) {
	const collected = { subjects: new Map(), memories: new Map(), cursor: since, rounds: 0 }
	for (let round = 0; round < 30; round += 1) {
		const reply = await pullOnce(auth, collected.cursor)
		for (const row of reply.subjects) collected.subjects.set(row.id, row)
		for (const row of reply.memories) collected.memories.set(row.id, row)
		if (reply.seq <= collected.cursor && reply.more) {
			throw new Error(`the cursor stopped at ${reply.seq} with more=true — no progress`)
		}
		collected.cursor = reply.seq
		collected.rounds = round + 1
		if (!reply.more) return collected
	}
	throw new Error('30 rounds and the server still says more — the cursor is not converging')
}

const grandchild = device('Ville')
const grandmother = device('Aino')
const now = Math.floor(Date.now() / 1000)

const memory = (subjectID, body) => ({
	id: randomUUID(),
	subject_id: subjectID,
	body,
	source: 'typed',
	created_at: now,
})

try {
	// --- Two phones, one family ----------------------------------------------

	await post('/family', {
		memberID: grandchild.memberID,
		secret: grandchild.secret,
		displayName: grandchild.name,
	})
	const invite = await post('/family/invite', {}, grandchild.auth)
	await post('/family/join', {
		memberID: grandmother.memberID,
		secret: grandmother.secret,
		displayName: grandmother.name,
		code: invite.code,
	})

	const photo = randomUUID()
	await post('/sync', {
		subjects: [{ id: photo, kind: 'photo', title: 'Mökin ranta', confirmed: 1, created_at: now }],
	}, grandchild.auth)

	// --- 1. The interleaving that lost a telling ------------------------------
	//
	// He is up to date. She tells something. He opens the app with a change of
	// his own queued — push first, then pull, as the app does. Her telling has
	// a lower number than his push, and a cursor taken from the push reply
	// would exclude it forever. The contract this pins: pulling from the
	// cursor the *pulls* built returns her row.

	let his = await pullAll(grandchild.auth, 0)

	const hers = memory(photo, 'Siinä rannassa istuttiin iltaisin.')
	await post('/sync', { memories: [hers] }, grandmother.auth)

	const hisNext = memory(photo, 'Tämä on se ranta josta mummo puhuu.')
	const pushReply = await post('/sync', { memories: [hisNext] }, grandchild.auth)
	his = await pullAll(grandchild.auth, his.cursor)

	check(
		'a telling pushed while this phone was away arrives on the next pull',
		his.memories.has(hers.id),
		`pulled ${his.memories.size} memories from cursor, push answered seq ${pushReply.seq}`,
	)
	check('the phone also gets its own push echoed back', his.memories.has(hisNext.id))

	// --- 2. Two pushes at once get two numbers --------------------------------
	//
	// The shared number was the concurrent copy of the same blind spot. The
	// reservation is one atomic statement now; two simultaneous pushes must
	// come back with distinct seqs.

	const [a, b] = await Promise.all([
		post('/sync', { memories: [memory(photo, 'Sauna lämpisi joka lauantai.')] }, grandchild.auth),
		post('/sync', { memories: [memory(photo, 'Laituri tehtiin talkoilla.')] }, grandmother.auth),
	])
	check(
		'two simultaneous pushes reserve two different numbers',
		a.seq !== b.seq,
		`both answered seq ${a.seq}`,
	)

	// --- 3. Mentions survive the batch boundary -------------------------------
	//
	// The lookup runs in batches of 100 ids because that is D1's parameter
	// limit; 120 memories force a second batch, and every mention must still
	// land on its own memory.

	const person = randomUUID()
	const told = Array.from({ length: 120 }, (_, i) => ({
		...memory(photo, `Kertomus ${i + 1}.`),
		mentions: [person],
	}))
	await post('/sync', {
		subjects: [{ id: person, kind: 'person', title: 'Aino', confirmed: 0, created_at: now }],
		memories: told,
	}, grandchild.auth)

	const full = await pullAll(grandmother.auth, 0)
	const withMention = told.filter((m) => full.memories.get(m.id)?.mentions?.includes(person))
	check(
		'every mention is attached across the 100-id batch boundary',
		withMention.length === told.length,
		`${withMention.length} of ${told.length} carried the mention`,
	)

	// --- 4. A capped table holds the cursor back ------------------------------
	//
	// Six hundred subjects in two pushes, then a handful of memories with
	// higher numbers. The first pull fills the subject cap at 500; a cursor at
	// the overall maximum would skip the remaining hundred subjects forever.
	// The reply must hold the cursor at what it is complete up to, and the
	// loop must deliver everything.

	const flood = Array.from({ length: 600 }, (_, i) => ({
		id: randomUUID(),
		kind: 'photo',
		title: `Albumin sivu ${i + 1}`,
		confirmed: 1,
		created_at: now,
	}))
	await post('/sync', { subjects: flood.slice(0, 300) }, grandchild.auth)
	await post('/sync', { subjects: flood.slice(300) }, grandchild.auth)
	const late = [memory(photo, 'Viimeisenä kerrottu.'), memory(photo, 'Ja vielä yksi.')]
	await post('/sync', { memories: late }, grandmother.auth)

	const first = await pullOnce(grandmother.auth, 0)
	const firstMax = [...first.subjects, ...first.memories].reduce(
		(max, row) => Math.max(max, row.seq),
		0,
	)
	check(
		'a reply with a capped table says there is more',
		first.subjects.length === 500 && first.more === true,
		`${first.subjects.length} subjects, more=${first.more}`,
	)
	check(
		'the cursor is held back by the capped table, not run to the maximum',
		first.seq < firstMax,
		`reply seq ${first.seq}, highest row seq ${firstMax}`,
	)

	const everything = await pullAll(grandmother.auth, 0)
	const floodArrived = flood.filter((s) => everything.subjects.has(s.id))
	check(
		'every subject beyond the cap arrives on the following rounds',
		floodArrived.length === flood.length,
		`${floodArrived.length} of ${flood.length} arrived in ${everything.rounds} rounds`,
	)
	check(
		'the rows with higher numbers than the cap arrive too',
		late.every((m) => everything.memories.has(m.id)),
	)
} catch (error) {
	failures += 1
	console.log(`  FAIL ${error.message}`)
	console.log(`       Nothing answered at ${API}.`)
	console.log('       cd backend && npx wrangler dev — and if 8787 was already')
	console.log('       taken, wrangler chose another port and said so on its Ready')
	console.log('       line. Pass that url as this script\'s first argument.')
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
