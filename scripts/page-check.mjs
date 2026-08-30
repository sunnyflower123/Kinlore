#!/usr/bin/env node
// The site, checked the way everything else here is checked.
//
//   node scripts/page-check.mjs
//
// docs/index.html was the one surface in this repository with no check of its
// own. Twenty-eight scripts guard the app and the Worker; verify.sh did not
// mention the page's three files once. That gap was not theoretical — two real
// defects shipped through it and were found by a person reading the rendered
// page in order, which is the slowest possible way to find anything:
//
//   * Ten headings and no <h1> at all, so a screen reader navigating by level
//     found no page heading — on a page whose argument is that this app is
//     built for somebody who navigates that way.
//   * "No relatives yet", and then a sentence beginning "No relatives yet."
//     The gloss had been written to translate a Finnish label; when the label
//     itself became English the translation became a repetition. It existed in
//     one language only, which is exactly why every existing scan missed it.
//
// Both are silent: the page renders, scrolls and reads fine with either one in
// place. Every rule below is one of those, or a rule the page would lose the
// same way — quietly, in one language, between two other changes.
//
// WHAT THIS DELIBERATELY DOES NOT DO:
//
//   * Open a browser. Contrast is computed from the declared tokens rather
//     than from a render, which catches the pair that is wrong and not the
//     element that inherited it. A render would be better and would also mean
//     a Chrome download on a fresh clone; this costs nothing and catches the
//     failure that actually happened (#C2410C is 5.2:1 on white and 4.43:1 on
//     the parchment this page uses — the token was fine and the page was not).
//   * Parse HTML properly. There is no DOM here, and the checks below are
//     written against this page's own conventions rather than against HTML in
//     general. A rewrite that abandons data-l pairs will make this shout; that
//     is the intended behaviour, not a bug to work around.
//   * Judge prose. It cannot tell you the copy is bad. It can tell you the
//     copy says the same thing twice, which is the version that ships.
//
// Exits non-zero on the first failing rule, naming the line.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const html = readFileSync(join(root, 'docs/index.html'), 'utf8');
const css = readFileSync(join(root, 'docs/assets/kinlore.css'), 'utf8');

const failures = [];
const fail = (rule, detail) => failures.push({ rule, detail });

// --- the page, as each language actually receives it ------------------------
// CSS removes the inactive half from the box AND from the accessibility tree,
// so "the English page" is a real object and not a reading of one.
const noComments = html.replace(/<!--[\s\S]*?-->/g, '');
const body = noComments
  .slice(noComments.indexOf('<body'))
  .replace(/<script[\s\S]*?<\/script>/g, '')
  .replace(/<style[\s\S]*?<\/style>/g, '');

function viewFor(lang) {
  const other = lang === 'en' ? 'fi' : 'en';
  // Both halves are always spans carrying data-l; drop the other one whole.
  return body.replace(
    new RegExp(`<span[^>]*data-l="${other}"[^>]*>[\\s\\S]*?</span>`, 'g'),
    ''
  ).replace(
    new RegExp(`<p[^>]*data-l="${other}"[^>]*>[\\s\\S]*?</p>`, 'g'),
    ''
  );
}

