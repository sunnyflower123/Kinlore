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
