#!/usr/bin/env node
// The one accessibility exemption that is wide enough to grow, pinned to what
// was measured.
//
// `AccessibilityPolicy.isDeliberate` holds twenty-one exemptions. Nineteen of
// them name a single label, a single element type or a frame, and cannot widen
// without somebody writing a new clause. `listHeaderAndFooterText` is the
// exception: it is a Set, so widening it is one line in a literal, and every
// sentence added to it stops being audited on every screen it appears on.
//
// That matters more since the set's gate began forgiving `.textClipped` as
// well as `.dynamicType`. Adding a sentence now switches off two checks rather
// than one, on a rule CLAUDE.md calls the product rather than a checklist.
//
// The failure this guards against is the file's own history rather than a
// hypothetical: the comments inside the set record four separate occasions on
// which a sentence was added after being measured, and the measurement is what
// justifies each one. An entry added without one would look exactly the same.
//
// **This is not a check that clipping still goes red.** Nothing here runs the
// audit; it reads source. What it pins is that the exemption is the size it
// was when somebody last measured it, so widening has to be deliberate and
// visible in a diff rather than quiet. The narrowness itself was measured by
// hand, in a worktree, with a deliberately truncated string outside the set —
// see the comment on the gate in AccessibilityAudit.swift.
//
//   node scripts/audit-exemption-check.mjs
//
// Costs nothing — no simulator, no build. Run it after touching
// AccessibilityPolicy's exemptions.

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const AUDIT = join(root, 'ios', 'KinloreUITests', 'AccessibilityAudit.swift')
const source = readFileSync(AUDIT, 'utf8').split('\n')

// Measured, each one with its reason written beside it in the file. Kept here
// in full rather than as a count: a count would pass a sentence swapped for
// another one, which is the same silence with different words.
const MEASURED = [
	'Kysymys näkyy perheelle Kerro-näytöllä, ja vastaus tallentuu tähän.',
	'Kertomasi muistot ovat vain tässä laitteessa.',
	'Kenen puhelin tämä on',
]

// Both types on purpose. The audit reports whichever the row's current shape
// produces, which is the same reason the precedent for `"Perheen jäsenet ja
// kutsut"` names both. `.contrast` must never appear here: a contrast finding
// forgiven by label would be rule 1 switched off by name, and the tab-bar fade
// already has its own answer that measures pixels instead.
const GATED_TYPES = ['.dynamicType', '.textClipped']

let failures = 0
function check(what, condition, detail = '') {
	const ok = Boolean(condition)
	if (!ok) failures += 1
	console.log(`${ok ? '  ok  ' : '  FAIL'} ${what}${ok || !detail ? '' : ` — ${detail}`}`)
}

// The set, read from its own brackets rather than from a window chosen by hand.
// A window is how this check's author first counted three entries as four.
const opens = source.findIndex((l) => l.includes('let listHeaderAndFooterText'))
check('the set is declared', opens >= 0, 'no listHeaderAndFooterText in the file')
if (opens < 0) process.exit(1)

let closes = -1
for (let i = opens + 1; i < source.length; i += 1) {
	if (/^\s{4}\]\s*$/.test(source[i])) { closes = i; break }
}
check('the set closes', closes > opens, 'no closing bracket at its own indent')
if (closes < 0) process.exit(1)

const entries = []
for (let i = opens + 1; i < closes; i += 1) {
	const line = source[i].trim()
	if (line === '' || line.startsWith('//')) continue
	const quoted = line.match(/^"((?:[^"\\]|\\.)*)",?$/)
	if (quoted) entries.push(quoted[1])
	else check(`line ${i + 1} is an entry or a comment`, false, line.slice(0, 60))
}

check(
	`the set still holds ${MEASURED.length} measured sentences`,
	entries.length === MEASURED.length,
	`found ${entries.length}`,
)
for (const sentence of MEASURED) {
	check(`  still exempt: "${sentence.slice(0, 44)}…"`, entries.includes(sentence))
}
for (const sentence of entries) {
	check(
		`  measured: "${sentence.slice(0, 44)}…"`,
		MEASURED.includes(sentence),
		'added to the set without being added here',
	)
}

// The other half of the pincer, and the half that matters most. The set could
// stay exactly this size while its gate quietly grew a third audit type.
const uses = source
	.map((line, i) => ({ line, i }))
	.filter(({ line }) => line.includes('listHeaderAndFooterText.contains(label)'))
check('exactly one gate reads the set', uses.length === 1, `${uses.length} gates`)

if (uses.length === 1) {
	let first = uses[0].i
	while (first > 0 && !source[first].trim().startsWith('if ')) first -= 1
	const condition = source.slice(first, uses[0].i + 1).join(' ')
	const named = [...condition.matchAll(/issue\.auditType\s*==\s*(\.\w+)/g)].map((m) => m[1])
	check(
		`the gate names ${GATED_TYPES.join(' and ')}`,
		named.length === GATED_TYPES.length && GATED_TYPES.every((t) => named.includes(t)),
		`names ${named.join(', ') || 'nothing'}`,
	)
	check('the gate does not forgive contrast', !named.includes('.contrast'))
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
