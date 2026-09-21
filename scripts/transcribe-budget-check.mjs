// The output budget the transcription sends along with the audio.
//
// `complete()` sends no cap unless told one, and the route's default is low:
// a long telling came back cut off, was rejected whole, and after three
// attempts the catch-up gave up on it — the longest memories were the ones
// that never got their text. The budget is the hallucination bound turned
// into tokens, and every way it can go wrong is silent: too small and the
// longest tellings lose their text again, too large and the guard against
// runaway output is gone. Runs on Node's own type stripping — no build, no
// Worker, no key. Run it after touching budget.ts or transcribe.ts.
//
//   node scripts/transcribe-budget-check.mjs

import { REASONING_BUDGET, boundedSeconds, extractionBudget, outputBudget, transcriptionMaxTokens } from '../backend/src/budget.ts'

let failures = 0
function check(label, actual, ok) {
  if (ok) console.log(`  ok   ${label} (${actual})`)
  else { failures += 1; console.log(`  FAIL ${label}: got ${actual}`) }
}

const demo = outputBudget(90, 'fi')
check('a 90 s Finnish telling fits comfortably', demo, demo >= 1024 && demo < 3000)

const twenty = outputBudget(20 * 60, 'fi')
check('twenty Finnish minutes get well over ten thousand tokens', twenty, twenty > 10_000 && twenty <= 16_000)

const hours = outputBudget(3 * 60 * 60, 'fi')
check('three hours stop at the ceiling', hours, hours === 16_000)

check('English costs fewer tokens per second than Finnish', outputBudget(600, 'en'),
  outputBudget(600, 'en') < outputBudget(600, 'fi'))

check('an unknown length gets the fixed budget', outputBudget(undefined, 'fi'), outputBudget(undefined, 'fi') === 4096)
check('a zero length gets the fixed budget too', outputBudget(0, 'en'), outputBudget(0, 'en') === 4096)
check('a one-second answer still gets the floor', outputBudget(1, 'fi'), outputBudget(1, 'fi') === 1024)

// `max_tokens` counts the model's reasoning too. A 40-second telling that
// reached the founder's phone as "Your voice is kept" on 21 Sep 2026 had been
// sent 1024 tokens; the model spent up to 980 of them thinking and was cut off.
// The hardest sample reasoned for 2 792 uncapped, so that is the least the
// whole budget must leave beside the answer's.
check('a 40 s telling leaves room to think as well as to write',
  transcriptionMaxTokens(40, 'en'), transcriptionMaxTokens(40, 'en') >= outputBudget(40, 'en') + 2792)
check('in Finnish too', transcriptionMaxTokens(40, 'fi'),
  transcriptionMaxTokens(40, 'fi') >= outputBudget(40, 'fi') + 2792)
check('the thinking is capped at what the room was sized for', REASONING_BUDGET,
  transcriptionMaxTokens(40, 'fi') === outputBudget(40, 'fi') + REASONING_BUDGET)
check('and the sum never passes the smallest output limit', transcriptionMaxTokens(3 * 60 * 60, 'fi'),
  transcriptionMaxTokens(3 * 60 * 60, 'fi') === 16_000)

// The duration is the client's own number, and both the meter and the
// hallucination ceiling are derived from it. `boundedSeconds` clamps it to what
// the bytes can hold. Every failure here is silent in the same direction:
// transcription keeps working and the family's month is never spent.
//
// Ninety seconds of the app's own recording is about 403 kB (ARCHITECTURE §5),
// which is roughly 552 kB of base64.
const NINETY_SECONDS_B64 = Math.round(403_000 * 1.37)

check('an honest claim is left exactly alone',
  boundedSeconds(90, NINETY_SECONDS_B64), boundedSeconds(90, NINETY_SECONDS_B64) === 90)

const omitted = boundedSeconds(undefined, NINETY_SECONDS_B64)
check('an omitted duration is charged, not waved through', omitted, omitted > 0)
check('and it rounds to something the meter will actually write',
  Math.round(omitted), Math.round(omitted) > 0)

check('a zero claim is charged the same floor',
  boundedSeconds(0, NINETY_SECONDS_B64), boundedSeconds(0, NINETY_SECONDS_B64) === omitted)

check('the floor never over-charges an honest client',
  omitted, omitted < 90)

const inflated = boundedSeconds(60 * 60, NINETY_SECONDS_B64)
check('an hour claimed for a small file is cut to what the bytes can hold',
  Math.round(inflated), inflated < 60 * 60 && inflated > 90)

