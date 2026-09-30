#!/usr/bin/env node
// Checks that a relationship made again under a new id cannot stop a phone's
// sync.
//
// `relation` is unique on (from_subject, to_subject, kind), deleted rows
// included, and the app makes a relationship it had taken back under a new
// id. Until 30 Sep 2026 the upsert in `sync.ts` handled only a clash on `id`,
// so that insert failed, `env.DB.batch` failed with it, and the Worker
// answered 502. The phone built the same batch next round and every round
// after, and every telling written afterwards rode in it: nothing more
// reached the family, and the screen said it was waiting for the network.
// Two members making the same relationship apart did the same. It was found
// by reading, and reproduced against a local Worker the same day.
//
// Costs nothing: no AI, no upstream call, only D1 writes into the local
// database. Each run leaves a few throwaway families behind.
//
// Requires a running Worker:
//   cd backend && npx wrangler dev
//
// Usage (from any directory):
//   node scripts/relation-readd-check.mjs
//   node scripts/relation-readd-check.mjs http://localhost:8787

import { randomUUID, randomBytes } from 'node:crypto'

const API = process.argv[2] ?? 'http://localhost:8787'
// An address of its own per run, for the reason family-sync-check.mjs gives.
const household = `10.${(Math.random() * 254) | 0}.${(Math.random() * 254) | 0}.1`
const json = {
	'content-type': 'application/json',
	...(new URL(API).hostname === 'localhost' || new URL(API).hostname === '127.0.0.1'
		? { 'CF-Connecting-IP': household }
		: {}),
}

let failures = 0

function check(what, condition, detail = '') {
	if (condition) {
		console.log(`  ok   ${what}`)
	} else {
		failures += 1
		console.log(`  FAIL ${what}${detail ? ` — ${detail}` : ''}`)
	}
}

function device(name) {
	const memberID = randomUUID()
	const secret = randomBytes(32).toString('hex')
	return { name, memberID, secret, auth: { Authorization: `Bearer ${memberID}.${secret}` } }
}

async function post(path, body, headers = {}) {
	const response = await fetch(`${API}${path}`, {
		method: 'POST',
		headers: { ...json, ...headers },
		body: JSON.stringify(body),
	})
	const text = await response.text()
	let parsed = {}
	try {
		parsed = text ? JSON.parse(text) : {}
	} catch {
		parsed = { raw: text.slice(0, 80) }
	}
	return { status: response.status, body: parsed }
}

async function pull(who) {
	const response = await fetch(`${API}/sync?since=0`, { headers: who.auth })
	if (!response.ok) throw new Error(`GET /sync → ${response.status}`)
	return response.json()
}

const now = Math.floor(Date.now() / 1000)

async function family() {
	const founder = device('Ville')
	const created = await post('/family', {
		memberID: founder.memberID,
		secret: founder.secret,
		displayName: founder.name,
		familyName: '',
	})
	if (created.status !== 200) throw new Error(`POST /family → ${created.status}`)
	return founder
}

async function twoPeople(who) {
	const a = randomUUID()
	const b = randomUUID()
	await post(
		'/sync',
		{
			subjects: [
				{ id: a, kind: 'person', title: 'Aino', confirmed: 1, created_at: now },
				{ id: b, kind: 'person', title: 'Eeva', confirmed: 1, created_at: now },
			],
		},
		who.auth,
	)
	return { a, b }
}

const relation = (id, from, to, extra = {}) => ({
	id,
	from_subject: from,
	to_subject: to,
	kind: 'parent_of',
	confirmed: 1,
	created_at: now,
	...extra,
})

const telling = (subject, who) => ({
	id: randomUUID(),
	subject_id: subject,
	author_name: who.name,
	body: 'Muisto, joka kirjoitettiin suhteen jälkeen.',
	source: 'typed',
	created_at: now,
})

const live = (rows, from, to) =>
	rows.filter((r) => r.from_subject === from && r.to_subject === to && r.kind === 'parent_of' && !r.deleted_at)

try {
	console.log('A relationship taken back and made again')
	{
		const phone = await family()
		const { a, b } = await twoPeople(phone)
		const first = randomUUID()
		await post('/sync', { relations: [relation(first, a, b)] }, phone.auth)
		await post('/sync', { relations: [relation(first, a, b, { deleted_at: now + 1 })] }, phone.auth)

		const memory = telling(a, phone)
		const again = await post(
			'/sync',
			{ memories: [memory], relations: [relation(randomUUID(), a, b)] },
			phone.auth,
		)
		check('the push that makes it again is stored', again.status === 200, JSON.stringify(again.body))

		const server = await pull(phone)
		check(
			'and the telling in the same push reaches the family',
			server.memories?.some((m) => m.id === memory.id),
		)
		const rows = live(server.relations ?? [], a, b)
		check('the relationship is there once', rows.length === 1, `${rows.length} live rows`)
		check('under the id every phone already knows', rows[0]?.id === first, rows[0]?.id)
	}

	console.log('The same relationship made by two members apart')
	{
		const founder = await family()
		const invite = await post('/family/invite', {}, founder.auth)
		const joiner = device('Aino')
		await post('/family/join', {
			memberID: joiner.memberID,
			secret: joiner.secret,
			displayName: joiner.name,
			code: invite.body.code,
		})
		const { a, b } = await twoPeople(founder)
		const hers = randomUUID()
		await post('/sync', { relations: [relation(hers, a, b, { confirmed: 1 })] }, founder.auth)

		const memory = telling(a, joiner)
		const his = await post(
			'/sync',
			{ memories: [memory], relations: [relation(randomUUID(), a, b, { confirmed: 0 })] },
			joiner.auth,
		)
		check("the second member's push is stored", his.status === 200, JSON.stringify(his.body))
		const server = await pull(founder)
		check('and the telling in it reaches the family', server.memories?.some((m) => m.id === memory.id))
		const rows = live(server.relations ?? [], a, b)
		check('the relationship is there once', rows.length === 1, `${rows.length} live rows`)
		check('and a guess under another id does not unconfirm it', rows[0]?.confirmed === 1, `${rows[0]?.confirmed}`)

		// A copy made and taken back on one phone before it was ever sent
		// is not the family's relationship being taken back.
		const taken = await post(
			'/sync',
			{ relations: [relation(randomUUID(), a, b, { deleted_at: now + 5 })] },
			joiner.auth,
		)
		check('a copy taken back under another id is stored', taken.status === 200)
		const after = await pull(founder)
		check(
			'and takes nothing away from the relationship',
			live(after.relations ?? [], a, b).length === 1,
		)
	}

	console.log('A rejection still travels by its own id')
	{
		const phone = await family()
		const { a, b } = await twoPeople(phone)
		const id = randomUUID()
		await post('/sync', { relations: [relation(id, a, b, { confirmed: 0 })] }, phone.auth)
		await post('/sync', { relations: [relation(id, a, b, { confirmed: 0, deleted_at: now + 1 })] }, phone.auth)
		// A phone that missed the rejection sends the same row back alive.
		await post('/sync', { relations: [relation(id, a, b, { confirmed: 0 })] }, phone.auth)
		const server = await pull(phone)
		check(
			'an old copy under the same id cannot bring it back',
			live(server.relations ?? [], a, b).length === 0,
		)
	}
} catch (err) {
	failures += 1
	console.log(`  FAIL the run itself — ${err.message}`)
}

if (failures > 0) {
	console.log(`\n${failures} check(s) failed`)
	process.exit(1)
}
console.log('\nall checks passed')
