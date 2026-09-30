#!/usr/bin/env node
// A relationship taken back and made again, and the same one made twice.
//
// `relation` is unique on (from_subject, to_subject, kind), tombstones
// included, and the phone makes every relationship under a fresh id: a
// relationship taken back and then added again is a new row with the old
// row's three columns. Until 30 Sep 2026 the upsert in `push` answered only
// a clash on `id`, so that row failed the whole batch — every row of the
// push, not just this one — and the phone rebuilt the identical request
// every round for ever. Its pull runs after the push in the same round, so
// it never pulled again either, and the screen said only that it was
// waiting for the network (ARCHITECTURE §1, known issues). Two members
// adding the same relationship under their own ids did the same.
//
// What the server does now, and each rule is silent when broken:
//
//   * made again after it was taken back, the stored row takes the new id
//     and the new row's state, so every phone pulls the id the maker holds
//     and the tombstone they hold under the old id stays one.
//   * a stale tombstone under the old id, from a phone that missed all of
//     it, does not bury what was made again: that id is no longer on file,
//     and a tombstone never takes a live row's place.
//   * made twice while live, the first row stays, confirmation still only
//     moves up, and the row moves past every cursor so the second maker's
//     phone pulls the id that is on file.
//   * a proposal made again after a confirmed relationship was taken back
//     is a proposal: the confirmation belonged to the row somebody removed.
//   * nothing crosses a family, and the push around the row still lands.
//
// Same technique as `memory-restore-check.mjs`: the real `push` and `pull`
// imported straight out of `backend/src` over the shipping schema.sql in an
// in-memory SQLite. Costs nothing: no Worker, no network, no key. Run it
// after touching the relation upsert in sync.ts or the table's constraints.
//
// The D1 shim and `check` are copied rather than shared, like the ones in
// the entitlement checks, for the reason given there.

import { DatabaseSync } from 'node:sqlite'
import { readFileSync } from 'node:fs'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const schema = readFileSync(join(root, 'backend', 'schema.sql'), 'utf8')
const src = (file) => pathToFileURL(join(root, 'backend', 'src', file)).href
const { push, pull } = await import(src('sync.ts'))

let failures = 0

function check(what, condition, detail = '') {
	if (condition) {
		console.log(`  ok   ${what}`)
	} else {
		failures += 1
		console.log(`  FAIL ${what}${detail ? ` — ${detail}` : ''}`)
	}
}

/// D1's statement shape over node:sqlite, with `batch` as one transaction.
function d1(db) {
	const wrap = (sql) => {
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
			runNow() {
				statement.run(...args)
			},
		}
		return bound
	}
	return {
		prepare: wrap,
		async batch(statements) {
			db.exec('BEGIN')
			try {
				for (const statement of statements) statement.runNow()
				db.exec('COMMIT')
			} catch (err) {
				db.exec('ROLLBACK')
				throw err
			}
			return []
		},
	}
}

/// Two families. In F1 `mummo` and `sanna` both keep the tree, over two
/// people and a photograph; F2 has people of its own.
function archive() {
	const db = new DatabaseSync(':memory:')
	db.exec(schema)
	for (const family of ['F1', 'F2']) {
		db.prepare('INSERT INTO family (id, name, created_at) VALUES (?, ?, 0)').run(family, family)
	}
	const member = (id, family) =>
		db
			.prepare(
				`INSERT INTO member (id, family_id, display_name, secret_hash, role, created_at)
				 VALUES (?, ?, ?, 'x', 'member', 0)`,
			)
			.run(id, family, id)
	member('mummo', 'F1')
	member('sanna', 'F1')
	member('vieras', 'F2')
	const subject = (id, family, kind) =>
		db
			.prepare('INSERT INTO subject (id, family_id, kind, created_at) VALUES (?, ?, ?, 0)')
			.run(id, family, kind)
	subject('aino', 'F1', 'person')
	subject('eino', 'F1', 'person')
	subject('photo1', 'F1', 'photo')
	subject('muu', 'F2', 'person')
	const env = { DB: d1(db) }
	const as = (memberID) => ({
		memberID,
		familyID: memberID === 'vieras' ? 'F2' : 'F1',
		role: 'member',
		displayName: memberID,
	})
	/// Every row the table holds for the pair, whatever its id.
	const stored = () =>
		db
			.prepare(`SELECT * FROM relation WHERE from_subject = 'aino' AND to_subject = 'eino'`)
			.all()
	/// What a phone that has pulled since `since` is handed.
	const pulled = async (since = 0) => (await pull(env, as('sanna'), since)).relations
	/// A push, and whether it went through. The defect was a throw.
	const tryPush = async (memberID, payload) => {
		try {
			await push(env, as(memberID), payload)
			return null
		} catch (err) {
			return err instanceof Error ? err.message : String(err)
		}
	}
	const cursor = async () => (await pull(env, as('sanna'), 0)).seq
	return { env, as, stored, pulled, tryPush, cursor }
}

