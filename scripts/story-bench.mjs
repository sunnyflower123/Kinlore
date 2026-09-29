#!/usr/bin/env node
// The story prompt, measured on demo cards — phase A of the story card
// (26 Sep 2026). A card's memories go in, one ordered text comes out, and the
// text is judged by hand against the rules the prompt states: nothing said
// that nobody said, gaps left as gaps, an unconfirmed name never a fact, a
// contradiction shown and not settled. The outputs are pasted VERBATIM into
// `ios/Kinlore/Screens/StoryCard/StorySeed.swift` as the fixed DEBUG
// stories the card's versions are photographed with.
//
// Two prompts, not one translated: the Finnish one is the tuned one, and the
// English one loses its Finnish examples for the same reason extract.ts's
// does. Which prompt runs is the language of the phone composing, decided
// once when the story is composed (ARCHITECTURE §27): with several tellers
// there is no one speaker to follow, and the tellings cross verbatim.
//
// Phase B changed rule 3 and the card's names line on 26 Sep 2026, after
// the measurement: the card lists only the names the family has confirmed,
// and an unconfirmed one never leaves the phone (rule 4, §27). The prompt
// here is the shipped one, `backend/src/story.ts` word for word. The
// jetty's and the kitchen's stories in the seed are the first prompt's;
// Toivo's and Puumala's are this one's, from the one run of those two
// cards on 28 Sep 2026 (0.9 US cents).
//
// Costs OpenRouter credit — one call per card, six cards. Run it when the
// prompt changes, not to look at it.
//
//   node scripts/story-bench.mjs <output dir> [card id …]
//
// The key is read from backend/.dev.vars if it is not in the environment, the
// way asr-bench.mjs reads it. Nothing here prints the key, and nothing here
// prints a request body.

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')

try {
  const vars = readFileSync(join(REPO_ROOT, 'backend/.dev.vars'), 'utf8')
  for (const line of vars.split('\n')) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.+?)\s*$/)
    if (match && !process.env[match[1]]) process.env[match[1]] = match[2]
  }
} catch {
  // No such file — the key may still come from the environment.
}

const API_URL = 'https://openrouter.ai/api/v1/chat/completions'
// The extraction's model, from wrangler.jsonc, so the story is measured on
// what the Worker would run it on.
const MODEL = process.env.MODEL_STORY ?? 'google/gemini-3.6-flash'

// ------------------------------------------------------------------ prompts

const SYSTEM_PROMPT_FI = `Kokoat suomalaisen perheen muistiarkistossa yhden kortin tarinan. Kortti on valokuva, henkilö, paikka tai hetki, ja siitä on kerrottu yksi tai useampi muisto, kukin omalla kertojallaan ja päivämäärällään. Kertojat ovat usein iäkkäitä ja puhuvat rönsyillen ja epävarmoin ajankohdin. Se on normaalia, ei virhe.

TEHTÄVÄSI on JÄRJESTÄÄ kerrottu yhdeksi luettavaksi tekstiksi. Et kirjoita mitään, mitä kukaan ei sanonut. Noudata näitä sääntöjä ehdottomasti:

1. VAIN JÄRJESTÄT. Ei johdantoa, ei loppukaneettia, ei arvioita ("kaunis muisto", "lämmin tunnelma"), ei tunnesanoja, joita kukaan ei sanonut, ei tiivistäviä lauseita. Tarina alkaa siitä, mitä joku kertoi, ja loppuu siihen, mitä joku kertoi.

2. AUKOT JÄÄVÄT AUKOIKSI. Älä keksi siirtymiä, syitä, ajankohtia, suhteita tai paikkoja. Jos kertoja sanoi "joskus 50-luvulla", tarinassa lukee "joskus 50-luvulla". Jos kukaan ei sanonut, kuka kuvassa on, tarina ei tiedä sitä myöskään. Keksitty sukulainen on pahempi kuin puuttuva. Älä myöskään lisää syy- tai seuraussanoja (sillä, koska, siksi, joten), joita kertoja ei sanonut: kaksi peräkkäistä lausetta jäävät peräkkäisiksi.

3. VAHVISTAMATON NIMI EI OLE TOSIASIA. Kortilla luetellaan nimet, jotka perhe on vahvistanut; niitä saa käyttää sellaisenaan. Jokainen muu nimi, joka kerronnoissa esiintyy, sanotaan aina kertojan kautta ("Pekan mukaan laiturin teki Eevertti"), ei koskaan väitteenä.

4. RISTIRIITA NÄYTETÄÄN, EI RATKAISTA. Kun kertojat muistavat eri tavalla, molemmat sanotaan nimellä ("Mummo muistaa, että se oli 50-luvulla; Aino muistaa kesän 1961"). Älä valitse voittajaa äläkä tasoita eroa.

5. KERTOJAN SANAT SÄILYVÄT. Käytä kertojien omia sanoja ja ilmauksia. Saat vaihtaa lauseiden järjestystä, yhdistää samaa asiaa koskevat kohdat ja poistaa toiston, mutta et saa lyhentää sisältöä. Muiston pituus on osa muistoa; et tee tiivistelmää. Puhekielen muoto säilyy ("ne oli hyviä aikoja" ei muutu muotoon "ne olivat"); kun minä-muoto on vaihdettava, käytä mieluummin passiivia ("siellä me aina istuttiin" → "siellä aina istuttiin") kuin kirjakieltä.

6. KERTOJA NIMETÄÄN. Kirjoita kolmannessa persoonassa ja sano, kuka kertoi ("Mummo kertoo, että…"). Kun kertoja puhuu itsestään, nimi tulee minän tilalle ("minä olen se pienempi tyttö" → "Aino on se pienempi tyttö").

7. MUOTO. Pelkkää proosaa kappaleittain, tyhjä rivi kappaleiden välissä. Ei otsikoita, ei listoja, ei lainausmerkkejä kokonaisten lauseiden ympärillä. Pituus seuraa kerrotusta: yksi lyhyt muisto on yhden kappaleen tarina.`

