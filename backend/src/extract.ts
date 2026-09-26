/// Memory extraction: from rambling speech to structure.
///
/// Mirrors the iOS-side `ExtractionResult` type. Years travel as integers rather
/// than unix timestamps, because language models handle years reliably and
/// timestamps not at all.
///
/// NOTE ON LANGUAGE: there are two system prompts and two sets of schema
/// `description` fields, and neither is a translation of the other. They are
/// input to the model rather than documentation, and what they instruct depends
/// on the language being spoken: rule 1 tells a model about Finnish case endings
/// and has no English counterpart, while the filler words, the common nouns and
/// the decade idiom in rules 2, 3 and 5 are the part that was tuned and do not
/// carry across. The Finnish was tuned by measurement and is not to be edited on
/// the way past. Everything else in this file is English.
///
/// Which one is used follows WHO IS SPEAKING, not who is reading the screen —
/// the app sends `lang` with the transcript. See PLAN.md §10.

// `.ts` on the specifier, and it is not a style choice: without it Node
// cannot resolve this import, so nothing in this module could be loaded by
// a check script — measured 11 Sep 2026 as `ERR_MODULE_NOT_FOUND`. That is
// the whole reason `budget.ts` was carved out as a file with no runtime
// imports at all. The extension is the cheaper answer: `tsconfig.json` sets
// `allowImportingTsExtensions` (legal under `noEmit`), esbuild bundles it
// unchanged, and `extract-shaping-check.mjs` can now import the two
// functions below. The same one word would unlock `transcribe.ts`,
// `family.ts` and `worker.ts`, which are the only other modules Node still
// refuses.
import { extractionBudget } from './budget.ts'
import { complete, UpstreamError, type Message } from './openrouter.ts'
import type { Env } from './worker'

export type Lang = 'fi' | 'en'

/// The schema's `description` fields, which are instructions and not comments.
/// One table rather than two schemas, so the shape cannot drift between the
/// languages while the wording differs — the shape is the contract with the
/// iOS side and the wording is the tuning.
const DESCRIPTIONS: Record<Lang, Record<string, string>> = {
	fi: {
		body: 'Muisto siivottuna luettavaan muotoon. Täytesanat pois, sisältö ja pituus ennallaan.',
		mentions:
			'Puheessa mainitut henkilöt ja paikat. VAIN erisnimet — ei yleisnimiä ' +
			'kuten "mummola", "mökki" tai "koulu".',
		name: 'Nimi PERUSMUODOSSA: "Ainon" → "Aino", "Puumalassa" → "Puumala".',
		confidence: '0–1. Alle 1 tarkoittaa että ihmisen pitää vahvistaa.',
		date: 'Ajankohta sellaisena kuin se puheessa esiintyi, ei tarkennettuna.',
		questions: 'Täsmälleen kolme jatkokysymystä jotka kohdistuvat aukkoihin.',
		level:
			'Kuinka paljon kysymys vaatii vastaajalta, 1–5. Arvioi vastauksen ' +
			'MUOTOA, älä aihetta. ' +
			'1 = vastaus on nimi tai yksi sana ("Kuka tässä kuvassa on?"). ' +
			'2 = yksi tieto, paikka tai vuosi ("Missä tämä on otettu?"). ' +
			'3 = muutama lause ihmisestä tai paikasta ("Millainen ihminen Aino oli?"). ' +
			'4 = kertomus jolla on alku ja loppu ("Kerro päivästä jolloin muutitte Ouluun."). ' +
			'5 = pohdinta merkityksestä tai tunteesta ("Mitä toivoisit lastenlastesi tietävän?").',
	},
	en: {
		body: 'The memory tidied into readable prose. Fillers out, content and length untouched.',
		mentions:
			'People and places named in the speech. PROPER NOUNS ONLY — not common ' +
			'nouns like "grandma\'s house", "the cottage" or "school".',
		// English does not decline names, so this is a smaller job than the
		// Finnish one and still not nothing: a possessive or a leading article
		// splits one person into two rows just as an inflected form does.
		name: 'The name as it would be written alone: "Aino\'s" → "Aino", "the Puumala house" → "Puumala".',
		confidence: '0–1. Below 1 means a person has to confirm it.',
		date: 'The date as it appeared in the speech, not sharpened.',
		questions: 'Exactly three follow-up questions aimed at the gaps.',
		level:
			'How much the question asks of the answerer, 1–5. Judge the SHAPE of ' +
			'the answer, not the subject. ' +
			'1 = the answer is a name or one word ("Who is in this photograph?"). ' +
			'2 = one fact, a place or a year ("Where was this taken?"). ' +
			'3 = a few sentences about a person or a place ("What sort of person was Aino?"). ' +
			'4 = a story with a beginning and an end ("Tell me about the day you moved to Oulu."). ' +
			'5 = a reflection on meaning or feeling ("What would you want your grandchildren to know?").',
	},
}

