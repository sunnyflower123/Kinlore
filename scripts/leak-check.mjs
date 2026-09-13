#!/usr/bin/env node
// Rule 9, run rather than read.
//
// The app is told `{ error: "upstream_failed" }` and nothing else. The reason
// this rule is written twice in CLAUDE.md — once for the client and once for
// the log — is that it has already been broken in the second half: until
// 16 Aug 2026 an extraction failure sent 300 characters of the just-told memory
// to `console.error`, and `observability` is on in `wrangler.jsonc`, so Workers
// Logs is a store beside D1 and R2. It is the one store a family cannot export,
// cannot clear with *"Tyhjennä tämä laite"*, and never agreed to.
//
// Reading the code is how that was found and it is not enough to keep it found:
// the leak was one interpolation, and the next one will be too.
//
// So this drives the real failure path and looks in both places. Two things
// make it cheap and safe:
//
//   - **No key, no call.** `complete()` throws `UpstreamError(401)` before it
//     touches the network when `OPENROUTER_API_KEY` is empty, and that throw
//     goes through exactly the same `failure()` as a real upstream error. No
//     OpenRouter request, no credits, no money.
//   - **A Worker of its own**, on its own port with its own `--persist-to`
//     state, because reading a log means owning the process that writes it.
//     Nothing here touches the Worker another session is running.
//
// What is asserted:
//
//   1. The client is told `upstream_failed`, and nothing else is in the body —
//      not a detail, not a hint, not a status from upstream.
//   2. The failure really happened. A check that greps a log for an absence
//      passes beautifully when the log is empty, which is why the log must
//      first be shown to contain the failure line at all.
//   3. **The words the family said are in neither place.** A transcript, a name
//      being corrected, the audio itself, and a photograph sent with what was
//      told about it.
//
//   node scripts/leak-check.mjs

import { spawn, execFileSync } from 'node:child_process'
import { randomUUID, randomBytes } from 'node:crypto'
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const backend =
	process.env.KINLORE_WORKER_DIR ??
	join(dirname(fileURLToPath(import.meta.url)), '..', 'backend')

// Out of the way of the Worker on 8787 and of another session's mutation run.
const PORT = 8800 + ((Math.random() * 90) | 0)
const API = `http://localhost:${PORT}`

// Words that belong to a family, chosen so that a partial leak is still caught:
// a substring of the transcript is as much of a leak as all of it.
const SAID = 'Aino kertoi kuinka Kuusamon mökki paloi talvella 1957'
const NAME = 'Eeva-Liisa Karjalainen'
const AUDIO = 'QUlOT05LRVJUT0lLVVVTQU1P'
// A JPEG's first bytes and then the family's. The route turns away anything
// that does not open like a JPEG, and a request refused at the door never
// reaches the failure this check exists to look at.
const PHOTO = '/9j/4AAQS0lOTE9SRUtVVkFBSU5P'

let failures = 0

function check(what, condition, detail = '') {
	if (condition) {
		console.log(`  ok   ${what}`)
	} else {
		failures += 1
		console.log(`  FAIL ${what}${detail ? ` — ${detail}` : ''}`)
	}
}

const state = mkdtempSync(join(tmpdir(), 'kinlore-leak-'))

/// A Worker with no key, in a state directory of its own.
function startWorker() {
	const out = spawn(
		'npx',
		[
			'wrangler',
			'dev',
			'--port',
			String(PORT),
			'--persist-to',
			join(state, 'd1'),
			// This is what makes the check free: with no key the upstream call
			// throws before any request is made. `--var` wins over `.dev.vars`.
			'--var',
			'OPENROUTER_API_KEY:',
		],
		{ cwd: backend, detached: true, stdio: ['ignore', 'pipe', 'pipe'] },
	)
	let log = ''
	const collect = (chunk) => {
		log += chunk
	}
	out.stdout.on('data', collect)
	out.stderr.on('data', collect)
	return { child: out, read: () => log }
}

async function waitForReady() {
	for (let i = 0; i < 60; i += 1) {
		try {
			const response = await fetch(`${API}/health`)
			const body = await response.json()
			if (body.ok) return body
		} catch {
			// not up yet
		}
		await new Promise((resolve) => setTimeout(resolve, 1000))
	}
	throw new Error(`the Worker did not come up on ${PORT}`)
}

