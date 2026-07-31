#!/usr/bin/env node
// Jäsennyksen testipenkki.
//
// Ajaa joukon suomenkielisiä muistoja `/extract`-päätepisteen läpi ja
// tarkistaa väittämät. Jokainen tapaus mittaa YHTÄ asiaa, jotta epäonnistuminen
// kertoo suoraan mikä on rikki.
//
// Nämä eivät kärsi TTS-ongelmasta: jäsennys toimii tekstillä, joten syöte on
// täsmälleen se mitä halutaan testata. Ainoa muuttuja on malli ja prompt.
//
// Vaatii että Worker on käynnissä:
//   cd backend && npx wrangler dev
//
// Käyttö (mistä tahansa hakemistosta):
//   node scripts/extract-tests.mjs
//   node scripts/extract-tests.mjs http://localhost:8787

const API = process.argv[2] ?? 'http://localhost:8787'

// ---------------------------------------------------------------- tapaukset

const CASES = [
  {
    name: 'perusmuoto: henkilö kolmessa sijamuodossa',
    why: 'Jos pintamuoto päätyy läpi, sukupuuhun syntyy kolme eri Ainoa.',
    transcript:
      'Ainolle annettiin se hopealusikka ristiäisissä. Ainon kanssa me leikittiin ' +
      'joka kesä, ja Aino oli aina se rohkein meistä.',
    expect: { people: ['Aino'], exactPeople: true },
  },
  {
    name: 'perusmuoto: paikka kolmessa sijamuodossa',
    why: 'Sama ansa paikoille: "Kuopiosta" ja "Kuopiossa" ovat sama paikka.',
    transcript:
      'Me muutettiin Kuopiosta pois kun olin pieni. Kuopiossa oli semmoinen tori ' +
      'jossa käytiin, ja Kuopioon palattiin joka kesä mummolaan.',
    expect: { places: ['Kuopio'], exactPlaces: true },
  },
  {
    name: 'harvinainen nimi: Aune ei saa muuttua Ainoksi',
    why: 'Malli korjasi savutestissä "puumassa" → "Puumala". Sama mekanismi voi ' +
      'normalisoida aidon harvinaisen nimen tutummaksi — hiljaa ja väärin.',
    transcript:
      'Aune oli äitini sisko. Aune asui Kajaanissa ja tuli meille aina jouluksi. ' +
      'Aune lauloi kauniisti.',
    expect: { people: ['Aune'], forbidPeople: ['Aino'] },
  },
  {
    name: 'harvinaiset vanhat etunimet säilyvät',
    why: 'Impi, Tyyne ja Eevertti ovat aitoja mutta harvinaisia. Näitä ei saa siistiä.',
    transcript:
      'Impi ja Tyyne olivat siskoksia. Eevertti oli heidän veljensä ja se muutti ' +
      'Amerikkaan eikä palannut koskaan.',
    expect: { people: ['Impi', 'Tyyne', 'Eevertti'] },
  },
  {
    name: 'ei ajankohtaa: ei saa keksiä',
    why: 'Keksitty vuosiluku on pahempi kuin puuttuva, koska se näyttää faktalta.',
    transcript:
      'Siinä kuvassa ollaan pihalla. Isä seisoo takana ja me lapset ollaan edessä. ' +
      'Aurinko paistoi ja oli lämmin.',
    expect: { datePrecision: 'unknown', dateYears: [null, null] },
  },
  {
    name: 'epätarkka vuosikymmen säilyy epätarkkana',
    why: 'Epävarmuus on ensiluokkainen tila, ei pyöristettävä.',
    transcript: 'Se oli joskus 50-luvulla, en mä nyt tarkkaan muista.',
    expect: { datePrecision: 'decade', dateYears: [1950, 1959] },
  },
  {
    name: 'tarkka vuosi tunnistetaan tarkaksi',
    why: 'Kun puhuja tietää vuoden, sitä ei saa löysätä vuosikymmeneksi.',
    transcript: 'Me mentiin naimisiin vuonna 1962 Tampereella.',
    expect: { datePrecision: 'year', dateYears: [1962, 1962] },
  },
  {
    name: 'ristiriitainen ajankohta ei kaada jäsennystä',
    why: 'Vanhus korjaa itseään kesken lauseen. Sen pitää olla normaalia syötettä.',
    transcript:
      'Se oli 50-luvulla... ei kun odotas, se taisi olla vasta 60-luvun alussa. ' +
      'En mä ole varma.',
    expect: { datePrecisionOneOf: ['decade', 'year', 'unknown'] },
  },
  {
    name: 'Salo paikkana',
    why: 'Salo, Lahti, Koski ja Nurmi ovat sekä paikkoja että sukunimiä.',
    transcript: 'Me käytiin Salossa katsomassa serkkuja joka kesä.',
    expect: { places: ['Salo'], forbidPeople: ['Salo'] },
  },
  {
    name: 'Salo henkilönä',
    why: 'Sama sana, eri rooli. Konteksti ratkaisee.',
    transcript: 'Salo oli isän työkaveri ja se tuli meille korttia pelaamaan.',
    expect: { people: ['Salo'], forbidPlaces: ['Salo'] },
  },
  {
    name: 'ei erisnimiä: ei saa keksiä henkilöitä',
    why: 'Tyhjä maininta­lista on oikea vastaus. Keksitty sukulainen on pahin virhe.',
    transcript:
      'Se oli semmoinen tavallinen kesäpäivä. Meillä oli hauskaa ja syötiin ' +
      'mansikoita pihalla.',
    expect: { maxMentions: 0 },
  },
  {
    name: 'lähes tyhjä sisältö',
    why: 'Joskus muistaminen ei onnistu. Silloinkaan ei saa täyttää aukkoja.',
    transcript: 'No en mä oikein muista. Se oli semmoinen. Joo.',
    expect: { maxMentions: 0, datePrecision: 'unknown' },
  },
  {
    name: 'monta henkilöä samassa muistossa',
    why: 'Yhdessä valokuvassa on usein koko suku. Kukaan ei saa pudota pois.',
    transcript:
      'Siinä on Väinö, Hilma, Kaarlo ja Sylvi. Väinö oli vanhin ja Sylvi nuorin. ' +
      'Kaarlo lähti merille myöhemmin.',
    expect: { people: ['Väinö', 'Hilma', 'Kaarlo', 'Sylvi'] },
  },
  {
    name: 'yleisnimet eivät ole mainintoja',
    why:
      '"Mummola" ja "mökki" ovat muiston tärkeimpiä paikkoja mutta kohteina ' +
      'tunnistamattomia: kenen mummola, kumman suvun mökki? Sääntö on ' +
      'yksiselitteinen, jottei arkistoon synny sekalaista.',
    transcript:
      'Me oltiin mummolassa koko kesä. Mökki oli järven rannassa ja koulu ' +
      'alkoi vasta elokuussa.',
    expect: { maxMentions: 0 },
  },
  {
    name: 'erisnimi poimitaan, yleisnimi ei — samassa lauseessa',
    why: 'Rajan pitää pitää silloinkin kun molemmat esiintyvät vierekkäin.',
    transcript: 'Mummola oli Sotkamossa ja siellä oli iso navetta.',
    expect: { places: ['Sotkamo'], exactPlaces: true },
  },
  {
    name: 'kysymyksiä on tasan kolme',
    why: 'Neljä ahdistaa iäkästä käyttäjää, kaksi ei vie kertomusta eteenpäin.',
    transcript: 'Toivo otti sen kuvan mökin rannassa.',
    expect: { questionCount: 3 },
  },
]

