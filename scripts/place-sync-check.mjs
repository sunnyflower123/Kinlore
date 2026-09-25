#!/usr/bin/env node
// Checks what sync does to a place's coordinates.
//
// The rule is one sentence — the coordinates answer the title, so they follow
// it — and four cases fall out of it that are easy to break later and silent
// when broken: a device that has not looked a name up must not wipe what
// another one resolved, a coarser answer must not displace the point a person
// placed by hand, a corrected title must not keep the old point, and a client
// must not be able to write a coordinate that is not one.
//
// Since 25 Sep 2026 that sentence covers a lookup's answer and nothing else.
// A point somebody in the family put on the map carries who and when
// (`geo_confirmed_by`, `geo_confirmed_at`), and it is their word rather than a
// cache of anything, so it follows the colours' rule instead: only a newer
// word moves it. Cases 8–16 are what that means — it survives lookups, older
// phones and a corrected title, it can be taken off the map for good, its
// moment cannot be set in the future, and a phone can repeat somebody else's
// word only where the server already holds it: on the same place, or on one
// merged into it.
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
// A second member of the same family, for the word that one phone repeats on
// another member's behalf (cases 10, 15 and 16) and the one it may not.
const second = { memberID: randomUUID(), secret: randomBytes(32).toString('hex') }
const secondAuth = { Authorization: `Bearer ${second.memberID}.${second.secret}` }
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

/// The fields these checks are about, for a failure's detail: the member by
/// role rather than by id, and the moment relative to the run.
function where(row) {
	const who = { [memberID]: 'owner', [second.memberID]: 'second member' }
	return JSON.stringify({
		title: row?.title,
		lat: row?.lat,
		lon: row?.lon,
		precision: row?.geo_precision,
		by: who[row?.geo_confirmed_by] ?? row?.geo_confirmed_by,
		at: typeof row?.geo_confirmed_at === 'number' ? row.geo_confirmed_at - now : row?.geo_confirmed_at,
		name: row?.geo_confirmed_by_name,
	})
}

