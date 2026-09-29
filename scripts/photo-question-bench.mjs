#!/usr/bin/env node
// The follow-up questions about a photograph, when the teller is in it.
//
// Rule 8 of the extraction prompt sends the photograph with the telling and
// asks for one question about something visible in it. On 29 Sep 2026 a phone
// test told about a picture and said "I am in it", and the question that came
// back asked who the child holding up three fingers was: the teller, asked to
// name themselves as a stranger. The model cannot see which face is the
// teller's, and rule 6 ("do not ask what the speech has already answered")
// does not reach a question the speech only half answered.
//
// Each case is a synthetic photograph and a telling about it. The photographs
// were generated for this bench and show nobody real; README.md beside them
// says with what, from which prompt and when. They are never a family's
// picture and never photo-saimaa.jpg.
//
// Three kinds of telling, because the fix must change one and leave two:
//
//   * unsaid — the teller says they are in the photograph and not which
//     person they are. A question about an unnamed person should offer the
//     teller first, as yes or no ("Is the boy raising his hand you?"), once,
//     rather than ask who it is, and nobody else unnamed should be asked
//     about beside it as a stranger: if the answer is no, that may be them.
//   * said — the teller says which person they are. Asking "is that you?"
//     again asks what the speech answered.
//   * absent — the teller says they are not in it. "Is that you?" is then a
//     question about somebody who was not there.
//
// What a string can decide is tagged here: the number of questions, a question
// that asks who somebody is, and a question that offers the teller. Whether a
// "who" question is about a person in the picture, and whether one question is
// about something visible, is read by hand from the questions printed
// verbatim — "Kuka otti kuvan?" and "Kuka on poika keskellä?" are the same
// shape to any matcher. The tags are a reading aid and the verdict is the
// reading.
//
// Costs OpenRouter credit: one extraction with a picture per case per run,
// 0.5–1.3 US cents each on 29 Sep 2026, so the default three runs are 30
// calls and about 25 cents. Run it when rule 8 changes, not to look at it.
// The call goes through a running Worker, so the key never leaves it.
// `--read` prints a saved run again, tagged afresh, and calls nothing:
//
//   cd backend && npx wrangler dev
//   node scripts/photo-question-bench.mjs [worker url] [--runs N] [--only fi|en] [--out file.json]
//   node scripts/photo-question-bench.mjs --read file.json
//
// The transcripts are Finnish and English because that is the input under
// test (see the language rule in CLAUDE.md).

import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = join(dirname(fileURLToPath(import.meta.url)), 'photo-question-bench')

const args = process.argv.slice(2)
const flag = (name) => {
  const at = args.indexOf(name)
  return at === -1 ? undefined : args.splice(at, 2)[1]
}
const RUNS = Number(flag('--runs') ?? 3)
const ONLY = flag('--only')
const OUT = flag('--out')
const READ = flag('--read')
const API = args[0] ?? 'http://localhost:8787'

// ---------------------------------------------------------------- cases