check('and the budget that comes out of it is bounded too',
  outputBudget(inflated, 'fi'), outputBudget(inflated, 'fi') < 16_000)

check('an empty body claims nothing', boundedSeconds(undefined, 0), boundedSeconds(undefined, 0) === 0)

// `seconds` is typed and not checked: it comes off `request.json()`, so it can
// be a string, an object, or a NaN wearing the `number` annotation. Every one
// of those used to propagate through the clamp and come back NaN — and NaN is
// FALSY, which is the whole of the damage. `looksHallucinated` opens with
// `if (!seconds …) return false`, so the guard against a model inventing a
// memory nobody told switched itself off for anybody who sent `"90"` instead
// of `90`. Nothing was logged and the transcription looked perfect.
//
// So the assertion is not "it returns something sensible" but the two things
// the rest of the code reads off it: the value is a real number, and it is
// above zero, because those are exactly the two tests that decide whether the
// ceiling runs at all.
for (const [label, rubbish] of [
  ['a numeric string', '90'],
  ['a word', 'abc'],
  ['NaN itself', NaN],
  ['Infinity', Infinity],
  ['negative Infinity', -Infinity],
  ['an object', {}],
  ['an array', []],
  ['a boolean', true],
  ['null', null],
]) {
  const seconds = boundedSeconds(rubbish, NINETY_SECONDS_B64)
  check(`${label} as a duration still leaves the ceiling on`,
    seconds, Number.isFinite(seconds) && seconds > 0)
}

check('a claim that is not a number is charged the byte floor, like an omitted one',
  boundedSeconds('90', NINETY_SECONDS_B64), boundedSeconds('90', NINETY_SECONDS_B64) === omitted)

// ------------------------------------------------- the structuring's budget
//
// The same defect as the transcription's, in the other half of the pipeline,
// found in the production log on 19 Sep 2026: `finish_reason=length` on the
// extraction. The cap was a flat 2000 and the measured need for one 126-word
// telling was 1735 on one run and 2376 on the next — a cap sitting inside the
// spread, so it failed intermittently, which is why it had never been seen.
// The visible cost is a doubled wait; the invisible one is the round falling
// through to `MODEL_EXTRACT_FALLBACK`, where `openai/gpt-4o-mini` writes
// Finnish badly enough to return "Ainoista" as a woman's name.
//
// The numbers asserted below are the measured maxima on
// `google/gemini-3.6-flash` through the shipping schema, with a photograph,
// which is the expensive case: 1451 completion tokens at 8 words, 1892 at 38,
// 2376 at 126. Being over budget is free — `max_tokens` is a ceiling and not a
// reservation — so every one of these asks for headroom rather than for a fit.

console.log('\n— structuring a telling is given room to come back —')
const tiny = extractionBudget('Tässä on Aino.', 'fi')
check('a few words still clear the measured floor of 1451', tiny, tiny > 1451)
check('and the old flat cap of 2000 as well', tiny, tiny > 2000)

const medium = extractionBudget(Array(38).fill('sana').join(' '), 'fi')
check('a medium telling clears its measured 1892', medium, medium > 1892)
const long = extractionBudget(Array(126).fill('sana').join(' '), 'fi')
check('a long one clears its measured 2376', long, long > 2376)
check('and a longer telling gets more than a shorter one', long, long > medium)

// Ninety seconds of Finnish at the hallucination guard's own ceiling.
const ninety = extractionBudget(Array(4 * 90 + 20).fill('sana').join(' '), 'fi')
check('a full ninety-second telling is budgeted past 3000', ninety, ninety > 3000)
check('a telling nobody could speak is still capped', extractionBudget(Array(20_000).fill('sana').join(' '), 'fi'),
  extractionBudget(Array(20_000).fill('sana').join(' '), 'fi') === 16_000)

// English words are shorter and tokenise into fewer pieces, the same reason
// `TOKENS_PER_WORD` is two numbers for the transcription.
check('English costs fewer tokens per word here too',
  extractionBudget(Array(100).fill('word').join(' '), 'en'),
  extractionBudget(Array(100).fill('word').join(' '), 'en') <
    extractionBudget(Array(100).fill('sana').join(' '), 'fi'))

// An empty transcript never reaches `extract()` — the route rejects it with
// `missing_transcript` — but a budget of zero would be a 400 dressed as a
// truncated model reply, which is three levels from the cause.
check('an empty transcript still gets the floor', extractionBudget('', 'fi'), extractionBudget('', 'fi') === 3072)
check('and so does one that is only whitespace', extractionBudget('   \n  ', 'fi'), extractionBudget('   \n  ', 'fi') === 3072)

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
