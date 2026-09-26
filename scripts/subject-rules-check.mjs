#!/usr/bin/env node
// What sync is allowed to do to a subject that already exists.
//
// The companion to `memory-rules-check.mjs`, and it exists because writing that
// one turned up a real defect rather than a missing test. A phone pushes its
// **whole local row**, always — `Subject.dto` in `MemoryStore+Sync.swift` fills
// every field from local state — so a device that has never seen a date sends
// three nulls with it. Until 16 Aug 2026 the subject upsert assigned those
// straight over the top, while the coordinates beside them were carefully
// protected. Measured against a running Worker: a place kept its point and lost
// "joskus viisikymmentäluvulla" the moment anybody on an older copy renamed it.
//
// That is rule 5 — uncertainty is stored, not rounded — losing its subject
// matter in the one way nobody would notice. A place with no date looks like a
// place nobody dated.
//
// The four rules in that statement, all silent when broken:
//
// 1. **A date survives a push from a device that has none.** The `date_precision`
//    the pushing row carries is the signal that it has an opinion at all.
// 2. **But "en tiedä" is an opinion.** A deliberately cleared date sends
//    `unknown` and does clear it, on every phone. Otherwise the cleared date
//    comes back from somebody's older copy on the next sync, for ever.
// 3. **Confirmation is one-way** (`MAX`). A week-old device must not turn a
//    confirmed person back into a proposal — rule 4 says a wrong relationship
//    is worse than a missing one, and an unconfirmed one is not a wrong one.
// 4. **A merge is sticky**, and so is a deletion. Undoing either would need an
//    operation that does not exist.
//
// Costs nothing: no AI, no money, one throwaway family in the local D1.
//
// Requires a running Worker:
//   cd backend && npx wrangler dev
//
//   node scripts/subject-rules-check.mjs

import { randomUUID, randomBytes } from 'node:crypto'

const API = process.argv[2] ?? 'http://localhost:8787'
// An address of its own — see the note in memory-rules-check.mjs. Local
// Workers only, as in place-sync-check.mjs: the real edge answers 403 to any
// request that brings its own `CF-Connecting-IP`.
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

