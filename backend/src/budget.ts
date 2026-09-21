// What the audio can hold: the word ceiling the hallucination guard uses,
// and the token budget the transcription sends along with the audio. In a
// file of its own with no runtime imports, so `transcribe-budget-check.mjs`
// can load it on Node's own type stripping — the Worker's other modules
// import each other without extensions, which Node will not resolve.

import type { Lang } from './extract'

/// Finnish is agglutinative: one long word carries what English needs three or
/// four for. Measured on this project's own paired samples, the same telling is
/// 27 Finnish words in 13.24 s and 35 English words in 11.61 s — 2.04 against
/// 3.01 words a second, and 30 % more words in English for identical content.
///
/// So one ceiling cannot mean the same thing twice. Four leaves Finnish twice
/// the headroom it needs and English only a third more than it uses, which is
/// not a margin — an excited speaker crosses it and has a real telling thrown
/// away as a fabrication. Six keeps English the same ratio to its measured rate
/// that four keeps for Finnish.
export const MAX_WORDS_PER_SECOND: Record<Lang, number> = { fi: 4, en: 6 }
/// A flat allowance for short recordings, so that a three-second clip is not
/// rejected because the speaker got two more words in than expected.
export const WORD_ALLOWANCE = 20

/// What the bytes say the duration cannot be.
///
/// `seconds` arrives in the request body: the app reads it off its own file
/// with `AVAudioPlayer` and sends it. Everything downstream trusts it — the
/// meter charges it, and the hallucination ceiling above is derived from it —
/// so a client that sends a small number, or leaves the field out, transcribes
/// without spending the family's month. `recordAISeconds` returns before it
/// writes anything once the value rounds to zero, and nothing at runtime
/// notices. The invite link is the only thing between that and an open
/// transcription endpoint billed to `OPENROUTER_API_KEY`.
///
/// The bytes are the one thing the caller cannot lie about, because the Worker
/// counted them. So the claim is clamped to what that many bytes can hold.
///
/// **This is a bound and not a measurement**, and the difference matters when
/// reading the numbers. Knowing the real duration means decoding the audio,
/// which this Worker will not do. The two rates are therefore deliberately
/// generous at both ends, so that the clamp never charges an honest client for
/// time they did not use: 40 kB/s is a higher bitrate than any speech recording
/// plausibly is, and 1 kB/s is lower. The app's own files sit at 4.5 kB/s
/// (measured, ARCHITECTURE §5 — 268 kB for 60 s), an order of magnitude inside
/// both.
///
/// What that buys, stated honestly: an omitted `seconds` on ninety seconds of
/// audio is charged ten seconds rather than nothing. The hole becomes a
/// discount rather than a free pass, and the token budget can no longer be
/// inflated by claiming an hour for a small file. Closing it completely needs
/// the decode.
const MAX_BYTES_PER_SECOND = 40_000
const MIN_BYTES_PER_SECOND = 1_000

/// Base64 inflates by roughly a third; `worker.ts` measures the size ceiling
/// the same way.
const BASE64_INFLATION = 1.37

/// `claimed` is TYPED and not checked, which is not the same thing. It comes
/// out of `request.json()`, so a string, an object or a NaN all arrive here
/// wearing `number | undefined`. Every one of them propagates through the
/// `Math.max`/`Math.min` below and comes out NaN — and NaN is falsy, which is
/// where the damage is: `looksHallucinated` opens with `if (!seconds …) return
/// false`, so the guard against a model inventing a memory nobody told simply
/// turns off, silently, for anyone who sends `{"seconds": "90"}`. Measured
/// 10 Sep 2026: `boundedSeconds('abc', 100000)` returned NaN, the ceiling was
/// skipped, the output budget fell back to its 4096 default, and
/// `recordAISeconds` bound NaN into the meter because NaN is not `=== 0`.
///
/// Anything that is not a finite number is an absent claim, which the clamp
/// below already knows what to do with: the bytes then set the floor. This is
/// the file whose whole subject is that the caller can lie about `seconds`,
/// and "not a number" was the one lie it did not cover.
export function boundedSeconds(claimed: number | undefined, base64Length: number): number {
	const asked = typeof claimed === 'number' && Number.isFinite(claimed) ? claimed : 0
	const bytes = base64Length / BASE64_INFLATION
	const atLeast = bytes / MAX_BYTES_PER_SECOND
	const atMost = bytes / MIN_BYTES_PER_SECOND
	return Math.min(Math.max(asked, atLeast), atMost)
}

/// How many tokens the transcript of `seconds` of speech can need, at most.
///
/// `complete()` sends no cap unless told one, and the route's default is low:
/// a twenty-minute telling came back with `finish_reason=length`, was rejected
/// whole as a 503, and after three attempts the catch-up gave up on it for
/// good — the longest and most valuable memories were the ones that never got
/// their text (founder's-eye review, 3 Sep 2026, finding #20). The cap is the
/// hallucination bound above turned into tokens: the most words the audio can
/// hold, times the tokens a word of that language costs, plus room to breathe.
/// Finnish words are long and tokenise into several pieces; English ones
/// mostly into one or two. Unknown length gets a generous fixed budget. The
/// top is not here: it belongs to the model, and `transcriptionMaxTokens`
/// applies it.
const TOKENS_PER_WORD: Record<Lang, number> = { fi: 3, en: 1.6 }
export function outputBudget(seconds: number | undefined, lang: Lang): number {
	if (!seconds || seconds <= 0) return 4096
	const words = seconds * MAX_WORDS_PER_SECOND[lang] + WORD_ALLOWANCE
	const tokens = Math.ceil(words * TOKENS_PER_WORD[lang]) + 256
	return Math.max(tokens, 1024)
}