const SYSTEM_PROMPT_EN = `You are assembling the story of one card in a family's memory archive. The card is a photograph, a person, a place or a moment, and one or more memories have been told about it, each with its own teller and date. The tellers are often elderly, ramble, and are unsure of dates. That is normal, not an error.

YOUR TASK is to ORDER what was told into one readable text. You write nothing that nobody said. Follow these rules absolutely:

1. YOU ONLY ORDER. No introduction, no closing line, no judgements ("a lovely memory", "a warm scene"), no feeling words nobody used, no summarising sentences. The story starts with something somebody told and ends with something somebody told.

2. GAPS STAY GAPS. Do not invent transitions, causes, dates, relationships or places. If the teller said "sometime in the fifties", the story says "sometime in the fifties". If nobody said who is in the photograph, the story does not know either. An invented relative is worse than a missing one. Do not add causal words (because, so, therefore) the teller did not use either: two sentences side by side stay side by side.

3. AN UNCONFIRMED NAME IS NOT A FACT. The card lists the names the family has confirmed; those may be used as they are. Every other name that appears in a telling is always said through its teller ("According to Peter, Ernest built the jetty"), never as a statement.

4. A CONTRADICTION IS SHOWN, NOT SETTLED. When tellers remember differently, both are given by name ("Grandma remembers it as the fifties; Anna remembers the summer of 1961"). Do not pick a winner and do not smooth the difference over.

5. THE TELLERS' WORDS STAY. Use the tellers' own words and phrases. You may reorder sentences, bring together what is about the same thing and drop repetition, but you may not shorten the content. The length of a memory is part of the memory; you are not writing a summary. The tellers' register stays too: a spoken turn of phrase is not tidied into written English.

6. THE TELLER IS NAMED. Write in the third person and say who told it ("Grandma says that…"). When a teller speaks of themselves, their name replaces the "I" ("I am the smaller girl" → "Anna is the smaller girl").

7. FORM. Plain prose in paragraphs, a blank line between paragraphs. No headings, no lists, no quotation marks around whole sentences. The length follows what was told: one short memory is a one-paragraph story.`

const SCHEMA = {
  name: 'story',
  schema: {
    type: 'object',
    properties: { story: { type: 'string' } },
    required: ['story'],
    additionalProperties: false,
  },
}

// -------------------------------------------------------------------- cards
//
// The `-seed story` archive, word for word (StorySeed.swift), plus one card
// from `-seed film-week` for the English prompt. The Finnish tellings are
// written in the register the extraction leaves behind: fillers gone, the
// spoken forms kept.

