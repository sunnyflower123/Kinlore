#!/usr/bin/env node
// The two doors somebody who was never invited can knock on.
//
// Creating a family and joining one are the only routes in this Worker that
// write to D1 without a member identity, and both are metered per address
// (`worker.ts`): five creations a minute, ten joins. §4 says this was measured
// against a local `wrangler dev` — by hand, once, and a hand-run is not a check:
// it does not run again when somebody edits `wrangler.jsonc`. §1 also lists,
// among the things that were written as done long before they were true, "the
// rate limit that existed only in this document".
//
// So this is that measurement made repeatable, and two properties the hand-run
// did not cover. Four in all, and the middle two are the ones that fail
// silently:
//
// 1. The limit is reached, and the answer is `429 too_many_requests` rather
//    than a crash or a half-created family.
// 2. **It is per address.** Keyed on anything constant, one busy household
//    would lock every other family out of ever being created — and the app
//    is deliberately vague about causes (rule 9), so nobody could diagnose it
//    from the phone.
// 3. **The two doors have separate buckets.** They are two namespaces with two
//    limits; sharing one id would mean a family that has just been created
//    cannot be joined from the same sofa, which is exactly the moment it is
//    joined.
// 4. **Everything behind a session is unmetered.** The limit protects the
//    unauthenticated write, not the family. A grandmother who has told five
//    memories quickly must not be throttled — rule 2.
//
// Costs nothing: no AI, no money. It does create a dozen throwaway families in
// the local D1, which is the point of it.
//
// Requires a running Worker:
//   cd backend && npx wrangler dev
//
//   node scripts/rate-limit-check.mjs

import { randomUUID, randomBytes } from 'node:crypto'

const API = process.argv[2] ?? 'http://localhost:8787'

// Each run knocks from an address of its own, and this script needs two of
// them: one to exhaust and one to prove the exhaustion did not spread. See
// the note in memory-rules-check.mjs — Cloudflare sets `CF-Connecting-IP` from
// the connection itself, so a client cannot do this in production.
const octet = () => (Math.random() * 254) | 0
const busy = `10.${octet()}.${octet()}.1`
const quiet = `10.${octet()}.${octet()}.2`

// From worker.ts / wrangler.jsonc. If these change there, this check should
// fail rather than quietly measure a limit nobody set.
const CREATE_LIMIT = 5

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

async function send(path, from, options = {}) {
	const response = await fetch(`${API}${path}`, {
		...options,
		headers: {
			'content-type': 'application/json',
			'CF-Connecting-IP': from,
			...(options.headers ?? {}),
		},
	})
	return { status: response.status, body: await response.json().catch(() => ({})) }
}

async function createFamily(who, from) {
	return send('/family', from, {
		method: 'POST',
		body: JSON.stringify({
			memberID: who.memberID,
			secret: who.secret,
			displayName: who.name,
			familyName: `${who.name}n perhe`,
		}),
	})
}

try {
	console.log('— the door closes —')
	let first = null
	let refused = null
	{
		const answers = []
		// One more than the limit: the last must be the one that is refused, and
		// the ones before it must all have gone through. A limit that refuses
		// early is as wrong as one that never refuses.
		for (let i = 0; i <= CREATE_LIMIT; i += 1) {
			const who = person(`Koputtaja${i}`)
			const answer = await createFamily(who, busy)
			answers.push(answer.status)
			if (i === 0) first = who
			if (answer.status === 429) refused = i
		}
		check(
			`the first ${CREATE_LIMIT} families are created`,
			answers.slice(0, CREATE_LIMIT).every((s) => s === 200),
			answers.join(' '),
		)
		check(`and the next one is refused`, refused === CREATE_LIMIT, `refused at ${refused}`)
	}
	{
		const { status, body } = await createFamily(person('Vielä yksi'), busy)
		check(
			'with a status and a word, not a crash',
			status === 429 && body.error === 'too_many_requests',
			`${status} ${JSON.stringify(body)}`,
		)
	}

	console.log('— but only for that address —')
	{
		const { status } = await createFamily(person('Toisaalla'), quiet)
		// Keyed on anything constant, this is where every other family in the
		// world stops being able to start one.
		check('somebody else can still start a family', status === 200, String(status))
	}

	console.log('— and the other door has a lock of its own —')
	{
		// The same sofa, seconds later: a family has just been created here and
		// the second phone joins it. One shared namespace id would refuse this.
		const { body: invite } = await send('/family/invite', busy, {
			method: 'POST',
			headers: first.auth,
		})
		const ville = person('Ville')
		const { status } = await send('/family/join', busy, {
			method: 'POST',
			body: JSON.stringify({
				memberID: ville.memberID,
				secret: ville.secret,
				displayName: ville.name,
				code: invite.code,
			}),
		})
		check('joining still works when creating cannot', status === 200, String(status))
	}

	console.log('— and nothing behind a session is metered (rule 2) —')
	{
		const subject = randomUUID()
		const { status } = await send('/sync', busy, {
			method: 'POST',
			headers: first.auth,
			body: JSON.stringify({
				subjects: [{ id: subject, kind: 'person', title: 'Aino', created_at: 0 }],
			}),
		})
		// The limit is on the unauthenticated write, never on the telling. A
		// family that has just used its five creations must still be able to say
		// something.
		check('a member can still tell the archive something', status === 200, String(status))
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
