/// Memory extraction: from rambling speech to structure.
///
/// Mirrors the iOS-side `ExtractionResult` type. Years travel as integers rather
/// than unix timestamps, because language models handle years reliably and
/// timestamps not at all.
///
/// NOTE ON LANGUAGE: the system prompt and the schema `description` fields below
/// are deliberately in Finnish. They are not documentation — they are input to
/// the model, and they instruct it about Finnish morphology (see rule 1). They
/// were tuned by measurement; rewriting them in English would be a behaviour
/// change, not a translation. Everything else in this file is English.

import { complete, UpstreamError, type Message } from './openrouter'
import type { Env } from './worker'

export const EXTRACTION_SCHEMA = {
	name: 'memory',
	schema: {
		type: 'object',
		properties: {
			body: {
				type: 'string',
				description:
					'Muisto siivottuna luettavaan muotoon. Täytesanat pois, sisältö ja pituus ennallaan.',
			},
			mentions: {
				type: 'array',
				description:
					'Puheessa mainitut henkilöt ja paikat. VAIN erisnimet — ei yleisnimiä ' +
					'kuten "mummola", "mökki" tai "koulu".',
				items: {
					type: 'object',
					properties: {
						name: {
							type: 'string',
							description: 'Nimi PERUSMUODOSSA: "Ainon" → "Aino", "Puumalassa" → "Puumala".',
						},
						kind: { type: 'string', enum: ['person', 'place'] },
						confidence: {
							type: 'number',
							description: '0–1. Alle 1 tarkoittaa että ihmisen pitää vahvistaa.',
						},
					},
					required: ['name', 'kind', 'confidence'],
					additionalProperties: false,
				},
			},
			date: {
				type: 'object',
				description: 'Ajankohta sellaisena kuin se puheessa esiintyi, ei tarkennettuna.',
				properties: {
					start_year: { type: ['integer', 'null'] },
					end_year: { type: ['integer', 'null'] },
					precision: {
						type: 'string',
						enum: ['day', 'month', 'year', 'decade', 'unknown'],
					},
				},
				required: ['start_year', 'end_year', 'precision'],
				additionalProperties: false,
			},
			questions: {
				type: 'array',
				description: 'Täsmälleen kolme jatkokysymystä jotka kohdistuvat aukkoihin.',
				items: { type: 'string' },
			},
		},
		required: ['body', 'mentions', 'date', 'questions'],
		additionalProperties: false,
	},
} as const

/// Finnish by design — see the note at the top of this file. The six rules, in
/// English for the reader: (1) names in base form, or the family tree fills with
/// duplicates; (2) clean up filler words but never shorten, the length is part
/// of the memory; (3) proper nouns only, a common noun like "grandma's house"
/// identifies nobody; (4) never invent, an invented relative is worse than a
/// missing one; (5) preserve uncertainty, a decade stays a decade; (6) exactly
/// three follow-up questions aimed at the gaps.
const SYSTEM_PROMPT = `Autat suomalaista perhettä säilyttämään muistoja. Käyttäjä on usein iäkäs ja puhuu rönsyillen, keskeneräisin lausein ja epävarmoin ajankohdin. Se on normaalia, ei virhe.

TEHTÄVÄSI on jäsentää puhe rakenteeksi. Noudata näitä sääntöjä ehdottomasti:

1. NIMET PERUSMUODOSSA. Suomen taivutus tuottaa samasta ihmisestä monta pintamuotoa: "Ainon", "Ainolle" ja "Aino" ovat sama henkilö. Palauta aina perusmuoto, muuten sukupuuhun syntyy kolme eri ihmistä joita kukaan ei osaa myöhemmin yhdistää. Sama koskee paikkoja: "Puumalassa" → "Puumala", "Kuopiosta" → "Kuopio".

2. ÄLÄ LYHENNÄ. Siivoa täytesanat ("niinku", "tota", "öö") ja korjaa selvät puhekielisyydet luettavaan muotoon, mutta säilytä kaikki sisältö ja tunnelma. Muiston pituus on osa muistoa. Et tee tiivistelmää.

3. VAIN ERISNIMET. Poimi mentions-listaan ainoastaan nimetyt henkilöt ja paikat. Yleisnimet kuten "mummola", "mökki", "koulu", "kirkko" tai "tori" EIVÄT ole mainintoja, vaikka ne olisivat muiston tärkeimpiä paikkoja — ne jäävät muiston tekstiin. Syy: "mummola" ei kerro kenen mummolasta on kyse, ja arkistoon syntyisi kohteita joita kukaan ei myöhemmin tunnista. Jos paikkaa ei voisi osoittaa kartalta nimellä, se ei kuulu listaan.

4. ÄLÄ KOSKAAN KEKSI. Jos ajankohtaa ei mainittu, precision on "unknown" ja vuodet null. Jos et ole varma onko nimi henkilö vai paikka, arvaa parhaasi mukaan mutta laske confidence-arvoa. Keksitty sukulainen on pahempi kuin puuttuva.

5. SÄILYTÄ EPÄVARMUUS. "Joskus 50-luvulla" on precision "decade", start_year 1950, end_year 1959 — älä pakota tarkkaan vuoteen. Kaksinumeroinen vuosikymmen tarkoittaa 1900-lukua, koska puhe koskee vanhoja valokuvia.

6. KOLME KYSYMYSTÄ. Kysy siitä mitä puheesta jäi puuttumaan: mainittu henkilö josta ei kerrottu mitään, paikka josta tiedetään vain nimi, tai aistimuisto. Kysy lämpimästi ja lyhyesti, yksi asia kerrallaan. Puhuttele suoraan ("Millainen ihminen Aino oli?"). Älä kysy asiaa johon puhe jo vastasi.

Kysymysteksteissä saat taivuttaa nimiä luonnollisesti. Vain mentions-listan name-kenttä on perusmuodossa.`

