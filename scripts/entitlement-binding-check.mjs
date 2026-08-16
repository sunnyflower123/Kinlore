#!/usr/bin/env node
// One purchase, one family — checked against the schema itself.
//
// `syncEntitlement` takes the customer id from the client and asks RevenueCat
// what that customer owns. Without a uniqueness rule on `member.rc_app_user_id`
// the same purchase reported from two families unlocks both of them, and the
// worse half is the webhook: it finds the payer with `WHERE rc_app_user_id = ?`
// and takes the first row, so a refund revokes the right from one family and
// leaves the other paid for ever. An error in that direction does not correct
// itself, and nobody would notice it until somebody looked at the bill.
//
// The guard in `entitlement.ts` answers that case politely (409 rather than a
// constraint violation), but the guard is TypeScript running in a Worker with
// RevenueCat secrets behind it — none of which exists on this machine. **The
// database rule is the half that can be proved here**, and it is also the half
// that holds when the guard is wrong: this loads the real `backend/schema.sql`
// into an in-memory SQLite and asks it.
//
//   node scripts/entitlement-binding-check.mjs
//
// Costs nothing: no Worker, no network, no D1, no RevenueCat. Run it after
// touching the member table or the entitlement path.

import { DatabaseSync } from 'node:sqlite'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const schema = readFileSync(join(root, 'backend', 'schema.sql'), 'utf8')

let failures = 0

function check(label, run, expected) {
	let outcome
	try {
		run()
		outcome = 'allowed'
	} catch (error) {
		outcome = String(error.message).includes('UNIQUE') ? 'refused' : `error: ${error.message}`
	}
	if (outcome === expected) {
		console.log(`  ok   ${label}`)
	} else {
		failures += 1
		console.log(`  FAIL ${label}: ${outcome}, expected ${expected}`)
	}
}

/// A fresh archive for every case, built from the shipping schema rather than
/// from a copy of it — a check against a hand-written table would pass happily
/// while the real one had no constraint at all.
function database() {
	const db = new DatabaseSync(':memory:')
	db.exec(schema)
	const family = (id) =>
		db
			.prepare('INSERT INTO family (id, name, created_at) VALUES (?, ?, 0)')
			.run(id, `family-${id}`)
	const member = (id, familyID) =>
		db
			.prepare(
				`INSERT INTO member (id, family_id, display_name, secret_hash, role, created_at)
				 VALUES (?, ?, ?, 'x', 'member', 0)`,
			)
			.run(id, familyID, `member-${id}`)
	family('perhe-a')
	family('perhe-b')
	member('a1', 'perhe-a')
	member('a2', 'perhe-a')
	member('b1', 'perhe-b')
	const bind = (memberID, customerID) =>
		db.prepare('UPDATE member SET rc_app_user_id = ? WHERE id = ?').run(customerID, memberID)
	return { db, bind }
}

console.log('— one purchase, one family —')
{
	const { bind } = database()
	check('the buyer can be bound to their purchase', () => bind('a1', 'cust-1'), 'allowed')
}
{
	const { bind } = database()
	bind('a1', 'cust-1')
	check(
		'the same purchase cannot also unlock another family',
		() => bind('b1', 'cust-1'),
		'refused',
	)
}
{
	const { bind } = database()
	bind('a1', 'cust-1')
	check(
		'nor a second member of the same family, while the first still holds it',
		() => bind('a2', 'cust-1'),
		'refused',
	)
}

console.log('— what must stay possible —')
{
	const { bind } = database()
	bind('a1', 'cust-1')
	// The restore path: the buyer changed phone, or another member of the same
	// family restored it. `syncEntitlement` releases the old row first, and this
	// is that sequence — the rule must not make it impossible.
	check(
		'the binding can move within the family once it is released',
		() => {
			bind('a1', null)
			bind('a2', 'cust-1')
		},
		'allowed',
	)
}
{
	const { bind } = database()
	// Most members never buy anything, and NULL is not a claim. If the index were
	// not partial this is where it would fail.
	check(
		'and everybody who has bought nothing shares that',
		() => {
			bind('a1', null)
			bind('a2', null)
			bind('b1', null)
		},
		'allowed',
	)
}

console.log('— the webhook can only find one —')
{
	const { db, bind } = database()
	bind('a1', 'cust-1')
	const rows = db.prepare('SELECT id, family_id FROM member WHERE rc_app_user_id = ?').all('cust-1')
	if (rows.length === 1 && rows[0].family_id === 'perhe-a') {
		console.log('  ok   a refund revokes the right from exactly one family')
	} else {
		failures += 1
		console.log(`  FAIL a refund revokes the right from exactly one family: ${rows.length} rows`)
	}
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
