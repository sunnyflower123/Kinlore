#!/usr/bin/env node
// The /colourise route's doors, driven through a real Worker with no key.
//
// `colourise-check.mjs` proves the pieces. This proves the route puts them in
// the right order, which is where each failure is silent:
//
//   1. **Nothing told, nothing coloured.** A photograph with no telling is
//      turned away before it goes anywhere (rule 4). A route that let it
//      through would answer with a perfectly good-looking guess.
//   2. **The meter answers before the model.** A family whose rounds are spent
//      is told so by the meter's own 402, and no request is made upstream.
//   3. **A round that failed is not charged.** quota.ts promises it, and a
//      counter written before the call would quietly take one of five for
//      nothing on every upstream error.
//   4. Only a JPEG, only so big, and only with a session.
//
// Costs nothing, for leak-check.mjs's reason: the Worker starts with an empty
// key, so a request that gets past every door fails in `send()` before any
// network, as a 502 — which is also how "turned away at the door" is told
// apart from "went through". Its own port and its own `--persist-to` state, so
// another session's Worker is never touched.
//
//   node scripts/colourise-route-check.mjs

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

const SAID = 'Äidin mekko oli tummanvihreä'
const PHOTO = '/9j/4AAQSkZJRgABAQ'

let failures = 0

function check(what, condition, detail = '') {
	if (condition) {
		console.log(`  ok   ${what}`)
	} else {
		failures += 1
		console.log(`  FAIL ${what}${detail ? ` — ${detail}` : ''}`)
	}
}

const state = mkdtempSync(join(tmpdir(), 'kinlore-colourise-'))
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
	return { child, read: () => log.replace(/\[[0-9;]*m/g, '') }
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
		body: body === undefined ? undefined : JSON.stringify(body),
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
	const created = await call('POST', '/family', { memberID, secret, displayName: 'Ville', familyName: 'Värikoe' })
	if (created.status !== 200) throw new Error(`could not create a family: ${created.status}`)
	const auth = { Authorization: `Bearer ${memberID}.${secret}` }
	const colourise = (body, headers = auth) => call('POST', '/colourise', body, headers)

	console.log('— nothing told, nothing coloured —')
	{
		const nothing = await colourise({ image: PHOTO, told: [] })
		check('a photograph with no telling is turned away', nothing.status === 400 && nothing.body.error === 'missing_told', JSON.stringify(nothing))
		const blank = await colourise({ image: PHOTO, told: ['   ', ''] })
		check('and so is one with only blank tellings', blank.status === 400 && blank.body.error === 'missing_told', JSON.stringify(blank))
	}

	console.log('— only a JPEG, only so big, only with a session —')
	{
		const png = await colourise({ image: 'iVBORw0KGgoAAAANSUhEUg', told: [SAID] })
		check('a PNG is turned away', png.status === 400 && png.body.error === 'missing_image', JSON.stringify(png))
		const huge = await colourise({ image: `/9j/${'A'.repeat(12 * 1024 * 1024)}`, told: [SAID] })
		check('a gigantic one is turned away', huge.status === 413 && huge.body.error === 'image_too_large', `${huge.status}`)
		const stranger = await colourise({ image: PHOTO, told: [SAID] }, {})
		check('and nobody without a session gets in', stranger.status === 401, `${stranger.status}`)
	}

	console.log('— a round that failed is not charged —')
	{
		const before = worker.read().length
		const failed = await colourise({ image: PHOTO, told: [SAID], aspect: '4:3' })
		check(
			'past every door it reaches the model, and fails there',
			failed.status === 502 && failed.body.error === 'upstream_failed',
			JSON.stringify(failed),
		)
		await pause(1500)
		// The presence the next section's absence depends on.
		check('and the log shows it got that far', /\[colourise\]/.test(worker.read().slice(before)))
		const shown = await call('GET', '/usage', undefined, auth)
		check(
			'the failed round took none of the five',
			shown.body.colourisations?.used === 0 && shown.body.colourisations?.limit === 5,
			JSON.stringify(shown.body.colourisations),
		)
	}

	console.log('— the meter answers before the model —')
	{
		const now = new Date()
		const period = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`
		sql([
			'--command',
			`INSERT INTO usage_counter (family_id, period, colourisations)
			 SELECT family_id, '${period}', 5 FROM member WHERE id = '${memberID}'
			 ON CONFLICT(family_id, period) DO UPDATE SET colourisations = 5`,
		])
		const before = worker.read().length
		const spent = await colourise({ image: PHOTO, told: [SAID] })
		check(
			'a family with its rounds spent is told by the meter',
			spent.status === 402 && spent.body.kind === 'colourisations' && spent.body.used === 5 && spent.body.limit === 5,
			JSON.stringify(spent),
		)
		await pause(1500)
		check('and nothing was asked of the model', !/\[colourise\]|\[openrouter\]/.test(worker.read().slice(before)))
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
