#!/usr/bin/env node
// Checks the path the whole app is built on: two phones, one family.
//
// A grandchild creates the archive and sends a link. Grandmother opens it and
// is in. She tells something; it appears on his phone. That sentence is the
// product, it is phase C of the plan, and PLAN.md §5 says that if it does not
// work the demo falls back to a family seeded by hand — so it is worth knowing
// which of those two worlds we are in, on demand, in four seconds.
//
// Every check here is silent when it breaks. A join that quietly lands in a
// family of its own still shows a working app: memories save, screens fill,
// and the only symptom is a family that never sees each other's memories and
// has no way to find out why. The same is true of an invite that stays usable
// after somebody has taken it back — the invite link is the entire security
// boundary (docs/ARCHITECTURE.md §4), and "Poista" on that row is the only
// control over it.
//
// What it does NOT cover: the screens. Creating a family and joining are two
// taps in an app, and nothing here presses them — this measures the contract
// underneath, which is the half that cannot be checked by looking.
//
// Costs nothing: no AI, no upstream call, only D1 writes into the local
// database. Each run leaves two throwaway members behind.
//
// Requires a running Worker:
//   cd backend && npx wrangler dev
//
// Usage (from any directory):
//   node scripts/family-sync-check.mjs
//   node scripts/family-sync-check.mjs http://localhost:8787

import { randomUUID, randomBytes } from 'node:crypto'

