#!/usr/bin/env node
// The invite link is the entire security boundary (ARCHITECTURE.md §4).
//
// There is no login. Whoever holds a code sees a family's memories of their
// dead relatives, and six rules are all that stand between the archive and
// anybody else: a code expires, a code can be revoked, a code belongs to one
// family, a code admits one person, the owner can close the door behind
// somebody who should not have come through it, and a wrong code must be
// indistinguishable from an expired, revoked or used one — otherwise guessing
// tells you when you have found a real family.
//
// Every one of those fails silently. A revoked code that still works looks
// exactly like a working app, and the only person who finds out is the one who
// revoked it and believed they had.
//
// **Beside `family-sync-check.mjs`, not instead of it.** That one walks the
// path the product is: two phones, one family, a memory crossing between them.
// This one stands at the door and pushes — the refusals, which are the half a
// happy path cannot see. Two cases overlap (a revoked code, a made-up one) and
// they are cheap; the rest are only here.
//
// **And, since 13 Sep 2026, the card an invitation is made for.** A member can
// be linked to a person card, and the link is an enforced foreign key — which
// gives this door one more silent way to fail, in the worst place: an
// invitation naming a card its inviter's phone has not synced yet, refused at
// the join after the code was claimed. The last cases press on that, on a
// member's link to their own card, and on a card from somebody else's family.
//
// Costs nothing: no AI, no upstream call, only D1 writes. Each run leaves two
// throwaway families behind, wherever it runs.
//
// Requires a running Worker:
//   cd backend && npx wrangler dev
//
// Ageing an invite past its expiry cannot be done over HTTP — there is no
// endpoint for it and there should not be — so that one case reaches into D1
// with wrangler. It has to be the same database the Worker in front of it is
// using, which is `--local` for `wrangler dev` and `--remote` for the deployed
// Worker; the URL decides, see `d1Scope`.
//
//   node scripts/invite-boundary-check.mjs
//   node scripts/invite-boundary-check.mjs http://localhost:8787
//
// Against a Worker running from another checkout, say where its database is or
// the expiry case will age the wrong one:
//
//   KINLORE_WORKER_DIR=/path/to/other/backend \
//     node scripts/invite-boundary-check.mjs http://localhost:8788
//
// And against the deployed Worker, which is where the boundary actually has to
// hold. First production run 29 Aug 2026, 12/12 — and the first time this was
// ever pointed there, which is how the `CF-Connecting-IP` claim below was
// found to be false. Second, 5 Sep 2026, 25/25, minutes after the single-use
// and removal rules were deployed, with the one-minute wait at the ninth
// join. It writes into the production database like any other caller: two
// families and their members stay behind.
//
//   node scripts/invite-boundary-check.mjs https://memorize.arkiste.workers.dev

import { randomUUID, randomBytes } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname, join as joinPath } from 'node:path'

const API = process.argv[2] ?? 'http://localhost:8787'
// The `--local` D1 lives beside the Worker that is using it, so ageing an
// invite has to reach into *that* copy. Pointing this script at another URL
// without saying where its state is aged the wrong database and made the expiry
// case pass for the wrong reason — which is how this variable came to exist.
const backend =
	process.env.KINLORE_WORKER_DIR ??
	joinPath(dirname(fileURLToPath(import.meta.url)), '..', 'backend')
