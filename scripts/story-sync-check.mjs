#!/usr/bin/env node
// The story on a card, on the server's side (ARCHITECTURE §27).
//
// A card's story crosses as one sealed string under one moment, and the
// Worker can read nothing in it — not the text, not which tellings it came
// from, not whether a person corrected it. So it cannot merge two stories;
// it can only keep one. The rule it keeps them by is the face's (§25) and
// the facts' (§26), and every way of breaking it is silent: a card that lost
// its story looks exactly like a card whose story has not been composed yet,
// and the phone would compose it again.
//
// 1. **The story and the moment travel whole**, and come back as they went,
//    on any kind of card.
// 2. **A phone that does not know the field wipes nothing.** It pushes its
//    whole row — a rename, a date — with no story and no moment, and a NULL
//    moment is never later than anything.
// 3. **The newest story wins whole**; an older one, or one under the same
//    moment, changes nothing. A cleared story is a story too, under a newer
//    moment, and an older copy cannot bring the old text back.
// 4. **Junk is no opinion**: a story that is not a string, a moment that is
//    not a number, a story without its moment, a moment without its story,
//    and a story past the cap all leave the row's own alone.
// 5. **A moment ahead of the clock is held to now**, so a phone with a wrong
//    clock cannot lock every other phone out of the card for a year.
//
// Costs nothing: no AI, no key, one throwaway family in the local D1.
//
// Requires a running Worker:
//   cd backend && npx wrangler dev
//
//   node scripts/story-sync-check.mjs [http://localhost:8787]

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

// What the phone actually sends: a sealed story is base64 of nonce,
// ciphertext and tag, and the Worker has no key. Random bytes stand in for it
// here, and the Worker must store them untouched — it has no business
// reading them.
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
			familyName: 'Tarina',
		}),
	})

	// A fraction of a second, because the column is a REAL and the phone's
	// moments are: `withStory` pushes a correction one millisecond past the
	// server's moment, and a column that rounded to the second would keep
	// its own.
	const T = Math.floor(Date.now() / 1000) - 3600 + 0.25
	const photo = randomUUID()
	const row = (more = {}) => ({ id: photo, kind: 'photo', title: 'Mökin laituri', created_at: 0, ...more })
	const story = async (id = photo) => {
		const s = (await subjects(mummo)).get(id)
		return { text: s?.story, at: s?.story_set_at, title: s?.title }
	}

	console.log('— a story under a moment —')
	const first = sealed()
	await push(mummo, [row({ story: first, story_set_at: T })])
	let f = await story()
	check('travels whole: the story and the moment, and comes back untouched, fraction and all', f.text === first && f.at === T, JSON.stringify(f))
	{
		const person = randomUUID()
		await push(mummo, [{ id: person, kind: 'person', title: 'Aino', created_at: 0, story: first, story_set_at: T }])
		const p = await story(person)
		check('on a person as on a photograph — every kind of card has a story', p.text === first && p.at === T, JSON.stringify(p))
	}

	console.log('— an older phone —')
	{
		// A phone that has never seen the field, renaming the card. It sends
		// its whole row, which means neither key.
		await push(mummo, [row({ title: 'Laituri Puumalassa' })])
		f = await story()
		check('a phone that does not know the field renames the card and wipes nothing', f.text === first && f.at === T && f.title === 'Laituri Puumalassa', JSON.stringify(f))
		// And one that knows the field and has nothing: both nulls.
		await push(mummo, [row({ story: null, story_set_at: null })])
		f = await story()
		check('nor does one that sends the pair as nulls', f.text === first && f.at === T, JSON.stringify(f))
		// An older story, arriving late from a phone that was away.
		await push(mummo, [row({ story: sealed(), story_set_at: T - 100 })])
		f = await story()
		check('an older story under an older moment loses', f.text === first && f.at === T, JSON.stringify(f))
		await push(mummo, [row({ story: sealed(), story_set_at: T })])
		f = await story()
		check('and the same moment is not later, so it loses too', f.text === first && f.at === T, JSON.stringify(f))
	}

	console.log('— a newer story —')
	const second = sealed()
	{
		await push(mummo, [row({ story: second, story_set_at: T + 0.001 })])
		f = await story()
		check('a story one millisecond newer replaces the older one whole, with its moment', f.text === second && f.at === T + 0.001, JSON.stringify(f))
		// The phone whose last telling was taken back sends a story with
		// nothing in it, sealed like any other, under a newer moment. To the
		// Worker that is one more newer story, and it must land like any
		// other.
		const cleared = sealed()
		await push(mummo, [row({ story: cleared, story_set_at: T + 120 })])
		f = await story()
		check('and so does the story a phone sends after its tellings were taken back', f.text === cleared && f.at === T + 120, JSON.stringify(f))
		await push(mummo, [row({ story: second, story_set_at: T + 0.001 })])
		f = await story()
		check('which the older story cannot bring back', f.text === cleared && f.at === T + 120, JSON.stringify(f))
	}

	console.log('— what the Worker refuses —')
	{
		const kept = (await story()).text
		const at = (await story()).at
		const unchanged = async (what) => {
			const now = await story()
			check(what, now.text === kept && now.at === at, JSON.stringify(now))
		}
		await push(mummo, [row({ story: 12345, story_set_at: T + 600 })])
		await unchanged('a story that is not a string is no opinion')
		await push(mummo, [row({ story: { text: 'Mummo kertoo' }, story_set_at: T + 600 })])
		await unchanged('nor is a story sent as an object, which a phone with no key would have to have written in the clear')
		await push(mummo, [row({ story: sealed(), story_set_at: 'now' })])
		await unchanged('a moment that is not a number is no opinion')
		await push(mummo, [row({ story: sealed() })])
		await unchanged('a story without its moment is no opinion')
		await push(mummo, [row({ story_set_at: T + 600 })])
		await unchanged('a moment without its story is no opinion')
		await push(mummo, [row({ story: 'x'.repeat(131_073), story_set_at: T + 600 })])
		await unchanged('a story past the cap is no opinion')
	}

	console.log('— a wrong clock —')
	{
		const ahead = sealed()
		await push(mummo, [row({ story: ahead, story_set_at: T + 10_000_000 })])
		f = await story()
		check('a moment in the future lands, held to now, so it cannot lock out every later story', f.text === ahead && f.at <= Math.floor(Date.now() / 1000) + 1 && f.at > T + 120, JSON.stringify(f))
		// Held to now is held to the Worker's second, and a push in the same
		// second is held to the same one — not later, so it loses. The next
		// phone with the right time writes a second later, and its moment is
		// then later than the one the clock was held to.
		await new Promise((resolve) => setTimeout(resolve, 1100))
		const after = sealed()
		await push(mummo, [row({ story: after, story_set_at: Date.now() / 1000 })])
		f = await story()
		check('and the next phone with the right time, a second later, still writes', f.text === after, JSON.stringify(f))
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
