#!/usr/bin/env node
// ASR comparison for Finnish elderly speech.
//
// This is risk #1 in the plan. Run it BEFORE writing app code: if no engine
// copes with real grandparent speech, the whole dictation concept has to be
// redesigned — and that is cheaper now than at the end of August.
//
// Usage:
//   1. Record 3 REAL samples. Not your own clear speech — that gives a
//      falsely good result. You need a quiet voice, dialect, pauses, unfinished
//      sentences, surnames and place names.
//   2. Write the correct text for each by hand into <name>.txt (same directory,
//      same name as the audio file).
//   3. export OPENAI_API_KEY=...   and/or   export ELEVENLABS_API_KEY=...
//                                  and/or   export GROQ_API_KEY=...
//   4. node scripts/asr-bench.mjs samples/
//
// Metrics:
//   WER  = word error rate. Below 15 % is usable, above 30 % is not.
//   NAME = proper-noun recall. This matters more than WER: getting "Aino" wrong
//          is worse than five wrong filler words, because proper nouns drive how
//          the family tree is built.

import { readdir, readFile } from 'node:fs/promises'
import { execFileSync } from 'node:child_process'
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { basename, dirname, extname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

// The repo root from the script's own location, not from the working directory:
// this can be run from any folder without the paths falling apart.
const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')

// Keys are read from backend/.dev.vars if they are not in the environment. The
// same file the Worker uses — not two places to keep in sync, and no pasting a
// key onto a command line where it stays in shell history.
try {
  const vars = readFileSync(join(REPO_ROOT, 'backend/.dev.vars'), 'utf8')
  for (const line of vars.split('\n')) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.+?)\s*$/)
    if (match && !process.env[match[1]]) process.env[match[1]] = match[2]
  }
} catch {
  // No such file — the keys may still come from the environment.
}

const AUDIO_EXT = new Set(['.m4a', '.mp3', '.wav', '.mp4', '.mpeg', '.mpga', '.webm', '.ogg', '.flac'])

// ---------------------------------------------------------------- engines

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
    // ElevenLabs uses its own header, not a Bearer token.
    header: 'xi-api-key',
    auth: (k) => k,
    // The field names differ from the OpenAI-compatible interface.
    fields: { model: 'model_id', lang: 'language_code' },
  },
  // OpenRouter has no transcriptions endpoint: audio goes as part of chat
  // completions, base64 encoded. Included because the same key also handles
  // extraction — if this holds up, the whole app needs one key.
  // Candidates for MODEL_TRANSCRIBE. Prices are $/Mtok of input.
  { name: 'voxtral-small (0.10)', key: 'OPENROUTER_API_KEY', model: 'mistralai/voxtral-small-24b-2507', custom: openRouterTranscribe, needsWav: true },
  { name: 'gemini-2.5-flash (0.30)', key: 'OPENROUTER_API_KEY', model: 'google/gemini-2.5-flash', custom: openRouterTranscribe },
  { name: 'gemini-3.1-flash-lite (0.25)', key: 'OPENROUTER_API_KEY', model: 'google/gemini-3.1-flash-lite', custom: openRouterTranscribe },
  { name: 'gemini-3.6-flash (1.50)', key: 'OPENROUTER_API_KEY', model: 'google/gemini-3.6-flash', custom: openRouterTranscribe },
  { name: 'gpt-audio-mini (0.60)', key: 'OPENROUTER_API_KEY', model: 'openai/gpt-audio-mini', custom: openRouterTranscribe, needsWav: true },
]

async function openRouterTranscribe(engine, filePath, bytes) {
  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env[engine.key]}`,
      'Content-Type': 'application/json',
      'X-Title': 'Kinlore ASR bench',
    },
    body: JSON.stringify({
      model: engine.model,
      temperature: 0,
      provider: { data_collection: 'deny' },
      messages: [
        {
          // Finnish on purpose: this mirrors the prompt in
          // backend/src/transcribe.ts, so the benchmark measures what the app
          // will actually do.
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

// Some models accept only wav/mp3, not m4a. Convert on the fly so the
// comparison measures the model rather than this script's limitation. NOTE: the
// same limitation applies to the app — it records m4a, so adopting these would
// require conversion in the Worker too, which is not trivial there.
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

// ---------------------------------------------------------------- metrics

// In Finnish, inflection makes some errors meaningless ("mökillä" vs
// "mökille"), but we do not try to be clever: raw WER is a more honest metric
// than a normalisation of our own invention. Only punctuation and case are
// stripped.
const normalize = (s) =>
  s.toLowerCase()
    .replace(/[.,!?;:"'()\[\]…—–-]/g, ' ')
    .split(/\s+/)
    .filter(Boolean)

// Levenshtein at the word level.
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

// Proper nouns: capitalised words in the reference that are not sentence
// initial. A crude heuristic, but enough for a comparison.
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

// ---------------------------------------------------------------- run

// Default directory relative to the repo root, so the command works from
// anywhere.
const dir = process.argv[2] ? resolve(process.argv[2]) : join(REPO_ROOT, 'samples')

let entries
try {
  entries = await readdir(dir)
} catch {
  console.error(`No such directory: ${dir}\n`)
  console.error('Create it and put the recordings and hand-written references there:')
  console.error(`  mkdir -p ${dir}`)
  console.error(`  # ${dir}/grandma-1.m4a  and  ${dir}/grandma-1.txt`)
  console.error('\nThe samples have to be REAL elderly speech — your own clear')
  console.error('speech gives a falsely good result and tells you nothing.')
  process.exit(1)
}