const CASES = [
  // --- unsaid: the case the phone test found
  {
    name: 'cousins on the steps, the teller is one of them',
    photo: 'cousins-steps.jpg',
    teller: 'unsaid',
    level: 1,
    transcript:
      'Tää kuva on otettu mummolan portailla joskus kuuskytluvun alussa. Mä oon siinä itsekin, ' +
      'serkkujen kanssa. Mummo oli just leiponut pullaa, ja me saatiin istua portailla syömässä. ' +
      'Se koira oli naapurin, se kulki aina meidän perässä.',
  },
  {
    name: 'cousins on the steps, the teller is one of them',
    lang: 'en',
    photo: 'cousins-steps.jpg',
    teller: 'unsaid',
    level: 1,
    transcript:
      "This was taken on the steps at my grandmother's house, sometime in the early sixties. I'm in " +
      'it too, with my cousins. Grandma had just baked buns and we were allowed to eat them out on ' +
      'the steps. The dog belonged to the neighbours, it followed us everywhere.',
  },
  {
    name: 'the jetty, the teller and a named brother',
    photo: 'jetty-rowboat.jpg',
    teller: 'unsaid',
    level: 1,
    transcript:
      'Tässä ollaan Puumalan mökin laiturilla kesällä viiskytkuus. Minä olen kuvassa, ja siinä on ' +
      'myös veljeni Toivo ja hänen vaimonsa. Toivo oli juuri tervannut sen veneen, ja koko ranta ' +
      'haisi tervalta.',
  },
  {
    name: 'the jetty, the teller and a named brother',
    lang: 'en',
    photo: 'jetty-rowboat.jpg',
    teller: 'unsaid',
    level: 1,
    transcript:
      'This is the jetty at our summer cottage in Puumala, the summer of fifty-six. I am in the ' +
      'picture, and so are my brother Toivo and his wife. Toivo had just tarred that boat, and the ' +
      'whole shore smelled of tar.',
  },
  {
    name: 'a birthday at the kitchen table, the teller at it',
    photo: 'birthday-table.jpg',
    teller: 'unsaid',
    level: 2,
    transcript:
      'Tämä on synttäreiltä joskus seitkytluvulla. Minäkin olen tässä kuvassa. Äiti leipoi aina ' +
      'mansikkakakun, ja kahvit keitettiin puuhellalla. Lahjoja ei ollut montaa, mutta ne ' +
      'avattiin aina vasta kakun jälkeen.',
  },
  {
    name: 'a birthday at the kitchen table, the teller at it',
    lang: 'en',
    photo: 'birthday-table.jpg',
    teller: 'unsaid',
    level: 2,
    transcript:
      "This is from a birthday, sometime in the seventies. I'm in this picture as well. Mum always " +
      'baked a strawberry cake, and the coffee was made on the wood stove. There were never many ' +
      'presents, but they were only opened after the cake.',
  },

  // --- said: the teller says which one they are
  {
    name: 'cousins on the steps, the teller says which one',
    photo: 'cousins-steps.jpg',
    teller: 'said',
    level: 1,
    transcript:
      'Tässä ollaan mummolan portailla serkkujen kanssa joskus kuuskytluvun alussa. Minä olen se ' +
      'tyttö raitamekossa vasemmalla. Mummo oli leiponut pullaa, ja me syötiin ne portailla.',
  },
  {
    name: 'cousins on the steps, the teller says which one',
    lang: 'en',
    photo: 'cousins-steps.jpg',
    teller: 'said',
    level: 1,
    transcript:
      "Here we are on the steps at my grandmother's with my cousins, in the early sixties. I'm the " +
      'girl in the striped dress on the left. Grandma had baked buns, and we ate them on the steps.',
  },

  // --- absent: the teller was not there
  {
    name: 'the jetty before the teller was born',
    photo: 'jetty-rowboat.jpg',
    teller: 'absent',
    level: 1,
    transcript:
      'Tämä on äidin ja isän kuva Puumalan mökiltä, ennen kuin minä olin syntynytkään. Isä oli ' +
      'innokas kalamies, ja äiti keitti aina kahvit laiturilla.',
  },
  {
    name: 'the jetty before the teller was born',
    lang: 'en',
    photo: 'jetty-rowboat.jpg',
    teller: 'absent',
    level: 1,
    transcript:
      "This is a picture of my mother and father at the cottage in Puumala, before I was even born. " +
      'Dad was a keen fisherman, and Mum always made the coffee out on the jetty.',
  },
].filter((c) => !ONLY || (c.lang ?? 'fi') === ONLY)

// ---------------------------------------------------------------- tagging

/// A question that asks who somebody is. Also catches "who took the picture"
/// and "who else was there", which is why this is a tag and not a verdict.
/// `\p{L}` rather than `\b`, which in JavaScript ends a word at "ä".
const WHO = {
  fi: /(?<!\p{L})(kuka|ketkä|keitä|kenet)(?!\p{L})/iu,
  en: /\bwho\b|\bwhich (person|one|man|woman|child|boy|girl)\b/i,
}

/// The teller offered as yes or no: "Is the boy raising his hand you?",
/// "Oletko sinä se poika, joka…?"
const OFFER = {
  fi: /^(oletko|olitko|olisitko|onko|oliko)(?!\p{L})[^?]*(?<!\p{L})(sinä|itse)(?!\p{L})|(?<!\p{L})sinäkö(?!\p{L})/iu,
  en: /^(is|are|was|were)\b[^?]*\byou\b/i,
}

/// The teller asked to pick themselves out: "Which of the two women is
/// you?", "Kumpi naisista olet sinä?" Not the bug, and not yes or no either.
const WHICH = {
  fi: /(?<!\p{L})(kumpi|kuka|ketkä)(ko|kö)?(?!\p{L})[^?]*(?<!\p{L})(sinä|olet|olit)(?!\p{L})/iu,
  en: /\b(which|who)\b[^?]*\b(is|are|was|were) you\b|\bwhich\b[^?]*\byou\b/i,
}

function tags(text, lang) {
  if (OFFER[lang].test(text)) return ['OFFER']
  if (WHICH[lang].test(text)) return ['WHICH']
  if (WHO[lang].test(text)) return ['WHO']
  return []
}


