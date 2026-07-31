#!/usr/bin/env node
// ASR-vertailu suomenkieliselle vanhuksen puheelle.
//
// Tämä on suunnitelman riski nro 1. Aja tämä ENNEN kuin kirjoitat sovelluskoodia:
// jos yksikään moottori ei pärjää oikealla isovanhemman puheella, koko
// sanelukonsepti pitää suunnitella uusiksi — ja se on halvempaa nyt kuin elokuun
// lopussa.
//
// Käyttö:
//   1. Nauhoita 3 OIKEAA näytettä. Ei omaa selkeää puhettasi — se antaa
//      valheellisen hyvän tuloksen. Tarvitset hiljaista ääntä, murretta,
//      taukoja, keskenjääviä lauseita, sukunimiä ja paikannimiä.
//   2. Kirjoita kustakin käsin oikea teksti tiedostoon <nimi>.txt (sama
//      kansio, sama nimi kuin äänitiedostolla).
//   3. export OPENAI_API_KEY=...   ja/tai   export ELEVENLABS_API_KEY=...
//                                  ja/tai   export GROQ_API_KEY=...
//   4. node scripts/asr-bench.mjs samples/
//
// Mittarit:
//   WER  = sanavirheprosentti. < 15 % on käyttökelpoinen, > 30 % ei ole.
//   NAME = erisnimien osuvuus. Tämä on tärkeämpi kuin WER: "Aino" väärin on
//          pahempi kuin viisi väärää täytesanaa, koska erisnimet ohjaavat
//          sukupuun rakentumista.

import { readdir, readFile } from 'node:fs/promises'
import { execFileSync } from 'node:child_process'
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { readFileSync } from 'node:fs'
import { basename, dirname, extname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

// Repon juuri skriptin sijainnista, ei työhakemistosta: tämän voi ajaa mistä
// tahansa kansiosta ilman että polut hajoavat.
const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')

// Avaimet luetaan backend/.dev.vars:sta jos niitä ei ole ympäristössä. Sama
// tiedosto jota Worker käyttää — ei kahta paikkaa joita pitää pitää synkassa,
// eikä avaimen liittämistä komentoriville jossa se jää shell-historiaan.
try {
  const vars = readFileSync(join(REPO_ROOT, 'backend/.dev.vars'), 'utf8')
  for (const line of vars.split('\n')) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.+?)\s*$/)
    if (match && !process.env[match[1]]) process.env[match[1]] = match[2]
  }
} catch {
  // Tiedostoa ei ole — avaimet voivat silti tulla ympäristöstä.
}

const AUDIO_EXT = new Set(['.m4a', '.mp3', '.wav', '.mp4', '.mpeg', '.mpga', '.webm', '.ogg', '.flac'])

// ---------------------------------------------------------------- moottorit

const ENGINES = [
  {
    name: 'openai/whisper-1',
    key: 'OPENAI_API_KEY',
    url: 'https://api.openai.com/v1/audio/transcriptions',
    model: 'whisper-1',
    auth: (k) => `Bearer ${k}`,
  },
  {
    name: 'openai/gpt-4o-transcribe',
    key: 'OPENAI_API_KEY',
    url: 'https://api.openai.com/v1/audio/transcriptions',
    model: 'gpt-4o-transcribe',
    auth: (k) => `Bearer ${k}`,
  },
  {
    name: 'groq/whisper-large-v3',
    key: 'GROQ_API_KEY',
    url: 'https://api.groq.com/openai/v1/audio/transcriptions',
    model: 'whisper-large-v3',
    auth: (k) => `Bearer ${k}`,
  },
  {
    name: 'elevenlabs/scribe_v1',
    key: 'ELEVENLABS_API_KEY',
    url: 'https://api.elevenlabs.io/v1/speech-to-text',
    model: 'scribe_v1',
    // ElevenLabs käyttää omaa headeria, ei Bearer-tokenia.
    header: 'xi-api-key',
    auth: (k) => k,
    // Kenttien nimet poikkeavat OpenAI-yhteensopivasta rajapinnasta.
    fields: { model: 'model_id', lang: 'language_code' },
  },
  // OpenRouterilla ei ole transcriptions-päätepistettä: ääni menee chat
  // completionsin osana base64:nä. Mukana koska sama avain hoitaa myös
  // jäsennyksen — jos tämä pärjää, koko sovellus tarvitsee yhden avaimen.
  // Ehdokkaat MODEL_TRANSCRIBE-muuttujalle. Hinnat $/Mtok syötettä.
  { name: 'voxtral-small (0,10)', key: 'OPENROUTER_API_KEY', model: 'mistralai/voxtral-small-24b-2507', custom: openRouterTranscribe, needsWav: true },
  { name: 'gemini-2.5-flash (0,30)', key: 'OPENROUTER_API_KEY', model: 'google/gemini-2.5-flash', custom: openRouterTranscribe },
  { name: 'gemini-3.1-flash-lite (0,25)', key: 'OPENROUTER_API_KEY', model: 'google/gemini-3.1-flash-lite', custom: openRouterTranscribe },
  { name: 'gemini-3.6-flash (1,50)', key: 'OPENROUTER_API_KEY', model: 'google/gemini-3.6-flash', custom: openRouterTranscribe },
  { name: 'gpt-audio-mini (0,60)', key: 'OPENROUTER_API_KEY', model: 'openai/gpt-audio-mini', custom: openRouterTranscribe, needsWav: true },
]

