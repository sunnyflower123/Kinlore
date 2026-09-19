// A Finnish sentence that is never LOOKED UP.
//
// `localisation-check.mjs` beside this one asks whether every key the app uses
// has an English translation. It cannot ask the question before that one:
// whether the string is looked up at all. It counts keys, and a literal that
// reaches the screen as a `String` is not a key to it — so the table can be
// complete, the check green, the Finnish build perfect, and an English phone
// still show one Finnish sentence in the middle of a screen.
//
// That is not hypothetical. Six of them have been found here, every one by
// accident:
//
//   * the placement sentence, `SubjectKind.label` and the date precision
//     picker — found by running the app in English and reading the screen
//     (5 Sep 2026), which is the expensive way;
//   * `Subject.displayTitle`'s "Valokuva", whose key sat in both tables from
//     30 Aug and was still read in Finnish on an English phone until 6 Sep;
//   * `CameraScreen.hint`'s "Tallennettu. Kuvaa seuraava.", found by a sweep
//     on 19 Sep;
//   * `RemoteError.errorDescription`'s photos branch and `FamilyScreen`'s
//     removal-failure alert, found the same evening by sweeping the class
//     rather than waiting for the seventh.
//
// WHAT COUNTS AS LOOKED UP. Four shapes, and the last two are why a naive
// regex over this codebase reports 166 findings instead of two:
//
//   1. A literal as the first argument of an initialiser that takes a
//      `LocalizedStringKey` — `Text`, `Button`, `.alert` and the rest below.
//   2. A literal inside `String(localized:)` or `LocalizedStringKey(...)`.
//   3. A literal returned from a member whose declared type IS
//      `LocalizedStringKey`. `awaitingText`, `intro`, `title` and `spoken` are
//      all written this way, and `RootView` says why: those four used to be a
//      `String` ternary and not one of them had ever been looked up.
//   4. A literal as the right-hand side of `??` where the left-hand side is a
//      `LocalizedStringKey?` property of the same file. `Text(afterward ?? "…")`
//      is fine for that reason; `Text(session.lastError ?? "…")` was not, and
//      that is the difference this rule exists to see — `lastError` is a
//      `String?`, so the coalescing picks `Text`'s String overload.
//
// A fifth shape cannot be seen from the producer at all, and pretending
// otherwise is what makes this kind of check useless. A literal can be stored
// as a plain `String` and looked up by whoever DRAWS it —
// `Text(LocalizedStringKey(choice.label))`, which `DateSheet`, `HeardNames`,
// `RootView` and `TellScreen` all do, and which `HelpScreen` does for its
// whole body. Reading those as defects reports forty of them, every one fine.
//
// So the question is narrowed to the one that can be answered here without
// following the value anywhere: IS THERE A KEY FOR IT AT ALL. A sentence that
// is not a key in `fi.lproj` cannot be looked up by anybody downstream, no
// matter who draws it — it is untranslatable by construction, and both of the
// sentences found on 19 Sep were exactly that. A sentence that IS a key may
// still be drawn wrong, which is the "Valokuva" failure and is out of reach
// from here; `localisation-check.mjs` counts it and neither check can see
// whether the lookup happens.
//
// WHAT IT DOES NOT DO:
//
//   * Find a string COMPOSED at runtime. A sentence built by concatenation, or
//     handed in from another module, is not a literal and cannot be seen here.
//     There is still no substitute for looking.
//   * Catch a key that exists and is drawn without being asked for. That is
//     the "Valokuva" failure, it needs the drawing site rather than the
//     literal, and nothing here or in `localisation-check.mjs` can see it.
//   * Resolve a property from another file. `something.lastError ?? "…"` is
//     reported, because this check cannot read `Session.swift` to learn the
//     type — and reporting it is the right way to be wrong, since that exact
//     shape was a real defect.
//   * Judge English. Every key in this app is Finnish by construction, so a
//     user-facing literal is a Finnish one.
//
// Exits non-zero listing every finding as path:line.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const swiftRoot = join(root, 'ios/Kinlore');

