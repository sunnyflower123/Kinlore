#!/usr/bin/env node
// The photographs and the voices, and who can reach them.
//
// R2 holds the two things this app exists to keep: the scanned photographs and
// the original audio of people who are often dead. `/media` is the only way in
// or out, and until now nothing checked either direction — the inventory said
// "Done and tested" and the export check reads media off the device, not out of
// the bucket.
//
// Four rules, and the second is the one that matters most:
//
// 1. What goes up comes back down, byte for byte. A photograph that returns
//    corrupted is a photograph nobody can tell is corrupted until they look.
// 2. **Another family cannot fetch it.** The key carries the family id and the
//    check happens before the bucket is touched, so guessing a key does not even
//    cause a lookup. This is §4's boundary applied to the content itself.
// 3. Audio is never refused for the photo limit. Rule 3: the recording is the
//    product, and a family out of photograph slots must still be able to keep a
//    voice.
// 4. Nothing anonymous gets in.
//
// Costs nothing: no AI, no money, and the bytes are a few hundred. Locally
// `wrangler dev` gives R2 its own simulated bucket, so this touches no real
// storage.
//
// Requires a running Worker:
//   cd backend && npx wrangler dev
//
//   node scripts/media-check.mjs

import { randomUUID, randomBytes } from 'node:crypto'

const API = process.argv[2] ?? 'http://localhost:8787'
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
	return { name, memberID, secret, auth: { Authorization: `Bearer ${memberID}.${secret}` } }
}

async function createFamily(who) {
	const response = await fetch(`${API}/family`, {
		method: 'POST',
		headers: json,
		body: JSON.stringify({
			memberID: who.memberID,
			secret: who.secret,
			displayName: who.name,
			familyName: `${who.name} check`,
		}),
	})
	if (!response.ok) throw new Error(`could not create a family: ${response.status}`)
	return response.json()
}

async function put(who, kind, bytes) {
	const response = await fetch(`${API}/media?kind=${kind}`, {
		method: 'POST',
		headers: { ...who.auth, 'content-type': 'application/octet-stream' },
		body: bytes,
	})
	return { status: response.status, body: await response.json().catch(() => ({})) }
}

async function get(who, key) {
	const response = await fetch(`${API}/media/${encodeURIComponent(key)}`, { headers: who.auth })
	return {
		status: response.status,
		bytes: response.ok ? Buffer.from(await response.arrayBuffer()) : Buffer.alloc(0),
	}
}

try {
	const mummo = person('Mummo')
	const stranger = person('Tuntematon')
	await createFamily(mummo)
	await createFamily(stranger)

	console.log('— what goes up comes back —')
	// Not random noise: a JPEG header, because the route sets a content type by
	// kind and something downstream may one day care what the bytes claim to be.
	const photo = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), randomBytes(512)])
	let key = ''
	{
		const { status, body } = await put(mummo, 'photo', photo)
		key = body.key ?? ''
		check('a photograph is accepted', status === 200 && key.length > 0, JSON.stringify(body))
	}
	{
		const { status, bytes } = await get(mummo, key)
		check(
			'and comes back byte for byte',
			status === 200 && bytes.equals(photo),
			`${status}, ${bytes.length} of ${photo.length} bytes`,
		)
	}

	console.log('— and nobody else can reach it —')
	{
		const { status } = await get(stranger, key)
		// 404 rather than 403, and the key is checked before the bucket is
		// touched: guessing must not even cause a lookup, and the answer must not
		// say whether the guess was close.
		check('another family gets nothing, and no hint', status === 404, String(status))
	}
	{
		const response = await fetch(`${API}/media/${encodeURIComponent(key)}`)
		check('and neither does somebody with no identity', response.status === 401, String(response.status))
	}

	console.log('— the voice is never refused for the photo limit (rule 3) —')
	{
		// A recording is not a photograph and does not answer to its ceiling. The
		// upload path checks the count only for `kind=photo`, and this is that
		// sentence made into a test.
		const audio = Buffer.concat([Buffer.from('ftypM4A '), randomBytes(256)])
		const { status, body } = await put(mummo, 'audio', audio)
		check('audio is accepted on the free tier', status === 200 && !!body.key, JSON.stringify(body))
		const { bytes } = await get(mummo, body.key ?? '')
		check('and it comes back whole', bytes.equals(audio), `${bytes.length} of ${audio.length} bytes`)
	}

	console.log('— and the obvious refusals —')
	{
		const { status } = await put(mummo, 'photo', Buffer.alloc(0))
		check('an empty upload is refused', status === 413, String(status))
	}
	{
		const { status } = await put(mummo, 'kirje', randomBytes(64))
		check('and so is a kind nobody asked for', status === 400, String(status))
	}
} catch (error) {
	failures += 1
	console.log(`\n  FAIL ${error.message}`)
	console.log('       Is the Worker running? cd backend && npx wrangler dev')
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
