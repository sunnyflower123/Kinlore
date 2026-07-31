/// Muiston jäsennys: rönsyilevästä puheesta rakenteeksi.
///
/// Vastaa iOS-puolen `ExtractionResult`-tyyppiä. Vuosiluvut kulkevat
/// kokonaislukuina eivätkä unix-aikaleimoina, koska kielimallit käsittelevät
/// vuosia luotettavasti ja aikaleimoja eivät lainkaan.

import { complete, type Message } from './openrouter'
import type { Env } from './worker'

export const EXTRACTION_SCHEMA = {
	name: 'muisto',
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

const SYSTEM_PROMPT = `Autat suomalaista perhettä säilyttämään muistoja. Käyttäjä on usein iäkäs ja puhuu rönsyillen, keskeneräisin lausein ja epävarmoin ajankohdin. Se on normaalia, ei virhe.

TEHTÄVÄSI on jäsentää puhe rakenteeksi. Noudata näitä sääntöjä ehdottomasti:

1. NIMET PERUSMUODOSSA. Suomen taivutus tuottaa samasta ihmisestä monta pintamuotoa: "Ainon", "Ainolle" ja "Aino" ovat sama henkilö. Palauta aina perusmuoto, muuten sukupuuhun syntyy kolme eri ihmistä joita kukaan ei osaa myöhemmin yhdistää. Sama koskee paikkoja: "Puumalassa" → "Puumala", "Kuopiosta" → "Kuopio".

2. ÄLÄ LYHENNÄ. Siivoa täytesanat ("niinku", "tota", "öö") ja korjaa selvät puhekielisyydet luettavaan muotoon, mutta säilytä kaikki sisältö ja tunnelma. Muiston pituus on osa muistoa. Et tee tiivistelmää.

3. VAIN ERISNIMET. Poimi mentions-listaan ainoastaan nimetyt henkilöt ja paikat. Yleisnimet kuten "mummola", "mökki", "koulu", "kirkko" tai "tori" EIVÄT ole mainintoja, vaikka ne olisivat muiston tärkeimpiä paikkoja — ne jäävät muiston tekstiin. Syy: "mummola" ei kerro kenen mummolasta on kyse, ja arkistoon syntyisi kohteita joita kukaan ei myöhemmin tunnista. Jos paikkaa ei voisi osoittaa kartalta nimellä, se ei kuulu listaan.

4. ÄLÄ KOSKAAN KEKSI. Jos ajankohtaa ei mainittu, precision on "unknown" ja vuodet null. Jos et ole varma onko nimi henkilö vai paikka, arvaa parhaasi mukaan mutta laske confidence-arvoa. Keksitty sukulainen on pahempi kuin puuttuva.

5. SÄILYTÄ EPÄVARMUUS. "Joskus 50-luvulla" on precision "decade", start_year 1950, end_year 1959 — älä pakota tarkkaan vuoteen. Kaksinumeroinen vuosikymmen tarkoittaa 1900-lukua, koska puhe koskee vanhoja valokuvia.

6. KOLME KYSYMYSTÄ. Kysy siitä mitä puheesta jäi puuttumaan: mainittu henkilö josta ei kerrottu mitään, paikka josta tiedetään vain nimi, tai aistimuisto. Kysy lämpimästi ja lyhyesti, yksi asia kerrallaan. Puhuttele suoraan ("Millainen ihminen Aino oli?"). Älä kysy asiaa johon puhe jo vastasi.

Kysymysteksteissä saat taivuttaa nimiä luonnollisesti. Vain mentions-listan name-kenttä on perusmuodossa.`

/// Lisäohje kun käyttäjä on korjannut puheentunnistuksen kuulemat nimet.
///
/// Korjaus on välttämätön, koska puheentunnistus erehtyy erisnimissä noin
/// joka kolmannessa: mitatussa vertailussa "Sotkamo" kuultiin "Skotlantina" ja
/// "Eevertti" sanana "edes". Väärä nimi rakentaa väärän henkilön sukupuuhun,
/// eikä kukaan osaa myöhemmin korjata sitä.
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

/// Puolustus muotoilupoikkeamia vastaan.
///
/// `strict: true` ei ole takuu — OpenRouterin dokumentaatio sanoo että osa
/// tarjoajista kohtelee tiukkaa tilaa ohjeena. Katkenneet vastaukset hylätään
/// jo `openrouter.ts`:ssä finish_reasonin perusteella, joten tänne jää vain
/// tapaus jossa JSON on kokonainen mutta kääritty johonkin.
function parseStructured(raw: string): ExtractionResult {
	try {
		return JSON.parse(raw)
	} catch {
		// jatketaan korjausyrityksiin
	}

	// Yleisin syy: malli kääri JSONin markdown-aitoihin.
	const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/)
	if (fenced) {
		try {
			const result = JSON.parse(fenced[1])
			console.warn('[extract] korjattu: JSON oli markdown-aidoissa')
			return result
		} catch {
			// jatketaan
		}
	}

	// Toiseksi yleisin: saatesanoja ennen tai jälkeen objektin.
	const start = raw.indexOf('{')
	const end = raw.lastIndexOf('}')
	if (start !== -1 && end > start) {
		try {
			const result = JSON.parse(raw.slice(start, end + 1))
			console.warn('[extract] korjattu: objektin ympärillä oli ylimääräistä tekstiä')
			return result
		} catch {
			// jatketaan
		}
	}

	// Alkupää lokiin jotta uusi poikkeama on diagnosoitavissa. Vain loki:
	// sisältö voi toistaa käyttäjän kertoman muiston.
	console.error(`[extract] kelvoton JSON, alku: ${raw.slice(0, 300)}`)
	throw new Error('Jäsennys palautti kelvottoman JSONin')
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

	// Tämä on sovelluksen ydinpolku: käyttäjä on juuri puhunut puolitoista
	// minuuttia, eikä tarjoajan satunnainen kaatuminen saa hukata sitä.
	// Mitattu virhetaajuus oli ~12 %, joten kaksi yritystä jättäisi yhä 1,4 %
	// läpi. Kolmas yritys vaihtaa mallia, koska vika on toistuvasti ollut
	// tarjoajassa eikä syötteessä — sama malli uudelleen ei auta siihen.
	const models = [env.MODEL_EXTRACT, env.MODEL_EXTRACT, env.MODEL_EXTRACT_FALLBACK || env.MODEL_EXTRACT]
	let lastError: unknown

	for (const [index, model] of models.entries()) {
		try {
			const raw = await complete(env, messages, {
				model,
				// Matala mutta ei nolla: jatkokysymyksistä tulee nollalla kaavamaisia.
				temperature: 0.4,
				schema: EXTRACTION_SCHEMA,
				// Reilusti yli pisimmän odotettavan muiston.
				maxTokens: 2000,
			})
			const parsed = parseStructured(raw)

			// Skeema ei takaa määrää, joten kolmeen rajaus tehdään täällä. Neljä
			// kysymystä ahdistaa iäkästä käyttäjää, kaksi ei vie kertomusta eteenpäin.
			parsed.questions = (parsed.questions ?? []).slice(0, 3)
			parsed.mentions = parsed.mentions ?? []
			return parsed
		} catch (err) {
			lastError = err
			if (index < models.length - 1) {
				console.warn(`[extract] yritys ${index + 1} (${model}) epäonnistui, jatketaan`)
			}
		}
	}

	throw lastError
}
