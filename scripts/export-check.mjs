#!/usr/bin/env node
// Opens the exported archive and checks that it is what it promises to be.
//
// The export is the one output that leaves the app for good. Its promise is in
// Settings, in the help page and in ARCHITECTURE.md §14: "sen voi avata millä
// tahansa koneella ilman tätä sovellusta". Nothing tested it — XCUITest cannot,
// because the file lands in the app's container and the test runner is not
// allowed to look inside it.
//
// So this runs the app, exports, pulls the zip out of the container and reads
// it. Costs nothing: no AI calls, no network, about a minute.
//
// **The trap it exists to avoid.** The demo archive has no local media, so an
// export of it contains a page and a JSON and looks complete. The half that
// matters — the original audio, which is rule 3's whole point — is only tested
// by an archive with a real recording in it. That is why this script records
// one first with `-defer once` instead of exporting the fixture.
//
//   node scripts/export-check.mjs
//
// Needs: a booted simulator with the app installed (any build or test run does
// that), and DEVELOPER_DIR pointing at the full Xcode as everywhere else here.

import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, readdirSync, existsSync, statSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const BUNDLE = 'com.kinlore.app'
const DEVELOPER_DIR = process.env.DEVELOPER_DIR ?? '/Applications/Xcode.app/Contents/Developer'

let failures = 0

function check(label, condition, detail = '') {
	if (condition) {
		console.log(`  ok   ${label}`)
	} else {
		failures += 1
		console.log(`  FAIL ${label}${detail ? `: ${detail}` : ''}`)
	}
}

function simctl(...args) {
	return execFileSync('xcrun', ['simctl', ...args], {
		encoding: 'utf8',
		env: { ...process.env, DEVELOPER_DIR },
		// Captured rather than inherited: terminating an app that is not running
		// is the ordinary first step here, and it prints four lines of failure
		// that mean nothing. A script whose clean run is full of red text
		// teaches people to skim it.
		stdio: ['ignore', 'pipe', 'pipe'],
	}).trim()
}

/// The device this session is allowed to use. Never "whichever is booted":
/// several sessions work in this worktree at once and installing, launching and
/// terminating one bundle id is exactly what they must not do to each other —
/// CLAUDE.md, the same rule the UI tests follow.
function device() {
	const named = process.env.KINLORE_TEST_SIM
	if (named) return named
	const booted = simctl('list', 'devices', 'booted')
		.split('\n')
		.map((line) => line.match(/\(([0-9A-F-]{36})\) \(Booted\)/))
		.filter(Boolean)
	if (booted.length === 1) return booted[0][1]
	console.error(
		booted.length === 0
			? 'No booted simulator. Boot your own device and set KINLORE_TEST_SIM.'
			: 'Several booted simulators — set KINLORE_TEST_SIM so this does not\n' +
					'interrupt another session mid-run.',
	)
	process.exit(2)
}

function launch(udid, args) {
	try {
		simctl('terminate', udid, BUNDLE)
	} catch {
		// Not running. Fine.
	}
	simctl('launch', udid, BUNDLE, ...args)
}

/// Long enough for a two-second recording, its transcription attempt and the
/// zip to be written. Polled rather than assumed where possible.
function waitFor(seconds) {
	execFileSync('sleep', [String(seconds)])
}

const udid = device()

console.log('— recording something worth exporting —')
try {
	// Otherwise the first launch meets the system's microphone prompt and the
	// recording never happens, which would leave the audio half untested while
	// everything else passed.
	simctl('privacy', udid, 'grant', 'microphone', BUNDLE)
} catch {
	console.log('  (could not grant the microphone; carrying on)')
}
launch(udid, ['-seed', 'empty', '-defer', 'once', '-api', ''])
waitFor(14)

console.log('— exporting —')
launch(udid, ['-seed', 'none', '-tab', 'people', '-screen', 'export', '-api', ''])
waitFor(14)

// What is installed, not what is on disk. This check reads whatever build the
// simulator happens to hold, and a stale one answers every question happily
// with last week's behaviour: the key-set assertion below failed for a whole
// run against an app built before the guessing round was cut, naming a field
// that no longer exists in any source file. Say the age out loud rather than
// guard against it — reinstalling from here would race the very sessions the
// device rule exists to keep apart.
{
	const bundle = simctl('get_app_container', udid, BUNDLE, 'app')
	const installed = statSync(bundle).mtimeMs
	const newest = execFileSync('git', ['ls-files', '-z', 'ios/Kinlore'], { encoding: 'utf8' })
		.split('\0')
		.filter(Boolean)
		.reduce((max, file) => Math.max(max, statSync(file).mtimeMs), 0)
	if (newest > installed) {
		const hours = Math.round((newest - installed) / 36e5 * 10) / 10
		console.log(
			`  note the installed app is older than the sources by ${hours} h — build first,\n` +
				'       or this measures a version of the app nobody is looking at',
		)
	}
}

