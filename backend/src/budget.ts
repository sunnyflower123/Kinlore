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

export function boundedSeconds(claimed: number | undefined, base64Length: number): number {
	const bytes = base64Length / BASE64_INFLATION
	const atLeast = bytes / MAX_BYTES_PER_SECOND
	const atMost = bytes / MIN_BYTES_PER_SECOND
	return Math.min(Math.max(claimed ?? 0, atLeast), atMost)
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
/// mostly into one or two. Unknown length gets a generous fixed budget; the
/// top is the smallest output limit among the audio models in use.
const TOKENS_PER_WORD: Record<Lang, number> = { fi: 3, en: 1.6 }
const MAX_OUTPUT_TOKENS = 16_000
export function outputBudget(seconds: number | undefined, lang: Lang): number {
	if (!seconds || seconds <= 0) return 4096
	const words = seconds * MAX_WORDS_PER_SECOND[lang] + WORD_ALLOWANCE
	const tokens = Math.ceil(words * TOKENS_PER_WORD[lang]) + 256
	return Math.min(Math.max(tokens, 1024), MAX_OUTPUT_TOKENS)
}
