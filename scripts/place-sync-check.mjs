#!/usr/bin/env node
// Checks what sync does to a place's coordinates.
//
// The rule is one sentence — the coordinates answer the title, so they follow
// it — and three cases fall out of it that are easy to break later and silent
// when broken: a device that has not looked a name up must not wipe what
// another one resolved, a corrected title must not keep the old point, and a
// client must not be able to write a coordinate that is not one.
//
// Silent is the operative word. Every one of these failures leaves a working
// app: memories still sync, places still open, and the only evidence is a point
// on a map that nobody has built yet. That is exactly the kind of bug this
// project keeps finding by reading a promise and checking the code under it —
// see the warning in docs/ARCHITECTURE.md §1.
//
// Costs nothing: no AI, no upstream call, only D1 writes into the local
// database. Each run leaves one throwaway family behind.
//
// Requires a running Worker:
//   cd backend && npx wrangler dev
//
// Usage (from any directory):
//   node scripts/place-sync-check.mjs
//   node scripts/place-sync-check.mjs http://localhost:8787

import { randomUUID, randomBytes } from 'node:crypto'

const API = process.argv[2] ?? 'http://localhost:8787'

const memberID = randomUUID()
const secret = randomBytes(32).toString('hex')
const auth = { Authorization: `Bearer ${memberID}.${secret}` }
// Every check knocks on the same two unauthenticated doors, and creating a
// family is limited to five a minute per address (worker.ts). Seven scripts run
// back to back in verify.sh and between them they create eleven families, so
// they were starving each other: whichever ran last failed with "could not
// create a family: 429", which reads like a broken Worker and is not one.
//
// So each run knocks from an address of its own — against a local Worker
// only. This comment used to claim the real edge "ignores what the client
// sends"; measured 24 Aug 2026, it does not ignore it, it answers 403 to the
// whole request. So against anything but localhost the header stays home and
// the run spends the machine's real allowance — one family per run, well
// under the limit.
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

async function post(path, body, headers = {}) {
	const response = await fetch(`${API}${path}`, {
		method: 'POST',
		headers: { ...json, ...headers },
		body: JSON.stringify(body),
	})
	if (!response.ok) throw new Error(`POST ${path} → ${response.status}`)
	return response.json()
}

/// Pushes one subject and reads it straight back. The read is a full pull from
/// zero rather than a lookup, because that is the path the app actually uses.
async function push(subject) {
	await post('/sync', { subjects: [subject] }, auth)
}

async function pull(id) {
	const response = await fetch(`${API}/sync?since=0`, { headers: auth })
	if (!response.ok) throw new Error(`GET /sync → ${response.status}`)
	const body = await response.json()
	return body.subjects.find((s) => s.id === id)
}

const now = Math.floor(Date.now() / 1000)
const base = { kind: 'place', confirmed: 1, created_at: now }

try {
	await post('/family', {
		memberID,
		secret,
		displayName: 'Place sync check',
		familyName: 'Place sync check',
	})

	// 1. A resolved point survives the round trip at all.
	const id = randomUUID()
	await push({ ...base, id, title: 'Puumala', lat: 61.524, lon: 28.185, geo_precision: 'town' })
	let row = await pull(id)
	check(
		'a looked-up point comes back from the server',
		row?.lat === 61.524 && row?.lon === 28.185 && row?.geo_precision === 'town',
		JSON.stringify({ lat: row?.lat, lon: row?.lon, geo_precision: row?.geo_precision }),
	)

	// 2. The device that has not looked it up sends nulls. It must not win:
	//    every other phone in the family would lose the answer.
	await push({ ...base, id, title: 'Puumala' })
	row = await pull(id)
	check(
		'a device with no coordinates does not wipe the ones another device found',
		row?.lat === 61.524 && row?.lon === 28.185,
		JSON.stringify({ lat: row?.lat, lon: row?.lon }),
	)

	// 3. The name was misheard and has been corrected. The old point is now an
	//    answer to a question nobody asked — and a wrong place reads as a fact.
	await push({ ...base, id, title: 'Sortavala' })
	row = await pull(id)
	check(
		'correcting the title clears the point that answered the old name',
		row?.lat === null && row?.lon === null && row?.geo_precision === null,
		JSON.stringify({ title: row?.title, lat: row?.lat, lon: row?.lon }),
	)

	// 4. Not a coordinate. A client is not trusted here, because this value is
	//    eventually drawn on a map and a NaN has no shape on one.
	const bad = randomUUID()
	await push({
		...base,
		id: bad,
		title: 'Roskaa',
		lat: 91,
		lon: 500,
		geo_precision: 'kunta',
	})
	row = await pull(bad)
	check(
		'an out-of-range coordinate is refused rather than stored',
		row?.lat === null && row?.lon === null && row?.geo_precision === null,
		JSON.stringify({ lat: row?.lat, lon: row?.lon, geo_precision: row?.geo_precision }),
	)

	// 5. Half a point is not half a location, it is a point off the coast of
	//    Ghana. Both halves or neither.
	const half = randomUUID()
	await push({ ...base, id: half, title: 'Puolikas', lat: 61.524 })
	row = await pull(half)
	check(
		'a latitude with no longitude is refused',
		row?.lat === null && row?.lon === null,
		JSON.stringify({ lat: row?.lat, lon: row?.lon }),
	)
} catch (error) {
	failures += 1
	console.log(`  FAIL ${error.message}`)
	console.log('       Is the Worker running? cd backend && npx wrangler dev')
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
