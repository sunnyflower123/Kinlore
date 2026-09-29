#!/usr/bin/env node
// The /story route's doors, driven through a real Worker with no key
// (ARCHITECTURE §27). `story-shaping-check.mjs` proves the pieces; this
// proves the route puts them in the right order, where each failure is
// silent:
//
//   1. **Nothing told, nothing composed.** A card with no telling is turned
//      away before it goes anywhere. A route that let it through would ask
//      the model to write a story out of nothing, which rule 2 of its prompt
//      forbids and which the model might do anyway.
//   2. **Too much is refused, not cut.** A card past the caps is a 413, and
//      no request is made upstream.
//   3. **Only with a session.** An open model call on a public URL is billed
//      to rule 7's key.
//   4. **Past every door it reaches the model**, and fails there — which is
//      how "turned away at the door" is told apart from "went through" — and
//      the log carries counts and not a word of what was told (rule 9).
//
// Costs nothing, for colourise-route-check.mjs's reason: the Worker starts
// with an empty key, so a request that gets past every door fails in
// `send()` before any network, as a 502. Its own port and its own
// `--persist-to` state, so another session's Worker is never touched.
//
//   node scripts/story-route-check.mjs

import { spawn, execFileSync } from 'node:child_process'
import { randomUUID, randomBytes } from 'node:crypto'
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const backend =
	process.env.KINLORE_WORKER_DIR ??
	join(dirname(fileURLToPath(import.meta.url)), '..', 'backend')

// Clear of 8787 and of leak-check.mjs's own range.
const PORT = 8900 + ((Math.random() * 90) | 0)
const API = `http://localhost:${PORT}`

const SAID = 'Siinä kuvassa ollaan sen mökin rannassa, se oli Puumalassa se mökki.'
const NAME = 'Eevertti'
const telling = (text = SAID) => ({ teller: 'Mummo', told: '14.6.2025', source: 'voice', text })
const card = (more = {}) => ({
	lang: 'fi',
	kind: 'photo',
	title: 'Mökin laituri',
	date: '1950-luku',
	mentions: [{ name: NAME, kind: 'person' }],
	memories: [telling()],
	...more,
})

let failures = 0

function check(what, condition, detail = '') {
	if (condition) {
		console.log(`  ok   ${what}`)
	} else {
		failures += 1
		console.log(`  FAIL ${what}${detail ? ` — ${detail}` : ''}`)
	}
}

const state = mkdtempSync(join(tmpdir(), 'kinlore-story-'))
const database = join(state, 'd1')
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

function startWorker() {
	const child = spawn(
		'npx',
		['wrangler', 'dev', '--port', String(PORT), '--persist-to', database, '--var', 'OPENROUTER_API_KEY:'],
		{ cwd: backend, detached: true, stdio: ['ignore', 'pipe', 'pipe'] },
	)
	let log = ''
	child.stdout.on('data', (chunk) => (log += chunk))
	child.stderr.on('data', (chunk) => (log += chunk))
	// wrangler colours its lines; a search must not be defeated by an escape code.
	return { child, read: () => log.replace(/\[[0-9;]*m/g, '') }
}

async function waitForReady() {
	for (let i = 0; i < 60; i += 1) {
		try {
			const body = await (await fetch(`${API}/health`)).json()
			if (body.ok) return body
		} catch {
			// not up yet
		}
		await pause(1000)
	}
	throw new Error(`the Worker did not come up on ${PORT}`)
}

function sql(args) {
	execFileSync('npx', ['wrangler', 'd1', 'execute', 'memorize', '--local', '--persist-to', database, ...args], {
		cwd: backend,
		stdio: 'ignore',
	})
}

async function call(method, path, body, headers = {}) {
	const response = await fetch(`${API}${path}`, {
		method,
		headers: { 'content-type': 'application/json', ...headers },
		body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
	})
	return { status: response.status, body: await response.json().catch(() => ({})) }
}

const worker = startWorker()

try {
	const health = await waitForReady()
	// With a key, a request that passes every door would be a paid call.
	if (health.hasKey) throw new Error('this Worker has a key — refusing to call upstream')

	sql(['--file=schema.sql'])
	const memberID = randomUUID()
	const secret = randomBytes(32).toString('hex')
	const created = await call('POST', '/family', { memberID, secret, displayName: 'Ville', familyName: 'Tarinakoe' })
	if (created.status !== 200) throw new Error(`could not create a family: ${created.status}`)
	const auth = { Authorization: `Bearer ${memberID}.${secret}` }
	const story = (body, headers = auth) => call('POST', '/story', body, headers)

	console.log('— nothing told, nothing composed —')
	{
		const nothing = await story(card({ memories: [] }))
		check('a card with no telling is turned away', nothing.status === 400 && nothing.body.error === 'missing_memories', JSON.stringify(nothing))
		const blank = await story(card({ memories: [telling('   '), telling('')] }))
		check('and so is one with only blank tellings', blank.status === 400 && blank.body.error === 'missing_memories', JSON.stringify(blank))
		const broken = await story('{"memories": [')
		check('and a body that is not JSON', broken.status === 400 && broken.body.error === 'invalid_json', JSON.stringify(broken))
	}

	console.log('— too much is refused, not cut —')
	{
		const before = worker.read().length
		const many = await story(card({ memories: Array.from({ length: 41 }, () => telling()) }))
		check('forty-one tellings are turned away', many.status === 413 && many.body.error === 'story_too_long', JSON.stringify(many))
		const long = await story(card({ memories: [telling('x'.repeat(8001))] }))
		check('and so is one telling past its cap', long.status === 413 && long.body.error === 'story_too_long', JSON.stringify(long))
		const soFar = await story(card({ soFar: 'x'.repeat(20_001) }))
		check('and a story so far past its own', soFar.status === 413 && soFar.body.error === 'story_too_long', JSON.stringify(soFar))
		await pause(1000)
		check('and none of them was asked of the model', !/\[story\]|\[openrouter\]/.test(worker.read().slice(before)))
	}

	console.log('— only with a session —')
	{
		const before = worker.read().length
		const stranger = await story(card(), {})
		check('nobody without a session gets in', stranger.status === 401, `${stranger.status}`)
		const wrong = await story(card(), { Authorization: `Bearer ${memberID}.${'0'.repeat(64)}` })
		check('nor with a wrong secret', wrong.status === 401, `${wrong.status}`)
		await pause(1000)
		check('and neither was asked of the model', !/\[story\]|\[openrouter\]/.test(worker.read().slice(before)))
	}

	console.log('— past every door, it reaches the model and fails there —')
	{
		const before = worker.read().length
		const failed = await story(card())
		check(
			'a card with a telling and a session reaches the model, and fails without a key',
			failed.status === 502 && failed.body.error === 'upstream_failed',
			JSON.stringify(failed),
		)
		await pause(1500)
		const since = worker.read().slice(before)
		check('and the log shows it got that far', /\[story\]/.test(since))
		check('and the app was told nothing about why', JSON.stringify(failed.body) === '{"error":"upstream_failed"}')
		check('and the log carries no word of what was told', !since.includes('Puumalassa') && !since.includes(NAME))
		const addition = await story(card({ soFar: 'Mummo kertoo, että kuvassa ollaan rannassa.' }))
		check('an addition takes the same road', addition.status === 502 && addition.body.error === 'upstream_failed', JSON.stringify(addition))
	}
} catch (error) {
	failures += 1
	console.log(`\n  FAIL ${error.message}`)
} finally {
	try {
		process.kill(-worker.child.pid, 'SIGTERM')
	} catch {
		// already gone
	}
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
