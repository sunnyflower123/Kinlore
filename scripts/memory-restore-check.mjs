#!/usr/bin/env node
// A telling taken back, and brought back by its teller's hand alone.
//
// Until 26 Sep 2026 a taking-back was for ever: `deleted_at` was COALESCEd,
// which kept a stale copy from reviving it (memory-rules-check.mjs, rule 6)
// and also kept its own teller from changing her mind, while the dialog that
// asked promised the recording was gone with it — and it was not (rule 3
// keeps it). Now the card offers the telling back for thirty days, and the
// server carries the answer: `restored_at`, a second moment beside the
// first. Every rule here is silent when broken:
//
//   * a stale NULL push never revives a tombstone. The author's other phone
//     — the Keychain identity syncs, so it pushes as the same author — that
//     was offline when the taking-back happened still holds the live copy.
//   * only the author brings a telling back, as only the author takes it
//     away: the same WHERE on `author_id`.
//   * the later of the two moments is the state, and each moves only
//     forward. A restoration older than the deletion it answers is a stale
//     phone, not a decision; a deletion older than the restoration on file
//     must not move the mark backwards and quietly revive what was buried
//     again after it.
//   * the pull answers the STATE, not the raw column: `deleted_at` comes
//     back NULL where the restoration is newer, so a phone built before the
//     column existed sees the telling come back too, and the phone's own
//     `told` keeps its one rule.
//   * a restoration advances the row's seq, or no other phone ever pulls it.
//   * the row's first push may already carry both moments — told, taken
//     back and brought back before the phone ever synced — and lands live.
//
// Same technique as `targeted-question-check.mjs`: the real `push` and `pull`
// imported straight out of `backend/src` over the shipping schema.sql in an
// in-memory SQLite. Costs nothing: no Worker, no network, no key. Run it
// after touching the memory upsert in sync.ts or `restored_at` anywhere.
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

/// One family: `mummo` tells, `sanna` reads. Moments are seconds, like the
/// phone's `timeIntervalSince1970`, and spaced so that "newer" is never a
/// tie.
function archive() {
	const db = new DatabaseSync(':memory:')
	db.exec(schema)
	db.prepare('INSERT INTO family (id, name, created_at) VALUES (?, ?, 0)').run('F1', 'F1')
	const member = (id, name) =>
		db
			.prepare(
				`INSERT INTO member (id, family_id, display_name, secret_hash, role, created_at)
				 VALUES (?, 'F1', ?, 'x', 'member', 0)`,
			)
			.run(id, name)
	member('mummo', 'Aili')
	member('sanna', 'Sanna')
	db.prepare(
		`INSERT INTO subject (id, family_id, kind, created_at) VALUES ('photo1', 'F1', 'photo', 0)`,
	).run()
	const env = { DB: d1(db) }
	const as = (memberID) => ({ memberID, familyID: 'F1', role: 'member', displayName: memberID })
	/// The row as stored. `SELECT *`, so that a database without the column
	/// — the code before 26 Sep 2026 — answers with FAIL lines rather than
	/// a thrown error, which is what makes the red run a measurement.
	const raw = (id) => {
		const row = db.prepare('SELECT * FROM memory WHERE id = ?').get(id)
		return { deleted_at: row?.deleted_at ?? null, restored_at: row?.restored_at ?? null, seq: row?.seq ?? null }
	}
	/// What a phone that has pulled everything sees of the row.
	const seen = async (id, since = 0) => {
		const reply = await pull(env, as('sanna'), since)
		return { reply, row: reply.memories.find((m) => m.id === id) ?? null }
	}
	return { env, as, raw, seen }
}

const T0 = 1_790_000_000
const memory = (id, fields) => ({
	id,
	subject_id: 'photo1',
	body: 'sealed',
	source: 'typed',
	created_at: T0,
	...fields,
})

// --------------------------------------------------------- taking back

console.log('taking back, and a phone that missed it')
{
	const { env, as, raw, seen } = archive()
	const mummo = as('mummo')
	await push(env, mummo, { memories: [memory('m1', {})] })
	check('a telling is live once told', (await seen('m1')).row?.deleted_at === null)

	await push(env, mummo, { memories: [memory('m1', { deleted_at: T0 + 10 })] })
	const gone = (await seen('m1')).row
	check(
		'taken back, the pull carries the moment, so the card can say when',
		gone?.deleted_at === T0 + 10,
		JSON.stringify(gone),
	)

	// The author's other phone, offline when it happened, pushing the live
	// copy it still holds: nothing on it says "bring it back".
	await push(env, mummo, { memories: [memory('m1', { deleted_at: null })] })
	check('a stale NULL push does not revive it', (await seen('m1')).row?.deleted_at === T0 + 10)
	await push(env, mummo, { memories: [memory('m1', { deleted_at: null, restored_at: null })] })
	check('nor a stale push that spells the nulls out', (await seen('m1')).row?.deleted_at === T0 + 10)

	// Somebody else in the family, however well-meaning.
	await push(env, as('sanna'), { memories: [memory('m1', { deleted_at: null, restored_at: T0 + 20 })] })
	check(
		'another member cannot bring it back',
		(await seen('m1')).row?.deleted_at === T0 + 10 && raw('m1').restored_at === null,
		JSON.stringify(raw('m1')),
	)
}

