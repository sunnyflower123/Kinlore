#!/usr/bin/env node
// The invite link is the entire security boundary (ARCHITECTURE.md §4).
//
// There is no login. Whoever holds a code sees a family's memories of their
// dead relatives, and four rules are all that stand between the archive and
// anybody else: a code expires, a code can be revoked, a code belongs to one
// family, and a wrong code must be indistinguishable from an expired or revoked
// one — otherwise guessing tells you when you have found a real family.
//
// Every one of those fails silently. A revoked code that still works looks
// exactly like a working app, and the only person who finds out is the one who
// revoked it and believed they had.
//
// **Beside `family-sync-check.mjs`, not instead of it.** That one walks the
// path the product is: two phones, one family, a memory crossing between them.
// This one stands at the door and pushes — the refusals, which are the half a
// happy path cannot see. Two cases overlap (a revoked code, a made-up one) and
// they are cheap; the rest are only here.
//
// Costs nothing: no AI, no upstream call, only D1 writes into the local
// database. Each run leaves two throwaway families behind.
//
// Requires a running Worker:
//   cd backend && npx wrangler dev
//
// Ageing an invite past its expiry cannot be done over HTTP — there is no
// endpoint for it and there should not be — so that one case reaches into the
// local D1 with wrangler. It is the same database the Worker in front of it is
// using.
//
//   node scripts/invite-boundary-check.mjs
//   node scripts/invite-boundary-check.mjs http://localhost:8787
//
// Against a Worker running from another checkout, say where its database is or
// the expiry case will age the wrong one:
//
//   KINLORE_WORKER_DIR=/path/to/other/backend \
//     node scripts/invite-boundary-check.mjs http://localhost:8788

import { randomUUID, randomBytes } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname, join as joinPath } from 'node:path'

const API = process.argv[2] ?? 'http://localhost:8787'
// The `--local` D1 lives beside the Worker that is using it, so ageing an
// invite has to reach into *that* copy. Pointing this script at another URL
// without saying where its state is aged the wrong database and made the expiry
// case pass for the wrong reason — which is how this variable came to exist.
const backend =
	process.env.KINLORE_WORKER_DIR ??
	joinPath(dirname(fileURLToPath(import.meta.url)), '..', 'backend')
const json = { 'content-type': 'application/json' }

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
	return { status: response.status, body: await response.json().catch(() => ({})) }
}

/// A person with a phone: an id, a secret, and the header the two make.
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

async function createFamily(who, familyName) {
	const { status } = await post('/family', {
		memberID: who.memberID,
		secret: who.secret,
		displayName: who.name,
		familyName,
	})
	if (status !== 200) throw new Error(`could not create ${familyName}: ${status}`)
}

async function invite(who) {
	const { body } = await post('/family/invite', {}, who.auth)
	if (!body.code) throw new Error('no invite code came back')
	return body.code
}

async function join(who, code) {
	return post('/family/join', {
		memberID: who.memberID,
		secret: who.secret,
		displayName: who.name,
		code,
	})
}

/// Moves an invite's expiry into the past. There is no route for this on
/// purpose: an endpoint that ages a code is an endpoint that can un-age one.
function age(code) {
	let out = ''
	const wrongDatabase = () =>
		new Error(
			`the invite could not be aged in ${backend}: that is not the database ` +
				`this Worker is using. Set KINLORE_WORKER_DIR to the backend it runs from.`,
		)
	try {
		out = execFileSync('npx', [
			'wrangler',
			'd1',
			'execute',
			'memorize',
			'--local',
			'--json',
			'--command',
			`UPDATE invite SET expires_at = 1 WHERE code = '${code}' RETURNING code`,
		],
			{ cwd: backend, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
		)
	} catch {
		// The tables are not even there. Same cause, same answer.
		throw wrongDatabase()
	}
	// It has to have aged *something*. Run from another checkout — a throwaway
	// worktree, a second Worker on another port — this reaches a different
	// `--local` database, one that may not even have the tables, and the expiry
	// case would then fail as though the app had let an expired code through.
	// A check that blames the app for its own wrong address is worse than no
	// check.
	if (!out.includes(code)) throw wrongDatabase()
}

try {
	const mummo = person('Mummo')
	const ville = person('Ville')
	const stranger = person('Tuntematon')
	await createFamily(mummo, 'Virtaset')
	await createFamily(stranger, 'Toinen perhe')

	console.log('— a code lets somebody in —')
	{
		const code = await invite(mummo)
		const { status, body } = await join(ville, code)
		check('the invited member joins', status === 200 && !body.error, JSON.stringify(body))
	}

	console.log('— and the four ways it must not —')
	{
		const outsider = person('Ohikulkija')
		const { body } = await join(outsider, 'ei-ole-koodi')
		check('a made-up code is refused', body.error === 'invalid_invite', JSON.stringify(body))
	}
	{
		const code = await invite(mummo)
		await fetch(`${API}/family/invite?code=${encodeURIComponent(code)}`, {
			method: 'DELETE',
			headers: mummo.auth,
		})
		const outsider = person('Peruttu')
		const { body } = await join(outsider, code)
		// The same words as a wrong code, deliberately: a different answer would
		// tell a guesser that the code was real and merely late.
		check(
			'a revoked code is refused, in the same words',
			body.error === 'invalid_invite',
			JSON.stringify(body),
		)
	}
	{
		const code = await invite(mummo)
		age(code)
		const outsider = person('Myöhässä')
		const { body } = await join(outsider, code)
		check(
			'an expired code is refused, in the same words',
			body.error === 'invalid_invite',
			JSON.stringify(body),
		)
	}
	{
		// The stranger already belongs to another family. Their code cannot pull
		// them across, and this is the rule that keeps two archives apart.
		const code = await invite(mummo)
		const { body } = await join(stranger, code)
		check(
			'somebody else\'s member cannot be pulled into this family',
			body.error === 'member_exists',
			JSON.stringify(body),
		)
	}

	console.log('— and one family cannot reach into another —')
	{
		const code = await invite(mummo)
		const response = await fetch(`${API}/family/invite?code=${encodeURIComponent(code)}`, {
			method: 'DELETE',
			headers: stranger.auth,
		})
		const body = await response.json().catch(() => ({}))
		// Revoking is scoped by family in the SQL itself. If that ever changes,
		// anybody who has seen a code could close somebody else's door.
		check(
			'a stranger cannot revoke this family\'s invite',
			body.revoked === false || body.error !== undefined,
			JSON.stringify(body),
		)
		const guest = person('Yhä kutsuttu')
		const { body: after } = await join(guest, code)
		check(
			'and the invite still works afterwards',
			after.error === undefined,
			JSON.stringify(after),
		)
	}
} catch (error) {
	failures += 1
	console.log(`\n  FAIL ${error.message}`)
	console.log('       Is the Worker running? cd backend && npx wrangler dev')
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
