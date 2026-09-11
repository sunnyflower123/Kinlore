// Rule 7, as a check instead of a habit.
//
// `OPENROUTER_API_KEY` lives only as a Worker secret, and CLAUDE.md's
// instruction for keeping it that way is "check `.dev.vars` before every
// push". That is a reminder rather than a check, and this repository has
// already been taught what a reminder is worth: `family-crypto-check` sat
// broken for a week because its own instruction said to run it after touching
// a file nobody had touched.
//
// **The asymmetry is why this one is worth a script.** Every other invariant
// here fails into something that can be fixed by the next commit. This one
// cannot. The repository goes public on 28 Sep and publishes its *history*,
// not merely its head — so a key committed today and deleted tomorrow is
// still published, and the only remedy left is rotating the key and rewriting
// 260-odd commits. A check that costs seven seconds against that is free.
//
// Three things, in the order they can go wrong:
//
//   1. The mechanism. `.dev.vars` is in `.gitignore` and is not tracked.
//      Both halves matter: a file already tracked keeps being committed no
//      matter what `.gitignore` says afterwards.
//   2. The tree. No tracked file holds a key-shaped string right now, which
//      is the commit about to be made.
//   3. The history. No commit ever held one. CLAUDE.md states this as
//      measured on 9 Sep 2026; nothing re-measured it, and every commit since
//      was a chance to make it false.
//
// It also tests itself. A matcher that has quietly stopped matching is worse
// than no matcher, because it reports green — so every pattern is run against
// a key of that shape before it is trusted, and the run fails if one slips
// through. The specimens are assembled at run time from pieces, so this file
// does not itself contain a string that its own tree scan would flag: a
// scanner that has to skip a file has a hole exactly the size of that file.
//
//   node scripts/secret-check.mjs
//
// Costs nothing: no network, no key, no Worker.

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

/** Every shape worth refusing, with a specimen of it built from pieces. */
const PATTERNS = [
	{
		name: 'OpenRouter key',
		re: /sk-or-v1-[0-9a-f]{32,}/,
		specimen: () => 'sk-' + 'or-v1-' + 'a1b2c3d4'.repeat(8),
	},
	{
		name: 'OpenAI-style key',
		re: /\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}/,
		specimen: () => 'sk-' + 'proj-' + 'A1b2C3d4E5f6G7h8I9j0K1',
	},
	{
		name: 'GitHub token',
		re: /\b(?:ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})/,
		specimen: () => 'ghp' + '_' + 'A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8',
	},
	{
		name: 'AWS access key id',
		re: /\bAKIA[0-9A-Z]{16}\b/,
		specimen: () => 'AKI' + 'A' + 'ABCDEFGHIJKLMNOP',
	},
	{
		name: 'Google API key',
		re: /\bAIza[0-9A-Za-z_-]{35}\b/,
		specimen: () => 'AIz' + 'a' + 'A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r',
	},
	{
		name: 'Slack token',
		re: /\bxox[baprs]-[A-Za-z0-9-]{12,}/,
		specimen: () => 'xox' + 'b-' + '123456789012-abcdefghijkl',
	},
	{
		// The shape a `.dev.vars` line has, wherever it is pasted. Sixteen
		// characters of value at least, so `OPENROUTER_API_KEY: string` in a
		// type and `env.OPENROUTER_API_KEY` in code are not it.
		name: 'a secret assigned a literal',
		re: /\b[A-Z][A-Z0-9_]*(?:_KEY|_SECRET|_TOKEN|_PASSWORD)\s*[:=]\s*["']?[A-Za-z0-9/+_-]{16,}/,
		specimen: () => 'OPENROUTER' + '_API_KEY=' + 'abcdefghijklmnop',
	},
]

let failures = 0

function check(label, ok, detail) {
	process.stdout.write(`  ${ok ? 'ok  ' : 'FAIL'}  ${label}\n`)
	if (!ok) {
		failures += 1
		if (detail) process.stdout.write(`        ${detail}\n`)
	}
}

function git(...args) {
	return execFileSync('git', args, {
		cwd: ROOT,
		encoding: 'utf8',
		maxBuffer: 512 * 1024 * 1024,
	})
}

/** The first pattern that matches, and the line it matched on. */
function firstHit(text) {
	for (const { name, re } of PATTERNS) {
		const m = re.exec(text)
		if (m) {
			const upto = text.slice(0, m.index)
			const line = upto.slice(upto.lastIndexOf('\n') + 1)
			return { name, line: (line + m[0]).slice(0, 120) }
		}
	}
	return null
}

// --- 0 · the matcher itself -------------------------------------------------

process.stdout.write('\n— the matcher catches what it is for —\n')
for (const p of PATTERNS) {
	const s = p.specimen()
	check(p.name, p.re.test(s), `did not match its own specimen: ${s.slice(0, 24)}…`)
}

