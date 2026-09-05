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

import { outputBudget } from '../backend/src/budget.ts'

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

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
