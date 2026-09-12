#!/usr/bin/env node
// The contrast ratios written into Elder.swift, measured against the colours
// the app actually ships.
//
// Rule 1 says contrast is the one thing eyes cannot check, and that file
// carries twenty-five ratios in its comments — "15.17:1 under primary text",
// "5.59:1 on wax", "1.39:1, never text". They are the argument for every
// colour decision in the app, and **nothing verified any of them**. Edit one
// hex in Assets.xcassets and every sentence around it becomes a lie, silently,
// in the file whose whole job is to be believed.
//
// `page-check.mjs` already does exactly this for the six tokens in
// `kinlore.css`. This is the same move for the app's palette, which had no
// equivalent.
//
// **The audit cannot stand in for it.** `performAccessibilityAudit` measures
// the rendered tree, which is better — it sees what a view actually composed —
// but it needs a simulator and a quiet machine, and on 12 Sep 2026 three
// consecutive suite runs proved it cannot be trusted under load: a run that
// began at load 7 and ended at 472 reported three contrast failures that were
// all the machine, and a run at load 638 reported three more of the same
// (docs in `AccessibilitySweepTests`' header and CLAUDE.md). This costs
// nothing, needs no simulator, and answers at any load — so the two are not
// alternatives. The audit catches a pair nobody wrote down; this catches the
// palette drifting out from under the sentences that justify it.
//
//   node scripts/palette-contrast-check.mjs
//
// Costs nothing. Run it after touching Elder.swift or any .colorset.

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const ELDER = join(root, 'ios', 'Kinlore', 'Design', 'Elder.swift')
const elder = readFileSync(ELDER, 'utf8')

let failures = 0
function check(what, condition, detail = '') {
	if (condition) {
		console.log(`  ok   ${what}`)
	} else {
		failures += 1
		console.log(`  FAIL ${what}${detail ? ` — ${detail}` : ''}`)
	}
}

// ---------------------------------------------------------------- the colours

/// A colour as the asset catalog stores it, alpha included.
///
/// Read from Assets.xcassets rather than restated here: the asset is what the
/// app draws, and a copy in this file would be the thing that drifts.
function asset(name) {
	const path = join(
		root, 'ios', 'Kinlore', 'Assets.xcassets', `${name}.colorset`, 'Contents.json',
	)
	const entry = JSON.parse(readFileSync(path, 'utf8')).colors
		.find((c) => c.color?.components?.red !== undefined)
	const { red, green, blue, alpha } = entry.color.components
	const channel = (v) => (String(v).startsWith('0x') ? parseInt(v, 16) : Math.round(parseFloat(v) * 255))
	return { rgb: [channel(red), channel(green), channel(blue)], alpha: parseFloat(alpha ?? '1') }
}

/// `destructive` is a literal in Elder.swift rather than an asset, so it is
/// read from the source for the same reason the others are read from the
/// catalog: whatever the app draws is what gets measured.
function swiftLiteral(name) {
	const m = elder.match(
		new RegExp(`static let ${name} = Color\\(red: ([\\d.]+), green: ([\\d.]+), blue: ([\\d.]+)\\)`),
	)
	if (!m) throw new Error(`no Color(red:green:blue:) literal for ${name}`)
	return { rgb: m.slice(1, 4).map((v) => Math.round(parseFloat(v) * 255)), alpha: 1 }
}

// ---------------------------------------------------------------- WCAG

const linear = (c) => (c / 255 <= 0.04045 ? c / 255 / 12.92 : (((c / 255) + 0.055) / 1.055) ** 2.4)
const luminance = ([r, g, b]) => 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)

function ratio(fg, bg) {
	const [a, b] = [luminance(fg), luminance(bg)].sort((x, y) => y - x)
	return (a + 0.05) / (b + 0.05)
}

/// A translucent colour is not a colour until something is behind it.
const over = (fg, alpha, bg) => fg.map((c, i) => c * alpha + bg[i] * (1 - alpha))

const paper = asset('Paper').rgb
const card = asset('Card').rgb
const cream = asset('Cream').rgb
const wax = asset('Wax').rgb
const proposal = asset('Proposal').rgb
const affirmative = asset('Affirmative').rgb
const destructive = swiftLiteral('destructive').rgb
const ruleAsset = asset('Rule')

/// **"Ink" is `#1C1917`, not black**, and that is worth stating because it is
/// not obvious and it was got wrong on the way here. Three of the documented
/// ratios are about ink, and under pure black they come out 18.21, 20.18 and
/// 19.89 against a documented 15.17, 16.81 and 16.56 — a consistent offset
/// that looked like drift and was a wrong constant. `Rule`'s own comment names
/// the colour: it is "ink at 16 %", and its asset is #1C1917 at 0.16. With
/// that, all three land exactly.
const ink = ruleAsset.rgb

// ---------------------------------------------------------------- the claims

