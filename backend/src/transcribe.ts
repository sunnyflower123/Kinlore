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

/// Sanaa sekunnissa, jonka yli purku ei voi olla aitoa. Suomea puhutaan
/// normaalisti 2–3 sanaa sekunnissa ja iäkäs hitaammin, joten neljä on reilu
/// yläraja jota kukaan ei ylitä vahingossa.
const MAX_WORDS_PER_SECOND = 4
/// Kiinteä lisä lyhyille nauhoituksille, jottei kolmen sekunnin pätkä hylkäydy
/// siksi että puhuja ehti sanoa kaksi sanaa odotettua enemmän.
const WORD_ALLOWANCE = 20

/// Havaitsee sepittämisen. Huonolla äänellä malli ei vaikene vaan syöksee
/// seinällisen tekstiä jota kukaan ei sanonut — mittasimme yhden mallin
/// tuottavan 135-kertaisen määrän sanoja suhteessa todellisuuteen.
///
/// Sovelluksen kannalta se on pahin mahdollinen lopputulos: käyttäjä saa
/// keksityn muiston joka näyttää aidolta ja menee arkistoon isoäidin nimissä.
/// Tyhjä tulos ja uudelleenyritys on aina parempi kuin sepitetty muisto.
function looksHallucinated(text: string, seconds: number | undefined): boolean {
	if (!seconds || seconds <= 0) return false
	const words = text.trim().split(/\s+/).filter(Boolean).length
	return words > seconds * MAX_WORDS_PER_SECOND + WORD_ALLOWANCE
}

/// `format` on OpenRouterin odottama muototunniste, esim. "m4a" tai "wav".
/// `seconds` on nauhoituksen kesto sovelluksen mittaamana; sitä käytetään
/// sepittämisen havaitsemiseen.
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

	// Nolla lämpötila: purku ei ole luova tehtävä. Malli ei saa arvata sanoja
	// joita ei kuullut, koska puhuja ei ehkä ole enää kysyttävissä.
	const text = (
		await complete(env, messages, { model: env.MODEL_TRANSCRIBE, temperature: 0 })
	).trim()

	if (looksHallucinated(text, seconds)) {
		const words = text.trim().split(/\s+/).length
		console.error(
			`[transcribe] hylätty sepitteenä: ${words} sanaa ${seconds} sekunnista ` +
				`(malli ${env.MODEL_TRANSCRIBE})`,
		)
		throw new Error('Purku tuotti enemmän tekstiä kuin ääneen mahtuu')
	}

	return text
}