/// Extra instruction for when the user has corrected the names that speech
/// recognition heard.
///
/// The correction step is essential, because speech recognition gets roughly one
/// proper noun in three wrong: in the measured comparison "Sotkamo" was heard as
/// "Skotlanti" and "Eevertti" as the word "edes". A wrong name builds a wrong
/// person into the family tree, and nobody can correct it later.
///
/// Finnish by design — see the note at the top of this file. In English: the
/// user's corrections are authoritative, must not be reverted anywhere, and must
/// also be applied to the memory text *inflected to fit the sentence*. That last
/// part is the whole point: a plain string replacement never matches an inflected
/// form, which is why the model does it instead.
function correctionInstruction(corrections: Correction[]): string {
	const list = corrections.map((c) => `"${c.from}" → "${c.to}"`).join(', ')
	return `

TÄRKEÄÄ — KÄYTTÄJÄN KORJAUKSET: ${list}

Puheentunnistus kuuli nämä nimet väärin ja kertoja on korjannut ne. Korjaukset ovat AUKTORITEETTI: käytä niitä sellaisenaan äläkä palauta vanhaa muotoa missään kohdassa.

Korjaa nimi myös muiston tekstiin, ja TAIVUTA SE OIKEIN asiayhteyteen. Jos teksti sanoo "Skotlannissa" ja korjaus on "Sotkamo", tekstiin tulee "Sotkamossa" — ei "Sotkamo" perusmuodossa keskelle lausetta. Tämä on koko korjauksen tarkoitus: pelkkä merkkijonon vaihto ei osu taivutettuun muotoon.`
}

export type Correction = { from: string; to: string }

export type ExtractionResult = {
	body: string
	mentions: { name: string; kind: 'person' | 'place'; confidence: number }[]
	date: {
		start_year: number | null
		end_year: number | null
		precision: 'day' | 'month' | 'year' | 'decade' | 'unknown'
	}
	questions: string[]
}

/// Defence against formatting deviations.
///
/// `strict: true` is not a guarantee — OpenRouter's documentation says some
/// providers treat strict mode as a hint. Truncated responses are already
/// rejected in `openrouter.ts` based on finish_reason, so what is left here is
/// the case where the JSON is complete but wrapped in something.
function parseStructured(raw: string): ExtractionResult {
	try {
		return JSON.parse(raw)
	} catch {
		// fall through to the repair attempts
	}

	// The most common cause: the model wrapped the JSON in markdown fences.
	const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/)
	if (fenced) {
		try {
			const result = JSON.parse(fenced[1])
			console.warn('[extract] repaired: JSON was inside markdown fences')
			return result
		} catch {
			// keep going
		}
	}

	// The second most common: prose before or after the object.
	const start = raw.indexOf('{')
	const end = raw.lastIndexOf('}')
	if (start !== -1 && end > start) {
		try {
			const result = JSON.parse(raw.slice(start, end + 1))
			console.warn('[extract] repaired: extra text around the object')
			return result
		} catch {
			// keep going
		}
	}

	// Log the beginning so a new deviation can be diagnosed. Log only: the
	// content can echo back the memory the user just told.
	console.error(`[extract] invalid JSON, starts with: ${raw.slice(0, 300)}`)
	throw new Error('Extraction returned invalid JSON')
}

export async function extract(
	env: Env,
	transcript: string,
	corrections: Correction[] = [],
): Promise<ExtractionResult> {
	const system =
		corrections.length > 0 ? SYSTEM_PROMPT + correctionInstruction(corrections) : SYSTEM_PROMPT

	const messages: Message[] = [
		{ role: 'system', content: system },
		{ role: 'user', content: `Jäsennä tämä muisto:\n\n${transcript}` },
	]

	// This is the app's core path: the user has just spoken for a minute and a
	// half, and a provider crashing at random must not lose it. The measured
	// failure rate was ~12 %, so two attempts would still let 1.4 % through. The
	// third attempt switches model, because the fault has repeatedly been in the
	// provider rather than the input — retrying the same model does not help.
	const models = [env.MODEL_EXTRACT, env.MODEL_EXTRACT, env.MODEL_EXTRACT_FALLBACK || env.MODEL_EXTRACT]
	let lastError: unknown

	for (const [index, model] of models.entries()) {
		try {
			const raw = await complete(env, messages, {
				model,
				// Low but not zero: at zero the follow-up questions become formulaic.
				temperature: 0.4,
				schema: EXTRACTION_SCHEMA,
				// Comfortably above the longest memory to be expected.
				maxTokens: 2000,
			})
			const parsed = parseStructured(raw)

			// The schema does not enforce the count, so the cap of three is
			// applied here. Four questions overwhelm an elderly user, two do not
			// carry the story forward.
			parsed.questions = (parsed.questions ?? []).slice(0, 3)
			parsed.mentions = parsed.mentions ?? []
			return parsed
		} catch (err) {
			lastError = err
			// Out of credits or a bad key: retrying fixes nothing, it only
			// triples the wait before the failure.
			if (err instanceof UpstreamError && !err.retryable) {
				console.error(`[extract] not retryable (HTTP ${err.status}) — giving up`)
				break
			}
			if (index < models.length - 1) {
				console.warn(`[extract] attempt ${index + 1} (${model}) failed, continuing`)
			}
		}
	}

	throw lastError
}
