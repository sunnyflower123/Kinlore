#!/usr/bin/env node
// There is no login, so this is the whole of authentication.
//
// A UUID and 32 random bytes in the Keychain, sent as `Bearer <id>.<secret>`.
// Everything else in the app — every read, every write, the isolation between
// two families — rests on `authenticate` in backend/src/auth.ts, and §1 has
// listed its rules as verified while nothing ran them.
//
// The four that matter:
//
// 1. A wrong secret is refused, and an unknown member is refused the same way.
// 2. One family cannot see another's rows. This is the boundary the whole
//    no-login design is traded against.
// 3. **A member who has left is out.** The row stays so the names on their
//    memories keep resolving, which makes "still in the database" and "still in
//    the family" two different things — and the difference is one column.
// 4. The secret is stored hashed. A database leak must not be a set of keys.
//
// Silent when broken, every one. A left member who can still read looks exactly
// like a working app to everybody except the family who asked them to leave.
//
// Costs nothing: no AI, no money, four families and a few rows in the local D1.
//
// Requires a running Worker:
//   cd backend && npx wrangler dev
//
//   node scripts/session-boundary-check.mjs
//   KINLORE_WORKER_DIR=/path/to/backend node scripts/session-boundary-check.mjs http://localhost:8788

import { randomUUID, randomBytes } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname, join as joinPath } from 'node:path'

const API = process.argv[2] ?? 'http://localhost:8787'
const backend =
	process.env.KINLORE_WORKER_DIR ??
	joinPath(dirname(fileURLToPath(import.meta.url)), '..', 'backend')
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
	return {
		name,
		memberID,
		secret,
		auth: { Authorization: `Bearer ${memberID}.${secret}` },
	}
}

async function send(path, options = {}) {
	const response = await fetch(`${API}${path}`, options)
	return { status: response.status, body: await response.json().catch(() => ({})) }
}

async function createFamily(who) {
	const { status } = await send('/family', {
		method: 'POST',
		headers: json,
		body: JSON.stringify({
			memberID: who.memberID,
			secret: who.secret,
			displayName: who.name,
			familyName: `${who.name}n perhe`,
		}),
	})
	if (status !== 200) throw new Error(`could not create a family: ${status}`)
}

async function push(who, subject) {
	return send('/sync', {
		method: 'POST',
		headers: { ...json, ...who.auth },
		body: JSON.stringify({ subjects: [subject] }),
	})
}

async function pull(who) {
	const { status, body } = await send('/sync?since=0', { headers: who.auth })
	return { status, subjects: body.subjects ?? [] }
}

function sql(statement) {
	try {
		return execFileSync(
			'npx',
			['wrangler', 'd1', 'execute', 'memorize', '--local', '--json', '--command', statement],
			{ cwd: backend, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
		)
	} catch {
		throw new Error(
			`could not reach the database in ${backend}: that is not the one this Worker ` +
				`is using. Set KINLORE_WORKER_DIR to the backend it runs from.`,
		)
	}
}

const now = Math.floor(Date.now() / 1000)

try {
	const mummo = person('Mummo')
	const naapuri = person('Naapuri')
	await createFamily(mummo)
	await createFamily(naapuri)

	// Something of Mummo's to try to reach.
	const secretSubject = randomUUID()
	await push(mummo, { id: secretSubject, kind: 'person', title: 'Aino', created_at: now })

	console.log('— a token is either right or it is nothing —')
	{
		const wrong = { Authorization: `Bearer ${mummo.memberID}.${randomBytes(32).toString('hex')}` }
		const { status } = await send('/sync?since=0', { headers: wrong })
		check('the right member with the wrong secret is refused', status === 401, String(status))
	}
	{
		const nobody = { Authorization: `Bearer ${randomUUID()}.${randomBytes(32).toString('hex')}` }
		const { status } = await send('/sync?since=0', { headers: nobody })
		check('and a member who does not exist, in the same way', status === 401, String(status))
	}
	{
		const { status } = await send('/sync?since=0', { headers: { Authorization: 'Bearer nonsense' } })
		check('a token with no shape at all is refused', status === 401, String(status))
	}

	console.log('— one family cannot see another —')
	{
		const { subjects } = await pull(naapuri)
		check(
			'the neighbour reads nothing of this family',
			!subjects.some((s) => s.id === secretSubject),
			`${subjects.length} subjects came back`,
		)
	}
	{
		// The write is accepted — it is a valid session — but it lands in the
		// neighbour's own family. What must never happen is it appearing here.
		await push(naapuri, { id: secretSubject, kind: 'person', title: 'Väärä', created_at: now })
		const { subjects } = await pull(mummo)
		const mine = subjects.find((s) => s.id === secretSubject)
		check(
			'and cannot write over what it cannot see',
			mine?.title === 'Aino',
			JSON.stringify({ title: mine?.title }),
		)
	}

	console.log('— and somebody who has left is out —')
	{
		const { body } = await send('/family/invite', { method: 'POST', headers: mummo.auth })
		const ville = person('Ville')
		await send('/family/join', {
			method: 'POST',
			headers: json,
			body: JSON.stringify({
				memberID: ville.memberID,
				secret: ville.secret,
				displayName: ville.name,
				code: body.code,
			}),
		})
		const joined = await pull(ville)
		check('a joined member reads the family', joined.status === 200, String(joined.status))

		await send('/family/me', { method: 'DELETE', headers: ville.auth })
		const after = await pull(ville)
		// The row is kept so the names on his memories still resolve. Being in
		// the database and being in the family are two different things, and the
		// difference is one column.
		check('and the moment he leaves, he reads nothing', after.status === 401, String(after.status))
	}

	console.log('— and the secret is not lying in the database —')
	{
		const out = sql(`SELECT secret_hash FROM member WHERE id = '${mummo.memberID}'`)
		check('what is stored is not the secret', !out.includes(mummo.secret))
		const hash = out.match(/"secret_hash":\s*"([0-9a-f]{64})"/)
		check('but a SHA-256 of it', hash !== null, hash ? hash[1].slice(0, 16) + '…' : 'no 64-hex value')
	}
} catch (error) {
	failures += 1
	console.log(`\n  FAIL ${error.message}`)
	console.log('       Is the Worker running? cd backend && npx wrangler dev')
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