// --------------------------------------------------------- bringing back

console.log('bringing back')
{
	const { env, as, raw, seen } = archive()
	const mummo = as('mummo')
	await push(env, mummo, { memories: [memory('m1', {})] })
	await push(env, mummo, { memories: [memory('m1', { deleted_at: T0 + 10 })] })
	const before = (await seen('m1')).reply.seq

	await push(env, mummo, { memories: [memory('m1', { deleted_at: null, restored_at: T0 + 20 })] })
	const { reply, row } = await seen('m1', before)
	check('the teller brings it back, and the pull answers a live row', row !== null && row.deleted_at === null, JSON.stringify(row))
	check('the restoration moved the row past every cursor, so every phone pulls it', reply.seq > before && row !== null, `${before} → ${reply.seq}`)
	check('the pull carries the restoration moment for the phone to push back', row?.restored_at === T0 + 20, JSON.stringify(row))
	check('the deletion moment stays on file underneath', raw('m1').deleted_at === T0 + 10, JSON.stringify(raw('m1')))

	// The author's other phone, which never saw the restoration, pushing
	// the tombstone it still holds: an older moment, not a decision.
	await push(env, mummo, { memories: [memory('m1', { deleted_at: T0 + 10 })] })
	check('a stale tombstone does not bury it again', (await seen('m1')).row?.deleted_at === null)
	await push(env, mummo, { memories: [memory('m1', { deleted_at: T0 + 10, restored_at: T0 + 20 })] })
	check('nor the same row pushed back as it was pulled', (await seen('m1')).row?.deleted_at === null)

	// A phone built before the column: no key at all.
	await push(env, mummo, { memories: [memory('m1', { deleted_at: null })] })
	check('a push that has never heard of restorations leaves one alone', (await seen('m1')).row?.deleted_at === null)
}

// --------------------------------------------------------- taking back again

console.log('taking back again, after bringing back')
{
	const { env, as, raw, seen } = archive()
	const mummo = as('mummo')
	await push(env, mummo, { memories: [memory('m1', {})] })
	await push(env, mummo, { memories: [memory('m1', { deleted_at: T0 + 10 })] })
	await push(env, mummo, { memories: [memory('m1', { deleted_at: null, restored_at: T0 + 20 })] })

	await push(env, mummo, { memories: [memory('m1', { deleted_at: T0 + 30, restored_at: T0 + 20 })] })
	check('a newer taking-back buries it again', (await seen('m1')).row?.deleted_at === T0 + 30, JSON.stringify(raw('m1')))

	// The other phone that saw the restoration but not the second
	// taking-back, pushing the live row it holds with the OLD restoration.
	await push(env, mummo, { memories: [memory('m1', { deleted_at: null, restored_at: T0 + 20 })] })
	check('a restoration older than the taking-back does not revive it', (await seen('m1')).row?.deleted_at === T0 + 30)

	// And the oldest copy of all, from before anything happened, after it
	// has been brought back a second time: the deletion mark must not move
	// backwards under the newer restoration.
	await push(env, mummo, { memories: [memory('m1', { deleted_at: null, restored_at: T0 + 40 })] })
	check('brought back a second time', (await seen('m1')).row?.deleted_at === null)
	await push(env, mummo, { memories: [memory('m1', { deleted_at: T0 + 10 })] })
	check(
		'the oldest tombstone neither buries it nor moves the mark backwards',
		(await seen('m1')).row?.deleted_at === null && raw('m1').deleted_at === T0 + 30,
		JSON.stringify(raw('m1')),
	)
	check('the newest restoration is the one on file', raw('m1').restored_at === T0 + 40, JSON.stringify(raw('m1')))
}

// --------------------------------------------------------- first push

console.log('a first push that already carries both moments')
{
	const { env, as, seen } = archive()
	await push(env, as('mummo'), { memories: [memory('m2', { deleted_at: T0 + 10, restored_at: T0 + 20 })] })
	check('told, taken back and brought back before the first sync lands live', (await seen('m2')).row?.deleted_at === null)
	await push(env, as('mummo'), { memories: [memory('m3', { deleted_at: T0 + 20, restored_at: T0 + 10 })] })
	check('and the other order lands as a tombstone', (await seen('m3')).row?.deleted_at === T0 + 20)
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