export const extractionSchema = (lang: Lang) => ({
	name: 'memory',
	schema: {
		type: 'object',
		properties: {
			body: { type: 'string', description: DESCRIPTIONS[lang].body },
			mentions: {
				type: 'array',
				description: DESCRIPTIONS[lang].mentions,
				items: {
					type: 'object',
					properties: {
						name: { type: 'string', description: DESCRIPTIONS[lang].name },
						kind: { type: 'string', enum: ['person', 'place'] },
						confidence: { type: 'number', description: DESCRIPTIONS[lang].confidence },
					},
					required: ['name', 'kind', 'confidence'],
					additionalProperties: false,
				},
			},
			date: {
				type: 'object',
				description: DESCRIPTIONS[lang].date,
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
				description: DESCRIPTIONS[lang].questions,
				items: {
					type: 'object',
					properties: {
						text: { type: 'string' },
						level: { type: 'integer', description: DESCRIPTIONS[lang].level },
					},
					required: ['text', 'level'],
					additionalProperties: false,
				},
			},
		},
		required: ['body', 'mentions', 'date', 'questions'],
		additionalProperties: false,
	},
})

/// Finnish by design — see the note at the top of this file. The six rules, in
/// English for the reader: (1) names in base form, or the family tree fills with
/// duplicates; (2) clean up filler words but never shorten, the length is part
/// of the memory; (3) proper nouns only, a common noun like "grandma's house"
/// identifies nobody; (4) never invent, an invented relative is worse than a
/// missing one; (5) preserve uncertainty, a decade stays a decade; (6) exactly
/// three follow-up questions aimed at the gaps, each labelled with how much it
/// asks of the answerer — and after a telling about a death, a war, abuse or
/// grief, aimed at the person, the place and the everyday life around it rather
/// than at the event, with no level 5 among them. The app asks those questions
/// with nobody beside the teller (docs/ARCHITECTURE.md §12).
const SYSTEM_PROMPT_FI = `Autat suomalaista perhettä säilyttämään muistoja. Käyttäjä on usein iäkäs ja puhuu rönsyillen, keskeneräisin lausein ja epävarmoin ajankohdin. Se on normaalia, ei virhe.

TEHTÄVÄSI on jäsentää puhe rakenteeksi. Noudata näitä sääntöjä ehdottomasti:

1. NIMET PERUSMUODOSSA. Suomen taivutus tuottaa samasta ihmisestä monta pintamuotoa: "Ainon", "Ainolle" ja "Aino" ovat sama henkilö. Palauta aina perusmuoto, muuten sukupuuhun syntyy kolme eri ihmistä joita kukaan ei osaa myöhemmin yhdistää. Sama koskee paikkoja: "Puumalassa" → "Puumala", "Kuopiosta" → "Kuopio".

2. ÄLÄ LYHENNÄ. Siivoa täytesanat ("niinku", "tota", "öö") ja korjaa selvät puhekielisyydet luettavaan muotoon, mutta säilytä kaikki sisältö ja tunnelma. Muiston pituus on osa muistoa. Et tee tiivistelmää.

3. VAIN ERISNIMET. Poimi mentions-listaan ainoastaan nimetyt henkilöt ja paikat. Yleisnimet kuten "mummola", "mökki", "koulu", "kirkko" tai "tori" EIVÄT ole mainintoja, vaikka ne olisivat muiston tärkeimpiä paikkoja — ne jäävät muiston tekstiin. Syy: "mummola" ei kerro kenen mummolasta on kyse, ja arkistoon syntyisi kohteita joita kukaan ei myöhemmin tunnista. Jos paikkaa ei voisi osoittaa kartalta nimellä, se ei kuulu listaan.

4. ÄLÄ KOSKAAN KEKSI. Jos ajankohtaa ei mainittu, precision on "unknown" ja vuodet null. Jos et ole varma onko nimi henkilö vai paikka, arvaa parhaasi mukaan mutta laske confidence-arvoa. Keksitty sukulainen on pahempi kuin puuttuva.

5. SÄILYTÄ EPÄVARMUUS. "Joskus 50-luvulla" on precision "decade", start_year 1950, end_year 1959 — älä pakota tarkkaan vuoteen. Kaksinumeroinen vuosikymmen tarkoittaa 1900-lukua, koska puhe koskee vanhoja valokuvia.

6. KOLME KYSYMYSTÄ. Kysy siitä mitä puheesta jäi puuttumaan: mainittu henkilö josta ei kerrottu mitään, paikka josta tiedetään vain nimi, tai aistimuisto. Kysy lämpimästi ja lyhyesti, yksi asia kerrallaan. Puhuttele suoraan ("Millainen ihminen Aino oli?"). Älä kysy asiaa johon puhe jo vastasi. Merkitse jokaiseen kysymykseen level-arvo sen mukaan kuinka pitkän vastauksen se vaatii.

Jos muisto kertoo kuolemasta, sodasta, kaltoinkohtelusta tai surusta, kysymykset eivät kaiva itse tapahtumaa: eivät kuolemaa, rintamaa, pommituksia tai väkivaltaa, eivätkä mitään sen päivää ensimmäisestä viimeiseen, lähtö ja paluu mukaan lukien. Älä kysy siitä aistimuistoa äläkä kysy, miltä se tuntui. Kysy sen sijaan ihmisestä, paikasta tai arjesta tapahtuman ympärillä: millainen hän oli, mitä hän teki mielellään, keitä muita siellä oli, miten arki jatkui sen jälkeen. Syy: kysymyksen esittää sovellus eikä ihminen, eikä kukaan ole vieressä, jos muisto satuttaa. Tällaisesta muistosta ei kysytä tason 5 kysymystä. Kysymyksiä on silti kolme.

Kysymysteksteissä saat taivuttaa nimiä luonnollisesti. Vain mentions-listan name-kenttä on perusmuodossa.`

