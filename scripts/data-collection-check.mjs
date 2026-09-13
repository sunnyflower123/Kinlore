#!/usr/bin/env node
// Rule 8: `provider: { data_collection: "deny" }` is unconditional.
//
// The content is a family's memories of dead relatives, and this one flag is
// what keeps them out of somebody else's training set. CLAUDE.md says why it is
// not a per-call option: "as a flag it would be forgotten on some call". That
// makes it a rule about *every* request, which is exactly the kind of rule
// reading cannot keep — there were three call sites when this was written, and
// the fourth, colourisation on 13 Sep 2026, does not go through `complete()` at
// all.
//
// It also cannot be checked by making a request. A real call costs credits, and
// the one thing a test must never do is send a family's words upstream to prove
// they are being protected.
//
// So the request is built and then not sent: `complete()` and `completeImage()`
// are imported straight out of `backend/src/openrouter.ts` — Node runs
// TypeScript as it is — and `fetch` is replaced with something that keeps the
// request and answers like OpenRouter. Nothing leaves this machine, nothing is
// spent, and what is asserted is the actual body the Worker would have sent
// rather than a reading of the source.
//
// Four properties:
//
//   1. Every call carries the deny — plain, structured, with audio in it, and
//      with a photograph going up and another coming back.
//   2. **The structured branch especially**, because it adds
//      `require_parameters` to the same object and is the one place where the
//      object could be replaced and the deny quietly lost — and because one
//      shared object would carry that addition into every call after it.
//   3. A caller cannot turn it off. It is not an option, and passing one is
//      ignored rather than honoured.
//   4. The key travels in the Authorization header and is nowhere in the body,
//      and the destination is https.
//
//   node scripts/data-collection-check.mjs

import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { pathToFileURL } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const { complete, completeImage } = await import(
	pathToFileURL(join(root, 'backend', 'src', 'openrouter.ts')).href
)

let failures = 0

function check(what, condition, detail = '') {
	if (condition) {
		console.log(`  ok   ${what}`)
	} else {
		failures += 1
		console.log(`  FAIL ${what}${detail ? ` — ${detail}` : ''}`)
	}
}

const KEY = 'sk-or-not-a-real-key'
const SAID = 'Aino kertoi kuinka mökki paloi.'

const WORDS = { choices: [{ message: { content: '{"ok":true}' }, finish_reason: 'stop' }] }
const PICTURE = {
	choices: [
		{
			message: { content: null, images: [{ image_url: { url: 'data:image/jpeg;base64,/9j/4AAQ' } }] },
			finish_reason: 'stop',
		},
	],
}

/// Builds the request the Worker would send, and keeps it here.
///
/// The reply is the smallest shape the call accepts, so the function runs to
/// the end rather than throwing on the way — a request captured from a call
/// that failed early would prove nothing about the calls that succeed.
async function request(options, call = complete, reply = WORDS) {
	let captured = null
	const real = globalThis.fetch
	globalThis.fetch = async (url, init) => {
		captured = { url, init }
		return { ok: true, json: async () => reply }
	}
	try {
		await call({ OPENROUTER_API_KEY: KEY }, options.messages, options.opts)
	} finally {
		globalThis.fetch = real
	}
	return { url: captured.url, init: captured.init, body: JSON.parse(captured.init.body) }
}

const plain = { messages: [{ role: 'user', content: SAID }], opts: { model: 'a/b' } }

console.log('— every request says no (rule 8) —')
{
	const { body } = await request(plain)
	check(
		'a plain call refuses data collection',
		body.provider?.data_collection === 'deny',
		JSON.stringify(body.provider),
	)
}
{
	// The branch that adds to `body.provider`. If that object is ever rebuilt
	// rather than added to, this is where the deny disappears — and every
	// structured call is an extraction, which is the memory itself.
	const { body } = await request({
		messages: plain.messages,
		opts: {
			model: 'a/b',
			schema: { name: 'muisto', schema: { type: 'object' } },
			maxTokens: 2000,
		},
	})
	check(
		'and so does a structured one',
		body.provider?.data_collection === 'deny',
		JSON.stringify(body.provider),
	)
	check(
		'which is also the one that adds require_parameters',
		body.provider?.require_parameters === true,
		JSON.stringify(body.provider),
	)
}
{
	// Transcription: the audio itself, as an input_audio part. The recording is
	// the product (rule 3), so it is the last thing that may be collected.
	const { body } = await request({
		messages: [
			{
				role: 'user',
				content: [
					{ type: 'text', text: 'Litteroi.' },
					{ type: 'input_audio', input_audio: { data: 'QUlOTw==', format: 'm4a' } },
				],
			},
		],
		opts: { model: 'a/b', temperature: 0 },
	})
	check(
		'and a request carrying the recording itself',
		body.provider?.data_collection === 'deny',
		JSON.stringify(body.provider),
	)
}
{
	// Colourisation: a family photograph goes up with what was told about it,
	// and a new picture comes back. It is built by `completeImage()`, not
	// `complete()`, so nothing above says anything about it.
	const { body } = await request(
		{
			messages: [
				{
					role: 'user',
					content: [
						{ type: 'text', text: SAID },
						{ type: 'image_url', image_url: { url: 'data:image/jpeg;base64,/9j/4AAQ' } },
					],
				},
			],
			opts: { model: 'a/b', aspectRatio: '4:3' },
		},
		completeImage,
		PICTURE,
	)
	check(
		'and a request carrying a photograph',
		body.provider?.data_collection === 'deny',
		JSON.stringify(body.provider),
	)
}
{
	// Built fresh for every request. Were it one shared object, the structured
	// call's `require_parameters` would ride along on every call after it.
	await request({
		messages: plain.messages,
		opts: { model: 'a/b', schema: { name: 'muisto', schema: { type: 'object' } } },
	})
	const { body } = await request(plain)
	check(
		"and one call's additions do not stick to the next",
		body.provider?.data_collection === 'deny' && body.provider?.require_parameters === undefined,
		JSON.stringify(body.provider),
	)
}

console.log('— and it is not a choice anybody gets to make —')
{
	const { body } = await request({
		messages: plain.messages,
		// Not part of CallOptions, deliberately. This asserts that saying it
		// anyway changes nothing: the rule is in the function, not in the call.
		opts: { model: 'a/b', provider: { data_collection: 'allow' } },
	})
	check(
		'asking for collection is ignored, not honoured',
		body.provider?.data_collection === 'deny',
		JSON.stringify(body.provider),
	)
}

console.log('— and the key goes where keys go —')
{
	const { url, init, body } = await request(plain)
	check(
		'in the Authorization header',
		init.headers?.Authorization === `Bearer ${KEY}`,
		String(init.headers?.Authorization).slice(0, 12) + '…',
	)
	check('and never in the body', !JSON.stringify(body).includes(KEY))
	check('nor in the address', !String(url).includes(KEY), String(url))
	check('which is https', String(url).startsWith('https://'), String(url))
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