try {
	await post('/family', {
		memberID,
		secret,
		displayName: 'Place sync check',
		familyName: 'Place sync check',
	})
	const { code } = await post('/family/invite', {}, auth)
	await post('/family/join', {
		memberID: second.memberID,
		secret: second.secret,
		displayName: 'Place sync check, second phone',
		code,
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

	// 6. A point somebody in the family placed by hand (`PlacePinSheet`) is
	//    `exact`, and every other phone is still holding the municipality the
	//    gazetteer answered with. Those phones push their copy with the next
	//    thing anybody changes about the place, so without a rule the family's
	//    own point is replaced by the circle it was placed to correct — and
	//    nothing on any screen would say so.
	//
	//    Re-placing the mark is the case that must keep working: that is
	//    `exact` over `exact`, and the newer push wins.
	const pinned = randomUUID()
	await push({ ...base, id: pinned, title: 'Koivula', lat: 61.5, lon: 28.1, geo_precision: 'town' })
	await push({ ...base, id: pinned, title: 'Koivula', lat: 61.512, lon: 28.134, geo_precision: 'exact' })
	await push({ ...base, id: pinned, title: 'Koivula', lat: 61.5, lon: 28.1, geo_precision: 'town' })
	row = await pull(pinned)
	check(
		'a looked-up circle does not displace a point the family placed by hand',
		row?.lat === 61.512 && row?.lon === 28.134 && row?.geo_precision === 'exact',
		JSON.stringify({ lat: row?.lat, lon: row?.lon, geo_precision: row?.geo_precision }),
	)

	await push({ ...base, id: pinned, title: 'Koivula', lat: 61.513, lon: 28.135, geo_precision: 'exact' })
	row = await pull(pinned)
	check(
		'the mark can be moved again once it has been placed',
		row?.lat === 61.513 && row?.lon === 28.135,
		JSON.stringify({ lat: row?.lat, lon: row?.lon }),
	)

	// 7. And the correction rule still outranks an exact point with nobody's
	//    word on it — what a build from before 25 Sep 2026 sends for a mark it
	//    placed, and what a street address the gazetteer resolved looks like.
	//    Nothing here can tell those two apart, so both answer the name they
	//    were found under. A point with a name on it is case 10's.
	await push({ ...base, id: pinned, title: 'Koivumäki' })
	row = await pull(pinned)
	check(
		'correcting the title clears an exact point nobody put their name to',
		row?.lat === null && row?.lon === null && row?.geo_precision === null,
		JSON.stringify({ title: row?.title, lat: row?.lat, lon: row?.lon }),
	)

	// 8. A point with somebody's word on it comes back with the word: who,
	//    when, and the name the panel under the map says ("Vahvisti …"),
	//    which the server derives from the member rather than taking from
	//    the phone.
	const home = randomUUID()
	const placed = {
		lat: 61.6,
		lon: 28.2,
		geo_precision: 'exact',
		geo_confirmed_by: memberID,
		geo_confirmed_at: now - 60,
	}
	await push({ ...base, id: home, title: 'Mummola', ...placed })
	row = await pull(home)
	check(
		'a point somebody placed comes back with who placed it and when',
		row?.lat === 61.6 &&
			row?.lon === 28.2 &&
			row?.geo_precision === 'exact' &&
			row?.geo_confirmed_by === memberID &&
			row?.geo_confirmed_at === now - 60 &&
			row?.geo_confirmed_by_name === 'Place sync check',
		where(row),
	)

	// 9. Every other phone still holds the municipality the gazetteer
	//    answered, and an older build sends a mark as a bare `exact` with
	//    nobody's name on it. Neither is a word, so neither moves one — and
	//    the second is exactly what the rule in case 6 lets through, exact
	//    over exact.
	await push({ ...base, id: home, title: 'Mummola', lat: 61.5, lon: 28.1, geo_precision: 'town' })
	row = await pull(home)
	check(
		'a looked-up circle does not displace a point somebody placed',
		row?.lat === 61.6 && row?.lon === 28.2 && row?.geo_precision === 'exact' && row?.geo_confirmed_at === now - 60,
		where(row),
	)
	await push({ ...base, id: home, title: 'Mummola', lat: 61.7, lon: 28.3, geo_precision: 'exact' })
	row = await pull(home)
	check(
		"nor does an exact point with nobody's word on it",
		row?.lat === 61.6 && row?.lon === 28.2 && row?.geo_confirmed_at === now - 60,
		where(row),
	)

	// 10. The title is corrected. A phone of the old build clears its own copy
	//     and sends nothing; one of the new build keeps the point and sends
	//     the whole row, somebody else's word included. That second push is
	//     the everyday relay — any phone that touches the place repeats the
	//     pair it pulled — and the place it repeats it on is the proof.
	await push({ ...base, id: home, title: 'Mummon talo' })
	row = await pull(home)
	check(
		'correcting the title keeps a point somebody placed',
		row?.title === 'Mummon talo' && row?.lat === 61.6 && row?.lon === 28.2 && row?.geo_confirmed_by === memberID,
		where(row),
	)
	await post('/sync', { subjects: [{ ...base, id: home, title: 'Mummola', ...placed }] }, secondAuth)
	row = await pull(home)
	check(
		'and another member correcting it back carries the word on unchanged',
		row?.title === 'Mummola' &&
			row?.lat === 61.6 &&
			row?.geo_confirmed_by === memberID &&
			row?.geo_confirmed_at === now - 60,
		where(row),
	)

	// 11. Placed again, later: the newer word wins. And a word from before
	//     that arrives late — a phone that was offline when it placed the
	//     mark — does not undo what the family said since.
	await push({ ...base, id: home, title: 'Mummola', ...placed, lat: 61.61, lon: 28.21, geo_confirmed_at: now - 30 })
	row = await pull(home)
	check(
		'a newer word moves the point',
		row?.lat === 61.61 && row?.lon === 28.21 && row?.geo_confirmed_at === now - 30,
		where(row),
	)
	await push({ ...base, id: home, title: 'Mummola', ...placed, lat: 61.62, lon: 28.22, geo_confirmed_at: now - 45 })
	row = await pull(home)
	check(
		'an older word arriving late does not',
		row?.lat === 61.61 && row?.lon === 28.21 && row?.geo_confirmed_at === now - 30,
		where(row),
	)

	// 12. Taken off the map: `unknown` under a word, with the coordinates kept,
	//     because the pair is both-or-neither and the phone's `PlaceHint`
	//     always holds one. Nothing draws `unknown`, nothing looks it up again,
	//     and a phone that has not heard yet, still holding the circle, must
	//     not put the place back.
	await push({
		...base,
		id: home,
		title: 'Mummola',
		lat: 61.61,
		lon: 28.21,
		geo_precision: 'unknown',
		geo_confirmed_by: memberID,
		geo_confirmed_at: now - 10,
	})
	await push({ ...base, id: home, title: 'Mummola', lat: 61.5, lon: 28.1, geo_precision: 'town' })
	row = await pull(home)
	check(
		'a place taken off the map stays off it',
		row?.geo_precision === 'unknown' && row?.geo_confirmed_at === now - 10,
		where(row),
	)

	// 13. A phone whose clock runs ten years fast would otherwise hold the
	//     place for ten years, because no honest word could ever be newer.
	//     The moment is capped at the server's own clock, and a word said a
	//     second later still wins.
	const fast = randomUUID()
	await push({
		...base,
		id: fast,
		title: 'Kellokas',
		lat: 61.7,
		lon: 28.4,
		geo_precision: 'exact',
		geo_confirmed_by: memberID,
		geo_confirmed_at: now + 10 * 365 * 86400,
	})
	row = await pull(fast)
	check(
		"a moment in the future is capped at the server's clock",
		typeof row?.geo_confirmed_at === 'number' && row.geo_confirmed_at <= Math.floor(Date.now() / 1000),
		where(row),
	)
	await new Promise((resolve) => setTimeout(resolve, 1100))
	await push({
		...base,
		id: fast,
		title: 'Kellokas',
		lat: 61.71,
		lon: 28.41,
		geo_precision: 'exact',
		geo_confirmed_by: memberID,
		geo_confirmed_at: Math.floor(Date.now() / 1000),
	})
	row = await pull(fast)
	check('and a word said a second later still moves the point', row?.lat === 61.71 && row?.lon === 28.41, where(row))

	// 14. A new word in somebody else's name. The owner's phone says the second
	//     member placed this, with a pair no row holds, and the server keeps
	//     only what it can vouch for: a point, with nobody's name on it.
	const forged = randomUUID()
	await push({
		...base,
		id: forged,
		title: 'Väärä nimi',
		lat: 61.8,
		lon: 28.5,
		geo_precision: 'exact',
		geo_confirmed_by: second.memberID,
		geo_confirmed_at: now - 5,
	})
	row = await pull(forged)
	check(
		"a new word in somebody else's name is not taken as theirs",
		row?.geo_confirmed_by === null && row?.geo_confirmed_at === null,
		where(row),
	)

	// 15. A merge on the second member's phone: "Mökki" was a mishearing of
	//     "Kesämökki", and the owner had placed Mökki by hand. The phone moves
	//     the word to the card that stays (`MemoryStore.rename`) and sends it
	//     in the same push as the tombstone. The server holds the pair, on a
	//     row merged into this one in that push, so it carries the word on —
	//     with the point from that row, not whatever the phone sent beside it.
	const misheard = randomUUID()
	const kept = randomUUID()
	const mokki = {
		lat: 61.9,
		lon: 28.6,
		geo_precision: 'exact',
		geo_confirmed_by: memberID,
		geo_confirmed_at: now - 20,
	}
	await push({ ...base, id: misheard, title: 'Mökki', ...mokki })
	await push({ ...base, id: kept, title: 'Kesämökki', lat: 61.5, lon: 28.1, geo_precision: 'town' })
	await post(
		'/sync',
		{
			subjects: [
				{ ...base, id: misheard, title: 'Mökki', merged_into: kept, ...mokki },
				{ ...base, id: kept, title: 'Kesämökki', ...mokki, lat: 61.95, lon: 28.65 },
			],
		},
		secondAuth,
	)
	row = await pull(kept)
	check(
		'a merge carries the word to the card that stays, from any phone',
		row?.geo_confirmed_by === memberID &&
			row?.geo_confirmed_at === now - 20 &&
			row?.geo_confirmed_by_name === 'Place sync check',
		where(row),
	)
	check(
		'with the point the word was about, not the one sent beside it',
		row?.lat === 61.9 && row?.lon === 28.6 && row?.geo_precision === 'exact',
		where(row),
	)

	//     And when the two travel in separate pushes — an outbox longer than
	//     one push carries — the tombstone the server already holds is proof
	//     enough.
	const misheard2 = randomUUID()
	const kept2 = randomUUID()
	const rantala = { ...mokki, lat: 62.0, lon: 28.7, geo_confirmed_at: now - 25 }
	await push({ ...base, id: misheard2, title: 'Rantala', ...rantala })
	await push({ ...base, id: kept2, title: 'Rantalahti' })
	await post('/sync', { subjects: [{ ...base, id: misheard2, title: 'Rantala', merged_into: kept2, ...rantala }] }, secondAuth)
	await post('/sync', { subjects: [{ ...base, id: kept2, title: 'Rantalahti', ...rantala }] }, secondAuth)
	row = await pull(kept2)
	check(
		'and so does a merge whose tombstone arrived in an earlier push',
		row?.geo_confirmed_by === memberID && row?.geo_confirmed_at === now - 25 && row?.lat === 62,
		where(row),
	)

	// 16. The same pair on a place that has nothing to do with it. The pair is
	//     real — the server holds it, on Mökki and now on Kesämökki — but a
	//     word about Mökki is not a word about the neighbour's yard, and
	//     carrying it there would let any member sign anybody's name under
	//     any point.
	const unrelated = randomUUID()
	await post(
		'/sync',
		{ subjects: [{ ...base, id: unrelated, title: 'Naapuri', ...mokki, lat: 61.4, lon: 28.0 }] },
		secondAuth,
	)
	row = await pull(unrelated)
	check(
		'a real pair on an unrelated place is not taken as a word',
		row?.geo_confirmed_by === null && row?.geo_confirmed_at === null,
		where(row),
	)
} catch (error) {
	failures += 1
	console.log(`  FAIL ${error.message}`)
	if (/→ 5\d\d$/.test(error.message)) {
		// Something answered, and it was the Worker failing. The usual reason
		// is a local database older than schema.sql — a column added since it
		// was created — which the Worker's own log names ("no column named").
		console.log(`       The Worker at ${API} answered with an error.`)
		console.log('       A local database older than schema.sql is the usual cause:')
		console.log('       compare PRAGMA table_info(subject) with the ALTERs in schema.sql.')
	} else {
		console.log(`       Nothing answered at ${API}.`)
		console.log('       cd backend && npx wrangler dev — and if 8787 was already')
		console.log('       taken, wrangler chose another port and said so on its Ready')
		console.log('       line. Pass that url as this script\'s first argument.')
	}
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
