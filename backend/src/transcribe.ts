/// Speech transcription via OpenRouter.
///
/// OpenRouter has no separate transcriptions endpoint: audio goes as an
/// `input_audio` part of chat completions, base64 encoded. That is why
/// transcription and extraction travel through the same key and the same client.
///
/// NOTE: a multimodal general-purpose model does not necessarily handle Finnish
/// elderly speech as well as a dedicated ASR. Compare before locking it in:
/// `node scripts/asr-bench.mjs samples/`.
///
/// LANGUAGE: the system prompt below is deliberately in Finnish — it is input to
/// the model describing Finnish speech, not documentation. See CLAUDE.md.

import { complete, type Message } from './openrouter.ts'
import { MAX_WORDS_PER_SECOND, REASONING_BUDGET, WORD_ALLOWANCE, transcriptionMaxTokens } from './budget.ts'
import type { Lang } from './extract'
import type { Env } from './worker'

/// In English: transcribe Finnish speech verbatim; the speaker is often elderly,
/// quiet, dialectal and leaves sentences unfinished. Do not tidy, summarise or
/// complete anything — filler words belong in the output, they are cleaned up
/// separately later and the raw transcript is kept. Pay particular attention to
/// proper nouns. Return plain text; return an empty string if no speech is heard.
const SYSTEM_PROMPT_FI = `Puret suomenkielistä puhetta tekstiksi. Puhuja on usein iäkäs: ääni voi olla hiljainen, puhe murteellista ja lauseet keskeneräisiä.

Kirjoita TÄSMÄLLEEN se mitä kuulet. Älä siisti, älä tiivistä, älä täydennä keskeneräisiä lauseita. Täytesanat ja toistot kuuluvat mukaan — ne siivotaan myöhemmin erikseen, ja alkuperäinen purku säilytetään.

Kiinnitä erityistä huomiota erisnimiin: henkilöiden ja paikkojen nimet ohjaavat koko arkiston rakennetta, ja väärin kuultu nimi on pahempi virhe kuin väärin kuultu täytesana.

Palauta pelkkä teksti ilman lainausmerkkejä tai selityksiä. Jos et kuule puhetta lainkaan, palauta tyhjä merkkijono.`

/// The same instruction for English speech. Not a translation of the Finnish —
/// that one names dialect and unfinished sentences because that is what a
/// Finnish elderly speaker does on tape. What is identical is the part that
/// matters: verbatim, no tidying, and proper nouns above everything, because a
/// misheard name builds a wrong person into the family tree and a misheard
/// filler builds nothing.
const SYSTEM_PROMPT_EN = `You are transcribing English speech. The speaker is often elderly: the voice may be quiet, the accent strong, and the sentences unfinished.

Write down EXACTLY what you hear. Do not tidy, do not condense, do not finish an unfinished sentence. Fillers and repetitions belong in the text — they are cleaned up later, separately, and the original transcript is kept.

Pay particular attention to proper nouns: the names of people and places shape the whole archive, and a misheard name is a worse error than a misheard filler.

Return the plain text with no quotation marks and no explanation. If you hear no speech at all, return an empty string.`

/// Words per second above which a transcript cannot be genuine — per language,
/// because the same story is not the same number of words.
///
/// Detects hallucination. On poor audio the model does not fall silent — it
/// pours out a wall of text nobody said. We measured one model producing 135
/// times as many words as reality contained.
///
/// For this app that is the worst possible outcome: the user gets an invented
/// memory that looks genuine and enters the archive under grandmother's name. An
/// empty result and a retry is always better than a fabricated memory.
function looksHallucinated(text: string, seconds: number | undefined, lang: Lang): boolean {
	if (!seconds || seconds <= 0) return false
	const words = text.trim().split(/\s+/).filter(Boolean).length
	return words > seconds * MAX_WORDS_PER_SECOND[lang] + WORD_ALLOWANCE
}

/// `format` is the format identifier OpenRouter expects, e.g. "m4a" or "wav".
/// `seconds` is the recording length as measured by the app; it is used for
/// hallucination detection.
export async function transcribe(
	env: Env,
	audioBase64: string,
	format: string,
	seconds?: number,
	/// The language being spoken. Defaults to Finnish so an un-updated client
	/// keeps the behaviour it was written against.
	lang: Lang = 'fi',
): Promise<string> {
	const messages: Message[] = [
		{ role: 'system', content: lang === 'en' ? SYSTEM_PROMPT_EN : SYSTEM_PROMPT_FI },
		{
			role: 'user',
			content: [
				{ type: 'text', text: 'Pura tämä nauhoitus tekstiksi.' },
				{ type: 'input_audio', input_audio: { data: audioBase64, format } },
			],
		},
	]

	// Zero temperature: transcription is not a creative task. The model must not
	// guess at words it did not hear, because the speaker may no longer be
	// around to ask.
	const text = (
		await complete(env, messages, {
			model: env.MODEL_TRANSCRIBE,
			temperature: 0,
			maxTokens: transcriptionMaxTokens(seconds, lang, env.MODEL_TRANSCRIBE),
			reasoningTokens: REASONING_BUDGET,
		})
	).trim()

	if (looksHallucinated(text, seconds, lang)) {
		const words = text.trim().split(/\s+/).length
		console.error(
			`[transcribe] rejected as hallucination: ${words} words from ${seconds} seconds ` +
				`(model ${env.MODEL_TRANSCRIBE})`,
		)
		throw new Error('Transcription produced more text than the audio can hold')
	}

	return text
}