// --- 1 · the mechanism ------------------------------------------------------

process.stdout.write('\n— the mechanism that keeps the key out —\n')

const ignore = existsSync(join(ROOT, '.gitignore'))
	? readFileSync(join(ROOT, '.gitignore'), 'utf8')
	: ''
check(
	'.dev.vars is in .gitignore',
	ignore.split('\n').some((l) => l.trim().replace(/^\/+/, '') === '.dev.vars'),
	'add a line reading .dev.vars'
)

const tracked = git('ls-files').split('\n').filter(Boolean)
const trackedVars = tracked.filter((f) => f.endsWith('.dev.vars'))
check(
	'no .dev.vars is tracked',
	trackedVars.length === 0,
	trackedVars.join(', ')
)

// A file that is ignored *and* tracked is the trap: git goes on committing it
// and `.gitignore` says nothing, because `.gitignore` only speaks about files
// git has not been told about yet. `ls-files -i -c` asks that question
// directly — asking it per file with `check-ignore` was 189 process spawns and
// most of this check's running time.
const ignoredButTracked = git('ls-files', '-i', '-c', '--exclude-standard')
	.split('\n')
	.filter(Boolean)
check(
	'nothing is both ignored and tracked',
	ignoredButTracked.length === 0,
	ignoredButTracked.slice(0, 5).join(', ')
)

// --- 2 · the tree -----------------------------------------------------------

process.stdout.write('\n— the commit about to be made —\n')

let treeHit = null
for (const file of tracked) {
	const path = join(ROOT, file)
	if (!existsSync(path)) continue
	let body
	try {
		body = readFileSync(path, 'utf8')
	} catch {
		continue // a binary or unreadable file holds no pasted key
	}
	const hit = firstHit(body)
	if (hit) {
		treeHit = `${file}: ${hit.name} — ${hit.line}`
		break
	}
}
check(`no tracked file holds a key (${tracked.length} files)`, treeHit === null, treeHit)

// --- 3 · the history --------------------------------------------------------

process.stdout.write('\n— every commit that will be published —\n')

// Every blob that has ever existed, each read once, rather than every
// commit's rendered patch. It is both faster and wider: a blob reachable from
// any branch or tag is here, and a file added and deleted in the same
// afternoon still has its blob. Scanned one at a time and never joined into a
// single string — these patterns are cheap on a file and expensive on a
// hundred megabytes of one, which cost this check fifteen seconds before it
// was measured.
//
// The matching stays in JavaScript rather than being handed to `grep`, which
// would be faster still. macOS ships BSD grep and CI runs GNU grep, and the
// two do not agree about `\b` — a check that quietly matches less on one of
// the machines it runs on is the exact failure this file exists to prevent.
// **One `git cat-file`, not one per blob.** Every blob that has ever existed
// comes back in a single stream — which is both faster than rendering every
// commit's patch and wider, because a blob reachable from any branch or tag is
// in it and so is a file that was added and deleted in the same afternoon.
//
// Two shapes of this were measured before this one was kept: joining every
// patch into a single string took 18 s, because these patterns are cheap on a
// file and expensive on a hundred megabytes of one; spawning `git cat-file` per
// blob took 82 s, all of it process startup. Reading the stream once and
// scanning each blob's own slice takes seconds.
//
// The matching stays in JavaScript rather than being handed to `grep`, which
// would be faster still. macOS ships BSD grep and CI runs GNU grep, and the two
// do not agree about `\b` — a check that quietly matches less on one of the
// machines it runs on is the exact failure this file exists to prevent.
const stream = execFileSync(
	'git',
	['cat-file', '--batch-all-objects', '--batch', '--buffer'],
	{ cwd: ROOT, maxBuffer: 2048 * 1024 * 1024 }
)

let historyHit = null
let blobs = 0
let at = 0
while (at < stream.length) {
	// `<sha> <type> <size>\n<contents>\n`
	const nl = stream.indexOf(0x0a, at)
	if (nl === -1) break
	const [sha, type, size] = stream.toString('utf8', at, nl).split(' ')
	const length = Number(size)
	if (!Number.isFinite(length)) break
	const body = stream.subarray(nl + 1, nl + 1 + length)
	at = nl + 1 + length + 1
	if (type !== 'blob') continue
	blobs += 1
	const hit = firstHit(body.toString('utf8'))
	if (hit) {
		historyHit = `${sha.slice(0, 8)}: ${hit.name} — ${hit.line}`
		break
	}
}

const commits = git('rev-list', '--all').split('\n').filter(Boolean)
check(
	`no blob ever held one (${blobs} blobs, ${commits.length} commits)`,
	historyHit === null,
	historyHit
)

// --- and the answer ---------------------------------------------------------

process.stdout.write('\n')
if (failures > 0) {
	process.stdout.write(`${failures} failed.\n`)
	process.exit(1)
}
process.stdout.write('all checks passed\n')