const container = simctl('get_app_container', udid, BUNDLE, 'data')
// The zip carries its date — Muistoarkisto-2026-09-05.zip — so a family's
// yearly copies do not write over each other. The newest is the one just made.
const tmp = join(container, 'tmp')
const zips = existsSync(tmp)
	? readdirSync(tmp).filter((name) => /^Muistoarkisto-\d{4}-\d{2}-\d{2}\.zip$/.test(name)).sort()
	: []
const zip = zips.length ? join(tmp, zips[zips.length - 1]) : join(tmp, 'Muistoarkisto-<date>.zip')
check('the export wrote a file with the date in its name', zips.length > 0, zip)
if (!zips.length) process.exit(1)

const out = mkdtempSync(join(tmpdir(), 'kinlore-export-'))
execFileSync('unzip', ['-q', zip, '-d', out])
const root = join(out, 'Muistoarkisto')

console.log('— what a family opens —')
const pagePath = join(root, 'muistot.html')
check('there is a readable page', existsSync(pagePath))
const page = existsSync(pagePath) ? readFileSync(pagePath, 'utf8') : ''

// The audio is the product, not a step towards it (rule 3), and a page that
// mentions it without carrying it would pass a shallower check than this.
const audio = page.match(/<audio[^>]*src="([^"]+)"/)
check('the page offers the original audio', audio !== null)
if (audio) {
	const src = audio[1]
	check('by a relative path, so the folder can be moved', !/^([a-z]+:|\/)/i.test(src), src)
	const file = join(root, src)
	check('and the file it points at is in the zip', existsSync(file), src)
	if (existsSync(file)) {
		const bytes = readFileSync(file)
		check('with something in it', bytes.length > 1024, `${bytes.length} bytes`)
		// `file` reads the header rather than the extension: an .m4a that is not
		// one plays on nothing, and that is the failure this whole archive is
		// insurance against.
		check(
			'and it really is audio',
			bytes.subarray(4, 8).toString('ascii') === 'ftyp',
			bytes.subarray(0, 12).toString('hex'),
		)
	}
}

console.log('— what a program reads —')
const jsonPath = join(root, 'arkisto.json')
check('there is a machine-readable copy', existsSync(jsonPath))
if (existsSync(jsonPath)) {
	const archive = JSON.parse(readFileSync(jsonPath, 'utf8'))
	const keys = Object.keys(archive).sort()
	// `guesses` was in this list until the guessing round was cut on
	// 16 Aug 2026 (PLAN.md §5, row 8). Spelled out rather than loosened to a
	// subset test: the point of the assertion is that nothing new drifts into
	// the file a family opens in twenty years, and a subset test would let it.
	check(
		'holding the archive and nothing else',
		keys.join(',') === 'memories,questions,relations,subjects',
		keys.join(','),
	)
	// The outbox and the server's cursor used to travel in here: facts about one
	// phone's sync on one afternoon, in the file a family opens in twenty years.
	check(
		'and none of this phone\'s sync bookkeeping',
		!keys.some((key) => key.startsWith('dirty') || key === 'syncSeq'),
		keys.filter((key) => key.startsWith('dirty') || key === 'syncSeq').join(','),
	)
	check('with the telling in it', archive.memories.length > 0, `${archive.memories.length} memories`)
	// An audio-only memory is a memory: the text arrives later, or never, and
	// the recording is what was promised.
	const withAudio = archive.memories.filter((memory) => memory.audioFilename || memory.audioR2Key)
	check('and the telling knows about its recording', withAudio.length > 0)
}

console.log('— size —')
check('the zip is not empty', statSync(zip).size > 2048, `${statSync(zip).size} bytes`)

// Rule 4 on the page. The demo archive holds Aino as an extraction's
// proposal (`confirmed: false`) with no memories of her own, and the list of
// subjects nobody has spoken about used to name her there — a guess, in the
// one copy that outlives the app. Exported separately because the recorded
// archive above has no proposal in it. Matched on markup rather than on the
// heading, which follows the simulator's language.
console.log('— what the page does not assert —')
launch(udid, ['-seed', 'archive', '-tab', 'people', '-screen', 'export', '-api', ''])
waitFor(14)
{
	const again = readdirSync(tmp).filter((name) => /^Muistoarkisto-\d{4}-\d{2}-\d{2}\.zip$/.test(name)).sort()
	const demoOut = mkdtempSync(join(tmpdir(), 'kinlore-export-demo-'))
	execFileSync('unzip', ['-q', join(tmp, again[again.length - 1]), '-d', demoOut])
	const demoPage = readFileSync(join(demoOut, 'Muistoarkisto', 'muistot.html'), 'utf8')
	const emptyList = [...demoPage.matchAll(/<p class="open">(?!<strong>)([^<]*)<\/p>/g)].map((m) => m[1])
	check('the demo export lists the subjects nobody has spoken about', emptyList.length === 1, `${emptyList.length} lists`)
	const names = (emptyList[0] ?? '').replace(/^[^:]*:\s*/, '').replace(/\.$/, '').split(', ')
	check('and names nobody the family has not confirmed', !names.includes('Aino'), names.join(', '))
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
