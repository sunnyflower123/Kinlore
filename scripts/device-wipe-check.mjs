#!/usr/bin/env node
// Everything this phone remembers about the person holding it, against the one
// function that promises to forget it.
//
// "Tyhjennä tämä laite" is a sentence in a dialog an 80-year-old is asked to
// read and believe. Behind it, `SettingsScreen.wipe()` is a list of calls, and
// the list is all there is: six services keep a device-local record in
// UserDefaults — the ladder's comfort, the upsell rhythm, the deck's skips,
// what the phone has seen of the family's tellings, which faces she was asked
// to name, and the recordings this device gave up on transcribing — and each
// one is cleared because somebody remembered to add a line to that function.
//
// Every one of them says so in its own comment: "Part of emptying the device,
// beside the ladder's, the rhythm's and the seen list's". A comment is not a
// check. The seventh service will be written by somebody who has not read the
// other six, and nothing fails, nothing shows, and no test goes red when its
// record outlives the archive it described. The phone simply keeps a record
// about a person after telling her it had not.
//
// So the rule is read out of the source rather than listed here: every key a
// service stores under is cleared by a reset() in the same file, and every
// such reset() is called by wipe(). A new service joins the rule by existing.
//
// SCOPE, stated rather than implied. This reads `ios/Kinlore/Services/` and
// the one device-local record that lives outside it and is not called reset(),
// `Elder.forgetLargerText()`. `Session`'s own keys are deliberately out: they
// are cleared by `session.renewIdentity()`, which is the wipe's last act and
// has its own reasons, and asserting a guess about them here would be a check
// that goes green for the wrong reason.
//
//   node scripts/device-wipe-check.mjs
//
// Costs nothing — no simulator, no build, no network. Run it after adding a
// UserDefaults key to a service, or after touching wipe().