// ---------------------------------------------------------------- printing

function printRun(run, number, lang) {
  if (run.error) {
    console.log(`   run ${number}: ERROR ${run.error}`)
    return
  }
  console.log(`   run ${number}: ${run.questions.length} questions`)
  for (const q of run.questions) {
    const tagged = tags(q.text, lang)
    console.log(`     [${q.level ?? '-'}] ${q.text}${tagged.length ? `   ‹${tagged.join(' ')}›` : ''}`)
  }
}

function printSummary(results, calls) {
  console.log('case                                               lang teller  replies  3q  WHO  WHICH  OFFER')
  for (const row of results) {
    const ok = row.runs.filter((r) => !r.error)
    const all = ok.flatMap((r) => r.questions)
    const count = (tag) => all.filter((q) => tags(q.text, row.lang).includes(tag)).length
    console.log(
      `${row.name.padEnd(50)} ${row.lang.padEnd(4)} ${row.teller.padEnd(7)} ${String(ok.length).padStart(7)}` +
        `  ${String(ok.filter((r) => r.questions.length === 3).length).padStart(2)}` +
        `  ${String(count('WHO')).padStart(3)}  ${String(count('WHICH')).padStart(5)}  ${String(count('OFFER')).padStart(5)}`,
    )
  }
  console.log(`\n${calls} calls to /extract`)
}

if (READ) {
  const saved = JSON.parse(readFileSync(READ, 'utf8'))
  console.log(`Photo question bench — read from ${READ} (${saved.api}, ${saved.runs} run(s) a case)\n`)
  for (const row of saved.results) {
    console.log(`━━ [${row.lang}] ${row.name} — teller ${row.teller}, level ${row.level}`)
    row.runs.forEach((run, index) => printRun(run, index + 1, row.lang))
    console.log()
  }
  printSummary(saved.results, saved.calls)
  process.exit(0)
}

// ---------------------------------------------------------------- run

const health = await fetch(`${API}/health`).then((r) => r.json()).catch(() => null)
if (!health) {
  console.error(`The Worker is not answering at ${API}`)
  console.error('Start it: cd backend && npx wrangler dev')
  process.exit(1)
}
if (!health.hasKey) {
  console.error('OPENROUTER_API_KEY is missing — add it to backend/.dev.vars')
  process.exit(1)
}

// A throwaway family, as extract-tests.mjs makes one: /extract wants a member.
const identity = {
  memberID: crypto.randomUUID().toUpperCase(),
  secret: [...crypto.getRandomValues(new Uint8Array(24))].map((b) => b.toString(16).padStart(2, '0')).join(''),
}
const created = await fetch(`${API}/family`, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ ...identity, displayName: 'Bench', familyName: 'Bench' }),
})
if (!created.ok) {
  console.error(`Could not create a family to run against: HTTP ${created.status}`)
  process.exit(1)
}
const AUTH = `Bearer ${identity.memberID}.${identity.secret}`

const photos = new Map()
const photo = (file) => {
  if (!photos.has(file)) photos.set(file, readFileSync(join(HERE, file)).toString('base64'))
  return photos.get(file)
}

console.log(`Photo question bench — ${API}, ${RUNS} run(s) a case\n`)

const results = []
let calls = 0

for (const testCase of CASES) {
  const lang = testCase.lang ?? 'fi'
  const row = { ...testCase, lang, runs: [] }
  results.push(row)
  console.log(`━━ [${lang}] ${testCase.name} — teller ${testCase.teller}, level ${testCase.level}`)
  for (let number = 1; number <= RUNS; number++) {
    calls += 1
    let run
    try {
      const res = await fetch(`${API}/extract`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: AUTH },
        body: JSON.stringify({
          transcript: testCase.transcript,
          corrections: [],
          lang,
          level: testCase.level,
          // What the app sends for a telling filed under an untitled
          // photograph nobody has told about before (ExtractionContext).
          context: { subject: { kind: 'photo', memories: 0 } },
          image: photo(testCase.photo),
        }),
      })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const result = await res.json()
      run = { questions: result.questions ?? [], mentions: result.mentions }
    } catch (err) {
      run = { error: String(err.message) }
    }
    row.runs.push(run)
    printRun(run, number, lang)
  }
  console.log()
}

printSummary(results, calls)

if (OUT) {
  writeFileSync(OUT, JSON.stringify({ api: API, runs: RUNS, calls, results }, null, 2))
  console.log(`written to ${OUT}`)
}