/// The most one reply from `model` may hold.
///
/// One ceiling of 16 000 stood here for every call, and it was the smallest
/// limit in use — `openai/gpt-4o-mini`'s 16 384, the extraction's fallback,
/// which never transcribes anything. So the transcription, which only ever
/// runs on Gemini, was held to a limit a quarter of its own: at a realistic
/// two Finnish words a second that ends a telling at about half an hour, and
/// the recording limit (`MAX_AUDIO_BYTES`) admits an hour and a half. The
/// structuring hit it sooner, because it writes the whole telling out again:
/// its budget reached the ceiling at about eighteen Finnish minutes.
///
/// The numbers are each model's `top_provider.max_completion_tokens` from
/// OpenRouter's /models, read on 21 Sep 2026 — somebody else's figures, which
/// can change without this repo changing. A model not listed here gets the old
/// 16 000, which is what every call was sent before and what every model in
/// use accepts, so changing a `MODEL_*` variable can cost a long telling its
/// room but cannot turn a request into a 400.
const OUTPUT_CEILINGS: Record<string, number> = {
	'google/gemini-3.6-flash': 65_536,
	'openai/gpt-4o-mini': 16_000,
}
export const DEFAULT_OUTPUT_CEILING = 16_000
export function outputCeiling(model: string): number {
	return OUTPUT_CEILINGS[model] ?? DEFAULT_OUTPUT_CEILING
}

/// What the transcription model may spend thinking before it writes a word.
///
/// `max_tokens` covers the reasoning as well as the answer, and
/// `outputBudget` above was written as if there were only the answer. Measured
/// 21 Sep 2026 on a 40-second telling that reached the founder's phone as
/// *"Your voice is kept"*: `gemini-3.6-flash` spent 566–980 tokens reasoning
/// against a transcript of about 90, so one run in three hit the 1024 cap and
/// came back `finish_reason=length` — rejected whole, audio kept, no text.
/// Finnish failed five times in five. Uncapped, the synthetic hard and noisy
/// samples reasoned for up to 2 792.
///
/// Reasoning is budgeted rather than switched off. `effort: minimal` passed
/// all 24 samples too, but it made the noisy ones worse (`haat-kohina` 5.9 %
/// word error rate against 35 %), and the model was chosen by measurement with
/// its reasoning on. Capped at this number, 8 of 8 of the runs that had failed
/// finished.
export const REASONING_BUDGET = 4096

/// The whole of `max_tokens` for a transcription: the answer's budget plus the
/// thinking's, never past what the model can write.
export function transcriptionMaxTokens(seconds: number | undefined, lang: Lang, model: string): number {
	return Math.min(outputBudget(seconds, lang) + REASONING_BUDGET, outputCeiling(model))
}

/// How many tokens the STRUCTURING of a telling can need, at most.
///
/// The same defect as `outputBudget` above, in the other half of the pipeline
/// and found the same way — by a `finish_reason=length` in the production log
/// on 19 Sep 2026, hours after the archive context and the photograph started
/// travelling with the transcript. `extract()` sent a flat 2000 whose comment
/// read "comfortably above the longest memory to be expected", and measurement
/// says it was not: the same 126-word telling through the shipping schema came
/// back at 1735 and at 2376 completion tokens on two consecutive runs.
///
/// **A flat cap in the middle of the range is the worst place for one**, which
/// is why nobody had seen this. A truncated reply is rejected whole, the second
/// attempt usually succeeds, and what the family sees is a telling that took
/// twice as long. When both attempts land high the round falls through to
/// `MODEL_EXTRACT_FALLBACK`, and `openai/gpt-4o-mini` writes Finnish visibly
/// worse — the run that exposed this returned "Ainoista", a plural of a woman's
/// name, and questions nobody would ask.
///
/// The photograph did not cause it. It raised the floor — measured at 8 words,
/// 901 and 1024 tokens without a picture against 1314 and 1451 with one — on a
/// budget that was already too tight for a long telling on its own.
///
/// The shape follows the measurement rather than the other way round. Most of
/// the completion is the model's own reasoning and it is largely CONSTANT: an
/// eight-word telling spends up to 1451 tokens before writing anything. What
/// scales is the body, and rule 2 of the prompt forbids shortening it, so it
/// costs the transcript again — once as text and once more as the reasoning
/// that grew with the input. Hence twice the transcript's tokens over a fixed
/// floor, against measured maxima of 1451 at 8 words, 1892 at 38 and 2376 at
/// 126.
///
/// Generous on purpose, and it is free to be: `max_tokens` is a ceiling and
/// not a reservation, so an unused budget costs nothing. What a tight one costs
/// is a retry, a doubled wait, and sometimes the weaker model.
///
/// The ceiling is the model's, so the fallback keeps the 16 000 it always had:
/// a telling too long for it fails there as it did before, and the primary
/// model's two attempts are the ones that now have room.
const EXTRACTION_FLOOR = 3072
export function extractionBudget(transcript: string, lang: Lang, model: string): number {
	const words = transcript.trim().split(/\s+/).filter(Boolean).length
	const tokens = Math.ceil(words * TOKENS_PER_WORD[lang] * 2) + EXTRACTION_FLOOR
	return Math.min(tokens, outputCeiling(model))
}
