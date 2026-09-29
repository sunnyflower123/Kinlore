/// The story on a card: what was told about it, ordered into one text
/// (docs/ARCHITECTURE.md §27).
///
/// The phone opens the card's sealed tellings and sends the words, the way
/// `/extract` is sent a transcript; nothing here is stored, and the story
/// that goes back is sealed by the phone before it travels (lever 3). The
/// prompt is the one `scripts/story-bench.mjs` measured on the `-seed story`
/// cards on 26 Sep 2026, moved here word for word. Its Finnish half was
/// tuned by measurement and is not edited on the way past (CLAUDE.md,
/// Language); which half runs follows the `lang` the composing phone sends,
/// its display language (ARCHITECTURE §27, rule 10). What the model may do is
/// the whole of the prompt: order, and
/// nothing else — no introduction, no judgement, a gap left a gap, a
/// contradiction shown by name, an unconfirmed name said as its teller's
/// (rule 4), and the tellers' own words at their own length (rule 3's
/// reading of a story: the log is the product, the story is a reading of it).
///
/// Imports carry their `.ts` on purpose, like `extract.ts`'s: Node can then
/// load this file as it is, which is how `story-shaping-check.mjs` reads the
/// prompt the Worker would send without a Worker, a key or a model.

import { outputCeiling } from './budget.ts'
import { complete, UpstreamError, type Message } from './openrouter.ts'
import type { Lang } from './extract.ts'
import type { Env } from './worker.ts'

// ------------------------------------------------------------------ prompts

const SYSTEM_PROMPT_FI = `Kokoat suomalaisen perheen muistiarkistossa yhden kortin tarinan. Kortti on valokuva, henkilö, paikka tai hetki, ja siitä on kerrottu yksi tai useampi muisto, kukin omalla kertojallaan ja päivämäärällään. Kertojat ovat usein iäkkäitä ja puhuvat rönsyillen ja epävarmoin ajankohdin. Se on normaalia, ei virhe.

TEHTÄVÄSI on JÄRJESTÄÄ kerrottu yhdeksi luettavaksi tekstiksi. Et kirjoita mitään, mitä kukaan ei sanonut. Noudata näitä sääntöjä ehdottomasti:

1. VAIN JÄRJESTÄT. Ei johdantoa, ei loppukaneettia, ei arvioita ("kaunis muisto", "lämmin tunnelma"), ei tunnesanoja, joita kukaan ei sanonut, ei tiivistäviä lauseita. Tarina alkaa siitä, mitä joku kertoi, ja loppuu siihen, mitä joku kertoi.

2. AUKOT JÄÄVÄT AUKOIKSI. Älä keksi siirtymiä, syitä, ajankohtia, suhteita tai paikkoja. Jos kertoja sanoi "joskus 50-luvulla", tarinassa lukee "joskus 50-luvulla". Jos kukaan ei sanonut, kuka kuvassa on, tarina ei tiedä sitä myöskään. Keksitty sukulainen on pahempi kuin puuttuva. Älä myöskään lisää syy- tai seuraussanoja (sillä, koska, siksi, joten), joita kertoja ei sanonut: kaksi peräkkäistä lausetta jäävät peräkkäisiksi.

3. VAHVISTAMATON NIMI EI OLE TOSIASIA. Kortilla luetellaan nimet, jotka perhe on vahvistanut; niitä saa käyttää sellaisenaan. Jokainen muu nimi, joka kerronnoissa esiintyy, sanotaan aina kertojan kautta ("Pekan mukaan laiturin teki Eevertti"), ei koskaan väitteenä.

4. RISTIRIITA NÄYTETÄÄN, EI RATKAISTA. Kun kertojat muistavat eri tavalla, molemmat sanotaan nimellä ("Mummo muistaa, että se oli 50-luvulla; Aino muistaa kesän 1961"). Älä valitse voittajaa äläkä tasoita eroa.

5. KERTOJAN SANAT SÄILYVÄT. Käytä kertojien omia sanoja ja ilmauksia. Saat vaihtaa lauseiden järjestystä, yhdistää samaa asiaa koskevat kohdat ja poistaa toiston, mutta et saa lyhentää sisältöä. Muiston pituus on osa muistoa; et tee tiivistelmää. Puhekielen muoto säilyy ("ne oli hyviä aikoja" ei muutu muotoon "ne olivat"); kun minä-muoto on vaihdettava, käytä mieluummin passiivia ("siellä me aina istuttiin" → "siellä aina istuttiin") kuin kirjakieltä.

6. KERTOJA NIMETÄÄN. Kirjoita kolmannessa persoonassa ja sano, kuka kertoi ("Mummo kertoo, että…"). Kun kertoja puhuu itsestään, nimi tulee minän tilalle ("minä olen se pienempi tyttö" → "Aino on se pienempi tyttö").

7. MUOTO. Pelkkää proosaa kappaleittain, tyhjä rivi kappaleiden välissä. Ei otsikoita, ei listoja, ei lainausmerkkejä kokonaisten lauseiden ympärillä. Pituus seuraa kerrotusta: yksi lyhyt muisto on yhden kappaleen tarina.`

