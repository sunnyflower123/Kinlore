#!/usr/bin/env node
// Test bench for extraction.
//
// Runs a set of Finnish memories through the `/extract` endpoint and checks the
// assertions. Each case measures ONE thing, so a failure says directly what is
// broken.
//
// These do not suffer from the TTS problem: extraction works on text, so the
// input is exactly what we want to test. The only variable is the model and the
// prompt.
//
// The transcripts are Finnish because that is the input under test — see the
// language rule in CLAUDE.md.
//
// Requires a running Worker:
//   cd backend && npx wrangler dev
//
// Usage (from any directory):
//   node scripts/extract-tests.mjs
//   node scripts/extract-tests.mjs http://localhost:8787

const API = process.argv[2] ?? 'http://localhost:8787'

// ---------------------------------------------------------------- cases

const CASES = [
  {
    name: 'base form: a person in three cases',
    why: 'If the surface form gets through, the family tree gains three different Ainos.',
    transcript:
      'Ainolle annettiin se hopealusikka ristiäisissä. Ainon kanssa me leikittiin ' +
      'joka kesä, ja Aino oli aina se rohkein meistä.',
    expect: { people: ['Aino'], exactPeople: true },
  },
  {
    name: 'base form: a place in three cases',
    why: 'The same trap for places: "Kuopiosta" and "Kuopiossa" are the same place.',
    transcript:
      'Me muutettiin Kuopiosta pois kun olin pieni. Kuopiossa oli semmoinen tori ' +
      'jossa käytiin, ja Kuopioon palattiin joka kesä mummolaan.',
    expect: { places: ['Kuopio'], exactPlaces: true },
  },
  {
    name: 'rare name: Aune must not become Aino',
    why: 'In a smoke test the model corrected "puumassa" → "Puumala". The same ' +
      'mechanism can normalise a genuine rare name into a more familiar one — ' +
      'silently and wrongly.',
    transcript:
      'Aune oli äitini sisko. Aune asui Kajaanissa ja tuli meille aina jouluksi. ' +
      'Aune lauloi kauniisti.',
    expect: { people: ['Aune'], forbidPeople: ['Aino'] },
  },
  {
    name: 'rare old first names survive',
    why: 'Impi, Tyyne and Eevertti are genuine but rare. These must not be tidied.',
    transcript:
      'Impi ja Tyyne olivat siskoksia. Eevertti oli heidän veljensä ja se muutti ' +
      'Amerikkaan eikä palannut koskaan.',
    expect: { people: ['Impi', 'Tyyne', 'Eevertti'] },
  },
  {
    name: 'no date given: must not invent one',
    why: 'An invented year is worse than a missing one, because it looks like fact.',
    transcript:
      'Siinä kuvassa ollaan pihalla. Isä seisoo takana ja me lapset ollaan edessä. ' +
      'Aurinko paistoi ja oli lämmin.',
    expect: { datePrecision: 'unknown', dateYears: [null, null] },
  },
  {
    name: 'a vague decade stays vague',
    why: 'Uncertainty is a first-class state, not something to round off.',
    transcript: 'Se oli joskus 50-luvulla, en mä nyt tarkkaan muista.',
    expect: { datePrecision: 'decade', dateYears: [1950, 1959] },
  },
  {
    name: 'an exact year is recognised as exact',
    why: 'When the speaker knows the year, it must not be loosened to a decade.',
    transcript: 'Me mentiin naimisiin vuonna 1962 Tampereella.',
    expect: { datePrecision: 'year', dateYears: [1962, 1962] },
  },
  {
    name: 'a self-contradicting date does not break extraction',
    why: 'An elderly speaker corrects themselves mid-sentence. That has to be normal input.',
    transcript:
      'Se oli 50-luvulla... ei kun odotas, se taisi olla vasta 60-luvun alussa. ' +
      'En mä ole varma.',
    expect: { datePrecisionOneOf: ['decade', 'year', 'unknown'] },
  },
  {
    name: 'Salo as a place',
    why: 'Salo, Lahti, Koski and Nurmi are both place names and surnames.',
    transcript: 'Me käytiin Salossa katsomassa serkkuja joka kesä.',
    expect: { places: ['Salo'], forbidPeople: ['Salo'] },
  },
  {
    name: 'Salo as a person',
    why: 'The same word, a different role. Context decides.',
    transcript: 'Salo oli isän työkaveri ja se tuli meille korttia pelaamaan.',
    expect: { people: ['Salo'], forbidPlaces: ['Salo'] },
  },
  {
    name: 'no proper nouns: must not invent people',
    why: 'An empty mention list is the right answer. An invented relative is the worst error.',
    transcript:
      'Se oli semmoinen tavallinen kesäpäivä. Meillä oli hauskaa ja syötiin ' +
      'mansikoita pihalla.',
    expect: { maxMentions: 0 },
  },
  {
    name: 'almost no content',
    why: 'Sometimes remembering does not work. Even then the gaps must not be filled.',
    transcript: 'No en mä oikein muista. Se oli semmoinen. Joo.',
    expect: { maxMentions: 0, datePrecision: 'unknown' },
  },
  {
    name: 'several people in one memory',
    why: 'One photograph often holds the whole family. Nobody may be dropped.',
    transcript:
      'Siinä on Väinö, Hilma, Kaarlo ja Sylvi. Väinö oli vanhin ja Sylvi nuorin. ' +
      'Kaarlo lähti merille myöhemmin.',
    expect: { people: ['Väinö', 'Hilma', 'Kaarlo', 'Sylvi'] },
  },
  {
    name: 'common nouns are not mentions',
    why:
      '"Mummola" and "mökki" are a memory\'s most important places but are ' +
      'unidentifiable as subjects: whose grandmother\'s house, which family\'s ' +
      'cottage? The rule is unambiguous so the archive does not fill with mush.',
    transcript:
      'Me oltiin mummolassa koko kesä. Mökki oli järven rannassa ja koulu ' +
      'alkoi vasta elokuussa.',
    expect: { maxMentions: 0 },
  },
  {
    name: 'proper noun taken, common noun not — in the same sentence',
    why: 'The boundary has to hold even when both appear side by side.',
    transcript: 'Mummola oli Sotkamossa ja siellä oli iso navetta.',
    expect: { places: ['Sotkamo'], exactPlaces: true },
  },
  {
    name: 'a correction is inflected correctly into the text',
    why:
      'Speech recognition gets roughly one proper noun in three wrong. The ' +
      "teller's correction is not enough for the subject name alone: the memory " +
      'text would still say "Skotlannissa". A string replacement never matches ' +
      'the inflected form, so the model handles the inflection — this test locks ' +
      'that in.',
    transcript:
      'Hilma jäi Skotlantiin hoitamaan taloa, ja Skotlannissa oli iso navetta.',
    corrections: [{ from: 'Skotlanti', to: 'Sotkamo' }],
    expect: {
      places: ['Sotkamo'],
      forbidPlaces: ['Skotlanti'],
      bodyIncludes: ['Sotkamoon', 'Sotkamossa'],
      bodyExcludes: ['Skotlan'],
    },
  },
  {
    name: 'there are exactly three questions',
    why: 'Four overwhelms an elderly user, two do not carry the story forward.',
    transcript: 'Toivo otti sen kuvan mökin rannassa.',
    expect: { questionCount: 3 },
  },
]