/// The same six rules for a language that does not inflect. Rule 1 is not the
/// Finnish rule translated — English splits a person into two rows through
/// possessives and articles rather than through case endings, so it asks for
/// much less and still has to ask. Rules 2, 3 and 5 keep their structure and
/// lose their Finnish examples entirely: "niinku" is not "like", it is the
/// filler a Finnish speaker reaches for, and "mummola" has no English word at
/// all. The examples are the tuning; they had to be chosen again. Rule 6's
/// paragraph on painful memories is the exception: it says the same thing in
/// both, because nothing in it depends on the language.
const SYSTEM_PROMPT_EN = `You are helping a family keep its memories. The person speaking is often elderly and rambles, leaves sentences unfinished and is unsure of dates. That is normal, not an error.

YOUR TASK is to turn speech into structure. Follow these rules absolutely:

1. NAMES AS THEY STAND ALONE. Return each name the way it would be written by itself: "Aino's" → "Aino", "the Puumala house" → "Puumala", "Grandad Toivo" → "Toivo" when Toivo is the name. Otherwise the family tree fills with two rows for one person and nobody can join them later.

2. DO NOT SHORTEN. Clean out fillers ("um", "uh", "like", "you know", "I mean") and tidy obvious spoken slips into readable prose, but keep all the content and all the feeling. The length of a memory is part of the memory. You are not writing a summary.

3. PROPER NOUNS ONLY. Put only named people and places in the mentions list. Common nouns like "grandma's house", "the cottage", "school", "church" or "the market" are NOT mentions, even when they are the most important place in the memory — they stay in the memory's text. The reason: "the cottage" does not say whose cottage, and the archive would fill with subjects nobody can identify later. If you could not point at the place on a map by that name, it does not belong in the list.

4. NEVER INVENT. If no date was mentioned, precision is "unknown" and the years are null. If you are unsure whether a name is a person or a place, make your best guess but lower the confidence. An invented relative is worse than a missing one.

5. KEEP THE UNCERTAINTY. "Sometime in the fifties" is precision "decade", start_year 1950, end_year 1959 — do not force a single year. A bare two-digit decade means the 1900s, because the speech is about old photographs.

6. THREE QUESTIONS. Ask about what the speech left out: a person who was named but not described, a place known only by its name, or a memory of a smell or a sound. Ask warmly and briefly, one thing at a time. Address the speaker directly ("What sort of person was Aino?"). Do not ask what the speech has already answered. Give every question a level according to how long an answer it asks for.

If the memory is about a death, a war, abuse or grief, the questions do not dig into the event itself: not the death, the front, the bombing or the violence, and not any day of it from the first to the last, the leaving and the coming home included. Do not ask for a smell or a sound of it, and do not ask how it felt. Ask about the person, the place or the everyday life around it instead: what they were like, what they loved doing, who else was there, how everyday life went on afterwards. The reason: the app is asking, not a person, and nobody is there if the memory hurts. A memory like this gets no level 5 question. It still gets three questions.`

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
function correctionInstruction(corrections: Correction[], lang: Lang): string {
	const list = corrections.map((c) => `"${c.from}" → "${c.to}"`).join(', ')
	if (lang === 'en') {
		// Shorter than the Finnish on purpose. That one exists mostly to make the
		// model inflect a corrected name into the sentence, which is the half
		// English does not need. What survives is the half that matters: the
		// correction is authoritative and has to reach the memory text too.
		return `

IMPORTANT — THE TELLER'S CORRECTIONS: ${list}

Speech recognition heard these names wrong and the teller has corrected them. The corrections are AUTHORITATIVE: use them as given and do not restore the old form anywhere.

Correct the name in the memory's text as well, keeping whatever grammar the sentence needs — a possessive stays a possessive ("Sotkamo's"), a plural stays a plural. Replacing the string alone is not enough.`
	}
	return `

TÄRKEÄÄ — KÄYTTÄJÄN KORJAUKSET: ${list}

Puheentunnistus kuuli nämä nimet väärin ja kertoja on korjannut ne. Korjaukset ovat AUKTORITEETTI: käytä niitä sellaisenaan äläkä palauta vanhaa muotoa missään kohdassa.

Korjaa nimi myös muiston tekstiin, ja TAIVUTA SE OIKEIN asiayhteyteen. Jos teksti sanoo "Skotlannissa" ja korjaus on "Sotkamo", tekstiin tulee "Sotkamossa" — ei "Sotkamo" perusmuodossa keskelle lausetta. Tämä on koko korjauksen tarkoitus: pelkkä merkkijonon vaihto ei osu taivutettuun muotoon.`
}