const T0 = 1_790_000_000
const relation = (id, fields = {}) => ({
	id,
	from_subject: 'aino',
	to_subject: 'eino',
	kind: 'spouse_of',
	confirmed: 1,
	created_at: T0,
	deleted_at: null,
	...fields,
})

// --------------------------------------------------------- the same id

// The clause that was there first, which the new one must not shadow: a
// row pushed again under its own id is the same row, whatever else holds.
console.log('the same id, as before')
{
	const { stored, tryPush } = archive()
	await tryPush('mummo', { relations: [relation('r1', { confirmed: 0 })] })
	await tryPush('sanna', { relations: [relation('r1', { confirmed: 1 })] })
	check('a yes confirms it', stored()[0]?.confirmed === 1, JSON.stringify(stored()))
	await tryPush('mummo', { relations: [relation('r1', { confirmed: 0 })] })
	check('an older copy does not unconfirm it', stored()[0]?.confirmed === 1, JSON.stringify(stored()))
	const failed = await tryPush('mummo', { relations: [relation('r1', { deleted_at: T0 + 10 })] })
	const rows = stored()
	check(
		'taken back under its own id, it is a tombstone',
		failed === null && rows.length === 1 && rows[0].id === 'r1' && rows[0].deleted_at === T0 + 10,
		failed ?? JSON.stringify(rows),
	)
	await tryPush('sanna', { relations: [relation('r1')] })
	check('and a stale live copy does not revive it', stored()[0]?.deleted_at === T0 + 10, JSON.stringify(stored()))
}

// --------------------------------------------------------- made again

console.log('taken back, then made again')
{
	const { stored, pulled, tryPush, cursor } = archive()
	await tryPush('mummo', { relations: [relation('r1')] })
	await tryPush('mummo', { relations: [relation('r1', { deleted_at: T0 + 10 })] })
	const before = await cursor()

	const failed = await tryPush('mummo', { relations: [relation('r2', { created_at: T0 + 20 })] })
	check('the push goes through', failed === null, failed ?? '')

	const rows = stored()
	check('one row for the pair, as the table allows', rows.length === 1, JSON.stringify(rows))
	check('it is live, under the id the maker holds', rows[0]?.id === 'r2' && rows[0]?.deleted_at === null, JSON.stringify(rows))
	check('it carries the new row\'s moment', rows[0]?.created_at === T0 + 20, JSON.stringify(rows))

	const seen = await pulled(before)
	check('it moved past every cursor, so every phone pulls it', seen.some((r) => r.id === 'r2' && r.deleted_at === null), JSON.stringify(seen))
}

console.log('the rest of the push')
{
	const { env, as, tryPush } = archive()
	await tryPush('mummo', { relations: [relation('r1')] })
	await tryPush('mummo', { relations: [relation('r1', { deleted_at: T0 + 10 })] })
	await tryPush('mummo', {
		relations: [relation('r2', { created_at: T0 + 20 })],
		memories: [{ id: 'm1', subject_id: 'photo1', body: 'sealed', source: 'typed', created_at: T0 + 20 }],
	})
	const memories = (await pull(env, as('sanna'), 0)).memories
	check('a telling in the same push reaches the family', memories.some((m) => m.id === 'm1'), JSON.stringify(memories))
}

