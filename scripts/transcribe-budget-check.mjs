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

import { boundedSeconds, outputBudget } from '../backend/src/budget.ts'

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

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