const active = ENGINES.filter((e) => process.env[e.key])
if (active.length === 0) {
  console.error('No API key is set. At least one is required:')
  console.error('  ' + [...new Set(ENGINES.map((e) => e.key))].join(', '))
  process.exit(1)
}

// Provenance, and it decides which of the two questions below can be answered.
//
// A sample counts as REAL only if it sits in a `real/` subdirectory. That fails
// closed on purpose: an unmarked file is treated as synthetic, so the worst case
// is a go/no-go that refuses to answer rather than one that answers wrongly.
// PLAN.md §8 spends three paragraphs untangling exactly this confusion, and the
// bench used to invite it by printing "usable" against text-to-speech.
const realDir = join(dir, 'real')
const realEntries = existsSync(realDir)
  ? readdirSync(realDir).filter((f) => AUDIO_EXT.has(extname(f).toLowerCase()))
  : []
const samples = [
  ...entries
    .filter((f) => AUDIO_EXT.has(extname(f).toLowerCase()))
    .map((f) => ({ file: f, dir, real: false })),
  ...realEntries.map((f) => ({ file: f, dir: realDir, real: true })),
]
if (samples.length === 0) {
  console.error(`No audio files in ${dir}`)
  process.exit(1)
}

console.log(`Engines: ${active.map((e) => e.name).join(', ')}`)
console.log(
  `Samples: ${samples.length} ` +
    `(${samples.filter((s) => s.real).length} real, ` +
    `${samples.filter((s) => !s.real).length} synthetic)\n`,
)

const totals = new Map(
  active.map((e) => [e.name, { werScores: [], nameScores: [], realWer: [], realNames: [] }]),
)

for (const entry of samples) {
  const sample = entry.file
  const audioPath = join(entry.dir, sample)
  const refPath = join(entry.dir, basename(sample, extname(sample)) + '.txt')

  let reference
  try {
    reference = (await readFile(refPath, 'utf8')).trim()
  } catch {
    console.log(`⚠ ${sample}: no reference (${basename(refPath)}) — skipping`)
    continue
  }

  const bytes = await readFile(audioPath)
  console.log(
    `\n━━ ${sample}  (${(bytes.length / 1024 / 1024).toFixed(1)} MB)  ` +
      `${entry.real ? 'REAL SPEECH' : 'synthetic'}`,
  )
  const refWords = normalize(reference)

  for (const engine of active) {
    const t0 = performance.now()
    let text
    try {
      text = await transcribe(engine, audioPath, bytes)
    } catch (err) {
      console.log(`  ${engine.name.padEnd(26)} ERROR  ${err.message}`)
      continue
    }
    const secs = ((performance.now() - t0) / 1000).toFixed(1)
    const w = wer(refWords, normalize(text))
    const names = nameRecall(reference, text)

    totals.get(engine.name).werScores.push(w)
    if (names) totals.get(engine.name).nameScores.push(names.recall)
    // Kept apart, because only these can answer the concept question.
    if (entry.real) {
      totals.get(engine.name).realWer.push(w)
      if (names) totals.get(engine.name).realNames.push(names.recall)
    }

    const nameStr = names
      ? `names ${(names.recall * 100).toFixed(0)}% (${names.total})` +
        (names.missed.length ? `  missed: ${names.missed.join(', ')}` : '')
      : 'names —'
    console.log(`  ${engine.name.padEnd(26)} WER ${(w * 100).toFixed(1).padStart(5)}%  ${nameStr}  ${secs}s`)
    console.log(`  ${' '.repeat(26)} “${text.slice(0, 160)}${text.length > 160 ? '…' : ''}”`)
  }
}

const avg = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : null)

console.log('\n━━ WHICH ENGINE (relative — this is what synthetic audio is good for)')
const ranked = active
  .map((e) => ({ name: e.name, ...totals.get(e.name) }))
  .filter((r) => r.werScores.length > 0)
  .map((r) => ({ name: r.name, wer: avg(r.werScores), names: avg(r.nameScores) }))
  .sort((a, b) => a.wer - b.wer)

