/// Puheen purku tekstiksi OpenRouterin kautta.
///
/// OpenRouterilla ei ole erillistä transcriptions-päätepistettä: ääni menee
/// chat completionsin `input_audio`-osana base64:nä. Siksi purku ja jäsennys
/// kulkevat saman avaimen ja saman klientin läpi.
///
/// HUOM: monimodaalinen yleismalli ei välttämättä pärjää suomenkieliselle
/// vanhuksen puheelle yhtä hyvin kuin omistettu ASR. Vertaa ennen kuin lukitset:
/// `node scripts/asr-bench.mjs samples/`.

import { complete, type Message } from './openrouter'
import type { Env } from './worker'

const SYSTEM_PROMPT = `Puret suomenkielistä puhetta tekstiksi. Puhuja on usein iäkäs: ääni voi olla hiljainen, puhe murteellista ja lauseet keskeneräisiä.

Kirjoita TÄSMÄLLEEN se mitä kuulet. Älä siisti, älä tiivistä, älä täydennä keskeneräisiä lauseita. Täytesanat ja toistot kuuluvat mukaan — ne siivotaan myöhemmin erikseen, ja alkuperäinen purku säilytetään.

Kiinnitä erityistä huomiota erisnimiin: henkilöiden ja paikkojen nimet ohjaavat koko arkiston rakennetta, ja väärin kuultu nimi on pahempi virhe kuin väärin kuultu täytesana.

Palauta pelkkä teksti ilman lainausmerkkejä tai selityksiä. Jos et kuule puhetta lainkaan, palauta tyhjä merkkijono.`

/// `format` on OpenRouterin odottama muototunniste, esim. "m4a" tai "wav".
export async function transcribe(env: Env, audioBase64: string, format: string): Promise<string> {
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

	// Nolla lämpötila: purku ei ole luova tehtävä. Malli ei saa arvata sanoja
	// joita ei kuullut, koska puhuja ei ehkä ole enää kysyttävissä.
	const text = await complete(env, messages, { model: env.MODEL_TRANSCRIBE, temperature: 0 })
	return text.trim()
}
