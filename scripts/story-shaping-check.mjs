#!/usr/bin/env node
// What the Worker tells the model when it composes a card's story, and what
// it believes back (ARCHITECTURE §27). No Worker, no key, no model: Node
// loads `story.ts` as it is, like `extract-shaping-check.mjs` loads
// `extract.ts`.
//
// Rule 4's instrument here is absence. The card lists the names the family
// has confirmed and nothing else, and the prompt says every other name it
// meets in a telling through the teller — so a name the model is never
// handed is a name it cannot state as fact. The phone sends only confirmed
// names (`StoryRequest`, story-check.swift); this side pins that a name
// marked unconfirmed by some other sender is dropped before the prompt
// rather than carried with a mark on it, that no flag reaches the text,
// that the tellings keep the order they came in, that a telling with
// nothing in it is not a telling, and that the caps are refusals rather
// than silent cuts. And the reply: an object with a story in it, or a fault
// the route retries once — never a story with nothing in it.
//
//   node scripts/story-shaping-check.mjs

import { fileURLToPath, pathToFileURL } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const { shapeStoryCard, render, messages, parseStory, storyBudget, MAX_STORY_MEMORIES, MAX_MEMORY_CHARACTERS } =
	await import(pathToFileURL(join(root, 'backend', 'src', 'story.ts')).href)

let failures = 0

function check(what, condition, detail = '') {
	if (condition) {
		console.log(`  ok   ${what}`)
	} else {
		failures += 1
		console.log(`  FAIL ${what}${detail ? ` — ${detail}` : ''}`)
	}
}

const telling = (text, more = {}) => ({ teller: 'Mummo', told: '14.6.2025', source: 'voice', text, ...more })
const jetty = {
	lang: 'fi',
	kind: 'photo',
	title: 'Mökin laituri',
	date: '1950-luku',
	mentions: [
		{ name: 'Aino', kind: 'person' },
		{ name: 'Puumala', kind: 'place' },
	],
	memories: [
		telling('Siinä kuvassa ollaan sen mökin rannassa.'),
		telling('Tämä on otettu kesällä 1961.', { teller: 'Aino', told: '2.8.2025', source: 'typed' }),
	],
}

console.log('— the card the model is shown —')
{
	const card = shapeStoryCard(jetty)
	check('a card with tellings is read as one', typeof card === 'object', String(card))
	const text = render(card)
	check('the kind is the prompt\'s word for it', text.startsWith('KORTTI: valokuva "Mökin laituri"'), text.split('\n')[0])
	check('the date is on the card', text.includes('AJANKOHTA: 1950-luku'))
	check('the confirmed names are listed as names, each with its kind', text.includes('VAHVISTETUT NIMET: Aino (henkilö), Puumala (paikka)'))
	check('the tellings keep the order they came in, oldest first', text.indexOf('1. Mummo, 14.6.2025, puhuttu: Siinä kuvassa') < text.indexOf('2. Aino, 2.8.2025, kirjoitettu: Tämä on otettu'))
	check('and the heading says so', text.includes('KERRONNAT vanhimmasta uusimpaan:'))
	check('no story so far means no addition', !text.includes('TARINA TÄHÄN ASTI'))
	const [system, user] = messages(card)
	check('the system prompt is the story prompt, without the addition half', system.content.startsWith('Kokoat suomalaisen perheen') && !system.content.includes('TÄYDENNYS'))
	check(
		'and its rule 3 says the card lists the confirmed names and every other name goes through its teller',
		system.content.includes('Kortilla luetellaan nimet, jotka perhe on vahvistanut') && system.content.includes('Jokainen muu nimi, joka kerronnoissa esiintyy, sanotaan aina kertojan kautta'),
	)
	check('and the user message is the card', user.content === text)
}

console.log('— the same card in English, for a speaker of it —')
{
	const card = shapeStoryCard({ ...jetty, lang: 'en', title: null, date: null })
	const text = render(card)
	check('the kind is the English word', text.startsWith('CARD: photograph "(untitled)"'), text.split('\n')[0])
	check('a missing date is said to be missing', text.includes('DATE: not known'))
	check('the names line is the English one', text.includes('CONFIRMED NAMES: Aino (person), Puumala (place)'))
	check('the source is the English word', text.includes(', spoken: ') && text.includes(', written: '))
	const [system] = messages(card)
	check('the English prompt runs', system.content.startsWith('You are assembling the story'))
}

