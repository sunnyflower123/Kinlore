#!/usr/bin/env node
// The facts on a person's card, on the server's side (ARCHITECTURE §26).
//
// A person's facts cross as one sealed list under one moment, and the Worker
// can read nothing in the list — not a name, not a trade, not which place a
// birth points at. So it cannot merge two lists; it can only keep one. The
// rule it keeps them by is the face's (§25), and every way of breaking it is
// silent: a card that lost its facts looks exactly like a card nobody wrote
// any on.
//
// 1. **The list and the moment travel whole**, and come back as they went.
// 2. **A phone that does not know the field wipes nothing.** It pushes its
//    whole row — a rename, a confirmation — with no list and no moment, and
//    a NULL moment is never later than anything.
// 3. **The newest list wins whole**; an older one, or one under the same
//    moment, changes nothing.
// 4. **Junk is no opinion**: a list that is not a string, a moment that is not
//    a number, a list without its moment, a moment without its list, a list
//    past the cap, and facts on anything but a person all leave the row's
//    own list alone.
// 5. **A moment ahead of the clock is held to now**, so a phone with a wrong
//    clock cannot lock every other phone out of the card for a year.
//
// Costs nothing: no AI, no key, one throwaway family in the local D1.
//
// Requires a running Worker:
//   cd backend && npx wrangler dev
//
//   node scripts/facts-sync-check.mjs [http://localhost:8787]

import { randomUUID, randomBytes } from 'node:crypto'

const API = process.argv[2] ?? 'http://localhost:8787'
// An address of its own — see the note in memory-rules-check.mjs. Local
// Workers only: the real edge answers 403 to any request that brings its own
// `CF-Connecting-IP`.
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

async function send(path, options = {}) {
	const response = await fetch(`${API}${path}`, options)
	return { status: response.status, body: await response.json().catch(() => ({})) }
}

async function push(who, subjects) {
	return send('/sync', {
		method: 'POST',
		headers: { ...json, ...who.auth },
		body: JSON.stringify({ subjects }),
	})
}

async function subjects(who) {
	const { body } = await send('/sync?since=0', { headers: who.auth })
	return new Map((body.subjects ?? []).map((s) => [s.id, s]))
}

// What the phone actually sends: a sealed list is base64 of nonce, ciphertext
// and tag, and the Worker has no key. Random bytes stand in for it here, and
// the Worker must store them untouched — it has no business reading them.
const sealed = () => randomBytes(48).toString('base64')