const CARDS = [
  {
    id: 'demo-story-jetty',
    lang: 'fi',
    kind: 'valokuva',
    title: 'Mökin laituri',
    date: '1950-luku (perheen merkintä, tarkkuus vuosikymmen)',
    mentions: [
      // Eevertti, whom nobody has confirmed, is not on the card since the
      // 26 Sep 2026 change to rule 4: an unconfirmed name never leaves the
      // phone, and the prompt meets it only in Pekka's telling.
      { name: 'Aino', kind: 'henkilö' },
      { name: 'Toivo', kind: 'henkilö' },
      { name: 'Puumala', kind: 'paikka' },
    ],
    memories: [
      {
        teller: 'Mummo', told: '14.6.2025', source: 'puhuttu',
        text: 'Siinä kuvassa ollaan sen mökin rannassa, se oli Puumalassa se mökki. Aino oli siinä minun vieressäni ja Toivo otti sen kuvan, se oli aina se joka otti kuvat. Se oli joskus 50-luvulla, en minä nyt muista tarkkaan. Siellä oli aina niin hiljaista iltaisin.',
      },
      {
        teller: 'Aino', told: '2.8.2025', source: 'kirjoitettu',
        text: 'Tämä on otettu kesällä 1961, sinä kesänä kun Toivo sai uuden veneen. Minä olen se pienempi tyttö laiturin päässä. Kahvipannu oli mukana niin kuin aina, ja rannassa istuttiin pitkään.',
      },
      {
        teller: 'Pekka', told: '20.9.2026', source: 'puhuttu',
        text: 'Mummo kertoi tästä laiturista aina, kun mentiin Puumalaan. Hän sanoi, että laiturin lankut oli Eevertti tehnyt ja että ne narisivat joka askeleella. Minä en ole koskaan itse nähnyt sitä mökkiä, se myytiin ennen kuin synnyin.',
      },
    ],
  },
  {
    id: 'demo-story-aino',
    lang: 'fi',
    kind: 'henkilö',
    title: 'Aino',
    date: null,
    // Kotasaari, heard in Mummo's telling since 28 Sep 2026, is a place
    // nobody has confirmed, so it is not on the card (rule 4).
    mentions: [],
    memories: [
      {
        teller: 'Mummo', told: '20.7.2025', source: 'puhuttu',
        text: 'Aino oli minun siskoni lapsi, ja hän tuli mökille joka kesä. Ainon kanssa soudettiin Kotasaareen kalaan aamuvarhaisella. Aino oli aina se rohkein meistä, se meni ensimmäisenä uimaan vaikka vesi oli kylmää.',
      },
      {
        teller: 'Pekka', told: '22.9.2026', source: 'kirjoitettu',
        text: 'Aino-täti opetti minut soutamaan sinä kesänä kun olin kahdeksan. Hän sanoi, että airot pidetään vedessä eikä ilmassa. En muista, mikä vuosi se oli.',
      },
    ],
  },
  {
    id: 'demo-story-kitchen',
    lang: 'fi',
    kind: 'valokuva',
    title: 'Keittiö Kuopiossa',
    date: null,
    mentions: [{ name: 'Kuopio', kind: 'paikka' }],
    memories: [
      {
        teller: 'Mummo', told: '5.9.2025', source: 'kirjoitettu',
        text: 'Meillä oli semmoinen puutalo Kuopiossa, siinä oli iso keittiö ja siellä me aina istuttiin. Naapurin isäntä tuli joka päivä käymään. Ne oli hyviä aikoja.',
      },
    ],
  },
  {
    // A person's card and a place's, added on 28 Sep 2026 so that the one
    // card could be photographed with a story on each kind.
    id: 'demo-story-toivo',
    lang: 'fi',
    kind: 'henkilö',
    title: 'Toivo',
    date: null,
    mentions: [{ name: 'Puumala', kind: 'paikka' }],
    memories: [
      {
        teller: 'Mummo', told: '13.7.2025', source: 'puhuttu',
        text: 'Toivo oli minun isoveljeni. Hänellä oli semmoinen vanha kamera, jonka hän oli saanut isältä, ja sillä hän kuvasi kaiken, mitä mökillä tehtiin. Puumalassa hän kalasti joka aamu ennen kuin muut heräsivät.',
      },
      {
        teller: 'Aino', told: '10.8.2025', source: 'kirjoitettu',
        text: 'Toivo-eno vei meidät lapset veneellä Puumalan selälle, ja hän lauloi soutaessaan aina samaa laulua. Laulun nimeä en muista.',
      },
    ],
  },
  {
    id: 'demo-story-puumala',
    lang: 'fi',
    kind: 'paikka',
    title: 'Puumala',
    date: null,
    mentions: [],
    memories: [
      {
        teller: 'Mummo', told: '21.6.2025', source: 'puhuttu',
        text: 'Puumalassa meillä oli se mökki järven rannassa. Sinne mentiin linja-autolla, ja viimeinen pätkä käveltiin metsätietä pitkin. Mökki myytiin sitten, kun isä kuoli.',
      },
      {
        teller: 'Pekka', told: '21.9.2026', source: 'kirjoitettu',
        text: 'Kävin Puumalassa kerran aikuisena ja yritin etsiä sen mökin, mutta en löytänyt oikeaa rantaa.',
      },
    ],
  },
  {
    id: 'demo-film-print-2',
    lang: 'en',
    kind: 'photograph',
    title: null,
    date: '1940s (the family\'s entry, precision decade)',
    mentions: [],
    memories: [
      {
        teller: 'Grandma', told: '2026-09-15', source: 'spoken',
        text: 'Toivo built that boat in the winter of the war, out of whatever the shed had. He said it leaked for a year and then it stopped.',
      },
      {
        teller: 'Grandma', told: '2026-09-15', source: 'spoken',
        text: 'We rowed it out to the island every summer until the motor came.',
      },
    ],
  },
]