async function openRouterTranscribe(engine, filePath, bytes) {
  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env[engine.key]}`,
      'Content-Type': 'application/json',
      'X-Title': 'Memorize ASR bench',
    },
    body: JSON.stringify({
      model: engine.model,
      temperature: 0,
      provider: { data_collection: 'deny' },
      messages: [
        {
          role: 'system',
          content:
            'Puret suomenkielistä puhetta tekstiksi. Kirjoita täsmälleen se mitä kuulet, ' +
            'älä siisti äläkä tiivistä. Kiinnitä erityistä huomiota erisnimiin. ' +
            'Palauta pelkkä teksti.',
        },
        {
          role: 'user',
          content: [
            { type: 'text', text: 'Pura tämä nauhoitus tekstiksi.' },
            {
              type: 'input_audio',
              input_audio: {
                data: bytes.toString('base64'),
                format: engine.needsWav ? 'wav' : extname(filePath).slice(1).toLowerCase() || 'm4a',
              },
            },
          ],
        },
      ],
    }),
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`)
  const json = await res.json()
  return (json.choices?.[0]?.message?.content ?? '').trim()
}

// Osa malleista hyväksyy vain wav/mp3, ei m4a:ta. Muunnetaan lennossa, jotta
// vertailu mittaa mallia eikä tämän skriptin rajoitetta. HUOM: sama rajoite
// koskee sovellusta — se nauhoittaa m4a:ta, joten näiden käyttöönotto vaatisi
// muunnoksen myös Workerissa, mikä ei ole siellä triviaalia.
const WAV_CACHE = new Map()
function asWav(filePath, bytes) {
  if (extname(filePath).toLowerCase() === '.wav') return bytes
  if (WAV_CACHE.has(filePath)) return WAV_CACHE.get(filePath)
  const dir = mkdtempSync(join(tmpdir(), 'asr-'))
  const out = join(dir, basename(filePath).replace(/\.[^.]+$/, '.wav'))
  execFileSync('afconvert', ['-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', filePath, out])
  const wavBytes = readFileSync(out)
  WAV_CACHE.set(filePath, wavBytes)
  return wavBytes
}