for (const r of ranked) {
  const band = r.wer < 0.15 ? 'usable' : r.wer < 0.30 ? 'borderline' : 'NOT ENOUGH'
  console.log(
    `  ${r.name.padEnd(26)} WER ${(r.wer * 100).toFixed(1).padStart(5)}%  ` +
      `names ${r.names === null ? '  —' : (r.names * 100).toFixed(0).padStart(3) + '%'}  ${band}`,
  )
}

// ── The other question, which is not the same one ────────────────────────────
//
// PLAN.md §8 sets two bars and calls the first of them a tripwire: below ~80 %
// on proper nouns, rethink the concept; and this file's own header says a word
// error rate above 30 % is not usable. Both are claims about ABSOLUTE quality on
// REAL elderly speech, and the ranking above cannot answer them — the generator
// says so in its own docstring, because text-to-speech produces no dialect, no
// stammering, no trailing off, and the figures are therefore optimistic.
//
// The optimistic run already missed both bars: 68 % on names against 80, and
// 37.8 % WER against 30. So this section exists to stop that being mistaken for
// the answer in either direction — it refuses rather than guesses.
const NAME_TRIPWIRE = 0.8
const WER_LIMIT = 0.3

/// The engine the app actually ships, read from the Worker's config rather than
/// repeated here. Two places for one fact is how the other numbers in this repo
/// went stale.
function shippedModel() {
  try {
    const raw = readFileSync(join(dirname(resolve(process.argv[1])), '..', 'backend', 'wrangler.jsonc'), 'utf8')
    return raw.match(/"MODEL_TRANSCRIBE"\s*:\s*"([^"]+)"/)?.[1] ?? null
  } catch {
    return null
  }
}

console.log('\n━━ IS THE CONCEPT VIABLE (absolute — needs real speech)')
const shipped = shippedModel()
const realCount = samples.filter((s) => s.real).length

if (realCount === 0) {
  console.log('  NOT ANSWERED. No real recordings were measured.')
  console.log('')
  console.log('  Every sample here is synthetic, and synthetic audio cannot answer this.')
  console.log('  Put real recordings of an elderly speaker in samples/real/, each with a')
  console.log('  hand-written .txt of what was actually said, and run this again. Three are')
  console.log('  enough. See PLAN.md §8 and samples/LUEMINUT.txt.')
  console.log('')
  console.log('  Until then risk 2 is a measurement that has not been taken, not a risk')
  console.log('  that has been retired — and the ranking above is not a second opinion on it.')
} else {
  const engine = active.find((e) => e.model === shipped) ?? null
  const scores = engine ? totals.get(engine.name) : null
  const rw = avg(scores?.realWer ?? [])
  const rn = avg(scores?.realNames ?? [])

  if (!engine) {
    console.log(`  The shipped model (${shipped ?? 'unknown'}) was not among the engines run.`)
    console.log('  The bars below are only meaningful for the one the app actually uses.')
  } else if (rw === null) {
    console.log(`  ${engine.name} produced no usable result on the real recordings.`)
  } else {
    const namesOK = rn !== null && rn >= NAME_TRIPWIRE
    const werOK = rw <= WER_LIMIT
    console.log(`  Engine: ${engine.name}   Real recordings: ${realCount}`)
    console.log(
      `  Proper nouns ${(rn === null ? NaN : rn * 100).toFixed(0)}% ` +
        `(tripwire ${NAME_TRIPWIRE * 100}%)  ${namesOK ? 'ok' : 'BELOW'}`,
    )
    console.log(
      `  Word errors  ${(rw * 100).toFixed(1)}% ` +
        `(limit ${WER_LIMIT * 100}%)  ${werOK ? 'ok' : 'ABOVE'}`,
    )
    console.log('')
    if (namesOK && werOK) {
      console.log('  PASSES both bars on real speech. Risk 2 can be retired — write down the')
      console.log('  numbers and the date in PLAN.md §8 rather than the word "passed".')
    } else {
      console.log('  DOES NOT PASS. PLAN.md §8 says to rethink the concept at this point.')
      console.log('  Read what it already says before doing that: the original audio is kept')
      console.log('  forever and is playable, the raw transcript is kept beside the cleaned')
      console.log('  text, and names can be corrected from the person card. One proper noun')
      console.log('  in three being wrong is the premise those were built for. The decision')
      console.log('  is whether the family still recognises what she said.')
    }
  }
}

console.log(
  '\nProper-noun recall weighs more than WER. The family tree is built out of\n' +
    'names, and a wrong name produces a wrong person that nobody can fix later.',
)