// Files whose Finnish is not interface. Each one is a rule from CLAUDE.md's
// language section, not a string somebody could not be bothered to translate.
const EXEMPT = [
  ['Data/MemoryStore.swift',
   'the demo archive — memories written INTO an archive, where an English word would be somebody\'s record of their own family'],
  ['Data/ClanFixture.swift',
   'demo names'],
  ['Services/QuestionLadder.swift',
   'matching patterns read against a transcript, not shown to anybody'],
  ['Services/Extraction.swift',
   'the starter questions, which carry their own English beside the Finnish and switch on who is SPEAKING'],
  ['Services/Transcription.swift',
   'the Finnish half of the prompts, tuned by measurement (CLAUDE.md rule on extract.ts and transcribe.ts)'],
  ['Screens/InviteShare.swift',
   'the invitation is a message sent to another person, not a screen; whether it should follow the sender\'s device is a product question and not a lookup bug'],
];

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    return statSync(p).isDirectory() ? swiftFiles(p) : p.endsWith('.swift') ? [p] : [];
  });
}

// Swift string literals, with the code immediately before each one.
//
// Written as a scanner rather than a regex because of one shape: interpolation
// can contain a string of its own. `"Perheessä on jo \(x ?? "") …"` ends a
// regex's literal at the empty string inside it and hands back the tail as a
// bare literal — four false findings out of five on the first attempt, every
// one of them a sentence that was already inside `String(localized:)`.
function literals(src) {
  const out = [];
  let i = 0, line = 1;
  const at = (s) => src.startsWith(s, i);

  // How far back the shape test can see. Long enough for
  // `.alert(\n            "…"` and for `?? String(localized: "…"`.
  const prefixOf = () => src.slice(Math.max(0, i - 120), i);

  while (i < src.length) {
    const c = src[i];
    if (c === '\n') { line++; i++; continue; }

    if (at('//')) { while (i < src.length && src[i] !== '\n') i++; continue; }

    if (at('/*')) {                       // Swift nests these.
      let depth = 0;
      while (i < src.length) {
        if (at('/*')) { depth++; i += 2; }
        else if (at('*/')) { depth--; i += 2; if (!depth) break; }
        else { if (src[i] === '\n') line++; i++; }
      }
      continue;
    }

    if (at('"""')) {
      const start = line, prefix = prefixOf();
      i += 3;
      let text = '';
      while (i < src.length && !at('"""')) { if (src[i] === '\n') line++; text += src[i++]; }
      i += 3;
      out.push({ line: start, text, prefix, multiline: true });
      continue;
    }

    if (c === '"') {
      const start = line, prefix = prefixOf();
      i++;
      let text = '';
      while (i < src.length && src[i] !== '"') {
        if (src[i] === '\\') {
          if (src[i + 1] === '(') {       // interpolation: skip it whole
            i += 2;
            let depth = 1;
            while (i < src.length && depth) {
              if (src[i] === '"') {       // a string inside the interpolation
                i++;
                while (i < src.length && src[i] !== '"') i += src[i] === '\\' ? 2 : 1;
              } else if (src[i] === '(') depth++;
              else if (src[i] === ')') depth--;
              else if (src[i] === '\n') line++;
              i++;
            }
            text += '%@';                 // stands for the interpolation
            continue;
          }
          // Keep the escape's meaning: the text is compared against a table
          // key, and a mangled one would miss.
          text += { n: '\n', t: '\t', '0': '\0' }[src[i + 1]] ?? src[i + 1];
          i += 2;
          continue;
        }
        if (src[i] === '\n') line++;       // only reachable in malformed source
        text += src[i++];
      }
      i++;
      out.push({ line: start, text, prefix, multiline: false });
      continue;
    }

    i++;
  }
  return out;
}

// The initialisers and modifiers whose argument SwiftUI reads as a
// LocalizedStringKey, plus the two explicit lookups.
const SHAPE = new RegExp(
  '(?:' +
    '\\b(?:Text|Button|Label|Toggle|TextField|SecureField|Picker|Link|Stepper' +
      '|NavigationLink|Section|LocalizedStringKey)\\(' +
    '|\\.(?:alert|confirmationDialog|navigationTitle|navigationBarTitle' +
      '|accessibilityLabel|accessibilityHint|accessibilityValue|help|searchable)\\(' +
    '|\\bString\\(localized:' +
  ')\\s*$'
);

