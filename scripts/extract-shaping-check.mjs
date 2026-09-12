#!/usr/bin/env node
// What the app is willing to believe a language model said.
//
// `extract.ts` has two pure functions between the model's JSON and the
// family's archive, and until 12 Sep 2026 neither was reachable by any check.
// Not for want of value — for want of a module loader. Node cannot resolve
// this file's extensionless `./openrouter` import, measured as
// `ERR_MODULE_NOT_FOUND`, which is the whole reason `budget.ts` exists as a
// file with no runtime imports. Writing `./openrouter.ts` and setting
// `allowImportingTsExtensions` is the cheaper answer: the Worker bundles
// unchanged and this script can import the functions directly.
//
// They are the layer that decides what a model is allowed to put in front of
// a family, and both were wrong in ways nothing reported:
//
//   * A mention with an empty name became a PERSON. Every entry becomes a
//     `subject` row — `findOrCreateSubject` takes the name it is handed — so
//     `{"name": "", "kind": "person"}` is a card the family is asked to
//     confirm, drawn as "Henkilö" because `displayTitle` falls back to the
//     kind. Rule 4 says a wrong person is worse than a missing one; a person
//     with no name is that failure with nothing to recognise.
//   * An untrimmed name became a SECOND person. "Aino " and "Aino" are two
//     titles to the comparison that decides whether a name is somebody the
//     archive already has, so a stray space is the duplicate card the
//     base-form requirement exists to prevent, arriving by another road.
//
// Neither shows in a screenshot: the card looks like a card, and the second
// Aino looks like a person the family simply has two of.
//
//   node scripts/extract-shaping-check.mjs
//
// Costs nothing: no Worker, no key, no network, no model. Run it after
// touching extract.ts.

import { fileURLToPath, pathToFileURL } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const { normaliseMentions, normaliseQuestions } = await import(
	pathToFileURL(join(root, 'backend', 'src', 'extract.ts')).href
)

let failures = 0

function check(what, actual, expected) {
	const a = JSON.stringify(actual)
	const e = JSON.stringify(expected)
	if (a === e) {
		console.log(`  ok   ${what}`)
	} else {
		failures += 1
		console.log(`  FAIL ${what}\n         got      ${a}\n         expected ${e}`)
	}
}

const person = (name, confidence = 0.9) => ({ name, kind: 'person', confidence })

console.log('— a name that is not a name never becomes a person —')
check('an empty name is dropped', normaliseMentions([person('')]), [])
check('and so is one that is only spaces', normaliseMentions([person('   ')]), [])
check('and one that is not a string at all', normaliseMentions([person(42)]), [])
check('and an entry that is not an object', normaliseMentions(['Aino', null, 7]), [])
// The schema asks for `mentions` and a provider that ignores it sends
// something else. That is a reply with no names in it, not a crash.
check('a reply whose mentions are not a list yields none', normaliseMentions('Aino'), [])
check('and a missing one yields none', normaliseMentions(undefined), [])

console.log('— and a stray space never becomes a second person —')
check(
	'a name is trimmed',
	normaliseMentions([person('  Aino  ')]),
	[{ name: 'Aino', kind: 'person', confidence: 0.9 }],
)
check(
	'so the spaced and the bare name are one person, not two',
	normaliseMentions([person(' Aino'), person('Aino ')]).map((m) => m.name),
	['Aino', 'Aino'],
)

console.log('— a kind is never guessed —')
// A place filed as a person joins the family tree. Rule 4 again: the client
// already drops an unknown kind rather than assuming, and the server is not
// allowed to be the looser of the two.
check('an unknown kind is dropped', normaliseMentions([{ name: 'Aino', kind: 'dog', confidence: 1 }]), [])
check('a missing kind is dropped', normaliseMentions([{ name: 'Aino', confidence: 1 }]), [])
check(
	'a place survives as a place',
	normaliseMentions([{ name: 'Puumala', kind: 'place', confidence: 0.4 }]),
	[{ name: 'Puumala', kind: 'place', confidence: 0.4 }],
)

console.log('— and what is well formed is passed through untouched —')
check(
	'a good mention keeps its name, kind and confidence',
	normaliseMentions([person('Aino', 0.75)]),
	[{ name: 'Aino', kind: 'person', confidence: 0.75 }],
)
// Nothing reads confidence today (see `MentionedEntity`), but it is decoded
// as a number on the client, and `undefined` there is a decode failure that
// would lose the whole mention.
check(
	'a missing confidence becomes a number rather than nothing',
	normaliseMentions([{ name: 'Aino', kind: 'person' }]),
	[{ name: 'Aino', kind: 'person', confidence: 0 }],
)
check(
	'the bad entries are dropped and the good ones kept, in order',
	normaliseMentions([person(''), person('Aino'), { name: 'X', kind: 'dog' }, person('Toivo')])
		.map((m) => m.name),
	['Aino', 'Toivo'],
)

console.log('— a question is worth more than its label —')
// A provider that ignored the object schema sends a bare string. Throwing
// that away would cost the family three questions to save a number the
// client can read off the wording anyway.
check(
	'a plain string is still a question',
	normaliseQuestions(['Kuka tässä on?']),
	[{ text: 'Kuka tässä on?', level: null }],
)
check('an empty string is not', normaliseQuestions(['', '   ']), [])
check(
	'a label out of range is dropped, the question is not',
	normaliseQuestions([{ text: 'Kuka tässä on?', level: 9 }]),
	[{ text: 'Kuka tässä on?', level: null }],
)
check(
	'and so is a missing one',
	normaliseQuestions([{ text: 'Kuka tässä on?' }]),
	[{ text: 'Kuka tässä on?', level: null }],
)
check(
	'a label inside the range survives',
	normaliseQuestions([{ text: 'Mitä toivoisit?', level: 5 }]),
	[{ text: 'Mitä toivoisit?', level: 5 }],
)
// `Number` then `Math.round`, so a provider sending the level as a string or
// as 3.4 still lands on a level rather than on null.
check(
	'a label as a string is read as the number it is',
	normaliseQuestions([{ text: 'Missä?', level: '2' }]),
	[{ text: 'Missä?', level: 2 }],
)
check(
	'and a fractional one is rounded into range',
	normaliseQuestions([{ text: 'Missä?', level: 3.4 }]),
	[{ text: 'Missä?', level: 3 }],
)
check('a question with no text is dropped', normaliseQuestions([{ level: 3 }]), [])
check('a reply whose questions are not a list yields none', normaliseQuestions({}), [])

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