// Every check knocks on the same two unauthenticated doors, and creating a
// family is limited to five a minute per address (worker.ts). Seven scripts run
// back to back in verify.sh and between them they create eleven families, so
// they were starving each other: whichever ran last failed with "could not
// create a family: 429", which reads like a broken Worker and is not one.
//
// So each local run knocks from an address of its own.
//
// **Local only, and the sentence that used to stand here was wrong.** It said
// Cloudflare sets `CF-Connecting-IP` from the connection and ignores what the
// client sends, so the header changed nothing in production. It does not
// ignore it: the edge refuses the request outright with `403 error code:
// 1000`, before the Worker is reached at all. Measured 29 Aug 2026, the first
// time this check was ever pointed at the deployed Worker — every family
// creation answered 403 and the run died on its first line. The header is
// therefore sent only where there is no Cloudflare in front to object.
//
// Against production the run pays the real rate limit instead. Two families
// fit inside five a minute; the joins do not fit inside ten any more — there
// are fourteen since the single-use and removal cases arrived — so `breathe`
// sits the window out once, at the ninth. The local Worker meters the same
// door with the same numbers (the first run of the fourteen failed its last
// five with `too_many_requests`), and there another synthetic address costs
// nothing, so locally `breathe` moves house instead of waiting.
const isLocalWorker = /^https?:\/\/(localhost|127\.0\.0\.1)\b/.test(API)
const household = () => `10.${(Math.random() * 254) | 0}.${(Math.random() * 254) | 0}.1`
// Which D1 the expiry case reaches into, decided by the same fact.
//
// It was `--local`, hardcoded, which is right for `npx wrangler dev` and wrong
// for the deployed Worker: pointed at production it aged a database nothing was
// reading, found no row, and threw — aborting the run a third of the way in, so
// the cases after it never ran at all. The other half of the same wrong-address
// trap `KINLORE_WORKER_DIR` was written for.
const d1Scope = isLocalWorker ? '--local' : '--remote'
const json = {
	'content-type': 'application/json',
	...(isLocalWorker ? { 'CF-Connecting-IP': household() } : {}),
}

let failures = 0
let joins = 0

/// Sit out the join door's rate window before it closes on this run: ten joins
/// a minute per address, and the cases below knock more often than that.
/// Locally the run knocks from a fresh synthetic address instead; against
/// production there is only the clock.
async function breathe() {
	if (joins < 9) return
	joins = 0
	if (isLocalWorker) {
		json['CF-Connecting-IP'] = household()
		return
	}
	console.log('  …   waiting out the join door\'s rate window (production only)')
	await new Promise((resolve) => setTimeout(resolve, 61_000))
}

function check(what, condition, detail = '') {
	if (condition) {
		console.log(`  ok   ${what}`)
	} else {
		failures += 1
		console.log(`  FAIL ${what}${detail ? ` — ${detail}` : ''}`)
	}
}

async function post(path, body, headers = {}) {
	const response = await fetch(`${API}${path}`, {
		method: 'POST',
		headers: { ...json, ...headers },
		body: JSON.stringify(body),
	})
	return { status: response.status, body: await response.json().catch(() => ({})) }
}

/// A person with a phone who types nothing at all when they join. The name on
/// the join form stopped being required when the invitation started carrying
/// one: on a phone handed to a grandparent, typing is the step worth removing.
function silent(label) {
	return { ...person(label), name: '' }
}

/// A person with a phone: an id, a secret, and the header the two make.
function person(name) {
	const memberID = randomUUID()
	const secret = randomBytes(32).toString('hex')
	return {
		name,
		memberID,
		secret,
		auth: { Authorization: `Bearer ${memberID}.${secret}` },
	}
}

async function createFamily(who, familyName) {
	const { status } = await post('/family', {
		memberID: who.memberID,
		secret: who.secret,
		displayName: who.name,
		familyName,
	})
	if (status !== 200) throw new Error(`could not create ${familyName}: ${status}`)
}

async function invite(who, displayName, personSubjectID) {
	const body_ = {
		...(displayName === undefined ? {} : { displayName }),
		...(personSubjectID === undefined ? {} : { personSubjectID }),
	}
	const { body } = await post('/family/invite', body_, who.auth)
	if (!body.code) throw new Error('no invite code came back')
	return body.code
}

/// What the family list calls somebody. The joiner asks with their own
/// credentials, which is also the only way to read this back — the invitation's
/// name is deliberately never handed out before joining.
async function nameOf(who) {
	const response = await fetch(`${API}/family`, { headers: { ...json, ...who.auth } })
	const body = await response.json().catch(() => ({}))
	return (body.members ?? []).find((m) => m.id === who.memberID)?.displayName
}