// ---------------------------------------------------------------- checking

const norm = (s) => s.trim().toLowerCase()

function check(result, expect) {
  const problems = []
  const people = result.mentions.filter((m) => m.kind === 'person').map((m) => m.name)
  const places = result.mentions.filter((m) => m.kind === 'place').map((m) => m.name)
  const has = (list, name) => list.some((x) => norm(x) === norm(name))

  for (const name of expect.people ?? []) {
    if (!has(people, name)) problems.push(`person "${name}" missing (got: ${people.join(', ') || 'nothing'})`)
  }
  for (const name of expect.places ?? []) {
    if (!has(places, name)) problems.push(`place "${name}" missing (got: ${places.join(', ') || 'nothing'})`)
  }
  for (const name of expect.forbidPeople ?? []) {
    if (has(people, name)) problems.push(`person "${name}" must NOT appear`)
  }
  for (const name of expect.forbidPlaces ?? []) {
    if (has(places, name)) problems.push(`place "${name}" must NOT appear`)
  }
  if (expect.exactPeople && people.length !== (expect.people ?? []).length) {
    problems.push(`expected ${expect.people.length} people, got ${people.length}: ${people.join(', ')}`)
  }
  if (expect.exactPlaces && places.length !== (expect.places ?? []).length) {
    problems.push(`expected ${expect.places.length} places, got ${places.length}: ${places.join(', ')}`)
  }
  if (expect.maxMentions !== undefined && result.mentions.length > expect.maxMentions) {
    problems.push(
      `expected at most ${expect.maxMentions} mentions, got ${result.mentions.length}: ` +
        result.mentions.map((m) => `${m.name}(${m.kind})`).join(', '),
    )
  }
  if (expect.datePrecision && result.date.precision !== expect.datePrecision) {
    problems.push(`expected precision "${expect.datePrecision}", got "${result.date.precision}"`)
  }
  if (expect.datePrecisionOneOf && !expect.datePrecisionOneOf.includes(result.date.precision)) {
    problems.push(`precision "${result.date.precision}" is not among the allowed values`)
  }
  if (expect.dateYears) {
    const [start, end] = expect.dateYears
    if (result.date.start_year !== start || result.date.end_year !== end) {
      problems.push(
        `expected years [${start}, ${end}], got [${result.date.start_year}, ${result.date.end_year}]`,
      )
    }
  }
  if (expect.questionCount !== undefined && result.questions.length !== expect.questionCount) {
    problems.push(`expected ${expect.questionCount} questions, got ${result.questions.length}`)
  }
  for (const needle of expect.bodyIncludes ?? []) {
    if (!result.body.includes(needle)) {
      problems.push(`text is missing "${needle}": "${result.body.slice(0, 120)}"`)
    }
  }
  for (const needle of expect.bodyExcludes ?? []) {
    if (result.body.includes(needle)) {
      problems.push(`text still contains "${needle}": "${result.body.slice(0, 120)}"`)
    }
  }
  // The memory text must not disappear: it is the entire content of the archive.
  if (!result.body || result.body.trim().length === 0) problems.push('body is empty')

  return problems
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

console.log(`Extraction tests — ${API}\n`)

let passed = 0
const failures = []

for (const testCase of CASES) {
  process.stdout.write(`  ${testCase.name} ... `)
  let result
  try {
    const res = await fetch(`${API}/extract`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        transcript: testCase.transcript,
        corrections: testCase.corrections ?? [],
      }),
    })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    result = await res.json()
  } catch (err) {
    console.log('ERROR')
    failures.push({ testCase, problems: [String(err.message)] })
    continue
  }

  const problems = check(result, testCase.expect)
  if (problems.length === 0) {
    console.log('ok')
    passed++
  } else {
    console.log('FAILED')
    failures.push({ testCase, problems, result })
  }
}

console.log(`\n${passed}/${CASES.length} passed\n`)

for (const { testCase, problems, result } of failures) {
  console.log(`━━ ${testCase.name}`)
  console.log(`   why it matters: ${testCase.why}`)
  console.log(`   input: "${testCase.transcript.slice(0, 110)}${testCase.transcript.length > 110 ? '…' : ''}"`)
  for (const problem of problems) console.log(`   ✗ ${problem}`)
  if (result) {
    const mentions = result.mentions.map((m) => `${m.name}(${m.kind})`).join(', ') || 'nothing'
    console.log(`   mentions: ${mentions}`)
    console.log(`   date: ${result.date.precision} [${result.date.start_year}, ${result.date.end_year}]`)
  }
  console.log()
}

process.exit(failures.length > 0 ? 1 : 0)