const SYSTEM_PROMPT_EN = `You are assembling the story of one card in a family's memory archive. The card is a photograph, a person, a place or a moment, and one or more memories have been told about it, each with its own teller and date. The tellers are often elderly, ramble, and are unsure of dates. That is normal, not an error.

YOUR TASK is to ORDER what was told into one readable text. You write nothing that nobody said. Follow these rules absolutely:

1. YOU ONLY ORDER. No introduction, no closing line, no judgements ("a lovely memory", "a warm scene"), no feeling words nobody used, no summarising sentences. The story starts with something somebody told and ends with something somebody told.

2. GAPS STAY GAPS. Do not invent transitions, causes, dates, relationships or places. If the teller said "sometime in the fifties", the story says "sometime in the fifties". If nobody said who is in the photograph, the story does not know either. An invented relative is worse than a missing one. Do not add causal words (because, so, therefore) the teller did not use either: two sentences side by side stay side by side.

3. AN UNCONFIRMED NAME IS NOT A FACT. The card lists the names the family has confirmed; those may be used as they are. Every other name that appears in a telling is always said through its teller ("According to Peter, Ernest built the jetty"), never as a statement.

4. A CONTRADICTION IS SHOWN, NOT SETTLED. When tellers remember differently, both are given by name ("Grandma remembers it as the fifties; Anna remembers the summer of 1961"). Do not pick a winner and do not smooth the difference over.

5. THE TELLERS' WORDS STAY. Use the tellers' own words and phrases. You may reorder sentences, bring together what is about the same thing and drop repetition, but you may not shorten the content. The length of a memory is part of the memory; you are not writing a summary. The tellers' register stays too: a spoken turn of phrase is not tidied into written English.

6. THE TELLER IS NAMED. Write in the third person and say who told it ("Grandma says that…"). When a teller speaks of themselves, their name replaces the "I" ("I am the smaller girl" → "Anna is the smaller girl").

7. FORM. Plain prose in paragraphs, a blank line between paragraphs. No headings, no lists, no quotation marks around whole sentences. The length follows what was told: one short memory is a one-paragraph story.`

/// The one thing the bench did not measure. A story somebody in the family
/// has corrected by hand is theirs, and the model never writes over it
/// (§27): what is told after the edit is composed on its own, as a
/// continuation the person is asked to add or leave out. The rule is stated
/// after the seven above rather than inside them, so that the measured
/// prompt stays the measured prompt. Unmeasured, and said so in §27.
const ADDITION_FI = `

TÄYDENNYS. Kortilla on jo tarina, jonka joku perheestä on tarkistanut käsin. Se on alla kohdassa TARINA TÄHÄN ASTI, eikä sitä muuteta eikä toisteta. Kirjoita vain uusista kerronnoista koottu jatko, joka luetaan tarinan perään, samoilla säännöillä.`

const ADDITION_EN = `

ADDITION. The card already has a story that somebody in the family has checked by hand. It is below under STORY SO FAR, and it is neither changed nor repeated. Write only the continuation composed from the new memories, to be read after the story, by the same rules.`

export const STORY_SCHEMA = {
	name: 'story',
	schema: {
		type: 'object',
		properties: { story: { type: 'string' } },
		required: ['story'],
		additionalProperties: false,
	},
}

// -------------------------------------------------------------------- input

/// What the phone sends: the card, the names on it the family has confirmed
/// — and only those: an unconfirmed name never leaves the phone (rule 4,
/// `StoryRequest`), so the prompt is never handed a name it could state as
/// fact, and says any other name it meets in a telling through the teller —
/// and the tellings oldest first, each with who told it, when, and whether
/// it was spoken or typed, plus the story so far when the call asks for an
/// addition. Shaped here rather than trusted: a card that cannot be read as
/// one is a 400, and one past the caps is a 413.
export type StoryCard = {
	lang: Lang
	kind: string
	title: string | null
	date: string | null
	mentions: { name: string; kind: string }[]
	memories: { teller: string; told: string; source: string; text: string }[]
	soFar: string | null
}