/// The family view as one member sees it.
async function familyOf(who) {
	const response = await fetch(`${API}/family`, { headers: { ...json, ...who.auth } })
	return response.json().catch(() => ({}))
}

/// A card as a phone's outbox sends it up. The title travels in clear here:
/// the server never reads one, and sealing it would test FamilyCrypto rather
/// than the link.
async function pushCard(who, { id = randomUUID(), kind = 'person' } = {}) {
	const { status } = await post(
		'/sync',
		{ subjects: [{ id, kind, title: 'Kortti', confirmed: 1, created_at: Math.floor(Date.now() / 1000) }] },
		who.auth,
	)
	if (status !== 200) throw new Error(`a card could not be pushed: ${status}`)
	return id
}

/// "This card is me" — or null, for no card at all.
async function linkMe(who, personSubjectID) {
	const response = await fetch(`${API}/family/me`, {
		method: 'PATCH',
		headers: { ...json, ...who.auth },
		body: JSON.stringify({ personSubjectID }),
	})
	return { status: response.status, body: await response.json().catch(() => ({})) }
}

async function join(who, code) {
	joins += 1
	return post('/family/join', {
		memberID: who.memberID,
		secret: who.secret,
		displayName: who.name,
		code,
	})
}

/// The owner's — or anybody's — attempt to remove a member.
async function remove(who, memberID) {
	const response = await fetch(`${API}/family/member?id=${encodeURIComponent(memberID)}`, {
		method: 'DELETE',
		headers: { ...json, ...who.auth },
	})
	return { status: response.status, body: await response.json().catch(() => ({})) }
}

/// Whether the server still opens the door to this identity at all.
async function isLetIn(who) {
	const response = await fetch(`${API}/family`, { headers: { ...json, ...who.auth } })
	return response.status === 200
}