/// Extra instruction for aiming the questions where the teller actually is.
///
/// Finnish by design — see the note at the top of this file. In English: one
/// question just below the given level, one at it and one just above. The spread
/// is deliberate. A single level makes a wrong estimate cost the whole round,
/// and letting the person choose between three is the cheapest calibration
/// there is — see docs/ARCHITECTURE.md §12.
///
/// Without this the questions come out at level 3–4 almost every time, because a
/// question aimed at a gap is naturally a "tell me about" question. That is a
/// wall for somebody who has not answered anything yet.
///
/// After a painful telling (rule 6) the question from level 5 comes from level
/// 3. Level 5 asks what something meant or how it felt, and after a death or a
/// war that is the loss itself; level 3 is a few sentences about the person or
/// the place, which is what the rule asks for. Rule 6 already forbids level 5,
/// and the line is repeated here because this instruction is the one that asks
/// for it.
function levelInstruction(level: number, lang: Lang): string {
	const below = Math.max(1, level - 1)
	const above = Math.min(5, level + 1)
	if (lang === 'en') {
		return `

QUESTION DEMAND. The teller is at level ${level} right now. Give three questions from different levels: one from ${below}, one from ${level} and one from ${above}.

1 = the answer is a name or one word ("Who is in this photograph?")
2 = one fact, a place or a year ("Where was this taken?")
3 = a few sentences about a person or a place ("What sort of person was Aino?")
4 = a story with a beginning and an end ("Tell me about the day you moved to Oulu.")
5 = a reflection on meaning or feeling ("What would you want your grandchildren to know?")

If the teller is at level 1 or 2, do not ask for a story or a reflection. An easy question an elderly person can answer is worth more than a deep one they leave alone.

If the memory is the painful kind rule 6 describes, the question from level 5 comes from level 3 instead.`
	}
	return `

KYSYMYSTEN VAATIVUUS. Kertoja on tällä hetkellä tasolla ${level}. Anna kolme kysymystä eri tasoilta: yksi tasolta ${below}, yksi tasolta ${level} ja yksi tasolta ${above}. Taso kuvaa vastauksen MUOTOA, ei aihetta:

1 = vastaus on nimi tai yksi sana ("Kuka tässä kuvassa on?")
2 = yksi tieto, paikka tai vuosi ("Missä tämä on otettu?")
3 = muutama lause ihmisestä tai paikasta ("Millainen ihminen Aino oli?")
4 = kertomus jolla on alku ja loppu ("Kerro päivästä jolloin muutitte Ouluun.")
5 = pohdinta merkityksestä tai tunteesta ("Mitä toivoisit lastenlastesi tietävän?")

Jos kertoja on tasolla 1 tai 2, älä pyydä kertomusta tai pohdintaa. Helppo kysymys johon iäkäs ihminen osaa vastata heti on arvokkaampi kuin syvällinen kysymys johon hän ei uskalla tarttua.

Jos muisto on säännön 6 tarkoittama kipeä muisto, tason 5 kysymyksen tilalle tulee kysymys tasolta 3.`
}