// 1950 to 1959, which is what "joskus viisikymmentäluvulla" actually means.
const FIFTIES_START = -631152000
const FIFTIES_END = -315619201

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
			familyName: 'Subjektisäännöt',
		}),
	})

	const place = randomUUID()

	console.log('— a date somebody was careful about (rule 5) —')
	{
		await push(mummo, [
			{
				id: place,
				kind: 'place',
				title: 'Kuusamo',
				lat: 65.96,
				lon: 29.18,
				geo_precision: 'town',
				date_start: FIFTIES_START,
				date_end: FIFTIES_END,
				date_precision: 'decade',
				created_at: 0,
			},
		])
		const s = (await subjects(mummo)).get(place)
		check(
			'is stored as the ten years it covers',
			s?.date_start === FIFTIES_START && s?.date_end === FIFTIES_END,
			JSON.stringify({ start: s?.date_start, end: s?.date_end }),
		)
		check('at the precision that was meant', s?.date_precision === 'decade', s?.date_precision)
	}
	{
		// The phone that has never seen the date, renaming the place. It sends
		// its whole row, which means three nulls where the date is.
		await push(mummo, [{ id: place, kind: 'place', title: 'Kuusamon mökki', created_at: 0 }])
		const s = (await subjects(mummo)).get(place)
		check(
			'and an older phone renaming it does not erase it',
			s?.date_start === FIFTIES_START && s?.date_precision === 'decade',
			JSON.stringify({ start: s?.date_start, precision: s?.date_precision }),
		)
		check('though the rename itself lands', s?.title === 'Kuusamon mökki', s?.title)
	}
	{
		// The other half, and the reason the fix is not simply "never overwrite":
		// somebody looked at the date and said they do not know after all.
		await push(mummo, [
			{
				id: place,
				kind: 'place',
				title: 'Kuusamon mökki',
				date_start: null,
				date_end: null,
				date_precision: 'unknown',
				created_at: 0,
			},
		])
		const s = (await subjects(mummo)).get(place)
		check(
			'but somebody saying "en tiedä" is heard',
			s?.date_start === null && s?.date_precision === 'unknown',
			JSON.stringify({ start: s?.date_start, precision: s?.date_precision }),
		)
	}
	{
		await push(mummo, [{ id: place, kind: 'place', title: 'Kuusamon mökki', created_at: 0 }])
		const s = (await subjects(mummo)).get(place)
		check(
			'and stays heard, rather than being answered again by an old copy',
			s?.date_precision === 'unknown',
			JSON.stringify({ precision: s?.date_precision }),
		)
	}

	console.log('— and the three that were already right —')
	const person = randomUUID()
	{
		await push(mummo, [
			{ id: person, kind: 'person', title: 'Aino', confirmed: 1, created_at: 0 },
		])
		// Rule 4 the other way round: a device that was offline while the family
		// confirmed her must not put the question mark back.
		await push(mummo, [
			{ id: person, kind: 'person', title: 'Aino', confirmed: 0, created_at: 0 },
		])
		const s = (await subjects(mummo)).get(person)
		check('a confirmed person cannot be unconfirmed by an old copy', s?.confirmed === 1, String(s?.confirmed))
	}
	{
		const duplicate = randomUUID()
		await push(mummo, [
			{ id: duplicate, kind: 'person', title: 'Aino Virtanen', merged_into: person, created_at: 0 },
		])
		await push(mummo, [
			{ id: duplicate, kind: 'person', title: 'Aino Virtanen', merged_into: null, created_at: 0 },
		])
		const s = (await subjects(mummo)).get(duplicate)
		check('a merge is not undone by a device that missed it', s?.merged_into === person, String(s?.merged_into))
	}
	{
		const rejected = randomUUID()
		await push(mummo, [{ id: rejected, kind: 'person', title: 'Ei kukaan', deleted_at: 1, created_at: 0 }])
		await push(mummo, [{ id: rejected, kind: 'person', title: 'Ei kukaan', deleted_at: null, created_at: 0 }])
		const s = (await subjects(mummo)).get(rejected)
		check('and neither is a rejection', Boolean(s?.deleted_at), String(s?.deleted_at))
	}

	console.log('— a colouring the family said yes to —')
	{
		// Every object this family owns lives under its id, and a yes may only
		// point at one of those.
		const familyID = (await send('/family', { headers: mummo.auth })).body.id
		const own = (name) => `${familyID}/${name}.jpg`
		const photo = randomUUID()
		// An hour ago, so that every moment below is safely in the past.
		const T = Math.floor(Date.now() / 1000) - 3600
		const yes = (key, at, by = memberID) => ({
			id: photo,
			kind: 'photo',
			title: '',
			r2_key: own('photo'),
			colour_r2_key: key,
			colour_confirmed_by: by,
			colour_confirmed_at: at,
			created_at: 0,
		})
		const colours = async () => {
			const s = (await subjects(mummo)).get(photo)
			return {
				key: s?.colour_r2_key,
				by: s?.colour_confirmed_by,
				at: s?.colour_confirmed_at,
				name: s?.colour_confirmed_by_name,
				title: s?.title,
			}
		}

		await push(mummo, [yes(own('colour-1'), T)])
		let c = await colours()
		check(
			'travels whole: the file, the name and the moment',
			c.key === own('colour-1') && c.by === memberID && c.at === T,
			JSON.stringify(c),
		)
		check("and the name is read from the family, like a telling's author's", c.name === 'Mummo', String(c.name))

		// A phone that has never seen the colouring, naming the photograph.
		await push(mummo, [{ id: photo, kind: 'photo', title: 'Mökin ranta', r2_key: own('photo'), created_at: 0 }])
		c = await colours()
		check(
			'an older phone naming the photograph does not take the colours away',
			c.key === own('colour-1') && c.title === 'Mökin ranta',
			JSON.stringify(c),
		)

		await push(mummo, [yes(own('colour-0'), T - 600)])
		c = await colours()
		check('an older yes arriving late does not replace a newer one', c.key === own('colour-1'), JSON.stringify(c))

		await push(mummo, [yes(own('colour-2'), T + 600)])
		c = await colours()
		check('a newer yes does', c.key === own('colour-2') && c.at === T + 600, JSON.stringify(c))

		await push(mummo, [yes(own('colour-3'), T + 1200, randomUUID())])
		c = await colours()
		check(
			"nobody can put another member's name on a yes",
			c.key === own('colour-2') && c.by === memberID,
			JSON.stringify(c),
		)

		await push(mummo, [yes(`${randomUUID()}/colour-4.jpg`, T + 1800)])
		c = await colours()
		check("nor point one at another family's objects", c.key === own('colour-2'), JSON.stringify(c))

		await push(mummo, [yes(own('colour-5'), T + 10 * 365 * 86_400)])
		c = await colours()
		check(
			'a moment in the future is held to now, so it cannot lock out every later yes',
			c.key === own('colour-5') && c.at <= Math.floor(Date.now() / 1000) + 1,
			JSON.stringify(c),
		)

		const somebody = randomUUID()
		await push(mummo, [
			{
				id: somebody,
				kind: 'person',
				title: 'Eeva',
				colour_r2_key: own('colour-6'),
				colour_confirmed_by: memberID,
				colour_confirmed_at: T,
				created_at: 0,
			},
		])
		const eeva = (await subjects(mummo)).get(somebody)
		check('and only a photograph has colours to confirm', eeva?.colour_r2_key === null, String(eeva?.colour_r2_key))
	}

	console.log('— a face on a person\'s card —')
	{
		// A choice is a photograph of this family and a point in it under a
		// moment; a removal is the same choice with no photograph. Every rule
		// below is silent when broken: a face that quietly falls off a card
		// looks exactly like a card nobody chose a face for.
		const T = Math.floor(Date.now() / 1000) - 3600
		const photo1 = randomUUID()
		const photo2 = randomUUID()
		const person = randomUUID()
		const picture = (id, more = {}) => ({ id, kind: 'photo', title: '', created_at: 0, ...more })
		const choice = (photoID, at, more = {}) => ({
			id: person,
			kind: 'person',
			title: 'Kalle',
			portrait_subject_id: photoID,
			portrait_focus_x: 0.4,
			portrait_focus_y: 0.3,
			portrait_set_at: at,
			created_at: 0,
			...more,
		})
		const face = async (id = person) => {
			const s = (await subjects(mummo)).get(id)
			return { photo: s?.portrait_subject_id, x: s?.portrait_focus_x, y: s?.portrait_focus_y, at: s?.portrait_set_at, title: s?.title }
		}

		// The person and the photograph in one request, the person first: the
		// Worker has to put the photograph in before it looks it up.
		await push(mummo, [choice(photo1, T), picture(photo1)])
		let f = await face()
		check(
			'travels whole: the photograph, the point and the moment, even when the photograph arrives in the same request behind it',
			f.photo === photo1 && f.x === 0.4 && f.y === 0.3 && f.at === T,
			JSON.stringify(f),
		)

		// A phone that has never seen the face, renaming the person.
		await push(mummo, [{ id: person, kind: 'person', title: 'Kalle Kustaa', created_at: 0 }])
		f = await face()
		check(
			'an older phone renaming the person does not take the face away',
			f.photo === photo1 && f.title === 'Kalle Kustaa',
			JSON.stringify(f),
		)

		await push(mummo, [picture(photo2)])
		await push(mummo, [choice(photo2, T - 600)])
		f = await face()
		check('an older choice arriving late does not replace a newer one', f.photo === photo1, JSON.stringify(f))

		await push(mummo, [choice(photo2, T + 600)])
		f = await face()
		check('a newer choice does', f.photo === photo2 && f.at === T + 600, JSON.stringify(f))

		await push(mummo, [choice(null, T + 1200)])
		f = await face()
		check('a removal is a choice too, and travels', f.photo === null && f.at === T + 1200, JSON.stringify(f))

		await push(mummo, [choice(photo2, T + 600)])
		f = await face()
		check('and the phone that chose the face, pushing its row again, does not bring it back', f.photo === null, JSON.stringify(f))

		await push(mummo, [choice(randomUUID(), T + 1800)])
		f = await face()
		check('a photograph the family does not have is no opinion, and changes nothing', f.photo === null && f.at === T + 1200, JSON.stringify(f))

		// Another family's photograph, which is a real row in the same table.
		const strangerID = randomUUID()
		const strangerSecret = randomBytes(32).toString('hex')
		const stranger = { auth: { Authorization: `Bearer ${strangerID}.${strangerSecret}` } }
		await send('/family', {
			method: 'POST',
			headers: json,
			body: JSON.stringify({ memberID: strangerID, secret: strangerSecret, displayName: 'Vieras', familyName: 'Toinen perhe' }),
		})
		const theirs = randomUUID()
		await push(stranger, [picture(theirs)])
		await push(mummo, [choice(theirs, T + 1800)])
		f = await face()
		check("nor may it be another family's photograph", f.photo === null && f.at === T + 1200, JSON.stringify(f))

		await push(mummo, [choice(person, T + 1800)])
		f = await face()
		check('nor a person', f.photo === null && f.at === T + 1200, JSON.stringify(f))

		await push(mummo, [picture(photo1, { deleted_at: T })])
		await push(mummo, [choice(photo1, T + 1800)])
		f = await face()
		check('nor a photograph the family has rejected', f.photo === null && f.at === T + 1200, JSON.stringify(f))

		await push(mummo, [choice(photo2, T + 2400, { portrait_focus_x: 1.4, portrait_focus_y: -2 })])
		f = await face()
		check('a point outside the picture is stored as none, and the face stays', f.photo === photo2 && f.x === null && f.y === null, JSON.stringify(f))

		await push(mummo, [choice(photo2, T + 10 * 365 * 86_400)])
		f = await face()
		check(
			'a moment in the future is held to now, so it cannot lock out every later choice',
			f.at <= Math.floor(Date.now() / 1000) + 1 && f.at > T + 2400,
			JSON.stringify(f),
		)

		// Last, because after this photo2 can be chosen by nobody.
		await push(mummo, [picture(photo2, { deleted_at: T })])
		f = await face()
		check(
			'a photograph rejected after it was chosen stays on the row: the decision is recorded, and the phone draws the initial',
			f.photo === photo2,
			JSON.stringify(f),
		)

		await push(mummo, [picture(randomUUID(), { portrait_subject_id: photo2, portrait_focus_x: 0.5, portrait_focus_y: 0.5, portrait_set_at: T })])
		const faces = [...(await subjects(mummo)).values()].filter((s) => s.kind === 'photo' && s.portrait_subject_id !== null)
		check('and only a person has a face', faces.length === 0, `${faces.length} photographs carry one`)
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