console.log('a phone that missed it all')
{
	const { stored, tryPush } = archive()
	await tryPush('mummo', { relations: [relation('r1')] })
	await tryPush('mummo', { relations: [relation('r1', { deleted_at: T0 + 10 })] })
	await tryPush('mummo', { relations: [relation('r2', { created_at: T0 + 20 })] })

	// Sanna's phone took it back too and never synced until now: the
	// tombstone it holds names the old id.
	const failed = await tryPush('sanna', { relations: [relation('r1', { deleted_at: T0 + 15 })] })
	check('its push goes through', failed === null, failed ?? '')
	const rows = stored()
	check('the old tombstone does not bury what was made again', rows.length === 1 && rows[0].id === 'r2' && rows[0].deleted_at === null, JSON.stringify(rows))

	// And its live copy of the old id, from before any of it.
	await tryPush('sanna', { relations: [relation('r1')] })
	const after = stored()
	check('nor does its live copy take the id back', after.length === 1 && after[0].id === 'r2', JSON.stringify(after))
}

console.log('a proposal made again')
{
	const { stored, tryPush } = archive()
	await tryPush('mummo', { relations: [relation('r1', { confirmed: 1 })] })
	await tryPush('mummo', { relations: [relation('r1', { confirmed: 1, deleted_at: T0 + 10 })] })
	await tryPush('mummo', { relations: [relation('r2', { confirmed: 0, created_at: T0 + 20 })] })
	const rows = stored()
	check(
		'is a proposal, not the confirmation somebody took back',
		rows.length === 1 && rows[0].id === 'r2' && rows[0].confirmed === 0,
		JSON.stringify(rows),
	)
}

// --------------------------------------------------------- made twice

console.log('made twice, by two members')
{
	const { stored, pulled, tryPush, cursor } = archive()
	await tryPush('sanna', { relations: [relation('r1', { confirmed: 0 })] })
	const before = await cursor()

	const failed = await tryPush('mummo', { relations: [relation('r2', { confirmed: 1, created_at: T0 + 20 })] })
	check('the second push goes through', failed === null, failed ?? '')
	const rows = stored()
	check('the first row stays, under its own id', rows.length === 1 && rows[0].id === 'r1' && rows[0].deleted_at === null, JSON.stringify(rows))
	check('the second maker\'s yes confirms it', rows[0]?.confirmed === 1, JSON.stringify(rows))
	const seen = await pulled(before)
	check('it moved past every cursor, so the second maker pulls the id on file', seen.some((r) => r.id === 'r1'), JSON.stringify(seen))

	await tryPush('sanna', { relations: [relation('r3', { confirmed: 0 })] })
	check('a proposal made a third time does not unconfirm it', stored()[0]?.confirmed === 1, JSON.stringify(stored()))
}

console.log('a duplicate taken back before it ever synced')
{
	const { stored, tryPush } = archive()
	await tryPush('sanna', { relations: [relation('r1')] })
	const failed = await tryPush('mummo', { relations: [relation('r2', { deleted_at: T0 + 10 })] })
	check('the push goes through', failed === null, failed ?? '')
	const rows = stored()
	check('another member\'s live row is not taken back by it', rows.length === 1 && rows[0].id === 'r1' && rows[0].deleted_at === null, JSON.stringify(rows))
}

// --------------------------------------------------------- families

console.log('another family')
{
	const { stored, tryPush } = archive()
	await tryPush('mummo', { relations: [relation('r1')] })
	await tryPush('mummo', { relations: [relation('r1', { deleted_at: T0 + 10 })] })
	// F1's subjects named from F2: nothing of F1's moves.
	await tryPush('vieras', { relations: [relation('x1', { created_at: T0 + 20 })] })
	const rows = stored()
	check(
		'cannot revive or take over another family\'s relationship',
		rows.length === 1 && rows[0].id === 'r1' && rows[0].family_id === 'F1' && rows[0].deleted_at === T0 + 10,
		JSON.stringify(rows),
	)
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