/// Moves an invite's expiry into the past. There is no route for this on
/// purpose: an endpoint that ages a code is an endpoint that can un-age one.
function age(code) {
	let out = ''
	const wrongDatabase = () =>
		new Error(
			`the invite could not be aged (${d1Scope}) from ${backend}: that is not the ` +
				`database this Worker is using. Set KINLORE_WORKER_DIR to the backend it runs from.`,
		)
	try {
		out = execFileSync('npx', [
			'wrangler',
			'd1',
			'execute',
			'memorize',
			d1Scope,
			'--json',
			'--command',
			`UPDATE invite SET expires_at = 1 WHERE code = '${code}' RETURNING code`,
		],
			{ cwd: backend, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
		)
	} catch {
		// The tables are not even there. Same cause, same answer.
		throw wrongDatabase()
	}
	// It has to have aged *something*. Run from another checkout — a throwaway
	// worktree, a second Worker on another port — this reaches a different
	// `--local` database, one that may not even have the tables, and the expiry
	// case would then fail as though the app had let an expired code through.
	// A check that blames the app for its own wrong address is worse than no
	// check.
	if (!out.includes(code)) throw wrongDatabase()
}

try {
	const mummo = person('Mummo')
	const ville = person('Ville')
	const stranger = person('Tuntematon')
	await createFamily(mummo, 'Virtaset')
	await createFamily(stranger, 'Toinen perhe')

	console.log('— a code lets somebody in —')
	{
		const code = await invite(mummo)
		const { status, body } = await join(ville, code)
		check('the invited member joins', status === 200 && !body.error, JSON.stringify(body))
	}

	console.log('— and the four ways it must not —')
	{
		const outsider = person('Ohikulkija')
		const { body } = await join(outsider, 'ei-ole-koodi')
		check('a made-up code is refused', body.error === 'invalid_invite', JSON.stringify(body))
	}
	{
		const code = await invite(mummo)
		await fetch(`${API}/family/invite?code=${encodeURIComponent(code)}`, {
			method: 'DELETE',
			headers: mummo.auth,
		})
		const outsider = person('Peruttu')
		const { body } = await join(outsider, code)
		// The same words as a wrong code, deliberately: a different answer would
		// tell a guesser that the code was real and merely late.
		check(
			'a revoked code is refused, in the same words',
			body.error === 'invalid_invite',
			JSON.stringify(body),
		)
	}
	{
		const code = await invite(mummo)
		age(code)
		const outsider = person('Myöhässä')
		const { body } = await join(outsider, code)
		check(
			'an expired code is refused, in the same words',
			body.error === 'invalid_invite',
			JSON.stringify(body),
		)
	}
	{
		// The stranger already belongs to another family. Their code cannot pull
		// them across, and this is the rule that keeps two archives apart.
		const code = await invite(mummo)
		const { body } = await join(stranger, code)
		check(
			'somebody else\'s member cannot be pulled into this family',
			body.error === 'member_exists',
			JSON.stringify(body),
		)
	}

	console.log('— and one family cannot reach into another —')
	{
		const code = await invite(mummo)
		const response = await fetch(`${API}/family/invite?code=${encodeURIComponent(code)}`, {
			method: 'DELETE',
			headers: stranger.auth,
		})
		const body = await response.json().catch(() => ({}))
		// Revoking is scoped by family in the SQL itself. If that ever changes,
		// anybody who has seen a code could close somebody else's door.
		check(
			'a stranger cannot revoke this family\'s invite',
			body.revoked === false || body.error !== undefined,
			JSON.stringify(body),
		)
		const guest = person('Yhä kutsuttu')
		const { body: after } = await join(guest, code)
		check(
			'and the invite still works afterwards',
			after.error === undefined,
			JSON.stringify(after),
		)
	}
	console.log('— a code admits one person —')
	{
		// `used_count` was recorded and compared to nothing, so one link in a
		// group chat was a week-long key for everybody in it. The second person
		// through the same door is refused in the same words as a wrong code:
		// a used code confirmed as "used" is a code confirmed as real.
		const code = await invite(mummo, 'Kaarina')
		const first = person('Kaarina')
		const second = person('Toinen samasta ketjusta')
		const { body: went } = await join(first, code)
		check('the first person through is let in', went.error === undefined, JSON.stringify(went))
		const { body } = await join(second, code)
		check(
			'the second is refused, in the same words as a wrong code',
			body.error === 'invalid_invite',
			JSON.stringify(body),
		)
		// The same phone again is not a second person: a reinstall or an
		// iCloud restore comes back through the door it came in by.
		const { body: again } = await join(first, code)
		check('the same phone may come back through it', again.error === undefined, JSON.stringify(again))
		const response = await fetch(`${API}/family`, { headers: { ...json, ...mummo.auth } })
		const family = await response.json().catch(() => ({}))
		check(
			'and the family view no longer lists the used code',
			Array.isArray(family.invites) && !family.invites.some((i) => i.code === code),
			JSON.stringify(family.invites),
		)
	}

	console.log('— and the owner can close the door behind somebody —')
	{
		await breathe()
		// The link went to the wrong person, and they are in. Until 5 Sep 2026
		// nothing could be done about it: the only way out of a family was
		// one's own.
		const wrong = person('Väärä vastaanottaja')
		await join(wrong, await invite(mummo))
		// A live invitation made before the removal, which the removed person
		// may well hold — being forwarded one is how they got in.
		const open = await invite(mummo, 'Kaarina')

		const asVille = await remove(ville, wrong.memberID)
		check('a member cannot remove another member', asVille.status === 403, String(asVille.status))
		check('and the other is still in', await isLetIn(wrong))

		const asMummo = await remove(mummo, wrong.memberID)
		check(
			'the owner removes them',
			asMummo.status === 200 && asMummo.body.removed === true,
			JSON.stringify(asMummo.body),
		)
		check('and they are refused at every door afterwards', !(await isLetIn(wrong)))
		const response = await fetch(`${API}/family`, { headers: { ...json, ...mummo.auth } })
		const family = await response.json().catch(() => ({}))
		check(
			'and the family view no longer lists them',
			Array.isArray(family.members) && !family.members.some((m) => m.id === wrong.memberID),
			JSON.stringify(family.members),
		)
		// The invite text carries the family key, so every open code went with
		// them. The owner makes a fresh one for whoever was meant to have it.
		const latecomer = person('Linkin saanut')
		const { body: after } = await join(latecomer, open)
		check(
			'every open invitation went with them',
			after.error === 'invalid_invite',
			JSON.stringify(after),
		)
		check(
			'removing somebody already gone changes nothing',
			(await remove(mummo, wrong.memberID)).body.removed === false,
		)

		// Leaving is the owner's own road, and it knows how to hand ownership
		// on; this one refuses the owner's own row.
		const self = await remove(mummo, mummo.memberID)
		check('the owner cannot remove their own row this way', self.status === 404, String(self.status))
		check('and is still in', await isLetIn(mummo))
	}

	console.log('— the name the invitation was addressed to —')
	{
		// The point of the whole column: the grandchild who makes the invitation
		// knows who it is for, so the grandmother who uses it types nothing.
		const code = await invite(mummo, 'Kaarina')
		const guest = silent('Nimetön')
		const { body } = await join(guest, code)
		check('a silent joiner is let in', body.error === undefined, JSON.stringify(body))
		check(
			"and is called what the invitation called them",
			(await nameOf(guest)) === 'Kaarina',
			await nameOf(guest),
		)
	}
	{
		// The person joining is still the authority on their own name. If this
		// ever inverted, an invitation could rename somebody who disagreed with
		// it, silently, at the one moment they were saying who they are.
		const code = await invite(mummo, 'Kaarina')
		const guest = person('Kaarina Virtanen')
		await join(guest, code)
		check(
			'what the joiner types beats what the invitation says',
			(await nameOf(guest)) === 'Kaarina Virtanen',
			await nameOf(guest),
		)
	}
	{
		// The shape this route had before the column existed, kept working: an
		// unnamed invitation and a joiner who types nothing still produces a
		// member rather than an error or an empty name.
		const code = await invite(mummo)
		const guest = silent('Nimetön kutsu')
		await join(guest, code)
		check(
			'an unnamed invitation still falls back to Perheenjäsen',
			(await nameOf(guest)) === 'Perheenjäsen',
			await nameOf(guest),
		)
	}

	console.log("— a member's own card in the tree —")
	{
		// `member.person_subject_id` is an enforced foreign key, so every write
		// of it has to find the card first. Linking is one's own act, and only
		// to a live person card of one's own family; everything else is refused
		// in one answer.
		const mine = await pushCard(ville)
		const linked = await linkMe(ville, mine)
		check(
			'a member links themselves to their card',
			linked.status === 200 && linked.body.personSubjectID === mine,
			`${linked.status} ${JSON.stringify(linked.body)}`,
		)
		const row = (await familyOf(mummo)).members?.find((m) => m.id === ville.memberID)
		const you = (await familyOf(ville)).you
		check(
			'and the family view returns it, on the member and on "you"',
			row?.personSubjectID === mine && you?.personSubjectID === mine,
			JSON.stringify({ row, you }),
		)

		const across = await linkMe(ville, await pushCard(stranger))
		check(
			'a card from another family is refused',
			across.status === 400 && across.body.error === 'unknown_person',
			`${across.status} ${JSON.stringify(across.body)}`,
		)
		const photo = await linkMe(ville, await pushCard(mummo, { kind: 'photo' }))
		check('so is a photograph', photo.status === 400, `${photo.status} ${JSON.stringify(photo.body)}`)
		check(
			'and neither refusal moved the link',
			(await familyOf(ville)).you?.personSubjectID === mine,
		)

		// The founder's card is made on the phone and linked from it once a sync
		// has carried it up. Until then the server has nothing to link to, and
		// this refusal is what the phone's retry waits out.
		const later = randomUUID()
		const early = await linkMe(ville, later)
		check('a card the server has not got yet is refused', early.status === 400, String(early.status))
		await pushCard(ville, { id: later })
		const arrived = await linkMe(ville, later)
		check(
			'and linked once a sync has brought it',
			arrived.status === 200 && arrived.body.personSubjectID === later,
			`${arrived.status} ${JSON.stringify(arrived.body)}`,
		)

		// The app's own road since 26 Sep 2026 — "Tämä olet sinä" taken back
		// on the person card; until then nothing had called it. The reply
		// carries the null as a key, the way the request does, and the family
		// view reads it back as null.
		const unlinked = await linkMe(ville, null)
		check(
			'null unlinks, the reply says so, and the family view reads it back',
			unlinked.status === 200
				&& 'personSubjectID' in unlinked.body
				&& unlinked.body.personSubjectID === null
				&& (await familyOf(ville)).you?.personSubjectID === null,
			`${unlinked.status} ${JSON.stringify(unlinked.body)}`,
		)
	}

	console.log('— the card an invitation is made for —')
	{
		await breathe()
		{
			// The first minute's invitation: the grandchild types grandmother's
			// name, her card is made, and the invitation carries it. Opening the
			// link makes her that card.
			const card = await pushCard(mummo)
			const guest = silent('Kortin Kaarina')
			const { status, body } = await join(guest, await invite(mummo, 'Kaarina', card))
			check('an invitation with a card lets its person in', status === 200 && !body.error, JSON.stringify(body))
			const you = (await familyOf(guest)).you
			check('and links them to the card', you?.personSubjectID === card, JSON.stringify(you))
		}
		{
			// The case the design is about. The inviter's phone made the card and
			// the invitation, and the sync that carries the card up has not
			// happened yet. The join claims the code before it writes the member,
			// so a join that failed on the foreign key would burn her invitation.
			const card = randomUUID()
			const guest = silent('Aune, kortti matkalla')
			const { status, body } = await join(guest, await invite(mummo, 'Aune', card))
			check(
				'a card not yet pushed does not break the join',
				status === 200 && !body.error,
				`${status} ${JSON.stringify(body)}`,
			)
			const you = (await familyOf(guest)).you
			check(
				'she is let in unlinked, and the reply names the card for her phone',
				you?.personSubjectID === null && body.personSubjectID === card,
				JSON.stringify({ you, reply: body }),
			)
			// What her phone does once a pull brings the card down.
			await pushCard(mummo, { id: card })
			const linked = await linkMe(guest, card)
			check(
				'and she links herself once the card has arrived',
				linked.status === 200 && (await familyOf(guest)).you?.personSubjectID === card,
				`${linked.status} ${JSON.stringify(linked.body)}`,
			)
		}
		{
			// Refusing another family's card at this door would tell the inviter
			// that the id exists somewhere, so it is kept like a card still on its
			// way — and it links nobody, because the join asks about the
			// invitation's own family.
			const guest = silent('Vieraan kortin kutsu')
			const { status } = await join(guest, await invite(mummo, undefined, await pushCard(stranger)))
			const you = (await familyOf(guest)).you
			check(
				"an invitation naming another family's card links nobody to it",
				status === 200 && you?.personSubjectID === null,
				`${status} ${JSON.stringify(you)}`,
			)
		}
		{
			const photo = await pushCard(mummo, { kind: 'photo' })
			const refused = await post('/family/invite', { personSubjectID: photo }, mummo.auth)
			check(
				'an invitation made for a photograph is refused',
				refused.status === 400 && refused.body.error === 'unknown_person',
				`${refused.status} ${JSON.stringify(refused.body)}`,
			)
		}
	}
} catch (error) {
	failures += 1
	console.log(`\n  FAIL ${error.message}`)
	console.log(`       Nothing answered at ${API}.`)
	console.log('       cd backend && npx wrangler dev — and if 8787 was already')
	console.log('       taken, wrangler chose another port and said so on its Ready')
	console.log('       line. Pass that url as this script\'s first argument.')
}

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} failed`)
process.exit(failures === 0 ? 0 : 1)