// A member whose declared type is the key type. Nearest one above the literal
// wins, which is how a literal in `var title: LocalizedStringKey` is told from
// one in `var body: some View`.
const DECLARATION =
  /\b(?:var|let)\s+\w+\s*:\s*([^={\n]+?)\s*(?:\{|=|$)|\bfunc\s+\w+\s*\([^)]*\)\s*(?:async\s+)?(?:throws\s+)?->\s*([^={\n]+?)\s*(?:\{|$)/;

// Finnish prose rather than an identifier, a key, a path or a format argument.
const prose = (s) =>
  s.includes(' ') && s.trim().length > 6 && !s.startsWith('-') && !s.includes('/')
  && (/[äöÄÖ]/.test(s) || /[.?!…]\s*$/.test(s));

// Every key the Finnish table declares. A sentence that is one of these can at
// least be looked up by whoever draws it; a sentence that is not cannot be
// looked up by anybody.
const KEYS = new Set(
  [...readFileSync(join(swiftRoot, 'fi.lproj/Localizable.strings'), 'utf8')
    .matchAll(/^"((?:[^"\\]|\\.)*)"\s*=/gm)]
    .map((m) => m[1].replace(/\\(.)/g, (_, c) => ({ n: '\n', t: '\t' }[c] ?? c)))
);

// The scanner writes %@ for an interpolation; the table writes %lld when the
// value is an Int. Both spellings are the same key.
const isKey = (s) => KEYS.has(s) || KEYS.has(s.replaceAll('%@', '%lld'));

let scanned = 0, literalCount = 0, carried = 0;
const findings = [];

for (const file of swiftFiles(swiftRoot)) {
  const rel = relative(swiftRoot, file);
  scanned++;
  const exempt = EXEMPT.find(([p]) => p === rel);
  if (exempt) continue;

  const src = readFileSync(file, 'utf8');
  const lines = src.split('\n');

  // Every declaration in the file, by line, with its type.
  const declarations = [];
  const keyProperties = new Set();
  lines.forEach((l, n) => {
    const m = DECLARATION.exec(l);
    if (!m) return;
    const type = (m[1] ?? m[2]).trim();
    declarations.push({ line: n + 1, type });
    const name = /\b(?:var|let)\s+(\w+)/.exec(l);
    if (name && /^LocalizedStringKey[?!]?$/.test(type)) keyProperties.add(name[1]);
  });

  for (const lit of literals(src)) {
    literalCount++;
    if (!prose(lit.text)) continue;
    if (SHAPE.test(lit.prefix)) continue;

    // Rule 4: `someKeyProperty ?? "…"`. A fallback behind a String is shown
    // verbatim however good the table is, so this one is reported even when
    // the key exists — which is how `FamilyScreen`'s removal alert read
    // Finnish on an English phone with the key sitting in both tables.
    const coalesced = /\b([\w.]+)\s*\?\?\s*$/.exec(lit.prefix);
    if (coalesced) {
      if (keyProperties.has(coalesced[1])) continue;
      findings.push({
        where: `ios/Kinlore/${rel}:${lit.line}`,
        text: lit.text,
        why: `the fallback behind \`${coalesced[1]} ??\`, which is not a `
           + 'LocalizedStringKey of this file, so the coalescing is a String',
      });
      continue;
    }

    // Rule 3: the nearest declaration above it is a LocalizedStringKey.
    let enclosing = null;
    for (const d of declarations) { if (d.line <= lit.line) enclosing = d; else break; }
    if (enclosing && /\bLocalizedStringKey\b/.test(enclosing.type)) continue;

    // Past here the literal reaches somebody as a String. Whether that String
    // is looked up where it is DRAWN cannot be seen from here — but if there
    // is no key for it, no drawing site can save it.
    if (isKey(lit.text)) { carried++; continue; }

    findings.push({
      where: `ios/Kinlore/${rel}:${lit.line}`,
      text: lit.text,
      why: 'not a key in fi.lproj, so nothing downstream can look it up',
    });
  }
}

if (findings.length) {
  const cut = (s) => (s.length > 78 ? `${s.slice(0, 78)}…` : s);
  console.error(`${findings.length} Finnish sentence(s) an English phone would read in Finnish:\n`);
  for (const f of findings) console.error(`  ${f.where}\n    "${cut(f.text)}"\n    ${f.why}\n`);
  console.error(
    'Wrap it in String(localized:), or declare the member as ' +
    'LocalizedStringKey, and add the key to both tables. If the string is not ' +
    'interface — archive content, a prompt, a matching pattern — add the file ' +
    'to EXEMPT with the reason it is not.'
  );
  process.exit(1);
}

console.log(
  `${scanned} Swift files, ${literalCount} literals, ${EXEMPT.length} files exempt, ` +
  `${carried} sentences carried as Strings with a key behind them; ` +
  'nothing reaches a screen with no key at all'
);