const strip = (s) => s.replace(/<[^>]+>/g, ' ').replace(/&[a-z]+;|&#\d+;/g, ' ')
  .replace(/\s+/g, ' ').trim();

// --- 1. one page heading, and no skipped levels -----------------------------
// The defect this is here for produced no error, no warning and no visual
// difference. Only a heading-level navigation showed it.
{
  const levels = [...body.matchAll(/<h([1-6])[^>]*>/g)].map((m) => +m[1]);
  const h1s = levels.filter((l) => l === 1).length;
  if (h1s !== 1) fail('headings', `expected exactly one <h1>, found ${h1s} (levels seen: ${levels.join(', ')})`);
  for (let i = 1; i < levels.length; i++) {
    if (levels[i] > levels[i - 1] + 1) {
      fail('headings', `h${levels[i - 1]} is followed by h${levels[i]} — a level is skipped`);
      break;
    }
  }
}

// --- 2. no block repeats the block above it ---------------------------------
// A label and the sentence that glosses it are next to each other by design,
// so the failure mode is the gloss swallowing the label. Eight characters is
// past "Free" and "Photos" and short of anything worth repeating on purpose.
for (const lang of ['fi', 'en']) {
  const blocks = [...viewFor(lang).matchAll(/<(p|h[1-6]|li)\b[^>]*>([\s\S]*?)<\/\1>/g)]
    .map((m) => strip(m[2]))
    .filter((t) => t.length >= 8);
  for (let i = 1; i < blocks.length; i++) {
    const a = blocks[i - 1], b = blocks[i];
    if (b.startsWith(a) || a.startsWith(b)) {
      fail('repetition', `[${lang}] one block repeats the one before it: "${a.slice(0, 60)}…"`);
    }
  }
}

// --- 3. every translated string has both halves -----------------------------
// A half on its own is invisible in the language it belongs to and silent in
// the other: the element is simply not there, and nothing reports it.
{
  const fi = (body.match(/data-l="fi"/g) || []).length;
  const en = (body.match(/data-l="en"/g) || []).length;
  // One asymmetry is deliberate and has to be named here rather than tolerated
  // by a loose comparison: .gloss-line says "that line is in the app itself,
  // not written for this page", which is only true for a reader of the
  // translation. In Finnish the heading above it IS the app's own words, so
  // the note has nothing to explain. Any OTHER mismatch still fails.
  const solo = (body.match(/class="gloss-line"[^>]*data-l="en"/g) || []).length;
  if (fi !== en - solo) {
    fail('language pairs', `${fi} fi halves and ${en - solo} pairable en halves — one side is missing ${Math.abs(fi - (en - solo))}`);
  }
  // A lang attribute has to travel with each half or a screen reader reads
  // Finnish with an English voice, which is unintelligible rather than merely
  // wrong. This is the one accessibility rule on this page that is inaudible
  // to somebody who does not use a screen reader.
  const unlabelled = [...body.matchAll(/data-l="(fi|en)"/g)]
    .filter((m) => {
      const tag = body.slice(body.lastIndexOf('<', m.index), body.indexOf('>', m.index) + 1);
      return !/\blang="(fi|en)"/.test(tag);
    });
  if (unlabelled.length) fail('language pairs', `${unlabelled.length} data-l element(s) carry no lang attribute`);
}

// --- 4. the English page is English ------------------------------------------
// Built from the page's own Finnish, so it needs no dictionary and cannot go
// stale: a word the fi side uses is a word the en side must not.
//
// The first version of this rule collected only words containing a or o with
// an umlaut, and a mutation test walked straight past it: "Kertominen" has
// neither, and neither do "Muistot", "Sanni" or half the app's own labels.
// Case endings are the other half of the signal and they are what makes this
// catch a word that merely looks Latin.
{
  const finnish = (w) => /[äö]/.test(w)
    || /(?:minen|nen|ssa|ssä|sta|stä|lla|llä|ksi|jen|ien|aan|ään|iset|ista|istä)$/.test(w);
  const fiWords = new Set(
    (strip(viewFor('fi')).toLowerCase().match(/[a-zäö]{5,}/g) || []).filter(finnish)
  );
  const enText = strip(viewFor('en')).toLowerCase();
  const leaked = [...fiWords].filter((w) => enText.includes(w));
  if (leaked.length) fail('english view', `Finnish words in the English page: ${leaked.slice(0, 6).join(', ')}`);
}

// --- 5. no developer artefacts in the copy ----------------------------------
// The page was rewritten on 30 Aug 2026 to read as something a family might be
// shown rather than something a judge audits. That decision has no other
// guard, and it is the kind that erodes one convenient <code> at a time.
{
  const visible = strip(body);
  const paths = visible.match(/[A-Za-z0-9_/.-]+\.(swift|ts|mjs|sql|jsonc?|plist|xcodeproj)\b/g) || [];
  if (paths.length) fail('developer artefacts', `file paths in the visible copy: ${[...new Set(paths)].join(', ')}`);
  const fields = visible.match(/\b(confirmed = 0|raw_transcript|audio_r2_key|date_precision|subject\.\w+|memory\.\w+)/g) || [];
  if (fields.length) fail('developer artefacts', `column or field names in the copy: ${[...new Set(fields)].join(', ')}`);
}

// --- 6. every control says what it is ---------------------------------------
{
  const nameless = [];
  for (const m of body.matchAll(/<button\b([^>]*)>([\s\S]*?)<\/button>/g)) {
    const attrs = m[1], inner = strip(m[2].replace(/<span[^>]*aria-hidden="true"[^>]*>[\s\S]*?<\/span>/g, ''));
    if (!inner && !/aria-label=/.test(attrs)) nameless.push(attrs.trim().slice(0, 50) || '(no attributes)');
  }
  if (nameless.length) fail('accessible names', `${nameless.length} button(s) with no name: ${nameless.join(' | ')}`);
  const imgs = [...body.matchAll(/<img\b([^>]*)>/g)].filter((m) => !/\balt=/.test(m[1]));
  if (imgs.length) fail('accessible names', `${imgs.length} <img> with no alt attribute`);
}

// --- 7. a toggle says which way it is set -----------------------------------
// The text-size button and the two language buttons are the page's only
// stateful controls. Without aria-pressed a screen reader reads three
// identical buttons and no indication of which one is on.
{
  for (const id of ['bigtext']) {
    const tag = body.match(new RegExp(`<button[^>]*id="${id}"[^>]*>`));
    if (!tag) fail('toggle state', `#${id} is gone — this rule outlived the control it guards`);
    else if (!/aria-pressed=/.test(tag[0])) fail('toggle state', `#${id} has no aria-pressed`);
  }
  const langButtons = [...body.matchAll(/<button[^>]*data-set-lang[^>]*>/g)];
  if (langButtons.length !== 2) fail('toggle state', `expected two language buttons, found ${langButtons.length}`);
  for (const b of langButtons) {
    if (!/aria-pressed=/.test(b[0])) fail('toggle state', 'a language button has no aria-pressed');
  }
}

// --- 8. the page still reads with no JavaScript ------------------------------
// The engine parks every cue at opacity 0, so without the <noscript> override
// this page is a blank sheet of parchment. It was blank once already.
{
  // In <head>, not <body> — the override has to be parsed before the engine's
  // stylesheet paints the first frame, so this looks at the whole document.
  const ns = noComments.match(/<noscript>[\s\S]*?<\/noscript>/);
  if (!ns) fail('no-JS', 'the <noscript> block is gone; the page renders blank without JavaScript');
  else {
    // Anything filled in by kinlore.js must be hidden or it is an empty box.
    for (const sel of ['.wire__code', '.wire__raw', '.wire__field', '.voicepick']) {
      if (!ns[0].includes(sel)) fail('no-JS', `${sel} is filled by JavaScript and the noscript block does not hide it`);
    }
    if (!/\.wire__short\s*\{\s*display:\s*grid/.test(ns[0])) {
      fail('no-JS', '.wire__short is what replaces them and the noscript block does not show it');
    }
  }
}

// --- 9. contrast, which is the one rule eyes cannot check --------------------
// This is rule 1 of CLAUDE.md, on the web. The failure it exists for is not a
// bad colour: #C2410C measures 5.2:1 on white, passes every palette it came
// from, and lands at 4.43:1 on this page's parchment.
{
  const token = (name) => {
    const m = css.match(new RegExp(`--${name}:\\s*(#[0-9A-Fa-f]{3,8})`));
    return m && m[1];
  };
  const srgb = (hex) => {
    let h = hex.slice(1);
    if (h.length === 3) h = [...h].map((c) => c + c).join('');
    return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
  };
  const lum = (hex) => {
    const [r, g, b] = srgb(hex).map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const ratio = (a, b) => {
    const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p);
    return (x + 0.05) / (y + 0.05);
  };

  const grounds = ['sc-canvas', 'sc-surface'];
  const inks = ['sc-ink', 'sc-ink-soft', 'k-accent-text', 'k-confirmed', 'k-destruct'];
  for (const g of grounds) {
    const bg = token(g);
    if (!bg) { fail('contrast', `--${g} is not declared as a hex colour`); continue; }
    for (const i of inks) {
      const fg = token(i);
      if (!fg) { fail('contrast', `--${i} is not declared as a hex colour`); continue; }
      const r = ratio(fg, bg);
      if (r < 4.5) fail('contrast', `--${i} on --${g} is ${r.toFixed(2)}:1, under the 4.5:1 minimum`);
    }
  }
}

// --- report ------------------------------------------------------------------
if (failures.length) {
  console.error(`docs/index.html — ${failures.length} failure(s)\n`);
  for (const f of failures) console.error(`  [${f.rule}] ${f.detail}`);
  console.error('');
  process.exit(1);
}
console.log('docs/index.html — 9 rules, all pass');