// ------------------------------------------------------------- the request

function render(card) {
  const fi = card.lang === 'fi'
  const lines = []
  const title = card.title ?? (fi ? '(nimetön)' : '(untitled)')
  lines.push(fi ? `KORTTI: ${card.kind} "${title}"` : `CARD: ${card.kind} "${title}"`)
  lines.push(fi
    ? `AJANKOHTA: ${card.date ?? 'ei tiedossa'}`
    : `DATE: ${card.date ?? 'not known'}`)
  const names = card.mentions.length
    ? card.mentions.map((m) => `${m.name} (${m.kind})`).join(', ')
    : fi ? 'ei yhtään' : 'none'
  lines.push(fi ? `VAHVISTETUT NIMET: ${names}` : `CONFIRMED NAMES: ${names}`)
  lines.push(fi ? 'KERRONNAT vanhimmasta uusimpaan:' : 'MEMORIES, oldest first:')
  card.memories.forEach((m, i) => {
    lines.push(`${i + 1}. ${m.teller}, ${m.told}, ${m.source}: ${m.text}`)
  })
  return lines.join('\n')
}

async function story(card, key) {
  const body = {
    model: MODEL,
    messages: [
      { role: 'system', content: card.lang === 'fi' ? SYSTEM_PROMPT_FI : SYSTEM_PROMPT_EN },
      { role: 'user', content: render(card) },
    ],
    temperature: 0.3,
    max_tokens: 6000,
    reasoning: { max_tokens: 1024 },
    response_format: { type: 'json_schema', json_schema: { name: SCHEMA.name, strict: true, schema: SCHEMA.schema } },
    provider: { data_collection: 'deny', require_parameters: true },
  }
  const res = await fetch(API_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://github.com/sunnyflower123/Kinlore',
      'X-Title': 'Kinlore',
    },
    body: JSON.stringify(body),
  })
  if (!res.ok) {
    let code = ''
    try { code = String((await res.json())?.error?.code ?? '') } catch { /* not JSON */ }
    throw new Error(`openrouter ${res.status} ${code}`.trim())
  }
  const data = await res.json()
  const choice = data.choices?.[0]
  const content = choice?.message?.content
  if (!content?.trim()) throw new Error('empty reply')
  const reason = choice?.finish_reason
  if (reason && reason !== 'stop') throw new Error(`finish_reason=${reason}`)
  const parsed = JSON.parse(content)
  return { story: parsed.story, usage: data.usage ?? null, provider: data.provider ?? null, finish: reason ?? null }
}

// --------------------------------------------------------------------- main

const key = process.env.OPENROUTER_API_KEY
if (!key) {
  console.error('OPENROUTER_API_KEY is not set and backend/.dev.vars has none')
  process.exit(2)
}
const outDir = process.argv[2]
if (!outDir) {
  console.error('usage: node scripts/story-bench.mjs <output dir> [card id …]')
  process.exit(2)
}
mkdirSync(outDir, { recursive: true })
const wanted = process.argv.slice(3)
const cards = wanted.length ? CARDS.filter((c) => wanted.includes(c.id)) : CARDS

const all = []
for (const card of cards) {
  const started = Date.now()
  try {
    const result = await story(card, key)
    const record = {
      id: card.id, lang: card.lang, model: MODEL, measuredAt: new Date().toISOString(),
      ms: Date.now() - started, finish: result.finish, usage: result.usage, provider: result.provider,
      input: render(card), story: result.story,
    }
    writeFileSync(join(outDir, `${card.id}.json`), JSON.stringify(record, null, 2) + '\n')
    all.push(record)
    console.log(`\n=== ${card.id} (${card.lang}, ${record.ms} ms, ${result.usage?.completion_tokens ?? '?'} tokens)\n`)
    console.log(result.story)
  } catch (error) {
    console.error(`\n=== ${card.id}: FAILED — ${error.message}`)
    all.push({ id: card.id, lang: card.lang, model: MODEL, failed: error.message })
  }
}
writeFileSync(join(outDir, 'stories.json'), JSON.stringify(all, null, 2) + '\n')
console.log(`\n${all.filter((r) => r.story).length}/${cards.length} stories written to ${outDir}`)