// ---------------------------------------------------------------- tarkistus

const norm = (s) => s.trim().toLowerCase()

function check(result, expect) {
  const problems = []
  const people = result.mentions.filter((m) => m.kind === 'person').map((m) => m.name)
  const places = result.mentions.filter((m) => m.kind === 'place').map((m) => m.name)
  const has = (list, name) => list.some((x) => norm(x) === norm(name))

  for (const name of expect.people ?? []) {
    if (!has(people, name)) problems.push(`henkilö "${name}" puuttuu (saatiin: ${people.join(', ') || 'ei mitään'})`)
  }
  for (const name of expect.places ?? []) {
    if (!has(places, name)) problems.push(`paikka "${name}" puuttuu (saatiin: ${places.join(', ') || 'ei mitään'})`)
  }
  for (const name of expect.forbidPeople ?? []) {
    if (has(people, name)) problems.push(`henkilö "${name}" EI saisi esiintyä`)
  }
  for (const name of expect.forbidPlaces ?? []) {
    if (has(places, name)) problems.push(`paikka "${name}" EI saisi esiintyä`)
  }
  if (expect.exactPeople && people.length !== (expect.people ?? []).length) {
    problems.push(`odotettiin ${expect.people.length} henkilöä, saatiin ${people.length}: ${people.join(', ')}`)
  }
  if (expect.exactPlaces && places.length !== (expect.places ?? []).length) {
    problems.push(`odotettiin ${expect.places.length} paikkaa, saatiin ${places.length}: ${places.join(', ')}`)
  }
  if (expect.maxMentions !== undefined && result.mentions.length > expect.maxMentions) {
    problems.push(
      `odotettiin enintään ${expect.maxMentions} mainintaa, saatiin ${result.mentions.length}: ` +
        result.mentions.map((m) => `${m.name}(${m.kind})`).join(', '),
    )
  }
  if (expect.datePrecision && result.date.precision !== expect.datePrecision) {
    problems.push(`tarkkuus odotettiin "${expect.datePrecision}", saatiin "${result.date.precision}"`)
  }
  if (expect.datePrecisionOneOf && !expect.datePrecisionOneOf.includes(result.date.precision)) {
    problems.push(`tarkkuus "${result.date.precision}" ei ole sallittujen joukossa`)
  }
  if (expect.dateYears) {
    const [start, end] = expect.dateYears
    if (result.date.start_year !== start || result.date.end_year !== end) {
      problems.push(
        `vuodet odotettiin [${start}, ${end}], saatiin [${result.date.start_year}, ${result.date.end_year}]`,
      )
    }
  }
  if (expect.questionCount !== undefined && result.questions.length !== expect.questionCount) {
    problems.push(`kysymyksiä odotettiin ${expect.questionCount}, saatiin ${result.questions.length}`)
  }
  // Muiston teksti ei saa kadota: se on koko arkiston sisältö.
  if (!result.body || result.body.trim().length === 0) problems.push('body on tyhjä')

  return problems
}