/// Forty tellings of eight thousand characters each is far past any card
/// that exists; a long spoken telling is a thousand and a half. The total is
/// what bounds the request, and the story so far is bounded on its own
/// because it is the model's or a person's text, which grows with the card.
export const MAX_STORY_MEMORIES = 40
export const MAX_MEMORY_CHARACTERS = 8000
export const MAX_STORY_CHARACTERS = 40_000
export const MAX_SO_FAR_CHARACTERS = 20_000
const MAX_MENTIONS = 40
const MAX_LABEL_CHARACTERS = 200

/// A short string as sent, or the fallback: anything that is not a string is
/// the fallback, and a long one is cut rather than refused, because a name
/// or a title that runs on is not a reason to lose a telling.
function label(value: unknown, fallback: string): string {
	return typeof value === 'string' ? value.trim().slice(0, MAX_LABEL_CHARACTERS) : fallback
}

/// The request as the route reads it, or the reason it cannot.
export function shapeStoryCard(payload: unknown): StoryCard | 'missing_memories' | 'story_too_long' {
	const p = (payload && typeof payload === 'object' ? payload : {}) as Record<string, unknown>
	const lang: Lang = p.lang === 'en' ? 'en' : 'fi'
	const rawMemories = Array.isArray(p.memories) ? p.memories : []
	const memories = rawMemories
		.map((m) => {
			const row = (m && typeof m === 'object' ? m : {}) as Record<string, unknown>
			const text = typeof row.text === 'string' ? row.text.trim() : ''
			return {
				teller: label(row.teller, lang === 'fi' ? 'Kertoja' : 'Teller'),
				told: label(row.told, lang === 'fi' ? 'ei tiedossa' : 'not known'),
				source: row.source === 'typed' ? 'typed' : 'voice',
				text,
			}
		})
		.filter((m) => m.text.length > 0)
	if (memories.length === 0) return 'missing_memories'
	const total = memories.reduce((sum, m) => sum + m.text.length, 0)
	const soFar = typeof p.soFar === 'string' && p.soFar.trim() ? p.soFar.trim() : null
	if (
		memories.length > MAX_STORY_MEMORIES ||
		memories.some((m) => m.text.length > MAX_MEMORY_CHARACTERS) ||
		total > MAX_STORY_CHARACTERS ||
		(soFar !== null && soFar.length > MAX_SO_FAR_CHARACTERS)
	) {
		return 'story_too_long'
	}
	const rawMentions = Array.isArray(p.mentions) ? p.mentions.slice(0, MAX_MENTIONS) : []
	const mentions = rawMentions
		// A name on the card is a confirmed one by construction. A row that
		// says it is not — no build sends the word since the flag left the
		// wire, and a name marked unconfirmed is not a fact, while the prompt
		// has no way to be handed a name except as one — is dropped before
		// the prompt, never carried with a mark on it (rule 4).
		.filter((m) => !(m && typeof m === 'object' && (m as Record<string, unknown>).confirmed === false))
		.map((m) => {
			const row = (m && typeof m === 'object' ? m : {}) as Record<string, unknown>
			return {
				name: label(row.name, ''),
				kind: typeof row.kind === 'string' ? row.kind : 'person',
			}
		})
		.filter((m) => m.name.length > 0)
	return {
		lang,
		kind: typeof p.kind === 'string' ? p.kind : 'event',
		title: typeof p.title === 'string' && p.title.trim() ? p.title.trim().slice(0, MAX_LABEL_CHARACTERS) : null,
		date: typeof p.date === 'string' && p.date.trim() ? p.date.trim().slice(0, MAX_LABEL_CHARACTERS) : null,
		mentions,
		memories,
		soFar,
	}
}

// ------------------------------------------------------------ the request

/// The words the prompt uses for a card's kind and a telling's source. The
/// phone sends the archive's own values (`SubjectKind`, `MemorySource`); the
/// prompt was measured with these.
const KIND_WORDS: Record<Lang, Record<string, string>> = {
	fi: { photo: 'valokuva', person: 'henkilö', place: 'paikka', event: 'hetki' },
	en: { photo: 'photograph', person: 'person', place: 'place', event: 'moment' },
}
const SOURCE_WORDS: Record<Lang, Record<string, string>> = {
	fi: { voice: 'puhuttu', typed: 'kirjoitettu' },
	en: { voice: 'spoken', typed: 'written' },
}

