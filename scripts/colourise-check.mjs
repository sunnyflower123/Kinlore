#!/usr/bin/env node
// Colouring an old photograph by what the family told about it — the three
// decisions the Worker makes, none of which a picture shows.
//
//   1. **What the model is told.** The tellings, trimmed and quoted in the
//      order the phone sent them, capped; a ratio the model knows or none. A
//      route that let an empty telling through would colour a photograph by
//      guess alone, which is rule 4's failure in the one shape nobody reads as
//      a guess: a photograph.
//   2. **What the Worker believes came back.** One image, of an image type,
//      from a generation that finished. A refusal arrives as words, and those
//      words can quote the family — so it is refused, and its words reach
//      neither the thrown error nor the log (rule 9).
//   3. **A meter of its own.** Five a month on the free tier, every round
//      counted, none of it taken from the telling minutes: the payer is not the
//      teller (PLAN.md §9), and a grandchild colouring photographs must not
//      spend the time a grandmother has to talk. No limit when paid.
//
// Costs nothing: `fetch` is replaced before anything could reach the network,
// and the meter runs over the real schema.sql in an in-memory SQLite, the way
// the entitlement checks do. No Worker, no key, no model.
//
//   node scripts/colourise-check.mjs

import { DatabaseSync } from 'node:sqlite'
import { readFileSync } from 'node:fs'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const source = (file) => pathToFileURL(join(root, 'backend', 'src', file)).href
const schema = readFileSync(join(root, 'backend', 'schema.sql'), 'utf8')
const { aspectRatio, colourise, toldText } = await import(source('colourise.ts'))
const { imageFromReply } = await import(source('openrouter.ts'))
const { checkAISeconds, checkColourisations, recordAISeconds, recordColourisation, usage } =
	await import(source('quota.ts'))

let failures = 0

function check(what, condition, detail = '') {
	if (condition) {
		console.log(`  ok   ${what}`)
	} else {
		failures += 1
		console.log(`  FAIL ${what}${detail ? ` — ${detail}` : ''}`)
	}
}

// Words that belong to a family, so that a leak of a fragment is still caught.
const SAID = 'Äidin mekko oli tummanvihreä, ja Kuusamon talo oli punainen'
// The opening bytes of a JPEG, which is all the route asks a photograph to be.
const PHOTO = '/9j/4AAQSkZJRgABAQ'

console.log('— the model is told what was told, and nothing else —')
{
	const told = toldText(['  uusin kerronta  ', 'vanhin kerronta'])
	check(
		'each telling is trimmed and quoted, in the order the phone sent them',
		told === '"uusin kerronta"\n\n"vanhin kerronta"',
		JSON.stringify(told),
	)
	check('an empty telling, or one that is not text, is dropped', toldText(['', '   ', 42, null, 'jäi']) === '"jäi"')
	check(
		'nothing told is nothing to colour by',
		toldText([]) === '' && toldText('ei lista') === '' && toldText(undefined) === '',
	)
	const book = toldText(['a'.repeat(50_000)])
	check('and a client cannot make the model read a book', book.length <= 8000, `${book.length} characters`)
	check('a ratio the model knows is passed on', aspectRatio('4:3') === '4:3' && aspectRatio('9:16') === '9:16')
	check('and any other is dropped rather than forwarded', aspectRatio('7:5') === undefined && aspectRatio(4 / 3) === undefined)
}

console.log('— the request: the photograph, the telling, and a picture asked for —')
{
	let body = null
	const real = globalThis.fetch
	globalThis.fetch = async (_url, init) => {
		body = JSON.parse(init.body)
		return {
			ok: true,
			json: async () => ({
				choices: [
					{
						message: { content: null, images: [{ image_url: { url: `data:image/jpeg;base64,${PHOTO}` } }] },
						finish_reason: 'stop',
					},
				],
			}),
		}
	}
	try {
		// Through a name, as data-collection-check does: sixteen characters
		// straight after an assignment to `…_KEY` is the shape secret-check refuses.
		const KEY = 'sk-or-not-a-real-key'
		const env = { OPENROUTER_API_KEY: KEY, MODEL_COLOURISE: 'google/gemini-3.1-flash-lite-image' }
		const image = await colourise(env, PHOTO, toldText([SAID]), '4:3')
		const parts = body.messages?.[0]?.content ?? []
		check('the model wrangler.jsonc names is the one asked', body.model === env.MODEL_COLOURISE, body.model)
		check(
			'a picture is asked for, not words',
			JSON.stringify(body.modalities) === JSON.stringify(['image', 'text']),
			JSON.stringify(body.modalities),
		)
		check('the telling travels verbatim', parts.some((part) => part.type === 'text' && part.text.includes(SAID)))
		check(
			'and the photograph as a JPEG',
			parts.some((part) => part.type === 'image_url' && part.image_url.url === `data:image/jpeg;base64,${PHOTO}`),
		)
		check('the ratio is sent when there is one', body.image_config?.aspect_ratio === '4:3', JSON.stringify(body.image_config))
		check(
			'and what came back is handed on',
			image.type === 'image/jpeg' && image.data === PHOTO,
			JSON.stringify(image).slice(0, 80),
		)
		await colourise(env, PHOTO, toldText([SAID]), undefined)
		check('no ratio, and none is sent', body.image_config === undefined, JSON.stringify(body.image_config))
	} finally {
		globalThis.fetch = real
	}
}