// ---------------------------------------------------------------- ajo

const health = await fetch(`${API}/health`).then((r) => r.json()).catch(() => null)
if (!health) {
  console.error(`Worker ei vastaa osoitteessa ${API}`)
  console.error('Käynnistä: cd backend && npx wrangler dev')
  process.exit(1)
}
if (!health.hasKey) {
  console.error('OPENROUTER_API_KEY puuttuu — lisää se backend/.dev.vars:iin')
  process.exit(1)
}

console.log(`Jäsennyksen testit — ${API}\n`)

let passed = 0
const failures = []

for (const testCase of CASES) {
  process.stdout.write(`  ${testCase.name} ... `)
  let result
  try {
    const res = await fetch(`${API}/extract`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ transcript: testCase.transcript }),
    })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    result = await res.json()
  } catch (err) {
    console.log('VIRHE')
    failures.push({ testCase, problems: [String(err.message)] })
    continue
  }

  const problems = check(result, testCase.expect)
  if (problems.length === 0) {
    console.log('ok')
    passed++
  } else {
    console.log('EPÄONNISTUI')
    failures.push({ testCase, problems, result })
  }
}

console.log(`\n${passed}/${CASES.length} läpi\n`)

for (const { testCase, problems, result } of failures) {
  console.log(`━━ ${testCase.name}`)
  console.log(`   miksi tärkeä: ${testCase.why}`)
  console.log(`   syöte: "${testCase.transcript.slice(0, 110)}${testCase.transcript.length > 110 ? '…' : ''}"`)
  for (const problem of problems) console.log(`   ✗ ${problem}`)
  if (result) {
    const mentions = result.mentions.map((m) => `${m.name}(${m.kind})`).join(', ') || 'ei mitään'
    console.log(`   maininnat: ${mentions}`)
    console.log(`   aika: ${result.date.precision} [${result.date.start_year}, ${result.date.end_year}]`)
  }
  console.log()
}

process.exit(failures.length > 0 ? 1 : 0)