export type Correction = { from: string; to: string }

/// A question and how much it asks of the answerer, 1–5. Null when the model
/// did not label it; the client then reads the level off the wording, so an
/// unlabelled question costs nothing.
export type ExtractedQuestion = { text: string; level: number | null }

export type ExtractionResult = {
	body: string
	mentions: { name: string; kind: 'person' | 'place'; confidence: number }[]
	date: {
		start_year: number | null
		end_year: number | null
		precision: 'day' | 'month' | 'year' | 'decade' | 'unknown'
	}
	questions: ExtractedQuestion[]
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

	// The shape, never the text. `raw` is the model's account of the memory that
	// was just told, and Workers Logs is a store like D1 and R2 — one no export
	// carries and no "Tyhjennä tämä laite" reaches (PLAN.md §10). A new
	// deviation announces itself in the structure, and this is the structure:
	// what the reply looks like, how long it is, and where the braces the
	// repairs above went looking for actually were.
	const shape =
		raw.length === 0
			? 'empty'
			: /^\s*[{[]/.test(raw)
				? 'json-ish'
				: /^\s*```/.test(raw)
					? 'fenced'
					: 'prose'
	console.error(
		`[extract] invalid JSON: ${shape}, ${raw.length} chars, ` +
			`braces at ${raw.indexOf('{')}/${raw.lastIndexOf('}')}`,
	)
	throw new Error('Extraction returned invalid JSON')
}

/// The names the model heard, with the ones that are not names taken out.
///
/// The schema asks for a string and does not ask for a non-empty one, and the
/// client turns every entry here into a `subject` row: `findOrCreateSubject`
/// is handed the name whatever it is, so `{"name": "", "kind": "person"}`
/// becomes a person the family is asked to confirm, drawn as *"Henkilö"*
/// because `displayTitle` falls back to the kind when the title is empty.
/// Rule 4 is that a wrong person is worse than a missing one; a person with
/// no name at all is the same failure with nothing to recognise.
///
/// Trimmed in the same pass, and that is the half with teeth. `Aino ` and
/// `Aino` are two different titles to `findOrCreateSubject`, which compares
/// them to decide whether a name is somebody the archive already has — so a
/// stray space is the duplicate card the whole base-form requirement exists
/// to prevent, arriving by a different road (found 11 Sep 2026).
export function normaliseMentions(raw: unknown): ExtractionResult['mentions'] {
	if (!Array.isArray(raw)) return []
	return raw.flatMap((item): ExtractionResult['mentions'] => {
		if (typeof item !== 'object' || item === null) return []
		const { name, kind, confidence } = item as {
			name?: unknown
			kind?: unknown
			confidence?: unknown
		}
		if (typeof name !== 'string') return []
		const trimmed = name.trim()
		// An unknown kind is dropped rather than guessed at, the same rule the
		// client already applies to it: a place filed as a person joins the
		// family tree.
		if (!trimmed || (kind !== 'person' && kind !== 'place')) return []
		return [{ name: trimmed, kind, confidence: typeof confidence === 'number' ? confidence : 0 }]
	})
}

/// Questions as the model actually returned them.
///
/// Two deviations are tolerated rather than fatal, because a question is worth
/// more than its label: a plain string (a provider that ignored the object
/// schema) and a `level` that is missing or out of range. Both become
/// `level: null`, and the client falls back to reading the level off the
/// wording.
export function normaliseQuestions(raw: unknown): ExtractedQuestion[] {
	if (!Array.isArray(raw)) return []
	return raw.flatMap((item): ExtractedQuestion[] => {
		if (typeof item === 'string') {
			return item.trim() ? [{ text: item, level: null }] : []
		}
		if (typeof item !== 'object' || item === null) return []
		const { text, level } = item as { text?: unknown; level?: unknown }
		if (typeof text !== 'string' || !text.trim()) return []
		const rounded = Math.round(Number(level))
		return [{ text, level: rounded >= 1 && rounded <= 5 ? rounded : null }]
	})
}

export async function extract(
	env: Env,
	transcript: string,
	corrections: Correction[] = [],
	/// Where the teller is on the question ladder, 1–5. Omitted for a caller
	/// that does not track it — the questions then come out wherever the gaps
	/// happen to lead.
	level?: number,
	/// The language being SPOKEN, which is not necessarily the language the app
	/// is being read in. Defaults to Finnish so that a client which has not been
	/// updated keeps the behaviour it was written against.
	lang: Lang = 'fi',
	/// What the family's archive already holds, and the photograph the telling
	/// is about. Empty for a caller that sends none — the questions then aim at
	/// the speech alone, which is what they did before 19 Sep 2026.
	context: ExtractContext = {},
): Promise<ExtractionResult> {
	let system = lang === 'en' ? SYSTEM_PROMPT_EN : SYSTEM_PROMPT_FI
	if (level) system += levelInstruction(level, lang)
	if (corrections.length > 0) system += correctionInstruction(corrections, lang)
	system += contextInstruction(context, lang)

	const ask =
		contextBlock(context, lang) +
		(lang === 'en' ? `Structure this memory:\n\n${transcript}` : `Jäsennä tämä muisto:\n\n${transcript}`)

	// The photograph rides on the same call rather than a second one: the
	// extraction model is already multimodal (`MODEL_EXTRACT` is a Gemini
	// Flash), so what the picture costs is input tokens on a call that was
	// going to happen anyway. Measured 19 Sep 2026 on one Puumala transcript:
	// a flat +1140 prompt tokens whatever the resolution — 512, 768 and 1024
	// px all tokenised identically — and $0.0045 to $0.0061 for the round,
	// about a sixth of a cent. Sent at 1024 for that reason: the small one
	// was not cheaper, and it was the one that answered with the cottage
	// rather than the rowing boat tied to the jetty.
	const messages: Message[] = [
		{ role: 'system', content: system },
		{
			role: 'user',
			content: context.image
				? [
						{ type: 'text', text: ask },
						{ type: 'image_url', image_url: { url: `data:image/jpeg;base64,${context.image}` } },
					]
				: ask,
		},
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
				schema: extractionSchema(lang),
				// Sized to the telling rather than fixed. The flat 2000 that
				// stood here truncated a long memory intermittently, which
				// costs a retry and sometimes the weaker fallback model — see
				// `extractionBudget`.
				maxTokens: extractionBudget(transcript, lang, model),
			})
			const parsed = parseStructured(raw)

			// The schema does not enforce the count, so the cap of three is
			// applied here. Four questions overwhelm an elderly user, two do not
			// carry the story forward.
			parsed.questions = normaliseQuestions(parsed.questions).slice(0, 3)
			parsed.mentions = normaliseMentions(parsed.mentions)
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

// --------------------------------------------------------------- context
//
// What the family's archive already holds, sent alongside the transcript so
// that a follow-up question can aim at a hole rather than at the speech.
//
// Without it the questions are as personal as ninety seconds of speech allows,
// which is not very: rule 6 above asks for a gap "in the speech", so the model
// converges on the three shapes that rule lists and asks them again on the
// fourth telling as readily as on the first. Measured 19 Sep 2026 on one
// Puumala transcript, the text-only reply was "Millainen se Puumalan mökki ja
// sen piha oli?" — a question no archive was needed to write.
//
// THE DATA GOES IN THE USER MESSAGE, NOT THE SYSTEM PROMPT. The instructions
// below are stable and belong in the system prompt; `asked` is free text the
// family and an earlier model wrote, and free text appended to a system prompt
// is somewhere for an instruction to hide. Keeping the two apart costs nothing
// and is the whole defence.

/// What an archive can be missing about a subject. A closed vocabulary, not
/// free text: these words are turned into a phrase in the prompt, so the client
/// cannot write the prompt by writing a gap.
const GAPS = ['date', 'place', 'birth_year', 'relation', 'description'] as const
export type Gap = (typeof GAPS)[number]

const GAP_WORDS: Record<Lang, Record<Gap, string>> = {
	fi: {
		date: 'ajankohta',
		place: 'paikka',
		birth_year: 'syntymävuosi',
		relation: 'sukulaisuus muihin',
		description: 'millainen hän oli',
	},
	en: {
		date: 'the date',
		place: 'the place',
		birth_year: 'a year of birth',
		relation: 'how they are related to the others',
		description: 'what they were like',
	},
}

export type ExtractContext = {
	/// The photo, person, place or event the telling was filed under. Absent in
	/// free dictation, where there is no subject until after extraction.
	subject?: {
		kind: 'photo' | 'person' | 'place' | 'event'
		title?: string
		/// Already rendered by the client — "1950-luku", "kesäkuu 1957". The
		/// client owns `DateHint.displayText` and this is not worth a second
		/// implementation.
		date?: string
		place?: string
		memories?: number
	}
	/// People and places the archive already links to this subject, with what it
	/// still does not know about each. Names, never memory text: what the
	/// archive HOLDS stays on the phone, only the shape of the hole is sent.
	known?: { name: string; kind: 'person' | 'place'; memories?: number; missing?: Gap[] }[]
	/// Questions already open on this subject. Sent so the model can aim
	/// elsewhere rather than be filtered down to fewer than three afterwards.
	asked?: string[]
	/// The photograph itself, base64 JPEG, when the telling is about one.
	image?: string
}

/// Keeps only what the shape allows, and only as much of it as is useful.
///
/// Every string is capped and every list is short. Not for the token bill —
/// the whole block is under 200 tokens — but because this is client-supplied
/// text on its way into a model call, and an unbounded field is an unbounded
/// call. Anything unrecognised is dropped rather than repaired.
export function normaliseContext(raw: unknown): ExtractContext {
	if (typeof raw !== 'object' || raw === null) return {}
	const { subject, known, asked } = raw as Record<string, unknown>
	const out: ExtractContext = {}

	const text = (value: unknown, max: number): string | undefined => {
		if (typeof value !== 'string') return undefined
		const trimmed = value.trim().slice(0, max)
		return trimmed || undefined
	}

	if (typeof subject === 'object' && subject !== null) {
		const s = subject as Record<string, unknown>
		if (s.kind === 'photo' || s.kind === 'person' || s.kind === 'place' || s.kind === 'event') {
			out.subject = {
				kind: s.kind,
				title: text(s.title, 120),
				date: text(s.date, 40),
				place: text(s.place, 80),
				memories: typeof s.memories === 'number' && s.memories >= 0 ? Math.round(s.memories) : undefined,
			}
		}
	}

	if (Array.isArray(known)) {
		out.known = known
			.flatMap((item): NonNullable<ExtractContext['known']> => {
				if (typeof item !== 'object' || item === null) return []
				const k = item as Record<string, unknown>
				const name = text(k.name, 60)
				if (!name || (k.kind !== 'person' && k.kind !== 'place')) return []
				const missing = Array.isArray(k.missing)
					? (k.missing.filter((g): g is Gap => GAPS.includes(g as Gap)).slice(0, 6) as Gap[])
					: []
				return [
					{
						name,
						kind: k.kind,
						memories: typeof k.memories === 'number' && k.memories >= 0 ? Math.round(k.memories) : undefined,
						missing,
					},
				]
			})
			.slice(0, 8)
	}

	if (Array.isArray(asked)) {
		out.asked = asked.flatMap((q) => text(q, 200) ?? []).slice(0, 12)
	}

	return out
}

/// True when there is anything in the context worth a word in the prompt.
/// An empty object must not add an instruction that refers to nothing — a rule
/// about a list that is not there is how a model starts inventing the list.
function hasContext(context: ExtractContext): boolean {
	return Boolean(context.subject || context.known?.length || context.asked?.length)
}

/// The instruction, which is stable, and therefore the system prompt's half.
///
/// Finnish by design — see the note at the top of this file. In English below,
/// and it is not a translation for the same reason nothing else here is.
function contextInstruction(context: ExtractContext, lang: Lang): string {
	let out = ''
	if (hasContext(context)) {
		out +=
			lang === 'en'
				? `

7. THE ARCHIVE. The user message carries what the family's archive already holds, under ARCHIVE. It is not part of the speech — the teller did not just say it, so never put it in the memory's text and never thank them for it.

Use it to aim. At least one of the three questions must go at something listed as not known. A question the archive can already answer is a wasted turn, and this audience does not get many.

Anything listed as already asked is closed: do not ask it again, and do not ask the same thing in other words.`
				: `

7. ARKISTO. Käyttäjän viestissä on ARKISTO-osio, jossa on se mitä perheen arkistossa jo on. Se EI ole osa puhetta — kertoja ei juuri sanonut sitä, joten älä koskaan kirjoita sitä muiston tekstiin äläkä kiitä siitä.

Käytä sitä kohdistamiseen. Vähintään yhden kolmesta kysymyksestä on osuttava johonkin, joka on merkitty tuntemattomaksi. Kysymys johon arkisto jo vastaa on hukattu vuoro, eikä tämä kertoja saa niitä montaa.

Jo kysytty on kysytty: älä kysy samaa uudestaan äläkä samaa asiaa toisin sanoin.`
	}

	if (context.image) {
		out +=
			lang === 'en'
				? `

8. THE PHOTOGRAPH. The user message carries the photograph this memory is about. Look at it.

At least one question must be about something VISIBLE in it that the speech did not mention — an object, a piece of clothing, a building, the landscape, an animal, what people are doing. That is the question only this photograph could have produced, and it is the reason the picture was sent.

Describe, never identify. "the woman on the left", "that striped dress" — do not put a name to a face unless the speech named them, and never say who somebody is. You cannot see who they are and neither can the app; a guess in the shape of a fact is the one thing this archive cannot carry.

Do not ask about age, health, money or mood, and do not remark on how anybody looks. The person answering is often in the photograph.`
				: `

8. VALOKUVA. Käyttäjän viestissä on se valokuva, jota muisto koskee. Katso sitä.

Vähintään yhden kysymyksen on koskettava jotakin, mikä kuvassa NÄKYY ja mistä puhe ei kertonut: esinettä, vaatetta, rakennusta, maisemaa, eläintä, sitä mitä ihmiset tekevät. Se on se kysymys, jonka vain tämä valokuva on voinut synnyttää, ja sitä varten kuva lähetettiin.

Kuvaile, älä tunnista. "Nainen vasemmalla", "se raidallinen mekko" — älä liitä nimeä kasvoihin, ellei puhe ole nimennyt häntä, äläkä koskaan sano kuka joku on. Et näe sitä, eikä sovelluskaan näe; arvaus faktan muodossa on juuri se, mitä tämä arkisto ei voi kantaa.

Älä kysy iästä, terveydestä, varallisuudesta tai mielialasta äläkä huomauta kenenkään ulkonäöstä. Vastaaja on usein itse kuvassa.`
	}

	return out
}

/// The data, which is the user message's half.
///
/// Returns an empty string when there is nothing to say, so the caller can
/// concatenate without a branch.
export function contextBlock(context: ExtractContext, lang: Lang): string {
	if (!hasContext(context)) return ''
	const fi = lang === 'fi'
	const lines: string[] = []

	if (context.subject) {
		const s = context.subject
		const kindWord = fi
			? { photo: 'valokuva', person: 'henkilö', place: 'paikka', event: 'hetki' }[s.kind]
			: { photo: 'a photograph', person: 'a person', place: 'a place', event: 'a moment' }[s.kind]
		const parts = [s.title ? `${kindWord} "${s.title}"` : kindWord]
		if (s.date) parts.push(fi ? `ajankohta ${s.date}` : `dated ${s.date}`)
		if (s.place) parts.push(fi ? `paikka ${s.place}` : `at ${s.place}`)
		if (typeof s.memories === 'number') {
			parts.push(fi ? `${s.memories} muistoa ennestään` : `${s.memories} memories already`)
		}
		lines.push((fi ? 'Kohde: ' : 'Subject: ') + parts.join(', '))
	}

	for (const k of context.known ?? []) {
		const kindWord = fi
			? k.kind === 'person'
				? 'henkilö'
				: 'paikka'
			: k.kind === 'person'
				? 'person'
				: 'place'
		const count =
			typeof k.memories === 'number' ? (fi ? `, ${k.memories} muistoa` : `, ${k.memories} memories`) : ''
		const missing = (k.missing ?? []).map((g) => GAP_WORDS[lang][g])
		const tail = missing.length
			? fi
				? ` — ei tiedossa: ${missing.join(', ')}`
				: ` — not known: ${missing.join(', ')}`
			: fi
				? ' — ei puuttuvia tietoja'
				: ' — nothing missing'
		lines.push(`${k.name} (${kindWord}${count})${tail}`)
	}

	if (context.asked?.length) {
		lines.push(fi ? 'Jo kysytty:' : 'Already asked:')
		for (const q of context.asked) lines.push(`- ${q}`)
	}

	const heading = fi
		? 'ARKISTO (ei puheesta — perheen arkistosta):'
		: 'ARCHIVE (not from the speech — from the family archive):'
	return `${heading}\n${lines.join('\n')}\n\n`
}
