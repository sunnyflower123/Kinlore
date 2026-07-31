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

import { complete, type Message } from './openrouter'
import type { Env } from './worker'

/// In English: transcribe Finnish speech verbatim; the speaker is often elderly,
/// quiet, dialectal and leaves sentences unfinished. Do not tidy, summarise or
/// complete anything — filler words belong in the output, they are cleaned up
/// separately later and the raw transcript is kept. Pay particular attention to
/// proper nouns. Return plain text; return an empty string if no speech is heard.
const SYSTEM_PROMPT = `Puret suomenkielistä puhetta tekstiksi. Puhuja on usein iäkäs: ääni voi olla hiljainen, puhe murteellista ja lauseet keskeneräisiä.

Kirjoita TÄSMÄLLEEN se mitä kuulet. Älä siisti, älä tiivistä, älä täydennä keskeneräisiä lauseita. Täytesanat ja toistot kuuluvat mukaan — ne siivotaan myöhemmin erikseen, ja alkuperäinen purku säilytetään.

Kiinnitä erityistä huomiota erisnimiin: henkilöiden ja paikkojen nimet ohjaavat koko arkiston rakennetta, ja väärin kuultu nimi on pahempi virhe kuin väärin kuultu täytesana.

Palauta pelkkä teksti ilman lainausmerkkejä tai selityksiä. Jos et kuule puhetta lainkaan, palauta tyhjä merkkijono.`

/// Words per second above which a transcript cannot be genuine. Finnish is
/// normally spoken at 2–3 words per second and an elderly speaker slower, so
/// four is a fair ceiling that nobody crosses by accident.
const MAX_WORDS_PER_SECOND = 4
/// A flat allowance for short recordings, so that a three-second clip is not
/// rejected because the speaker got two more words in than expected.
const WORD_ALLOWANCE = 20

/// Detects hallucination. On poor audio the model does not fall silent — it
/// pours out a wall of text nobody said. We measured one model producing 135
/// times as many words as reality contained.
///
/// For this app that is the worst possible outcome: the user gets an invented
/// memory that looks genuine and enters the archive under grandmother's name. An
/// empty result and a retry is always better than a fabricated memory.
function looksHallucinated(text: string, seconds: number | undefined): boolean {
	if (!seconds || seconds <= 0) return false
	const words = text.trim().split(/\s+/).filter(Boolean).length
	return words > seconds * MAX_WORDS_PER_SECOND + WORD_ALLOWANCE
}

/// `format` is the format identifier OpenRouter expects, e.g. "m4a" or "wav".
/// `seconds` is the recording length as measured by the app; it is used for
/// hallucination detection.
export async function transcribe(
	env: Env,
	audioBase64: string,
	format: string,
	seconds?: number,
): Promise<string> {
	const messages: Message[] = [
		{ role: 'system', content: SYSTEM_PROMPT },
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
		await complete(env, messages, { model: env.MODEL_TRANSCRIBE, temperature: 0 })
	).trim()

	if (looksHallucinated(text, seconds)) {
		const words = text.trim().split(/\s+/).length
		console.error(
			`[transcribe] rejected as hallucination: ${words} words from ${seconds} seconds ` +
				`(model ${env.MODEL_TRANSCRIBE})`,
		)
		throw new Error('Transcription produced more text than the audio can hold')
	}

	return text
}