console.log('— what came back is a picture, or it is refused —')
{
	const picture = (url, reason = 'stop') => ({
		choices: [{ message: { content: null, images: [{ image_url: { url } }] }, finish_reason: reason }],
	})
	/// Runs the shaping and keeps what it logged, so the log can be searched too.
	const attempt = (reply) => {
		const logged = []
		const real = console.error
		console.error = (...parts) => logged.push(parts.join(' '))
		try {
			return { image: imageFromReply(reply, 'a/b'), logged }
		} catch (error) {
			return { error: String(error?.message), logged }
		} finally {
			console.error = real
		}
	}

	check('a JPEG is taken', attempt(picture(`data:image/jpeg;base64,${PHOTO}`)).image?.data === PHOTO)
	check('and so is a PNG', attempt(picture('data:image/png;base64,iVBORw0KGgo')).image?.type === 'image/png')
	{
		const refusal = attempt({
			choices: [{ message: { content: `En voi värittää tätä: ${SAID}` }, finish_reason: 'stop' }],
		})
		check('words instead of a picture are refused', refusal.error !== undefined)
		check(
			'and the words are in neither the error nor the log',
			!refusal.error?.includes('Kuusamon') && !refusal.logged.join('\n').includes('Kuusamon'),
			refusal.logged.join(' | '),
		)
		// The absence above means nothing if nothing was logged at all.
		check(
			'though the log does say that it happened',
			refusal.logged.some((line) => line.includes('no usable image')),
			refusal.logged.join(' | '),
		)
	}
	check('something that is not an image is refused', attempt(picture('data:text/html;base64,PGgxPg==')).error !== undefined)
	check(
		'so is a generation that did not finish',
		attempt(picture(`data:image/jpeg;base64,${PHOTO}`, 'length')).error !== undefined,
	)
	check('and a reply with nothing in it', attempt({}).error !== undefined && attempt(null).error !== undefined)
}

/// D1's statement shape over node:sqlite — prepare().bind().first()/.run(),
/// which is all quota.ts uses.
function d1(db) {
	return {
		prepare(sql) {
			const statement = db.prepare(sql)
			let args = []
			const bound = {
				bind(...values) {
					args = values
					return bound
				},
				async first() {
					return statement.get(...args) ?? null
				},
				async run() {
					statement.run(...args)
					return {}
				},
				async all() {
					return { results: statement.all(...args) }
				},
			}
			return bound
		},
	}
}

/// A family on the shipping schema. A null expiry is perpetual, so a paid one
/// is paid without RevenueCat being asked anything.
function family(entitlement = 'free') {
	const db = new DatabaseSync(':memory:')
	db.exec(schema)
	db.prepare(
		`INSERT INTO family (id, name, created_at, entitlement, entitlement_expires_at)
		 VALUES ('perhe', 'Perhe', 0, ?, NULL)`,
	).run(entitlement)
	return {
		DB: d1(db),
		FREE_AI_SECONDS_PER_MONTH: '600',
		FREE_PHOTO_LIMIT: '20',
		FREE_COLOURISATIONS_PER_MONTH: '5',
	}
}

const session = { memberID: 'lapsenlapsi', familyID: 'perhe', role: 'member', displayName: 'Ville' }

console.log('— five a month on the free tier, on a counter of its own —')
{
	const env = family()
	const let_through = []
	for (let round = 0; round < 5; round += 1) {
		let_through.push((await checkColourisations(env, session)) === null)
		await recordColourisation(env, session)
	}
	check('five rounds go through', let_through.every(Boolean), JSON.stringify(let_through))
	const denial = await checkColourisations(env, session)
	check(
		'the sixth is refused, and says which meter',
		denial?.error === 'quota_exceeded' && denial.kind === 'colourisations' && denial.used === 5 && denial.limit === 5,
		JSON.stringify(denial),
	)
	const shown = await usage(env, session)
	check(
		'not one second of it came out of the telling minutes',
		(await checkAISeconds(env, session, 60)) === null && shown.aiSeconds.used === 0,
		JSON.stringify(shown.aiSeconds),
	)
	check(
		'and the app can see what is left',
		shown.colourisations?.used === 5 && shown.colourisations?.limit === 5,
		JSON.stringify(shown.colourisations),
	)
}
{
	const env = family()
	await recordAISeconds(env, session, 600)
	check(
		'nor does telling use up the colourisations',
		(await checkColourisations(env, session)) === null && (await usage(env, session)).colourisations.used === 0,
	)
}
{
	const env = family('archive')
	for (let round = 0; round < 12; round += 1) await recordColourisation(env, session)
	check('a paid family is never refused', (await checkColourisations(env, session)) === null)
	const shown = await usage(env, session)
	check('and is shown no limit', shown.colourisations?.limit === null, JSON.stringify(shown.colourisations))
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
