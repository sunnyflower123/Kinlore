// The browser half of PLAN.md §10 lever 3. Pair to webcrypto-interop-check.swift
// beside it, which explains what is being measured and why.
//
// Nothing here is Node-specific on purpose: `webcrypto.subtle` is the same
// WebCrypto API a page gets, called the same way, so what passes here passes in
// Safari and in Chrome. There is no library, no polyfill and no helper — a
// helper would be a second implementation, and then the check would be measuring
// the helper.
//
// Reads the sealed material on stdin from the Swift half's `emit`, and writes
// what it sealed in return to the path given as the first argument, for that
// half's `verify` to open. The command that chains all three is in CLAUDE.md.
//
// Exit status is the point: 0 when a browser can read this archive, 1 when it
// cannot. Shown to be load-bearing by tampering with one character of a sealed
// body and dropping one byte from the sealed bytes — that reddens exactly those
// two lines and leaves the other five green.

import { webcrypto } from 'node:crypto'
import { readFileSync, writeFileSync } from 'node:fs'

const subtle = webcrypto.subtle

/// The version marker FamilyCrypto writes. A value without it is plaintext from
/// before lever 3 and must pass through untouched.
const MARKER = 'k1.'

const b64 = (bytes) => Buffer.from(bytes).toString('base64')
const unb64 = (text) => new Uint8Array(Buffer.from(text, 'base64'))
const hex = (bytes) => Buffer.from(bytes).toString('hex')
const sha256 = async (bytes) => new Uint8Array(await subtle.digest('SHA-256', bytes))

let failures = 0
function report(ok, label, detail = '') {
	console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? ` — ${detail}` : ''}`)
	if (!ok) failures++
}

const returnPath = process.argv[2]
if (!returnPath) {
	console.error('usage: webcrypto-interop-check emit | node scripts/webcrypto-interop-check.mjs <return-file>')
	process.exit(2)
}

const emitted = JSON.parse(readFileSync(0, 'utf8'))
const keyBytes = unb64(emitted.key)

const aes = await subtle.importKey('raw', keyBytes, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt'])
const mac = await subtle.importKey('raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])

/// A sealed value is MARKER + base64(nonce ‖ ciphertext ‖ tag). CryptoKit calls
/// that whole tail `combined`; WebCrypto wants the 12-byte nonce as `iv` and
/// everything after it — authentication tag included — as the body.
const split = (combined) => ({ iv: combined.slice(0, 12), body: combined.slice(12) })

async function openString(sealed) {
	if (!sealed.startsWith(MARKER)) return sealed
	const { iv, body } = split(unb64(sealed.slice(MARKER.length)))
	const plain = await subtle.decrypt({ name: 'AES-GCM', iv, tagLength: 128 }, aes, body)
	return new TextDecoder().decode(plain)
}

console.log('\nCryptoKit sealed it, WebCrypto opens it')
console.log('─'.repeat(58))

// A memory body. The randomised seal, and the thing a reader is actually here for.
try {
	const opened = await openString(emitted.sealedBody)
	report(opened === emitted.body, 'randomised text seal opens')
} catch (error) {
	report(false, 'randomised text seal opens', error.message)
}

// A subject title. The deterministic seal, which is the one sync.ts compares.
try {
	const opened = await openString(emitted.sealedTitleA)
	report(opened === emitted.title, 'deterministic title seal opens')
} catch (error) {
	report(false, 'deterministic title seal opens', error.message)
}

// The property sync.ts depends on, checked here because a browser that gets it
// wrong wipes coordinates rather than showing an error.
report(emitted.sealedTitleA === emitted.sealedTitleB, 'the same title seals to the same bytes twice')

// Can a browser REPRODUCE the nonce? Reading never needs this; writing a title
// does, and without it every push from a web client reads as a rename.
try {
	const derived = new Uint8Array(await subtle.sign('HMAC', mac, new TextEncoder().encode(emitted.title))).slice(0, 12)
	const actual = split(unb64(emitted.sealedTitleA.slice(MARKER.length))).iv
	report(hex(derived) === hex(actual), 'WebCrypto reproduces the HMAC-derived nonce', hex(derived))
} catch (error) {
	report(false, 'WebCrypto reproduces the HMAC-derived nonce', error.message)
}

// A photograph or a recording. The marker is raw bytes here, not base64, and the
// hash is what catches a re-encoding that would otherwise look like success.
try {
	const raw = unb64(emitted.sealedBytesB64)
	const prefix = new TextEncoder().encode(MARKER)
	const marked = prefix.every((byte, index) => raw[index] === byte)
	const { iv, body } = split(raw.slice(prefix.length))
	const plain = new Uint8Array(await subtle.decrypt({ name: 'AES-GCM', iv, tagLength: 128 }, aes, body))
	report(marked && hex(await sha256(plain)) === emitted.bytesSHA256,
		'sealed bytes open, SHA-256 matches byte for byte', `${plain.length} bytes`)
} catch (error) {
	report(false, 'sealed bytes open, SHA-256 matches byte for byte', error.message)
}

// Pre-lever-3 plaintext. FamilyCrypto.open hands an unmarked value back
// unchanged; a browser that does not would show a family nothing.
report(await openString('vanha selkokielinen arvo') === 'vanha selkokielinen arvo',
	'unmarked legacy plaintext passes through')

// The wrong key must fail closed. Returning something would be worse than any
// error here — it is the case FamilyCrypto's own doc comment is written against.
try {
	const stranger = await subtle.importKey('raw', webcrypto.getRandomValues(new Uint8Array(32)), { name: 'AES-GCM' }, false, ['decrypt'])
	const { iv, body } = split(unb64(emitted.sealedBody.slice(MARKER.length)))
	await subtle.decrypt({ name: 'AES-GCM', iv, tagLength: 128 }, stranger, body)
	report(false, 'the wrong key is refused', 'it decrypted, which is the worst outcome available')
} catch {
	report(true, 'the wrong key is refused, not silently wrong')
}

// The return direction, sealed here and handed to the Swift half.
const expected = 'Selaimessa suljettu: Aino ja Ville, Puumala 1953.'
const iv = webcrypto.getRandomValues(new Uint8Array(12))
const sealedByBrowser = MARKER + b64(Buffer.concat([
	Buffer.from(iv),
	Buffer.from(new Uint8Array(await subtle.encrypt({ name: 'AES-GCM', iv, tagLength: 128 }, aes, new TextEncoder().encode(expected)))),
]))

const byteSource = new Uint8Array(Array.from({ length: 256 }, (_, index) => index))
const byteIV = webcrypto.getRandomValues(new Uint8Array(12))
const sealedBytesByBrowserB64 = b64(Buffer.concat([
	Buffer.from(MARKER),
	Buffer.from(byteIV),
	Buffer.from(new Uint8Array(await subtle.encrypt({ name: 'AES-GCM', iv: byteIV, tagLength: 128 }, aes, byteSource))),
]))

writeFileSync(returnPath, JSON.stringify({
	key: emitted.key,
	sealedByBrowser,
	expected,
	sealedBytesByBrowserB64,
	expectedBytesSHA256: hex(await sha256(byteSource)),
}))

console.log('\nWebCrypto sealed it, CryptoKit opens it')
console.log('─'.repeat(58))

process.exitCode = failures === 0 ? 0 : 1
