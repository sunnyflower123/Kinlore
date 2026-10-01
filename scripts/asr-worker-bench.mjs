#!/usr/bin/env node
// The shipped transcription, measured on asr-bench.mjs's own samples through
// the app's own path.
//
// asr-bench.mjs calls each engine directly with its own short prompt, which is
// right for choosing an engine and wrong for saying what the app does: the
// Worker sends backend/src/transcribe.ts's longer prompt, and the key belongs in
// the Worker alone (rule 7). So this sends every sample in samples/ to a local
// Worker's /transcribe, as the app does, and scores the text with the bench's
// own metrics, copied below unchanged so the two sets of numbers compare.
//
//   cd backend && npx wrangler dev
//   node scripts/asr-worker-bench.mjs http://localhost:8787
//
// It spends OpenRouter credit (one short call per sample, 24 for the samples
// made so far) and leaves two throwaway families in the local database, one
// per language, so each language gets a free month of its own.
//
// The samples are synthetic, which the bench's header explains: the figures are
// optimistic, and they say nothing about a real older voice.

import { readdirSync, readFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { basename, dirname, extname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const API = process.argv[2] ?? 'http://localhost:8787'
const DIR = process.argv[3] ? resolve(process.argv[3]) : join(REPO_ROOT, 'samples')

// ---- unchanged from asr-bench.mjs ---------------------------------------
const normalize = (s) =>
  s.toLowerCase()
    .replace(/[.,!?;:"'()\[\]…—–-]/g, ' ')
    .split(/\s+/)
    .filter(Boolean)

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
// -------------------------------------------------------------------------

// The file name carries the language and the degradation step, as
// make-synthetic-samples.py writes them: "en-cottage-noisy", "mokki-kohina".
const languageOf = (f) => (basename(f).startsWith('en-') ? 'en' : 'fi')
const stepOf = (f) => basename(f, extname(f)).split('-').pop()

// The real duration, because the Worker's hallucination ceiling and meter are
// both worked out from it.
const seconds = (p) =>
  Number(execFileSync('afinfo', [p], { encoding: 'utf8' }).match(/estimated duration:\s*([\d.]+)/)?.[1])

async function family() {
  const identity = {
    memberID: crypto.randomUUID().toUpperCase(),
    secret: [...crypto.getRandomValues(new Uint8Array(24))].map((b) => b.toString(16).padStart(2, '0')).join(''),
  }
  const res = await fetch(`${API}/family`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ ...identity, displayName: 'Bench', familyName: 'Bench' }),
  })
  if (!res.ok) throw new Error(`Could not create a family to run against: HTTP ${res.status}`)
  return `Bearer ${identity.memberID}.${identity.secret}`
}

const health = await fetch(`${API}/health`).then((r) => r.json()).catch(() => null)
if (!health?.hasKey) {
  console.error(`No Worker with a key at ${API}. Start one: cd backend && npx wrangler dev`)
  process.exit(1)
}

const auth = { fi: await family(), en: await family() }
const rows = []
for (const f of readdirSync(DIR).filter((f) => extname(f) === '.m4a').sort()) {
  const lang = languageOf(f)
  const reference = readFileSync(join(DIR, basename(f, '.m4a') + '.txt'), 'utf8').trim()
  const res = await fetch(`${API}/transcribe`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: auth[lang] },
    body: JSON.stringify({
      audio: readFileSync(join(DIR, f)).toString('base64'),
      format: 'm4a',
      seconds: seconds(join(DIR, f)),
      lang,
    }),
  })
  if (!res.ok) {
    console.log(`${f.padEnd(26)} HTTP ${res.status}`)
    continue
  }
  const { text } = await res.json()
  const w = wer(normalize(reference), normalize(text))
  const n = nameRecall(reference, text)
  rows.push({ lang, step: stepOf(f), w, n })
  console.log(
    `${f.padEnd(26)} WER ${(w * 100).toFixed(1).padStart(5)} %  names ${n ? `${n.total - n.missed.length}/${n.total}` : '—'}` +
      (n?.missed.length ? `  missed: ${n.missed.join(', ')}` : ''),
  )
}

// Averaged the bench's way, as the mean of each sample's recall, so the result
// sits beside the figures in docs/DETAILS.md. The pooled count is printed too,
// because seven names per step is few enough that one name moves it a lot.
const avg = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : NaN)
const pct = (x) => `${(x * 100).toFixed(1)} %`
for (const lang of ['fi', 'en']) {
  const mine = rows.filter((r) => r.lang === lang)
  if (mine.length === 0) continue
  const named = mine.filter((r) => r.n)
  const hits = named.reduce((s, r) => s + r.n.total - r.n.missed.length, 0)
  const total = named.reduce((s, r) => s + r.n.total, 0)
  console.log(
    `\n${lang}: ${mine.length} samples  WER ${pct(avg(mine.map((r) => r.w)))}  ` +
      `names ${pct(avg(named.map((r) => r.n.recall)))} (${hits}/${total})`,
  )
  for (const step of [...new Set(mine.map((r) => r.step))]) {
    const s = mine.filter((r) => r.step === step)
    console.log(`  ${step.padEnd(10)} WER ${pct(avg(s.map((r) => r.w)))}  names ${pct(avg(s.filter((r) => r.n).map((r) => r.n.recall)))}`)
  }
}