async function post(path, body, headers = {}) {
	const response = await fetch(`${API}${path}`, {
		method: 'POST',
		headers: { 'content-type': 'application/json', ...headers },
		body: JSON.stringify(body),
	})
	return { status: response.status, body: await response.json().catch(() => ({})) }
}

const worker = startWorker()

try {
	const health = await waitForReady()
	// If a key were present the next call would cost money and measure nothing.
	// Stop rather than spend.
	if (health.hasKey) throw new Error('this Worker has a key — refusing to call upstream')

	// Every model route is behind a session, so this Worker needs a family of
	// its own — its `--persist-to` database is empty, which is the point of it.
	execFileSync(
		'npx',
		[
			'wrangler',
			'd1',
			'execute',
			'memorize',
			'--local',
			'--persist-to',
			join(state, 'd1'),
			'--file=schema.sql',
		],
		{ cwd: backend, stdio: 'ignore' },
	)
	const memberID = randomUUID()
	const secret = randomBytes(32).toString('hex')
	await post('/family', {
		memberID,
		secret,
		displayName: 'Mummo',
		familyName: 'Vuotokoe',
	})
	const auth = { Authorization: `Bearer ${memberID}.${secret}` }

	console.log('— the app is told nothing (rule 9, first half) —')
	let answer = null
	{
		answer = await post(
			'/extract',
			{
				transcript: SAID,
				corrections: [{ from: 'Eeva Liisa', to: NAME }],
				level: 2,
			},
			auth,
		)
		check('an extraction failure answers 502', answer.status === 502, String(answer.status))
		check(
			'and the body is upstream_failed, on its own',
			answer.body.error === 'upstream_failed' && Object.keys(answer.body).length === 1,
			JSON.stringify(answer.body),
		)
	}
	{
		const transcription = await post(
			'/transcribe',
			{ audio: AUDIO, format: 'm4a', seconds: 8 },
			auth,
		)
		check(
			'and so does a transcription failure',
			transcription.status === 502 &&
				transcription.body.error === 'upstream_failed' &&
				Object.keys(transcription.body).length === 1,
			`${transcription.status} ${JSON.stringify(transcription.body)}`,
		)
	}
	{
		// The photograph and what was told about it, which go up together.
		const colourisation = await post(
			'/colourise',
			{ image: PHOTO, told: [SAID, NAME], aspect: '4:3' },
			auth,
		)
		check(
			'and so does a colourisation failure',
			colourisation.status === 502 &&
				colourisation.body.error === 'upstream_failed' &&
				Object.keys(colourisation.body).length === 1,
			`${colourisation.status} ${JSON.stringify(colourisation.body)}`,
		)
	}

	// Workers Logs is written from this process's output, so give it a moment
	// to arrive before reading it.
	await new Promise((resolve) => setTimeout(resolve, 2000))
	// wrangler wraps each line in colour codes; strip them so a search for a
	// leaked word cannot be defeated by an escape sequence landing inside it.
	const log = worker.read().replace(/\[[0-9;]*m/g, '')

	console.log('— and the log is not where it went instead (second half) —')
	{
		// The absence below means nothing unless the failure reached the log at
		// all. This is the assertion that stops the whole check from passing on
		// an empty file.
		check(
			'the failure did reach the log',
			/\[extract\]/.test(log) && /\[transcribe\]/.test(log) && /\[colourise\]/.test(log),
			`${log.length} characters captured`,
		)
	}
	for (const [what, secret] of [
		['the telling', SAID],
		['a fragment of it', 'Kuusamon mökki paloi'],
		['the name being corrected', NAME],
		['the audio', AUDIO],
		['the photograph', PHOTO],
	]) {
		check(`${what} is not in the log`, !log.includes(secret))
	}
	{
		// The client's copy, checked as text rather than as fields: a leak may
		// arrive in a key nobody thought to look at.
		const asText = JSON.stringify(answer.body)
		check(
			'nor in what came back to the app',
			!asText.includes(SAID) && !asText.includes(NAME),
			asText,
		)
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