/// The user message, exactly as `scripts/story-bench.mjs` renders a card,
/// with the story so far under it when the call is for an addition.
export function render(card: StoryCard): string {
	const fi = card.lang === 'fi'
	const kind = KIND_WORDS[card.lang][card.kind] ?? card.kind
	const lines: string[] = []
	const title = card.title ?? (fi ? '(nimetön)' : '(untitled)')
	lines.push(fi ? `KORTTI: ${kind} "${title}"` : `CARD: ${kind} "${title}"`)
	lines.push(fi ? `AJANKOHTA: ${card.date ?? 'ei tiedossa'}` : `DATE: ${card.date ?? 'not known'}`)
	const names = card.mentions.length
		? card.mentions.map((m) => `${m.name} (${KIND_WORDS[card.lang][m.kind] ?? m.kind})`).join(', ')
		: fi
			? 'ei yhtään'
			: 'none'
	lines.push(fi ? `VAHVISTETUT NIMET: ${names}` : `CONFIRMED NAMES: ${names}`)
	if (card.soFar !== null) {
		lines.push(fi ? 'TARINA TÄHÄN ASTI:' : 'STORY SO FAR:')
		lines.push(card.soFar)
		lines.push(fi ? 'UUDET KERRONNAT vanhimmasta uusimpaan:' : 'NEW MEMORIES, oldest first:')
	} else {
		lines.push(fi ? 'KERRONNAT vanhimmasta uusimpaan:' : 'MEMORIES, oldest first:')
	}
	card.memories.forEach((m, i) => {
		const source = SOURCE_WORDS[card.lang][m.source] ?? m.source
		lines.push(`${i + 1}. ${m.teller}, ${m.told}, ${source}: ${m.text}`)
	})
	return lines.join('\n')
}

export function messages(card: StoryCard): Message[] {
	const system =
		card.lang === 'fi'
			? SYSTEM_PROMPT_FI + (card.soFar !== null ? ADDITION_FI : '')
			: SYSTEM_PROMPT_EN + (card.soFar !== null ? ADDITION_EN : '')
	return [
		{ role: 'system', content: system },
		{ role: 'user', content: render(card) },
	]
}

/// Room for the answer. Rule 5 of the prompt says the story is not shorter
/// than the tellings, so the budget follows their length: Finnish runs at
/// about three characters a token and the framing adds a little, and the
/// bench's flat 6000 is kept as the floor. Capped at what the model can
/// write at all (`budget.ts`), and the reasoning is bounded on its own so a
/// thinking model cannot spend the answer's room before writing a word.
export function storyBudget(card: StoryCard, model: string): number {
	const characters = card.memories.reduce((sum, m) => sum + m.text.length, 0)
	return Math.min(outputCeiling(model), Math.max(6000, 1500 + Math.ceil(characters / 2)))
}
const STORY_REASONING_TOKENS = 1024

// ---------------------------------------------------------------- the call

/// Which model composes. `google/gemini-3.6-flash` is what the bench ran;
/// `wrangler.jsonc` names it, and a Worker deployed without the var still
/// composes.
export function storyModel(env: Env): string {
	return env.MODEL_STORY || 'google/gemini-3.6-flash'
}

/// The story, or an error the route turns into `upstream_failed`. Two
/// attempts, as the extraction has: a provider crashing at random must not
/// leave a card without its story until the next telling. A fault that
/// retrying cannot fix — no credit, a bad key — gives up at once.
export async function composeStory(env: Env, card: StoryCard): Promise<{ story: string }> {
	const model = storyModel(env)
	const budget = storyBudget(card, model)
	const characters = card.memories.reduce((sum, m) => sum + m.text.length, 0)
	let lastError: unknown
	for (let attempt = 1; attempt <= 2; attempt += 1) {
		try {
			const raw = await complete(env, messages(card), {
				model,
				temperature: 0.3,
				schema: STORY_SCHEMA,
				maxTokens: budget,
				reasoningTokens: STORY_REASONING_TOKENS,
			})
			const story = parseStory(raw)
			// Shape, counts and sizes only: the words themselves never reach
			// the log (rule 9).
			console.log(
				`[story] ${card.lang} ${card.kind}: ${card.memories.length} memories, ${characters} chars` +
					`${card.soFar !== null ? ', addition' : ''} → ${story.length} chars`,
			)
			return { story }
		} catch (err) {
			lastError = err
			if (err instanceof UpstreamError && !err.retryable) {
				console.error(`[story] not retryable (HTTP ${err.status}) — giving up`)
				break
			}
			if (attempt < 2) console.warn(`[story] attempt ${attempt} (${model}) failed, continuing`)
		}
	}
	throw lastError
}

/// The model's JSON, read strictly. Anything but an object with a non-empty
/// `story` string is a malformed reply, which the caller retries once — a
/// reply with nothing in it is not a story with nothing in it.
export function parseStory(raw: string): string {
	let parsed: unknown
	try {
		parsed = JSON.parse(raw)
	} catch {
		throw new Error('story reply is not JSON')
	}
	const story = (parsed as { story?: unknown } | null)?.story
	if (typeof story !== 'string' || !story.trim()) throw new Error('story reply has no story')
	return story.trim()
}