console.log('— an unconfirmed name never reaches the model —')
{
	const card = shapeStoryCard({
		...jetty,
		mentions: [
			{ name: 'Eevertti', kind: 'person', confirmed: false },
			{ name: 'Toivo', kind: 'person', confirmed: true },
			{ name: 'Aino', kind: 'person' },
			{ name: '', kind: 'person' },
		],
	})
	const text = render(card)
	check('a name marked unconfirmed is dropped before the prompt, and is nowhere in what the model is shown', !text.includes('Eevertti') && !JSON.stringify(card).includes('Eevertti'))
	check('a name marked confirmed, or not marked at all, is a name on the card', text.includes('VAHVISTETUT NIMET: Toivo (henkilö), Aino (henkilö)'))
	check('and no flag is carried to the prompt, in either word', !text.includes('VAHVISTAMATON') && !text.includes('vahvistettu)') && card.mentions.every((m) => !('confirmed' in m)))
	check('a mention with no name is no mention', card.mentions.length === 2, JSON.stringify(card.mentions))
	const none = render(shapeStoryCard({ ...jetty, mentions: [] }))
	check('no confirmed names is said as none', none.includes('VAHVISTETUT NIMET: ei yhtään'))
}

console.log('— an addition to a story a person corrected —')
{
	const card = shapeStoryCard({ ...jetty, soFar: 'Mummo kertoo, että kuvassa ollaan mökin rannassa.', memories: [telling('Pekka muistaa laiturin narinan.', { teller: 'Pekka' })] })
	const text = render(card)
	check('the story so far is on the card', text.includes('TARINA TÄHÄN ASTI:\nMummo kertoo, että kuvassa ollaan mökin rannassa.'))
	check('and the tellings are named as new', text.includes('UUDET KERRONNAT vanhimmasta uusimpaan:'))
	const [system] = messages(card)
	check('the addition rule is appended after the measured prompt, not inside it', system.content.endsWith('samoilla säännöillä.') && system.content.indexOf('7. MUOTO.') < system.content.indexOf('TÄYDENNYS'))
	const blank = shapeStoryCard({ ...jetty, soFar: '   ' })
	check('a blank story so far is no story so far', blank.soFar === null)
}

console.log('— what is not a card —')
{
	check('no tellings is missing_memories', shapeStoryCard({ ...jetty, memories: [] }) === 'missing_memories')
	check('and so are tellings with nothing in them', shapeStoryCard({ ...jetty, memories: [telling('  '), telling('')] }) === 'missing_memories')
	check('and no payload at all', shapeStoryCard(null) === 'missing_memories')
	check('a telling that is not an object is skipped, not fatal', shapeStoryCard({ ...jetty, memories: [42, telling('Sanottu.')] }).memories.length === 1)
	const many = shapeStoryCard({ ...jetty, memories: Array.from({ length: MAX_STORY_MEMORIES + 1 }, () => telling('Sanottu.')) })
	check('one telling too many is refused as too long', many === 'story_too_long', String(many))
	const long = shapeStoryCard({ ...jetty, memories: [telling('x'.repeat(MAX_MEMORY_CHARACTERS + 1))] })
	check('a telling past the cap is refused', long === 'story_too_long', String(long))
	const total = shapeStoryCard({ ...jetty, memories: Array.from({ length: 6 }, () => telling('x'.repeat(7000))) })
	check('and so is a card whose tellings together pass the total', total === 'story_too_long', String(total))
	const soFar = shapeStoryCard({ ...jetty, soFar: 'x'.repeat(20_001) })
	check('and a story so far past its own cap', soFar === 'story_too_long', String(soFar))
	const cut = shapeStoryCard({ ...jetty, title: 'x'.repeat(500), memories: [telling('Sanottu.', { teller: 'y'.repeat(500) })] })
	check('a long title or teller is cut, not refused', typeof cut === 'object' && cut.title.length === 200 && cut.memories[0].teller.length === 200)
	const kind = shapeStoryCard({ ...jetty, kind: 'castle' })
	check('a kind the prompt has no word for is passed as it came', render(kind).startsWith('KORTTI: castle'))
}

console.log('— room for the answer —')
{
	const short = storyBudget(shapeStoryCard(jetty), 'google/gemini-3.6-flash')
	check('a short card gets the bench\'s floor', short === 6000, String(short))
	const long = storyBudget(shapeStoryCard({ ...jetty, memories: Array.from({ length: 5 }, () => telling('x'.repeat(7000))) }), 'google/gemini-3.6-flash')
	check('a long one gets more, sized to the tellings', long === 1500 + 17_500, String(long))
	const capped = storyBudget(shapeStoryCard({ ...jetty, memories: Array.from({ length: 5 }, () => telling('x'.repeat(7000))) }), 'some/unknown-model')
	check('and never more than the model can write', capped === 16_000, String(capped))
}

console.log('— what the Worker believes came back —')
{
	check('a story in an object is the story, trimmed', parseStory('{"story":"  Mummo kertoo.  "}') === 'Mummo kertoo.')
	const refused = (raw) => {
		try {
			parseStory(raw)
			return false
		} catch {
			return true
		}
	}
	check('an empty story is refused, for the retry', refused('{"story":""}'))
	check('and one that is only spaces', refused('{"story":"   "}'))
	check('and a reply with no story in it', refused('{"text":"x"}'))
	check('and one that is not JSON', refused('Mummo kertoo.'))
	check('and a bare string', refused('"Mummo kertoo."'))
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
