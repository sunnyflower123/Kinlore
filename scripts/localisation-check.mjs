#!/usr/bin/env node
// Every string the app shows has an English translation.
//
//   node scripts/localisation-check.mjs
//
// The app speaks Finnish because the person it was built for does. English was
// added on 30 Aug 2026 so that the app can be shown to people who do not read
// Finnish — the competition's judges, and the demo video — and it was added in
// the cheapest possible way: SwiftUI already treats a string literal in Text,
// Button, Label, navigationTitle and accessibilityLabel as a lookup key, so the
// Finnish source strings ARE the keys and en.lproj/Localizable.strings is the
// only new file that carries text.
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
//   * Check Finnish. Finnish is the development language, so a key with no
//     entry anywhere renders as itself, which is the Finnish. That is why
//     fi.lproj/Localizable.strings is deliberately empty.
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
const SHOWN = String.raw`(?:Text|Button|Label|Toggle|TextField|SecureField`
  + String.raw`|navigationTitle|accessibilityLabel|accessibilityHint|alert|confirmationDialog)`;

const keys = new Set();
for (const file of swiftFiles(swiftRoot)) {
  const src = readFileSync(file, 'utf8');
  for (const m of src.matchAll(new RegExp(SHOWN + String.raw`\(\s*"((?:[^"\\]|\\.)*)"`, 'g'))) {
    const key = m[1];
    if (!/[a-zA-ZäöåÄÖÅ]/.test(key)) continue;          // "·", "%@" and friends
    if (key.includes('\\(')) continue;                   // interpolated: see below
    keys.add(key);
  }
}

const table = readFileSync(join(root, 'ios/Kinlore/en.lproj/Localizable.strings'), 'utf8');
const translated = new Set(
  [...table.matchAll(/^"((?:[^"\\]|\\.)*)"\s*=/gm)].map((m) => m[1])
);

const missing = [...keys].filter((k) => !translated.has(k)).sort();

// An interpolated literal becomes a format key — "Poista \(x)" is looked up as
// "Poista %@" — and which specifier depends on the interpolated type, which no
// regex knows. They are counted rather than checked, so that a sudden change in
// how many there are is at least visible.
const interpolated = new Set();
for (const file of swiftFiles(swiftRoot)) {
  const src = readFileSync(file, 'utf8');
  for (const m of src.matchAll(new RegExp(SHOWN + String.raw`\(\s*"([^"]*\\\([^"]*)"`, 'g'))) {
    interpolated.add(m[1]);
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
  `${keys.size} literal keys, all translated; `
  + `${interpolated.size} interpolated, ${formatKeys} format keys in the table`
);
