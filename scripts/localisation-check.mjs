#!/usr/bin/env node
// Every string the app shows has an English translation.
//
//   node scripts/localisation-check.mjs
//
// The app is written in Finnish and English is its default, which sounds like a
// contradiction and is not. SwiftUI treats a string literal in Text, Button,
// Label, navigationTitle and accessibilityLabel as a lookup key, so the Finnish
// source strings are the KEYS; both tables translate away from them. English is
// the default because the app is presented, judged and filmed in English, and a
// phone with no Finnish should not be handed a language its owner cannot read.
// A Finnish phone still gets Finnish.
//
// That cheapness is also the whole risk. Nothing about writing
//
//     Text("Uusi nappi")
//
// tells anybody a translation is now missing. The Finnish build is perfect, the
// build succeeds, no warning is emitted, and the English build shows one Finnish
// word in the middle of an English screen — which is the exact defect the site
// had and which took a person reading it to find. Nobody runs the app in English
// except when filming, and by then it is the evening of the shoot.
//
// So this counts. It is the only thing standing between "English mode" and
// "English mode except wherever somebody has worked since".
//
// WHAT IT DOES NOT DO:
//
//   * Judge the translations. A wrong one passes. A missing one does not.
//   * Find strings composed at runtime. A String built from parts and handed to
//     Text is not looked up at all, and a regex cannot tell one from a literal.
//     Three of those were found by running the app in English and reading the
//     screen: the placement sentence, the subject-kind label and the date
//     precision picker. There is no substitute for looking, only a guard
//     against the cases where looking is not necessary.
//   * Judge the Finnish. It checks that fi.lproj has an entry for every key,
//     which is what stops a Finnish phone falling through to English — not that
//     the entry says the right thing. The entries are generated from the keys,
//     so being wrong would mean the key itself is wrong.
//
// Exits non-zero listing every key with no English.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const swiftRoot = join(root, 'ios/Kinlore');

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    return statSync(p).isDirectory() ? swiftFiles(p) : p.endsWith('.swift') ? [p] : [];
  });
}

// The initialisers whose first string argument SwiftUI reads as a
// LocalizedStringKey. A literal anywhere else in this app is not shown to
// anybody, and adding one here that is not user-facing would make this check
// demand translations for identifiers.
// The SwiftUI initialisers that read a literal as a LocalizedStringKey, plus
// String(localized:) — which is how the exported archive's prose is looked up.
// The export is not SwiftUI and is the one output that leaves the app for good,
// so its strings are the last place a missing translation should hide.
// Two shapes, not one alternation with an optional bracket: the SwiftUI
// initialisers take the literal as their first argument, String(localized:)
// takes it after a label. Folding them together needs an optional paren, and an
// optional paren matches Text followed by anything at all — which on the first
// attempt swallowed a doc comment whole and reported it as an untranslated
// string. Two patterns cost one more line and cannot do that.
const SHOWN = [
  String.raw`(?:Text|Button|Label|Toggle|TextField|SecureField`
    + String.raw`|navigationTitle|accessibilityLabel|accessibilityHint|alert|confirmationDialog)`
    + String.raw`\s*\(\s*"((?:[^"\\]|\\.)*)"`,
  String.raw`String\(localized:\s*"((?:[^"\\]|\\.)*)"`,
];

// The help page hands its sentences to a helper rather than to Text, and the
// patterns above cannot see through a helper: the whole page was Finnish under
// an English title on an English phone until 4 Sep 2026, and nothing here
// noticed. Every string literal inside a `section(` call is a key — comments
// included, which is why HelpScreen keeps its comments outside the calls.
const HELPER = String.raw`\bsection\s*\(((?:[^()"]|"(?:[^"\\]|\\.)*")*)\)`;
const LITERAL = String.raw`"((?:[^"\\]|\\.)*)"`;

const keys = new Set();
const add = (key) => {
  if (!/[a-zA-ZäöåÄÖÅ]/.test(key)) return;          // "·", "%@" and friends
  if (key.includes('\\(')) return;                   // interpolated: see below
  keys.add(key);
};
for (const file of swiftFiles(swiftRoot)) {
  const src = readFileSync(file, 'utf8');
  for (const m of SHOWN.flatMap((p) => [...src.matchAll(new RegExp(p, 'g'))])) add(m[1]);
  for (const call of src.matchAll(new RegExp(HELPER, 'g'))) {
    for (const m of call[1].matchAll(new RegExp(LITERAL, 'g'))) add(m[1]);
  }
}

const keysOf = (lproj) => new Set(
  [...readFileSync(join(root, `ios/Kinlore/${lproj}.lproj/Localizable.strings`), 'utf8')
    .matchAll(/^"((?:[^"\\]|\\.)*)"\s*=/gm)].map((m) => m[1])
);
const translated = keysOf('en');

// The two tables have to carry the same keys, and this is not tidiness.
// fi.lproj was deliberately EMPTY while Finnish was the development language: a
// key with no entry renders as itself, and the keys are the Finnish. When
// English became the default on 30 Aug 2026 that inverted — the fallback for a
// missing key is the DEVELOPMENT language, not the key — and a Finnish phone
// looked in fi.lproj, found nothing, fell through to en.lproj and was shown
// English. The app spoke the wrong language to the one person it was built for,
// and it took a screenshot on a Finnish device to see it. Nothing else reported
// it: the build was clean and the English was correct English.
const finnish = keysOf('fi');
const missingFi = [...translated].filter((k) => !finnish.has(k));
const strayFi = [...finnish].filter((k) => !translated.has(k));
if (missingFi.length || strayFi.length) {
  console.error(
    `the two tables have drifted — a key missing from fi.lproj is shown in `
    + `English on a Finnish phone\n`
  );
  for (const k of missingFi) console.error(`  only in en.lproj: "${k}"`);
  for (const k of strayFi) console.error(`  only in fi.lproj: "${k}"`);
  console.error('\nRegenerate fi.lproj from the keys of en.lproj.');
  process.exit(1);
}

const missing = [...keys].filter((k) => !translated.has(k)).sort();

// An interpolated literal becomes a format key — "Poista \(x)" is looked up as
// "Poista %@" — and which specifier depends on the interpolated type, which no
// regex knows. They are counted rather than checked, so that a sudden change in
// how many there are is at least visible.
const interpolated = new Set();
for (const file of swiftFiles(swiftRoot)) {
  const src = readFileSync(file, 'utf8');
  for (const m of SHOWN.flatMap((p) => [...src.matchAll(new RegExp(p, 'g'))])) {
    if (m[1].includes('\\(')) interpolated.add(m[1]);
  }
}
const formatKeys = [...translated].filter((k) => /%(@|lld|ld|d)/.test(k)).length;

if (missing.length) {
  console.error(`${missing.length} string(s) shown to the user with no English:\n`);
  for (const k of missing) console.error(`  "${k}"`);
  console.error('\nAdd them to ios/Kinlore/en.lproj/Localizable.strings.');
  process.exit(1);
}

console.log(
  `${keys.size} literal keys, all translated; ${interpolated.size} interpolated, `
  + `${formatKeys} format keys; fi and en tables match at ${finnish.size} entries`
);
