#!/usr/bin/env node
// What the free tier counts, and the one thing it must never stop.
//
// Rule 2 is the shortest rule this app has: **telling is never paywalled.** The
// quota limits photographs and AI minutes; it does not limit the act of saying
// something. Rule 3 stands behind it — a recording made with the minutes gone is
// kept and transcribed later, never rejected.
//
// Nothing has ever checked either of them. `scripts/` has had no quota check at
// all, and the inventory in ARCHITECTURE §1 said "Done and tested" — the exact
// shape of claim that section's own warning is about.
//
// Every failure here is silent. A counter that never resets locks a family out
// of transcription for ever and shows no error anywhere; a limit that blocks
// `/sync` turns the one rule this app promises out loud into a lie, on the day
// a family happens to reach twenty photographs.
//
// Costs nothing: no AI call, no upstream request, no money. The minutes are put
// where they need to be with a direct D1 write rather than by spending them —
// buying a real quota failure would cost ten minutes of transcription.
//
// Requires a running Worker:
//   cd backend && npx wrangler dev
//
//   node scripts/quota-check.mjs
//   KINLORE_WORKER_DIR=/path/to/backend node scripts/quota-check.mjs http://localhost:8788

import { randomUUID, randomBytes } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname, join as joinPath } from 'node:path'

const API = process.argv[2] ?? 'http://localhost:8787'
const backend =
	process.env.KINLORE_WORKER_DIR ??
	joinPath(dirname(fileURLToPath(import.meta.url)), '..', 'backend')

const memberID = randomUUID()
const secret = randomBytes(32).toString('hex')
const auth = { Authorization: `Bearer ${memberID}.${secret}` }
// Every check knocks on the same two unauthenticated doors, and creating a
// family is limited to five a minute per address (worker.ts). Seven scripts run
// back to back in verify.sh and between them they create eleven families, so
// they were starving each other: whichever ran last failed with "could not
// create a family: 429", which reads like a broken Worker and is not one.
//
// So each run knocks from an address of its own. Cloudflare sets
// `CF-Connecting-IP` from the connection itself and ignores what the client
// sends, so this changes nothing in production — it only stops the checks from
// spending each other's allowance locally.
const household = `10.${(Math.random() * 254) | 0}.${(Math.random() * 254) | 0}.1`
const json = { 'content-type': 'application/json', 'CF-Connecting-IP': household }

let failures = 0
let familyID = ''

function check(what, condition, detail = '') {
	if (condition) {
		console.log(`  ok   ${what}`)
	} else {
		failures += 1
		console.log(`  FAIL ${what}${detail ? ` — ${detail}` : ''}`)
	}
}

async function post(path, body) {
	const response = await fetch(`${API}${path}`, {
		method: 'POST',
		headers: { ...json, ...auth },
		body: JSON.stringify(body),
	})
	if (!response.ok) throw new Error(`POST ${path} → ${response.status}`)
	return response.json()
}

async function usage() {
	const response = await fetch(`${API}/usage`, { headers: auth })
	if (!response.ok) throw new Error(`GET /usage → ${response.status}`)
	return response.json()
}

/// Writes straight into the local D1, for the two states that cannot be reached
/// any other way: a month's minutes spent, and a family that has paid. Spending
/// them for real would cost ten minutes of transcription and prove the same
/// thing.
function sql(statement) {
	let out = ''
	const wrongDatabase = () =>
		new Error(
			`could not reach the database in ${backend}: that is not the one this ` +
				`Worker is using. Set KINLORE_WORKER_DIR to the backend it runs from.`,
		)
	try {
		out = execFileSync(
			'npx',
			['wrangler', 'd1', 'execute', 'memorize', '--local', '--json', '--command', statement],
			{ cwd: backend, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
		)
	} catch {
		throw wrongDatabase()
	}
	if (!out.includes('"success": true')) throw wrongDatabase()
	return out
}

const now = Math.floor(Date.now() / 1000)
const period = new Date().toISOString().slice(0, 7)

try {
	const created = await post('/family', {
		memberID,
		secret,
		displayName: 'Quota check',
		familyName: 'Quota check',
	})
	familyID = created.familyID

	console.log('— what a new family is given —')
	{
		const seen = await usage()
		check(
			'the month starts at nothing used',
			seen.aiSeconds.used === 0 && seen.photos.used === 0,
			JSON.stringify({ ai: seen.aiSeconds, photos: seen.photos }),
		)
		check(
			'with the free limits stated rather than implied',
			seen.aiSeconds.limit > 0 && seen.photos.limit > 0,
			JSON.stringify({ ai: seen.aiSeconds.limit, photos: seen.photos.limit }),
		)
	}

	console.log('— photographs are counted where they are, not in a tally —')
	const photos = [randomUUID(), randomUUID(), randomUUID()]
	{
		await post('/sync', {
			subjects: photos.map((id) => ({ id, kind: 'photo', title: '', created_at: now })),
		})
		const seen = await usage()
		check('three photographs count as three', seen.photos.used === 3, String(seen.photos.used))
	}
	{
		// §7 says a deleted photo frees its slot, because the count is derived
		// from the table rather than kept beside it. A family that clears out a
		// mistake and stays locked out would have no way to understand why.
		await post('/sync', {
			subjects: [{ id: photos[0], kind: 'photo', title: '', created_at: now, deleted_at: now }],
		})
		const seen = await usage()
		check('and a deleted one gives its slot back', seen.photos.used === 2, String(seen.photos.used))
	}

	console.log('— the month can run out —')
	{
		const limit = (await usage()).aiSeconds.limit
		sql(
			`INSERT INTO usage_counter (family_id, period, ai_seconds) VALUES ('${familyID}', '${period}', ${limit})
			 ON CONFLICT(family_id, period) DO UPDATE SET ai_seconds = ${limit}`,
		)
		const seen = await usage()
		check(
			'and the app is told so plainly',
			seen.aiSeconds.used >= seen.aiSeconds.limit,
			JSON.stringify(seen.aiSeconds),
		)
	}

	console.log('— and telling still is not paywalled (rule 2) —')
	{
		// The minutes are gone. A typed memory needs none of them, and the rule
		// says it goes through — this is the one that must never be broken by a
		// tidy-looking change to the quota path.
		const id = randomUUID()
		const subject = randomUUID()
		await post('/sync', {
			subjects: [{ id: subject, kind: 'event', title: 'Kiintiön jälkeen', created_at: now }],
			memories: [
				{
					id,
					subject_id: subject,
					body: 'Tämä kirjoitettiin kun kuukauden minuutit olivat lopussa.',
					source: 'typed',
					created_at: now,
				},
			],
		})
		const reply = await fetch(`${API}/sync?since=0`, { headers: auth })
		const body = await reply.json()
		check(
			'a written memory is stored with the minutes spent',
			body.memories.some((m) => m.id === id),
			`${body.memories.length} memories came back`,
		)
	}

	console.log('— and paying takes the ceiling away —')
	{
		sql(`UPDATE family SET entitlement = 'archive' WHERE id = '${familyID}'`)
		const seen = await usage()
		check(
			'no limit is reported once the family has paid',
			seen.aiSeconds.limit === null && seen.photos.limit === null,
			JSON.stringify({ ai: seen.aiSeconds.limit, photos: seen.photos.limit }),
		)
		check('and what was used is still counted', seen.aiSeconds.used > 0, String(seen.aiSeconds.used))
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
