// A Finnish sentence that is never LOOKED UP.
//
// `localisation-check.mjs` beside this one asks whether every key the app uses
// has an English translation. It cannot ask the question before that one:
// whether the string is looked up at all. It counts keys, and a literal that
// reaches the screen as a `String` is not a key to it — so the table can be
// complete, the check green, the Finnish build perfect, and an English phone
// still show one Finnish sentence in the middle of a screen.
//
// That is not hypothetical. Every one found before this check existed was
// found by accident:
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
//     rather than waiting for the seventh;
//   * `CameraScreen`'s photograph count, `GalleryScreen`'s import progress and
//     `SettingsScreen`'s export status, found later the same evening in this
//     check's own blind spot — see `prose` below, which was throwing them away
//     before any rule could look at them.
//
// WHAT COUNTS AS LOOKED UP. Four shapes, and the last two are why a naive
// regex over this codebase reports 166 findings instead of two:
//
//   1. A literal as the first argument of an initialiser that takes a
//      `LocalizedStringKey` — `Text`, `Button`, `.alert` and the rest below —
//      or as a branch of a ternary that IS that argument, when every branch
//      is a literal: the type checker gives such a ternary the key type.
//   2. A literal inside `String(localized:)` or `LocalizedStringKey(...)`.
//   3. A literal returned from a member whose declared type IS
//      `LocalizedStringKey`. `awaitingText`, `intro`, `title` and `spoken` are
//      all written this way. `awaitingText`'s sentences used to be one
//      nested ternary inside a `Label`, and not one of them had a key.
//   4. A literal as the right-hand side of `??` where the left-hand side is a
//      `LocalizedStringKey?` property of the same file. `Text(afterward ?? "…")`
//      is fine for that reason; `Text(session.lastError ?? "…")` was not, and
//      that is the difference this rule exists to see — `lastError` is a
//      `String?`, so the coalescing picks `Text`'s String overload.
//
// Rule 5 in the loop runs the other way round: a literal INSIDE one of those
// initialisers but not where a key goes — a ternary branch beside a `String`,
// one half of a `+`, a labelled argument — makes the argument a String, so it
// is reported whatever the table says. Rule 6 is the same verdict on a literal
// inside an interpolation: in `Text("\(owner ? "Perustaja" : "Jäsen") · …")`,
// which `FamilyScreen` wrote until 5 Sep 2026, the compiler types the ternary
// `String` and puts it into the key as a `%@` argument, verbatim.
//
// A TERNARY OF LITERALS IS NOT ONE OF THEM, and until 21 Sep 2026 rule 5 said
// it was. It reported every branch as the String overload, on a belief that
// nineteen comments across six files of the app repeated that day, and on
// 19 Sep it "found" `PlaceMapCard`'s invitation that way — two keys already in
// both tables. The type checker disagrees. `swiftc -dump-ast` at the app's
// deployment target types the ternary in `Text(a ? "x" : "y")`,
// `Label(n == 0 ? "Kerro" : "\(n)", …)`, a nested ternary, `Button`,
// `.accessibilityLabel` and `.navigationTitle` as `LocalizedStringKey`, and
// makes it a `String` only when a branch is one — `String(localized:)`, a
// `+`, a variable. On an English simulator that very `Label`, the Albumi
// badge, reads "Tell". Every Finnish word the belief was built on had a
// missing key instead: #38's "Käytetty 2 kertaa", the refused-photos label,
// `awaitingText`. So a branch is checked the way a bare key is — is it in the
// table — and at 9c2c470 that finds the camera count and the import progress
// as missing keys, the export status as a String, and leaves the invitation
// alone, which is what each of them was.
//
// A fifth shape cannot be seen from the producer at all, and pretending
// otherwise is what makes this kind of check useless. A literal can be stored
// as a plain `String` and looked up by whoever DRAWS it —
// `Text(LocalizedStringKey(choice.label))`, which `DateSheet`, `HeardNames`,
// `RootView` and `TellScreen` all do, and which `HelpScreen` does for its
// whole body. Reading those as defects reports dozens of them, every one fine.
//
// So the question is narrowed to the one that can be answered here without
// following the value anywhere: IS THERE A KEY FOR IT AT ALL. A sentence that
// is not a key in `fi.lproj` cannot be looked up by anybody downstream, no
// matter who draws it — it is untranslatable by construction, and the camera's
// saved line and `RemoteError`'s photos branch were exactly that. A sentence
// that IS a key may still be drawn wrong, which is the "Valokuva" failure and
// is out of reach from here; `localisation-check.mjs` counts it and neither
// check can see whether the lookup happens.
//
// WHAT IT DOES NOT DO:
//
//   * Recognise one Finnish word that is not a key yet. A single word is
//     considered only once the table has it, so `Text(title ?? "Nimetön")`
//     with no "Nimetön" key passes. The test that would see it — a word with
//     an ä or ö, or a stem from the table — finds "Perustaja" and "Etsi" in
//     the tree of 4 Sep 2026, and at HEAD on 21 Sep six words, every one of
//     them wrong: a demo name, two folder names inside the export, an SF
//     symbol and two identifiers. It needs an exemption list of its own first.
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
  ['Data/LargeArchiveFixture.swift',
   'the large demo archive (`-seed large`): records written INTO an archive, each in both languages, and the phone\'s language picks one when the seed runs'],
  ['Services/QuestionLadder.swift',
   'matching patterns read against a transcript, not shown to anybody'],
  ['Services/Extraction.swift',
   'the starter questions, which carry their own English beside the Finnish and switch on who is SPEAKING'],
  ['Services/Transcription.swift',
   'the Finnish half of the prompts, tuned by measurement (CLAUDE.md rule on extract.ts and transcribe.ts)'],
  ['Screens/StoryCard/StorySeed.swift',
   'the story card\'s demo archive — the same memories written INTO an archive as MemoryStore.swift\'s, and the input the story prompt was measured on'],
  ['Services/StoryComposer.swift',
   'the stub composer\'s sentence — a story written INTO an archive in the UI tests, in the language the telling was made in, as the model\'s would be'],
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
// one of them a sentence that was already inside `String(localized:)`. Those
// inner strings are kept, marked `inside`, because rule 6 is about them.
function literals(src) {
  const out = [];
  let i = 0, line = 1;
  const at = (s) => src.startsWith(s, i);

  // The same source, the same length, with every literal's contents and every
  // comment blanked — so that a bracket or a comma inside either is never
  // counted when an argument is read out of it (`argumentOf`).
  const code = src.split('');
  const blank = (from, to, ch) => {
    for (let k = from; k < to; k++) if (code[k] !== '\n') code[k] = ch;
  };

  // How far back the shape test can see. Long enough for
  // `.alert(\n            "…"` and for `?? String(localized: "…"`.
  const prefixOf = () => src.slice(Math.max(0, i - 120), i);

  while (i < src.length) {
    const c = src[i];
    if (c === '\n') { line++; i++; continue; }

    if (at('//')) {
      const from = i;
      while (i < src.length && src[i] !== '\n') i++;
      blank(from, i, ' ');
      continue;
    }

    if (at('/*')) {                       // Swift nests these.
      const from = i;
      let depth = 0;
      while (i < src.length) {
        if (at('/*')) { depth++; i += 2; }
        else if (at('*/')) { depth--; i += 2; if (!depth) break; }
        else { if (src[i] === '\n') line++; i++; }
      }
      blank(from, i, ' ');
      continue;
    }

    if (at('"""')) {
      const start = line, prefix = prefixOf(), from = i;
      i += 3;
      let text = '';
      while (i < src.length && !at('"""')) { if (src[i] === '\n') line++; text += src[i++]; }
      i += 3;
      blank(from + 3, i - 3, 'x');
      out.push({ line: start, text, prefix, multiline: true, start: from, end: i });
      continue;
    }

    if (c === '"') {
      const start = line, prefix = prefixOf(), from = i;
      i++;
      let text = '';
      while (i < src.length && src[i] !== '"') {
        if (src[i] === '\\') {
          if (src[i + 1] === '(') {       // interpolation: skip it whole
            i += 2;
            let depth = 1;
            while (i < src.length && depth) {
              if (src[i] === '"') {       // a string inside the interpolation
                const inner = i, before = src.slice(Math.max(0, i - 120), i);
                i++;
                let innerText = '';
                while (i < src.length && src[i] !== '"') {
                  innerText += src[i] === '\\' ? src[i + 1] : src[i];
                  i += src[i] === '\\' ? 2 : 1;
                }
                out.push({ line, text: innerText, prefix: before, multiline: false,
                  start: inner, end: i + 1, inside: true });
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
      blank(from + 1, i - 1, 'x');
      out.push({ line: start, text, prefix, multiline: false, start: from, end: i });
      continue;
    }

    i++;
  }
  return { found: out, code: code.join('') };
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

// The argument a literal is part of, read from the blanked source: the call it
// belongs to, whether it is that call's first argument, its label, and where
// its text begins once the label is taken off. Null when the nearest open
// bracket is not a call's — a closure's brace, an array's.
const argumentOf = (code, lit) => {
  let depth = 0, a = lit.start - 1, comma = -1;
  for (; a >= 0; a--) {
    const c = code[a];
    if (')]}'.includes(c)) depth++;
    else if ('([{'.includes(c)) { if (depth === 0) break; depth--; }
    else if (c === ',' && depth === 0 && comma < 0) comma = a;
  }
  if (a < 0 || code[a] !== '(') return null;
  let b = lit.end;
  for (depth = 0; b < code.length; b++) {
    const c = code[b];
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) { if (depth === 0) break; depth--; }
    else if (c === ',' && depth === 0) break;
  }
  const from = (comma < 0 ? a : comma) + 1;
  const label = /^\s*([A-Za-z_]\w*)\s*:/.exec(code.slice(from, b));
  return {
    call: /([A-Za-z_]\w*)\s*$/.exec(code.slice(Math.max(0, a - 80), a))?.[1] ?? '',
    first: comma < 0,
    label: label?.[1] ?? null,
    from: from + (label ? label[0].length : 0),
    to: b,
  };
};

// The initialisers and modifiers that take EITHER a LocalizedStringKey or a
// String. Which one a literal inside them reaches is decided by where it sits
// in its argument — see `branchRole`.
const DUAL = new Set([
  'Text', 'Button', 'Label', 'Toggle', 'TextField', 'SecureField', 'Picker',
  'Link', 'Stepper', 'NavigationLink', 'Section', 'ProgressView', 'LabeledContent',
  'navigationTitle', 'accessibilityLabel', 'accessibilityHint',
  'accessibilityValue', 'help', 'searchable',
]);

// A literal once blanked: `"xxx"`, or a multi-line one.
const LITERAL = /^(?:"x*"|"""[x\s]*""")$/;

// Where a literal sits in the argument that takes the key: an unlabelled first
// one, or `.searchable`'s `prompt:` with its label taken off.
//
//   key        the argument IS the literal.
//   branch     the argument is a ternary whose every branch is a literal (or a
//              LocalizedStringKey property of the file). The type checker gives
//              that ternary the key type, so each branch is looked up exactly
//              as a bare literal would be.
//   condition  it is only compared against — `role == "owner" ? … : …`.
//   string     anything else: a branch beside a String, one half of a `+`.
//              Then the argument is a String and nothing looks it up.
const branchRole = (code, arg, lit, keyProperties) => {
  const text = code.slice(arg.from, arg.to), at = lit.start - arg.from;
  const parts = [], ops = [];
  let depth = 0, from = 0;
  for (let k = 0; k < text.length; k++) {
    const c = text[k];
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) depth--;
    // A ternary's `?` has space on both sides, which `??`, `?.` and `try?`
    // never do; and the key's argument, once its label is off, has no other
    // colon.
    else if (depth === 0 && (c === ':'
        || (c === '?' && /\s/.test(text[k - 1] ?? '') && /\s/.test(text[k + 1] ?? '')))) {
      parts.push([from, k]); ops.push(c); from = k + 1;
    }
  }
  parts.push([from, text.length]);
  const piece = ([p, q]) => text.slice(p, q).trim().replace(/^\(([\s\S]*)\)$/, '$1').trim();
  if (!ops.length) return LITERAL.test(piece(parts[0])) ? 'key' : 'string';
  // `c ? a : d ? b : e`, and nothing more tangled than that.
  if (ops.length % 2 || ops.some((o, n) => o !== (n % 2 ? ':' : '?'))) return 'string';
  const isBranch = (n) => n % 2 === 1 || n === parts.length - 1;
  if (!isBranch(parts.findIndex(([p, q]) => at >= p && at < q))) return 'condition';
  return parts.filter((_, n) => isBranch(n))
    .every((part) => LITERAL.test(piece(part)) || keyProperties.has(piece(part)))
    ? 'branch' : 'string';
};

// A member whose declared type is the key type. Nearest one above the literal
// wins, which is how a literal in `var title: LocalizedStringKey` is told from
// one in `var body: some View`.
const DECLARATION =
  /\b(?:var|let)\s+\w+\s*:\s*([^={\n]+?)\s*(?:\{|=|$)|\bfunc\s+\w+\s*\([^)]*\)\s*(?:async\s+)?(?:throws\s+)?->\s*([^={\n]+?)\s*(?:\{|$)/;

// Finnish prose rather than an identifier, a key, a path or a format argument.
//
// The Finnishness test used to be "contains ä or ö, or ends in a full stop",
// and that was this check's own hiding place. `Text(captured == 1 ? "Kuvattu 1
// kuva" : …)`, `ProgressView("Tuodaan kuvia")` and `Text(exportStatus ??
// "Kootaan arkistoa")` have neither, so all three were dropped before any rule
// could look at them — rule 4 was already right about the third and never ran.
//
// Dropping the test altogether instead reports 23, of which 19 are developer
// log lines, `Bearer %@` and HTML fragments. So the app's own Finnish table is
// the vocabulary: a literal is Finnish when one of its words shares a
// four-letter stem with a word in `fi.lproj`. Measured over those 23 that
// separated 15 of 16 correctly, the exception being
// `[export] wrote %@ (%@ bytes, %@ missing)`, whose "missing" meets "Missä" —
// which is why a developer log line, `[`-prefixed by this repo's convention,
// is excluded outright. The vocabulary grows with the app: a new Finnish word
// is covered as soon as one sentence using it is translated.
const prose = (s) =>
  s.includes(' ') && s.trim().length > 6
  && !s.startsWith('-') && !s.startsWith('[') && !s.includes('/') && !s.includes('<')
  && (/[äöÄÖ]/.test(s) || /[.?!…]\s*$/.test(s)
      || (s.toLowerCase().match(/[a-zäöå]+/g) ?? [])
           .some((w) => w.length >= 4 && FINNISH_STEMS.has(w.slice(0, 4))));

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

// The Finnish words this app already uses, cut to a four-letter stem so that a
// case ending does not hide one — "kuva" stands for "kuvia" and "kuvaa".
const FINNISH_STEMS = new Set(
  [...KEYS].flatMap((k) => k.toLowerCase().match(/[a-zäöå]+/g) ?? [])
    .filter((w) => w.length >= 4)
    .map((w) => w.slice(0, 4))
);

let scanned = 0, literalCount = 0, carried = 0, keyed = 0;
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

  const { found, code } = literals(src);
  for (const lit of found) {
    literalCount++;
    if (!prose(lit.text) && !isKey(lit.text)) continue;
    if (SHAPE.test(lit.prefix)) continue;

    // Rule 6, first because nothing below can see where it is: a literal inside
    // an interpolation is a String argument of the sentence around it, whatever
    // that sentence is. `Text("\(owner ? "Perustaja" : "Jäsen") · …")` is the
    // one shape where a ternary of literals really is a String — the type
    // checker has nothing to make it a key from, and `-dump-ast` shows it
    // typed `String` — and `FamilyScreen` wrote exactly that until 5 Sep 2026.
    // Asking for its own lookup (`String(localized:)` inside the
    // interpolation) is what SHAPE let past.
    if (lit.inside) {
      findings.push({
        where: `ios/Kinlore/${rel}:${lit.line}`,
        text: lit.text,
        why: 'inside an interpolation, so it is a String argument of the sentence '
           + 'around it and is never looked up',
      });
      continue;
    }

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

    // Rule 5: inside a dual-overload initialiser, where the literal's place in
    // its argument decides which overload it reaches (`branchRole`).
    // `Text(verbatim:)` is the language saying not to look it up, and is the
    // one position inside these calls that is right to leave alone.
    const arg = argumentOf(code, lit);
    if (arg && DUAL.has(arg.call) && arg.label !== 'verbatim') {
      const where = `ios/Kinlore/${rel}:${lit.line}`;
      // `.searchable`'s key is its `prompt:`, the one labelled argument of
      // these that SwiftUI reads as a LocalizedStringKey.
      const keyPlace = (arg.first && !arg.label)
        || (arg.call === 'searchable' && arg.label === 'prompt');
      const role = keyPlace ? branchRole(code, arg, lit, keyProperties) : 'string';
      if (role === 'condition') continue;
      if (role === 'key' || role === 'branch') {
        if (isKey(lit.text)) { keyed++; continue; }
        findings.push({
          where, text: lit.text,
          why: `looked up as a key by \`${arg.call}(\`, and not a key in fi.lproj`
             + (role === 'branch'
               ? ' — a ternary\'s branches are invisible to localisation-check.mjs' : ''),
        });
        continue;
      }
      findings.push({
        where, text: lit.text,
        why: keyPlace
          ? `part of an argument of \`${arg.call}(\` that is neither a literal nor `
            + 'a ternary of literals, so it is a String and is never looked up'
          : `not the key of \`${arg.call}(\` but `
            + (arg.label ? `its \`${arg.label}:\`` : 'a later argument')
            + ', a String that is never looked up',
      });
      continue;
    }

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
  `${keyed} keys read out of a ternary or a call SHAPE leaves out, every one in the table, ` +
  `${carried} sentences carried as Strings with a key behind them; ` +
  'nothing reaches a screen with no key at all'
);
