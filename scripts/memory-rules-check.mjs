#!/usr/bin/env node
// What sync is allowed to do to a memory that already exists.
//
// One `ON CONFLICT DO UPDATE` in `backend/src/sync.ts` carries most of this
// repo's promises about the telling itself, and nothing ran any of them.
// `family-sync-check.mjs` walks the happy path — two phones, one family, a
// memory crossing between them. This one is about the second push of the same
// memory, which is where all the damage lives.
//
// 1. **Rule 3.** The original audio and the raw transcript are always kept.
//    They are `COALESCE`d, so a device that no longer holds them cannot strip
//    them by pushing the same row again — and the author's *other* phone is
//    exactly such a device, pushing under the same Keychain identity.
// 2. **An empty body never overwrites a real one** (§16). The audio is saved
//    first and the text follows; the untranscribed copy must not unwrite it.
// 3. **A memory with audio and no text is a memory.** Refusing it was the quiet
//    half of the §16 bug: the client cleared its outbox all the same, and the
//    recording stayed on one phone for ever.
// 4. **The author comes from the session, not from the payload.** A client must
//    not be able to say that grandmother told something.
// 5. **Only the author edits their own.** Being in the family is not permission
//    to rewrite what somebody else said, even by accident.
// 6. **A deletion is final.** A stale push cannot bring back what a person
//    chose to take away.
//
// Every one of them is silent. A stripped transcript, a rewritten sentence, a
// memory that came back from the dead — the app looks exactly the same
// afterwards, and the person who could say otherwise is often the reason this
// archive exists.
//
// Costs nothing: no AI, no money, one throwaway family in the local D1.
//
// Requires a running Worker:
//   cd backend && npx wrangler dev
//
//   node scripts/memory-rules-check.mjs

import { randomUUID, randomBytes } from 'node:crypto'

// Against the deployed Worker — first production run 6 Sep 2026, 14/14, the
// evening the move rule was deployed. Leaves one throwaway family behind.
//
//   node scripts/memory-rules-check.mjs https://memorize.arkiste.workers.dev
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
// `CF-Connecting-IP` from the connection and ignores what the client sends. It
// does not: the edge refuses the request outright with `403 error code: 1000`
// before the Worker is reached — measured on the invite check on 29 Aug 2026,
// and this script carried the same false sentence until it was pointed at
// production on 6 Sep 2026. Against production the run pays the real rate
// limit, which one family and two joins fit inside.
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

function person(name) {
	const memberID = randomUUID()
	const secret = randomBytes(32).toString('hex')
	return { name, memberID, secret, auth: { Authorization: `Bearer ${memberID}.${secret}` } }
}

async function send(path, options = {}) {
	const response = await fetch(`${API}${path}`, options)
	return { status: response.status, body: await response.json().catch(() => ({})) }
}

async function push(who, payload) {
	return send('/sync', {
		method: 'POST',
		headers: { ...json, ...who.auth },
		body: JSON.stringify(payload),
	})
}

/// Everything the family has, by memory id.
async function memories(who) {
	const { body } = await send('/sync?since=0', { headers: who.auth })
	return new Map((body.memories ?? []).map((m) => [m.id, m]))
}

const now = Math.floor(Date.now() / 1000)