import { readFileSync, readdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const SERVICES = join(root, 'ios', 'Kinlore', 'Services')
const SETTINGS = join(root, 'ios', 'Kinlore', 'Screens', 'SettingsScreen.swift')
const ELDER = join(root, 'ios', 'Kinlore', 'Design', 'Elder.swift')

let failures = 0
function check(what, condition, detail = '') {
	const ok = Boolean(condition)
	if (!ok) failures += 1
	console.log(`${ok ? '  ok  ' : '  FAIL'} ${what}${ok || !detail ? '' : ` — ${detail}`}`)
}

// --- Readers, kept as pure functions of their source text, so that the
//     self-test at the bottom can run the same ones over a copy broken on
//     purpose. A checker that cannot be made to fail has not been checked.

/// The body of a Swift declaration, brace-matched from its opening line.
function bodyAt(source, signature) {
	const start = source.indexOf(signature)
	if (start < 0) return null
	let depth = 0
	for (let i = start; i < source.length; i += 1) {
		if (source[i] === '{') depth += 1
		else if (source[i] === '}') {
			depth -= 1
			if (depth === 0) return source.slice(start, i + 1)
		}
	}
	return null
}

/// Every `static func reset()` in one file, with the top-level type it sits in.
function resetsIn(source) {
	const lines = source.split('\n')
	const found = []
	for (let i = 0; i < lines.length; i += 1) {
		if (!/^\s*static func reset\(\)/.test(lines[i])) continue
		let type = null
		for (let j = i; j >= 0; j -= 1) {
			const named = lines[j].match(/^(?:final\s+)?(?:enum|class|struct|actor)\s+(\w+)/)
			if (named) {
				type = named[1]
				break
			}
		}
		found.push({ type, body: bodyAt(source.slice(source.indexOf(lines[i])), 'static func reset()') })
	}
	return found
}

/// Every key a file STORES under — writes and removals, never reads.
///
/// The distinction is the whole correctness of this check. On iOS a launch
/// argument arrives as a UserDefaults value, so `-defer once`, `-sample film`,
/// `-sync refused` and five more read through exactly the same call as a
/// stored record does. Eight of them live in these files. A matcher that
/// counted reads reported all eight as records this phone must forget, which
/// is both wrong and the kind of wrong that gets a check disabled.
///
/// Both receiver spellings are here on purpose: the ladder binds
/// `UserDefaults.standard` to a local before writing, so a matcher that
/// insisted on the full name would read that file as storing nothing and pass.
function keysIn(source) {
	const keys = new Set()
	const call = /(?:UserDefaults\.standard|defaults)\.(?:set|removeObject)\(/g
	for (const match of source.matchAll(call)) {
		let depth = 0
		let end = match.index
		for (let i = match.index + match[0].length - 1; i < source.length; i += 1) {
			if (source[i] === '(') depth += 1
			else if (source[i] === ')') {
				depth -= 1
				if (depth === 0) {
					end = i
					break
				}
			}
		}
		const named = source.slice(match.index, end).match(/forKey:\s*(?:Self\.)?([A-Za-z_]\w*|"[^"]*")/)
		if (named) keys.add(named[1])
	}
	return [...keys]
}

/// What is wrong, as a list rather than as printing, so the self-test can ask.
function audit(settings, services) {
	const wipe = bodyAt(settings, 'private func wipe() async {')
	const missingCalls = []
	const missingClears = []
	let types = 0
	let keys = 0

	for (const { name, source } of services) {
		const resets = resetsIn(source)
		const cleared = resets.map((r) => r.body ?? '').join('\n')
		for (const { type } of resets) {
			types += 1
			if (!type) missingCalls.push(`${name}: a reset() outside any named type`)
			else if (!wipe?.includes(`${type}.reset()`)) missingCalls.push(`${type}.reset()`)
		}
		for (const key of keysIn(source)) {
			keys += 1
			if (!cleared.includes(`removeObject(forKey: ${key})`)) {
				missingClears.push(`${name}: ${key}`)
			}
		}
	}
	return { wipe, missingCalls, missingClears, types, keys }
}

// --- The real thing

const services = readdirSync(SERVICES)
	.filter((f) => f.endsWith('.swift'))
	.map((f) => ({ name: f, source: readFileSync(join(SERVICES, f), 'utf8') }))
const settings = readFileSync(SETTINGS, 'utf8')
const elder = readFileSync(ELDER, 'utf8')
const result = audit(settings, services)

console.log('— the function that promises to forget —')
check('wipe() is there to read', Boolean(result.wipe), 'no `private func wipe() async` in SettingsScreen')
check(
	'and the brace matching landed on the whole of it',
	result.wipe?.includes('store.wipe()') && result.wipe?.includes('session.renewIdentity()'),
	'the body is missing its first or last act',
)
if (!result.wipe) process.exit(1)

console.log('\n— every device-local record —')
check(
	`${result.types} services keep one, and the scanner found them`,
	result.types >= 6,
	`found ${result.types}, which is fewer than the six this rule was written over`,
)
check(
	`${result.keys} keys are stored under, and the scanner found them`,
	result.keys >= 8,
	`found ${result.keys}`,
)
check(
	'each one is cleared by its own reset()',
	result.missingClears.length === 0,
	result.missingClears.join('; '),
)
check(
	'and every reset() is called when the device is emptied',
	result.missingCalls.length === 0,
	result.missingCalls.join('; '),
)

console.log('\n— the record that is not called reset() —')
check('Elder still declares forgetLargerText()', elder.includes('static func forgetLargerText()'))
check(
	'and the wipe still calls it',
	result.wipe.includes('Elder.forgetLargerText()'),
	'whose phone this is would outlive the archive it was asked for',
)

// --- The self-test. Both halves of the rule are asserted to go red when the
//     failure they describe is introduced, so this cannot go quietly green on
//     a matcher that stopped matching.

console.log('\n— the check against itself —')
const withoutACall = audit(settings.replace('Deck.reset()', 'Deck.self'), services)
check(
	'a reset() dropped from the wipe is reported',
	withoutACall.missingCalls.includes('Deck.reset()'),
	`reported ${withoutACall.missingCalls.length} missing calls`,
)
const brokenService = services.map((s) =>
	s.name === 'NewFromFamily.swift'
		? { ...s, source: s.source.replace('UserDefaults.standard.removeObject(forKey: seenKey)', '') }
		: s,
)
const withoutAClear = audit(settings, brokenService)
check(
	'a key its reset() stopped clearing is reported',
	withoutAClear.missingClears.some((m) => m.startsWith('NewFromFamily.swift')),
	`reported ${withoutAClear.missingClears.length} missing clears`,
)
check(
	'and an intact tree reports neither',
	result.missingCalls.length === 0 && result.missingClears.length === 0,
)

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