try {
	const memberID = randomUUID()
	const secret = randomBytes(32).toString('hex')
	const mummo = { auth: { Authorization: `Bearer ${memberID}.${secret}` } }
	await send('/family', {
		method: 'POST',
		headers: json,
		body: JSON.stringify({
			memberID,
			secret,
			displayName: 'Mummo',
			familyName: 'Tiedot',
		}),
	})

	const T = Math.floor(Date.now() / 1000) - 3600
	const person = randomUUID()
	const row = (more = {}) => ({ id: person, kind: 'person', title: 'Eeva', created_at: 0, ...more })
	const facts = async (id = person) => {
		const s = (await subjects(mummo)).get(id)
		return { list: s?.facts, at: s?.facts_set_at, title: s?.title }
	}

	console.log('— a list under a moment —')
	const first = sealed()
	await push(mummo, [row({ facts: first, facts_set_at: T })])
	let f = await facts()
	check('travels whole: the list and the moment, and comes back untouched', f.list === first && f.at === T, JSON.stringify(f))

	console.log('— an older phone —')
	{
		// A phone that has never seen the field, renaming the person. It sends
		// its whole row, which means neither key.
		await push(mummo, [row({ title: 'Eeva Virtanen' })])
		f = await facts()
		check('a phone that does not know the field renames the person and wipes nothing', f.list === first && f.at === T && f.title === 'Eeva Virtanen', JSON.stringify(f))
		// And one that knows the field and has nothing: both nulls.
		await push(mummo, [row({ facts: null, facts_set_at: null })])
		f = await facts()
		check('nor does one that sends the pair as nulls', f.list === first && f.at === T, JSON.stringify(f))
		// An older list, arriving late from a phone that was away.
		await push(mummo, [row({ facts: sealed(), facts_set_at: T - 100 })])
		f = await facts()
		check('an older list under an older moment loses', f.list === first && f.at === T, JSON.stringify(f))
		await push(mummo, [row({ facts: sealed(), facts_set_at: T })])
		f = await facts()
		check('and the same moment is not later, so it loses too', f.list === first && f.at === T, JSON.stringify(f))
	}

	console.log('— a newer list —')
	const second = sealed()
	{
		await push(mummo, [row({ facts: second, facts_set_at: T + 60 })])
		f = await facts()
		check('a newer list replaces the older one whole, with its moment', f.list === second && f.at === T + 60, JSON.stringify(f))
		// The phone that took every fact off the card still sends a list — of
		// tombstones — under a newer moment. To the Worker that is one more
		// newer list, and it must land like any other.
		const cleared = sealed()
		await push(mummo, [row({ facts: cleared, facts_set_at: T + 120 })])
		f = await facts()
		check('and so does the list a phone sends after taking every fact off', f.list === cleared && f.at === T + 120, JSON.stringify(f))
		await push(mummo, [row({ facts: second, facts_set_at: T + 60 })])
		f = await facts()
		check('which the older list cannot bring back', f.list === cleared && f.at === T + 120, JSON.stringify(f))
	}

	console.log('— what the Worker refuses —')
	{
		const kept = (await facts()).list
		const at = (await facts()).at
		const unchanged = async (what) => {
			const now = await facts()
			check(what, now.list === kept && now.at === at, JSON.stringify(now))
		}
		await push(mummo, [row({ facts: 12345, facts_set_at: T + 600 })])
		await unchanged('a list that is not a string is no opinion')
		await push(mummo, [row({ facts: { birth: 1932 }, facts_set_at: T + 600 })])
		await unchanged('nor is a list sent as an object, which a phone with no key would have to have written in the clear')
		await push(mummo, [row({ facts: sealed(), facts_set_at: 'now' })])
		await unchanged('a moment that is not a number is no opinion')
		await push(mummo, [row({ facts: sealed() })])
		await unchanged('a list without its moment is no opinion')
		await push(mummo, [row({ facts_set_at: T + 600 })])
		await unchanged('a moment without its list is no opinion')
		await push(mummo, [row({ facts: 'x'.repeat(65_537), facts_set_at: T + 600 })])
		await unchanged('a list past the cap is no opinion')
		const photo = randomUUID()
		await push(mummo, [{ id: photo, kind: 'photo', title: '', created_at: 0, facts: sealed(), facts_set_at: T + 600 }])
		const p = await facts(photo)
		check('and only a person has facts', p.list === null && p.at === null, JSON.stringify(p))
	}

	console.log('— a wrong clock —')
	{
		const ahead = sealed()
		await push(mummo, [row({ facts: ahead, facts_set_at: T + 10_000_000 })])
		f = await facts()
		check('a moment in the future lands, held to now, so it cannot lock out every later list', f.list === ahead && f.at <= Math.floor(Date.now() / 1000) + 1 && f.at > T + 120, JSON.stringify(f))
		// Held to now is held to the Worker's second, and a push in the same
		// second is held to the same one — not later, so it loses. The next
		// phone with the right time writes a second later, and its moment is
		// then later than the one the clock was held to. Measured 26 Sep
		// 2026: without the wait this line was the check's one red.
		await new Promise((resolve) => setTimeout(resolve, 1100))
		const after = sealed()
		await push(mummo, [row({ facts: after, facts_set_at: Math.floor(Date.now() / 1000) })])
		f = await facts()
		check('and the next phone with the right time, a second later, still writes', f.list === after, JSON.stringify(f))
	}
} catch (error) {
	failures += 1
	console.log(`\n  FAIL ${error.message}`)
	console.log(`       Nothing answered at ${API}.`)
	console.log('       cd backend && npx wrangler dev — and if 8787 was already')
	console.log('       taken, wrangler chose another port and said so on its Ready')
	console.log('       line. Pass that url as this script\'s first argument.')
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