try {
	const mummo = person('Mummo')
	await send('/family', {
		method: 'POST',
		headers: json,
		body: JSON.stringify({
			memberID: mummo.memberID,
			secret: mummo.secret,
			displayName: mummo.name,
			familyName: 'Muistisäännöt',
		}),
	})

	const subject = randomUUID()
	await push(mummo, { subjects: [{ id: subject, kind: 'person', title: 'Aino', created_at: now }] })

	const told = randomUUID()
	const spoken = 'Aino asui Karjalassa ennen sotaa.'
	const heard = 'aino asu karjalassa ennen sotaa'
	const audio = `family/x/${randomUUID()}.m4a`

	console.log('— what was said comes back —')
	{
		await push(mummo, {
			memories: [
				{
					id: told,
					subject_id: subject,
					body: spoken,
					raw_transcript: heard,
					audio_r2_key: audio,
					audio_seconds: 12,
					source: 'spoken',
					created_at: now,
				},
			],
		})
		const m = (await memories(mummo)).get(told)
		check('the telling is stored', m?.body === spoken, JSON.stringify(m?.body))
		check(
			'with the recording and the words as they were heard',
			m?.raw_transcript === heard && m?.audio_r2_key === audio,
			JSON.stringify({ raw: m?.raw_transcript, audio: m?.audio_r2_key }),
		)
	}

	console.log('— and nothing later takes them away (rule 3) —')
	{
		// The author's other phone: same identity, same memory, and it never had
		// the transcript. It must not be able to unwrite what it does not know.
		await push(mummo, {
			memories: [
				{
					id: told,
					subject_id: subject,
					body: spoken,
					raw_transcript: null,
					audio_r2_key: null,
					created_at: now,
				},
			],
		})
		const m = (await memories(mummo)).get(told)
		check(
			'a push without them does not strip them',
			m?.raw_transcript === heard && m?.audio_r2_key === audio,
			JSON.stringify({ raw: m?.raw_transcript, audio: m?.audio_r2_key }),
		)
	}
	{
		await push(mummo, {
			memories: [{ id: told, subject_id: subject, body: '', audio_r2_key: audio, created_at: now }],
		})
		const m = (await memories(mummo)).get(told)
		check('and an empty text does not overwrite a real one', m?.body === spoken, JSON.stringify(m?.body))
	}

	console.log('— a recording with no text is still a memory (§16) —')
	{
		const untranscribed = randomUUID()
		await push(mummo, {
			memories: [
				{
					id: untranscribed,
					subject_id: subject,
					body: '',
					audio_r2_key: `family/x/${randomUUID()}.m4a`,
					audio_seconds: 30,
					source: 'spoken',
					created_at: now,
				},
			],
		})
		const kept = (await memories(mummo)).has(untranscribed)
		// Refusing this row is what left a recording on one phone for ever: the
		// client had already cleared its outbox.
		check('the family receives it before the words arrive', kept)
	}
	{
		const nothing = randomUUID()
		await push(mummo, {
			memories: [{ id: nothing, subject_id: subject, body: '', created_at: now }],
		})
		check('but neither text nor sound is not a memory', !(await memories(mummo)).has(nothing))
	}

	console.log('— and nobody speaks for somebody else —')
	{
		const claimed = randomUUID()
		await push(mummo, {
			memories: [
				{
					id: claimed,
					subject_id: subject,
					// A claim, not a fact. The server takes the author from the
					// session and ignores this.
					author_id: randomUUID(),
					body: 'Minä muka sanoin tämän.',
					created_at: now,
				},
			],
		})
		const m = (await memories(mummo)).get(claimed)
		check(
			'the author is whoever the session is',
			m?.author_id === mummo.memberID,
			JSON.stringify(m?.author_id),
		)
	}
	{
		// Ville is family. He still does not get to tidy up what Mummo said —
		// and the refusal is silent by design, so only the row can show it.
		const { body: invite } = await send('/family/invite', { method: 'POST', headers: mummo.auth })
		const ville = person('Ville')
		await send('/family/join', {
			method: 'POST',
			headers: json,
			body: JSON.stringify({
				memberID: ville.memberID,
				secret: ville.secret,
				displayName: ville.name,
				code: invite.code,
			}),
		})
		await push(ville, {
			memories: [
				{ id: told, subject_id: subject, body: 'Ei se noin mennyt.', created_at: now },
			],
		})
		const m = (await memories(mummo)).get(told)
		check(
			'another member of the family cannot rewrite it',
			m?.body === spoken,
			JSON.stringify(m?.body),
		)
		check('nor take the telling for himself', m?.author_id === mummo.memberID, JSON.stringify(m?.author_id))
	}

	console.log('— a telling can be moved to another card, by its teller —')
	{
		// The AI filed it under the wrong place; the teller moves it. Ville,
		// who is family, does not get to move it back — the same author rule
		// as the words, and the refusal is as silent.
		const elsewhere = randomUUID()
		await push(mummo, {
			subjects: [{ id: elsewhere, kind: 'place', title: 'Sortavala', created_at: now }],
		})
		await push(mummo, {
			memories: [{ id: told, subject_id: elsewhere, body: spoken, created_at: now }],
		})
		let m = (await memories(mummo)).get(told)
		check('the teller moves it', m?.subject_id === elsewhere, JSON.stringify(m?.subject_id))
		check('and the words travel with it unchanged', m?.body === spoken, JSON.stringify(m?.body))
		// A second member, invited for this: the one above lives in its own
		// block, and a code admits one person.
		const { body: invite } = await send('/family/invite', { method: 'POST', headers: mummo.auth })
		const toinen = person('Toinen')
		await send('/family/join', {
			method: 'POST',
			headers: json,
			body: JSON.stringify({
				memberID: toinen.memberID,
				secret: toinen.secret,
				displayName: toinen.name,
				code: invite.code,
			}),
		})
		await push(toinen, {
			memories: [{ id: told, subject_id: subject, body: spoken, created_at: now }],
		})
		m = (await memories(mummo)).get(told)
		check('another member cannot move it back', m?.subject_id === elsewhere, JSON.stringify(m?.subject_id))
	}

	console.log('— the names in a telling are a set, not a pile —')
	{
		// `INSERT OR IGNORE INTO mention` only ever added, and the client
		// treats `mentions` as a list it replaces. So a name could be put on a
		// telling and never taken off it, and the two corrections that exist
		// to take one off both quietly failed (found 10 Sep 2026):
		//
		//   - "ei tuo Matti" (`MemoryStore.split`) points the telling at a
		//     fresh card. The server kept the old row, the pull handed back
		//     both, and `applyRemote` overwrote the local list with the pair —
		//     so the telling named the two people the correction exists to
		//     tell apart, on every phone including the one that corrected it.
		//   - A rename that merges two cards left the telling naming the
		//     tombstone and the survivor at once.
		//
		// Both are silent in this repo's usual way: the app draws a name, and
		// the name is wrong in the direction rule 4 cares about most.
		const [aino, puumala, matti, toinenMatti] = [
			randomUUID(), randomUUID(), randomUUID(), randomUUID(),
		]
		await push(mummo, {
			subjects: [
				{ id: aino, kind: 'person', title: 'Aino', created_at: now },
				{ id: puumala, kind: 'place', title: 'Puumala', created_at: now },
				{ id: matti, kind: 'person', title: 'Matti', created_at: now },
				{ id: toinenMatti, kind: 'person', title: 'Matti', created_at: now },
			],
		})

		const named = randomUUID()
		const mentionsOf = async (id) => ((await memories(mummo)).get(id)?.mentions ?? []).sort()
		await push(mummo, {
			memories: [
				{
					id: named,
					subject_id: subject,
					body: 'Aino ja Matti olivat Puumalassa.',
					mentions: [aino, matti, puumala],
					created_at: now,
				},
			],
		})
		check(
			'a telling arrives with everyone it named',
			(await mentionsOf(named)).join() === [aino, matti, puumala].sort().join(),
			JSON.stringify(await mentionsOf(named)),
		)

		// The correction itself: Matti becomes the other Matti, and the first
		// one is no longer in the telling at all.
		await push(mummo, {
			memories: [
				{
					id: named,
					subject_id: subject,
					body: 'Aino ja Matti olivat Puumalassa.',
					mentions: [aino, toinenMatti, puumala],
					created_at: now,
				},
			],
		})
		const afterSplit = await mentionsOf(named)
		check(
			'"ei tuo Matti" puts the new card in',
			afterSplit.includes(toinenMatti),
			JSON.stringify(afterSplit),
		)
		check(
			'and takes the old one out, which is the whole correction',
			!afterSplit.includes(matti),
			JSON.stringify(afterSplit),
		)
		check(
			'while everybody the telling still names stays',
			afterSplit.includes(aino) && afterSplit.includes(puumala),
			JSON.stringify(afterSplit),
		)

		// A push that says nothing about the names is not a push that says
		// there are none: the field is optional, and an older client does not
		// send it.
		await push(mummo, {
			memories: [
				{ id: named, subject_id: subject, body: 'Aino ja Matti olivat Puumalassa.', created_at: now },
			],
		})
		check(
			'a push with no mentions field leaves them alone',
			(await mentionsOf(named)).length === 3,
			JSON.stringify(await mentionsOf(named)),
		)

		// The removal is a write like any other, so it is the author's alone.
		// Without this the DELETE would be a way for anybody in the family to
		// strip the names off what somebody else told — silently, and worse
		// than the bug it replaced.
		const { body: invite } = await send('/family/invite', { method: 'POST', headers: mummo.auth })
		const kolmas = person('Kolmas')
		await send('/family/join', {
			method: 'POST',
			headers: json,
			body: JSON.stringify({
				memberID: kolmas.memberID,
				secret: kolmas.secret,
				displayName: kolmas.name,
				code: invite.code,
			}),
		})
		await push(kolmas, {
			memories: [
				{ id: named, subject_id: subject, body: 'Aino ja Matti olivat Puumalassa.', mentions: [], created_at: now },
			],
		})
		check(
			'another member cannot strip the names off it',
			(await mentionsOf(named)).length === 3,
			JSON.stringify(await mentionsOf(named)),
		)
	}

	console.log('— a push is capped, and the cap is a number two files share —')
	// LOCAL ONLY, and the reason is a cost rather than a risk.
	//
	// This case writes 500 rows to prove that the 505 it offered were sliced,
	// and in a local database that is a throwaway file. Run against
	// production on 12 Sep 2026 it put 500 `Ylivuoto` subjects into the real
	// D1 and took it from 532 kB to 733 kB — inside a throwaway family and
	// invisible to every real one, but junk that then had to be deleted by
	// hand from the database this project's whole recovery story is about.
	// The case was written for `verify.sh` and its production cost was not
	// thought about.
	//
	// Nothing is lost by skipping it there: `MAX_ROWS` is a constant in
	// sync.ts, not a fact about a deployment, so the local run measures the
	// same slice the deployed Worker performs. That is not true of the
	// mention cases above — those are SQL, and D1 enforces a
	// hundred-bound-parameter limit local SQLite does not — which is why
	// those still run everywhere and this one does not.
	if (!isLocalWorker) {
		console.log('  skip  the 500-row cap — local only, it would leave 500 rows behind')
	} else {
		// `MAX_ROWS` in sync.ts slices every table of a push and writes no
		// more. `MemoryStore.maxRowsPerPush` on the Swift side offers no more
		// than that for exactly this reason: until 10 Sep 2026 the client
		// offered its whole outbox, the server sliced the overflow away
		// without saying so, and `clearPending` emptied the outbox of the rows
		// that were never stored. An archive opened to a family for the first
		// time is the case that overflows, and every row in it is the only
		// copy.
		//
		// The Swift half cannot be checked from here — MemoryStore.swift
		// imports UIKit and does not compile into a harness. This pins the
		// number it has to agree with, so a change on one side has something
		// to fail against.
		const MAX_ROWS = 500
		const overflowing = Array.from({ length: MAX_ROWS + 5 }, () => randomUUID())
		await push(mummo, {
			subjects: overflowing.map((id) => ({
				id, kind: 'person', title: 'Ylivuoto', created_at: now,
			})),
		})
		// Paged, because the pull caps a reply at the same number: asking once
		// would count the reply's cap rather than what was written, and the
		// check would pass for the wrong reason.
		const stored = new Set()
		let since = 0
		for (let page = 0; page < 10; page += 1) {
			const { body } = await send(`/sync?since=${since}`, { headers: mummo.auth })
			for (const s of body.subjects ?? []) stored.add(s.id)
			since = body.seq
			if (!body.more) break
		}
		const arrived = overflowing.filter((id) => stored.has(id)).length
		check(
			`a push of ${MAX_ROWS + 5} rows stores exactly ${MAX_ROWS} of them`,
			arrived === MAX_ROWS,
			`${arrived} arrived`,
		)
	}

	console.log('— and what was taken away stays away —')
	{
		await push(mummo, {
			memories: [
				{ id: told, subject_id: subject, body: spoken, deleted_at: now, created_at: now },
			],
		})
		const deleted = (await memories(mummo)).get(told)
		check('a telling can be taken back', Boolean(deleted?.deleted_at), JSON.stringify(deleted?.deleted_at))

		// A phone that was offline when it happened, pushing the version it still
		// has. The rejection is a decision, and an old copy does not overrule it.
		await push(mummo, {
			memories: [
				{ id: told, subject_id: subject, body: spoken, deleted_at: null, created_at: now },
			],
		})
		const after = (await memories(mummo)).get(told)
		check(
			'and a phone that missed it cannot bring it back',
			Boolean(after?.deleted_at),
			JSON.stringify(after?.deleted_at),
		)
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