const API = process.argv[2] ?? 'http://localhost:8787'
// Every check knocks on the same two unauthenticated doors, and creating a
// family is limited to five a minute per address (worker.ts). Seven scripts run
// back to back in verify.sh and between them they create eleven families, so
// they were starving each other: whichever ran last failed with "could not
// create a family: 429", which reads like a broken Worker and is not one.
//
// So each local run knocks from an address of its own.
//
// **Local only.** The sentence that stood here said Cloudflare sets
// `CF-Connecting-IP` from the connection and ignores what the client sends.
// It does not: the edge refuses the request outright with `403 error code:
// 1000` before the Worker is reached — measured on the invite check on 29 Aug
// 2026, and this script carried the same false sentence until it was pointed
// at production on 6 Sep 2026 for the rename. Against production the run
// pays the real rate limit, which one family and one join fit inside.
//
//   node scripts/family-sync-check.mjs https://memorize.arkiste.workers.dev
const isLocalWorker = /^https?:\/\/(localhost|127\.0\.0\.1)\b/.test(API)
const household = `10.${(Math.random() * 254) | 0}.${(Math.random() * 254) | 0}.1`
const json = {
	'content-type': 'application/json',
	...(isLocalWorker ? { 'CF-Connecting-IP': household } : {}),
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

/// A phone: an identity in its own Keychain, and the header that proves it.
function device(name) {
	const memberID = randomUUID()
	const secret = randomBytes(32).toString('hex')
	return {
		name,
		memberID,
		auth: { Authorization: `Bearer ${memberID}.${secret}` },
		secret,
	}
}

async function post(path, body, headers = {}) {
	const response = await fetch(`${API}${path}`, {
		method: 'POST',
		headers: { ...json, ...headers },
		body: JSON.stringify(body),
	})
	const text = await response.text()
	return { status: response.status, body: text ? JSON.parse(text) : {} }
}

async function get(path, headers) {
	const response = await fetch(`${API}${path}`, { headers })
	if (!response.ok) throw new Error(`GET ${path} → ${response.status}`)
	return response.json()
}

async function del(path, headers) {
	const response = await fetch(`${API}${path}`, { method: 'DELETE', headers })
	return { status: response.status, body: await response.json().catch(() => ({})) }
}

const grandchild = device('Ville')
const grandmother = device('Aino')
const now = Math.floor(Date.now() / 1000)

try {
	// --- He creates the archive ---------------------------------------------

	const created = await post('/family', {
		memberID: grandchild.memberID,
		secret: grandchild.secret,
		displayName: grandchild.name,
		familyName: '',
	})
	check('a family can be created at all', created.status === 200, JSON.stringify(created.body))

	const invite = await post('/family/invite', {}, grandchild.auth)
	check('the archive hands out an invite code', Boolean(invite.body?.code), JSON.stringify(invite.body))

	// He puts a photo and a memory of his own into it, so that there is
	// something for her to arrive to. An empty family proves less: a join can
	// land in the wrong family and still look right when there is nothing in
	// either of them.
	const photo = randomUUID()
	const his = randomUUID()
	await post(
		'/sync',
		{
			subjects: [{ id: photo, kind: 'photo', title: 'Mökin ranta', confirmed: 1, created_at: now }],
			memories: [
				{
					id: his,
					subject_id: photo,
					author_name: grandchild.name,
					body: 'Tämä on se ranta josta mummo aina puhuu.',
					source: 'typed',
					created_at: now,
				},
			],
		},
		grandchild.auth,
	)

	// --- She opens the link --------------------------------------------------

	const joined = await post('/family/join', {
		memberID: grandmother.memberID,
		secret: grandmother.secret,
		displayName: grandmother.name,
		code: invite.body.code,
	})
	check('the link lets a second phone in', joined.status === 200, JSON.stringify(joined.body))

	// The one that is silent when it breaks. A join that creates a family of
	// its own answers 200 and looks perfect from both ends until somebody
	// notices, months later, that nothing has ever crossed between them.
	const hersFromServer = await get('/sync?since=0', grandmother.auth)
	check(
		'she lands in his family and not one of her own',
		hersFromServer.memories?.some((m) => m.id === his),
		`saw ${hersFromServer.memories?.length ?? 0} memories`,
	)
	check(
		"his memory arrives with his name on it",
		hersFromServer.memories?.find((m) => m.id === his)?.author_name === grandchild.name,
		JSON.stringify(hersFromServer.memories?.find((m) => m.id === his)?.author_name),
	)

	// --- He changes his own name ---------------------------------------------
	//
	// The name lives on the member row and every telling's author is read
	// from it, so one change reaches every memory he ever told, on her phone
	// too, on her next pull. Nothing wrote this column after the join until
	// 6 Sep 2026.
	{
		const response = await fetch(`${API}/family/me`, {
			method: 'PATCH',
			headers: { ...json, ...grandchild.auth },
			body: JSON.stringify({ displayName: '  Ville-pappa  ' }),
		})
		const renamed = await response.json().catch(() => ({}))
		check('a member can change their own name', response.status === 200, JSON.stringify(renamed))
		check('and it is stored trimmed', renamed.displayName === 'Ville-pappa', JSON.stringify(renamed))
		const family = await get('/family', grandmother.auth)
		check(
			'the family sees the new name',
			family.members?.some((m) => m.displayName === 'Ville-pappa'),
			JSON.stringify(family.members?.map((m) => m.displayName)),
		)
		const pulled = await get('/sync?since=0', grandmother.auth)
		check(
			'and his old telling now carries it',
			pulled.memories?.find((m) => m.id === his)?.author_name === 'Ville-pappa',
			JSON.stringify(pulled.memories?.find((m) => m.id === his)?.author_name),
		)
		const empty = await fetch(`${API}/family/me`, {
			method: 'PATCH',
			headers: { ...json, ...grandchild.auth },
			body: JSON.stringify({ displayName: '   ' }),
		})
		check('an empty name is refused', empty.status === 400, `answered ${empty.status}`)
		grandchild.name = 'Ville-pappa'
	}

	// --- She tells something -------------------------------------------------

	const hers = randomUUID()
	await post(
		'/sync',
		{
			memories: [
				{
					id: hers,
					subject_id: photo,
					author_name: grandmother.name,
					body: 'Siinä rannassa istuttiin iltaisin kun oli hiljaista.',
					source: 'voice',
					created_at: now + 1,
				},
			],
		},
		grandmother.auth,
	)

	const hisFromServer = await get('/sync?since=0', grandchild.auth)
	check(
		'what she tells reaches his phone',
		hisFromServer.memories?.some((m) => m.id === hers),
		`saw ${hisFromServer.memories?.length ?? 0} memories`,
	)
	check(
		'both memories hang on the same photo',
		hisFromServer.memories?.filter((m) => m.subject_id === photo).length === 2,
		JSON.stringify(hisFromServer.memories?.map((m) => m.subject_id)),
	)

	// The family screen is the only visibility anybody has into the boundary,
	// so it has to show her arrival.
	const family = await get('/family', grandchild.auth)
	check(
		'the family screen sees both of them',
		family.members?.length === 2 &&
			family.members.some((m) => m.displayName === grandmother.name),
		JSON.stringify(family.members?.map((m) => m.displayName)),
	)

	// --- Taking the invite back ----------------------------------------------

	// "Poista" on the invite row is the only control over the boundary §4 calls
	// the whole of it. A revoke that does not revoke leaves a link working
	// somewhere in a message thread, and nothing on any screen would say so.
	const revoked = await del(`/family/invite?code=${encodeURIComponent(invite.body.code)}`, grandchild.auth)
	check('an invite can be taken back', revoked.status === 200, JSON.stringify(revoked.body))

	const stranger = device('Kolmas')
	const refused = await post('/family/join', {
		memberID: stranger.memberID,
		secret: stranger.secret,
		displayName: stranger.name,
		code: invite.body.code,
	})
	check(
		'a taken-back invite no longer lets anybody in',
		refused.status !== 200,
		`join answered ${refused.status}`,
	)

	const guesser = device('Arvaaja')
	const wrong = await post('/family/join', {
		memberID: guesser.memberID,
		secret: guesser.secret,
		displayName: guesser.name,
		code: 'ei-tallainen-koodi',
	})
	check('a made-up code does not open a family', wrong.status !== 200, `join answered ${wrong.status}`)
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