async function transcribe(engine, filePath, bytes) {
  if (engine.custom) {
    return engine.custom(engine, filePath, engine.needsWav ? asWav(filePath, bytes) : bytes)
  }

  const apiKey = process.env[engine.key]
  const form = new FormData()
  const f = engine.fields ?? {}
  form.set('file', new Blob([bytes]), basename(filePath))
  form.set(f.model ?? 'model', engine.model)
  form.set(f.lang ?? 'language', 'fi')

  const res = await fetch(engine.url, {
    method: 'POST',
    headers: { [engine.header ?? 'Authorization']: engine.auth(apiKey) },
    body: form,
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`)
  const json = await res.json()
  return (json.text ?? '').trim()
}

// ---------------------------------------------------------------- mittarit

// Suomessa taivutus tekee osasta virheistä merkityksettömiä ("mökillä" vs
// "mökille"), mutta emme yritä olla fiksuja: raaka WER on rehellisempi mittari
// kuin oma keksitty normalisointi. Poistetaan vain välimerkit ja kirjainkoko.
const normalize = (s) =>
  s.toLowerCase()
    .replace(/[.,!?;:"'()\[\]…—–-]/g, ' ')
    .split(/\s+/)
    .filter(Boolean)

// Levenshtein sanatasolla.
function wer(refWords, hypWords) {
  const n = refWords.length
  const m = hypWords.length
  if (n === 0) return m === 0 ? 0 : 1
  let prev = Array.from({ length: m + 1 }, (_, j) => j)
  for (let i = 1; i <= n; i++) {
    const cur = [i]
    for (let j = 1; j <= m; j++) {
      const cost = refWords[i - 1] === hypWords[j - 1] ? 0 : 1
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
    }
    prev = cur
  }
  return prev[m] / n
}

// Erisnimet: referenssistä isolla alkukirjaimella kirjoitetut sanat jotka eivät
// ole lauseen ensimmäisiä. Karkea heuristiikka, mutta riittää vertailuun.
function properNouns(reference) {
  const out = new Set()
  for (const sentence of reference.split(/(?<=[.!?])\s+/)) {
    const words = sentence.trim().split(/\s+/)
    for (let i = 1; i < words.length; i++) {
      const w = words[i].replace(/[.,!?;:"'()]/g, '')
      if (/^[A-ZÅÄÖ][a-zåäö]+$/.test(w)) out.add(w.toLowerCase())
    }
  }
  return out
}

function nameRecall(reference, hypothesis) {
  const names = properNouns(reference)
  if (names.size === 0) return null
  const hyp = new Set(normalize(hypothesis))
  let hit = 0
  for (const n of names) if (hyp.has(n)) hit++
  return { recall: hit / names.size, total: names.size, missed: [...names].filter((n) => !hyp.has(n)) }
}

// ---------------------------------------------------------------- ajo

// Oletuskansio repon juuresta, jotta komento toimii mistä tahansa ajettuna.
const dir = process.argv[2] ? resolve(process.argv[2]) : join(REPO_ROOT, 'samples')

let entries
try {
  entries = await readdir(dir)
} catch {
  console.error(`Kansiota ei ole: ${dir}\n`)
  console.error('Luo se ja laita sinne nauhoitukset sekä käsin kirjoitetut oikeat tekstit:')
  console.error(`  mkdir -p ${dir}`)
  console.error(`  # ${dir}/mummo-1.m4a  ja  ${dir}/mummo-1.txt`)
  console.error('\nNäytteiden pitää olla OIKEAA vanhuksen puhetta — oma selkeä')
  console.error('puheesi antaa valheellisen hyvän tuloksen eikä kerro mitään.')
  process.exit(1)
}

const active = ENGINES.filter((e) => process.env[e.key])
if (active.length === 0) {
  console.error('Yhtään API-avainta ei ole asetettu. Tarvitaan vähintään yksi:')
  console.error('  ' + [...new Set(ENGINES.map((e) => e.key))].join(', '))
  process.exit(1)
}

const samples = entries.filter((f) => AUDIO_EXT.has(extname(f).toLowerCase()))
if (samples.length === 0) {
  console.error(`Ei äänitiedostoja kansiossa ${dir}`)
  process.exit(1)
}

console.log(`Moottorit: ${active.map((e) => e.name).join(', ')}`)
console.log(`Näytteet:  ${samples.length}\n`)

const totals = new Map(active.map((e) => [e.name, { werScores: [], nameScores: [] }]))

for (const sample of samples) {
  const audioPath = join(dir, sample)
  const refPath = join(dir, basename(sample, extname(sample)) + '.txt')

  let reference
  try {
    reference = (await readFile(refPath, 'utf8')).trim()
  } catch {
    console.log(`⚠ ${sample}: ei referenssiä (${basename(refPath)}) — ohitetaan`)
    continue
  }

  const bytes = await readFile(audioPath)
  console.log(`\n━━ ${sample}  (${(bytes.length / 1024 / 1024).toFixed(1)} MB)`)
  const refWords = normalize(reference)

  for (const engine of active) {
    const t0 = performance.now()
    let text
    try {
      text = await transcribe(engine, audioPath, bytes)
    } catch (err) {
      console.log(`  ${engine.name.padEnd(26)} VIRHE  ${err.message}`)
      continue
    }
    const secs = ((performance.now() - t0) / 1000).toFixed(1)
    const w = wer(refWords, normalize(text))
    const names = nameRecall(reference, text)

    totals.get(engine.name).werScores.push(w)
    if (names) totals.get(engine.name).nameScores.push(names.recall)

    const nameStr = names
      ? `nimet ${(names.recall * 100).toFixed(0)}% (${names.total})` +
        (names.missed.length ? `  hukassa: ${names.missed.join(', ')}` : '')
      : 'nimet —'
    console.log(`  ${engine.name.padEnd(26)} WER ${(w * 100).toFixed(1).padStart(5)}%  ${nameStr}  ${secs}s`)
    console.log(`  ${' '.repeat(26)} “${text.slice(0, 160)}${text.length > 160 ? '…' : ''}”`)
  }
}

const avg = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : null)

console.log('\n━━ YHTEENVETO')
const ranked = active
  .map((e) => ({ name: e.name, ...totals.get(e.name) }))
  .filter((r) => r.werScores.length > 0)
  .map((r) => ({ name: r.name, wer: avg(r.werScores), names: avg(r.nameScores) }))
  .sort((a, b) => a.wer - b.wer)

for (const r of ranked) {
  const verdict = r.wer < 0.15 ? 'käyttökelpoinen' : r.wer < 0.30 ? 'rajatapaus' : 'EI RIITÄ'
  console.log(
    `  ${r.name.padEnd(26)} WER ${(r.wer * 100).toFixed(1).padStart(5)}%  ` +
      `nimet ${r.names === null ? '  —' : (r.names * 100).toFixed(0).padStart(3) + '%'}  ${verdict}`,
  )
}

console.log(
  '\nMuista: erisnimien osuvuus painaa enemmän kuin WER. Sukupuu rakentuu nimistä,\n' +
    'ja väärä nimi tuottaa väärän henkilön jota kukaan ei myöhemmin osaa korjata.',
)
