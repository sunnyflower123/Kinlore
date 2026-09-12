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
// An address of its own — see the note in memory-rules-check.mjs.
const household = `10.${(Math.random() * 254) | 0}.${(Math.random() * 254) | 0}.1`
const json = { 'content-type': 'application/json', 'CF-Connecting-IP': household }

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