/// Each row is a sentence in Elder.swift turned into arithmetic.
///
/// `claimed` is checked twice over: the computed ratio has to match it, **and**
/// the number has to still appear in Elder.swift as written. So an edited hex
/// fails on the first and an edited sentence fails on the second, and the two
/// can only move together on purpose.
///
/// `floor` is what the pair has to clear — 4.5 for anything carrying words,
/// 3.0 for a shape judged by WCAG 1.4.11. `ceiling` is for the one colour
/// that must stay *under* a bound: a hairline that measured like a boundary
/// would be a boundary somebody relied on.
const CLAIMS = [
	{ what: 'paper under primary text', fg: ink, bg: paper, claimed: 15.17, floor: 4.5 },
	{ what: 'card under primary text', fg: ink, bg: card, claimed: 16.81, floor: 4.5 },
	{ what: 'cream on ink', fg: cream, bg: ink, claimed: 16.56, floor: 4.5 },
	{ what: 'cream on wax', fg: cream, bg: wax, claimed: 5.59, floor: 4.5 },
	{ what: 'wax against paper', fg: wax, bg: paper, claimed: 5.12, floor: 3 },
	{ what: 'proposal on paper', fg: proposal, bg: paper, claimed: 5.14, floor: 4.5 },
	{ what: 'proposal on card', fg: proposal, bg: card, claimed: 5.7, floor: 4.5 },
	{ what: 'affirmative on paper', fg: affirmative, bg: paper, claimed: 5.26, floor: 4.5 },
	{ what: 'affirmative on card', fg: affirmative, bg: card, claimed: 5.83, floor: 4.5 },
	// Measured on the ground the app has. Until 12 Sep 2026 this sentence
	// quoted 6.5:1, which is the number on WHITE — the exact trap the top of
	// Elder.swift warns about, where #C2410C is 5.2:1 on white and 4.43:1 on
	// this parchment. It stayed above the minimum, so nothing was wrong with
	// the colour; what was wrong was the evidence for it.
	{ what: 'destructive on paper', fg: destructive, bg: paper, claimed: 5.67, floor: 4.5 },
	{ what: 'destructive on card', fg: destructive, bg: card, claimed: 6.28, floor: 4.5 },
	// Never text and never the only edge of a control. The check is that it
	// stays UNDER the bound a boundary would have to clear.
	//
	// Against `card`, which is the ground it is actually drawn on — `elderCard`
	// puts this hairline round a card. On `paper` the same colour is 1.3845,
	// and taking that for the claim was this script's own first error: it
	// reported Elder.swift as drifting when the file was right and the table
	// here had picked the wrong ground.
	{
		what: 'rule is a suggestion of an edge, not an edge',
		fg: over(ruleAsset.rgb, ruleAsset.alpha, card), bg: card, claimed: 1.39, ceiling: 3,
	},
]

// **`Elder.supporting` is deliberately not in that table**, and the reason is
// the limit of what this script may claim to know.
//
// It is `Color.primary.opacity(0.75)`, and `Color.primary` is the system's
// label colour — not a value this repository declares anywhere. Measuring it
// would mean hard-coding what iOS draws for `.label` in light mode, and the
// answer moves the result a long way: pure black gives 9.62:1 on paper, the
// 85 %-black figure quoted two comments above it in Elder.swift gives 6.31:1,
// and the file itself says "about 6.6:1". All three clear the minimum
// comfortably, so nothing here is unsafe — but a check that asserted one of
// them would be asserting a guess, and a guess that goes green is worse than
// no check.
//
// The audit is the right instrument for that pair, because it reads the
// pixels iOS actually drew. This script's claim is narrower and is the one it
// can keep: the colours this repository owns, measured against each other.

console.log('— the ratios Elder.swift argues from —')
for (const { what, fg, bg, claimed, floor, ceiling } of CLAIMS) {
	const got = ratio(fg, bg)
	check(
		`${what} is ${claimed}:1`,
		Math.abs(got - claimed) < 0.01,
		`computed ${got.toFixed(2)}:1`,
	)
	if (floor !== undefined) {
		check(`  and clears ${floor}:1`, got >= floor, `computed ${got.toFixed(2)}:1`)
	}
	if (ceiling !== undefined) {
		check(`  and stays under ${ceiling}:1`, got < ceiling, `computed ${got.toFixed(2)}:1`)
	}
}

console.log('— and the file still says so —')
// The other half of the pincer. Without this the table above could be quietly
// corrected to match a changed asset while every sentence in Elder.swift went
// on claiming the old number — which is the failure this script exists for,
// wearing the opposite face.
for (const { what, claimed } of CLAIMS) {
	check(
		`Elder.swift still writes ${claimed}:1 (${what})`,
		elder.includes(`${claimed}:1`) || elder.includes(`${claimed.toFixed(2)}:1`),
		`no "${claimed}:1" anywhere in the file`,
	)
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
