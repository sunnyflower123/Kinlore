/// Sync.
///
/// Local first: the client always writes to its own storage and pushes changes
/// in the background. A memory must not be lost to the network — the speaker may
/// no longer be around to ask. See docs/ARCHITECTURE.md §3.

import type { Session } from './auth'
import type { Env } from './worker'

/// Upper bound for a single request. A family's entire archive is hundreds of
/// rows, so this is enough for the first full fetch while still stopping a
/// misbehaving client from sending a megabyte at once.
const MAX_ROWS = 500

export type SubjectRow = {
	id: string
	kind: string
	title: string | null
	r2_key: string | null
	// A photograph's confirmed colours, who said yes and when. The name is
	// derived on read from `member.display_name`, like a memory's author's.
	colour_r2_key: string | null
	colour_confirmed_by: string | null
	colour_confirmed_by_name?: string | null
	colour_confirmed_at: number | null
	// The face on a person's card: a live photograph of the same family, the
	// point in it somebody tapped as fractions of its width and height, and
	// the moment of choosing, which is what settles two phones choosing
	// differently. Null on every other kind of subject.
	portrait_subject_id: string | null
	portrait_focus_x: number | null
	portrait_focus_y: number | null
	portrait_set_at: number | null
	// Where a place is: a device's lookup of its name, or where somebody in the
	// family put it. Null until one of the two has happened. A lookup's point is
	// null again when the name is corrected; a confirmed one is not.
	lat: number | null
	lon: number | null
	geo_precision: string | null
	// Who put the place there and when, null under a lookup's answer. The name
	// is derived on read, like a colouring's.
	geo_confirmed_by: string | null
	geo_confirmed_by_name?: string | null
	geo_confirmed_at: number | null
	date_start: number | null
	date_end: number | null
	date_precision: string | null
	confirmed: number
	merged_into: string | null
	created_at: number
	deleted_at: number | null
	seq: number
}

export type MemoryRow = {
	id: string
	subject_id: string
	author_id: string
	author_name?: string
	body: string
	raw_transcript: string | null
	audio_r2_key: string | null
	audio_seconds: number | null
	source: string
	mentions: string[]
	/// Who told it, as against who pushed it — a person card chosen on the
	/// result screen, or, with the flag, a teller who asked not to be named.
	/// Null and 0 is every telling made before 19 Sep 2026 and reads as the
	/// author, which is what those tellings have always said.
	teller_subject_id: string | null
	teller_hidden: number
	created_at: number
	deleted_at: number | null
	seq: number
}

export type QuestionRow = {
	id: string
	subject_id: string | null
	// Who asked; null for questions the extraction generated. The name is
	// derived on read from `member.display_name`, like a memory's author.
	author_id: string | null
	author_name?: string
	// Who it is aimed at; null for the whole family. Named on read like the
	// asker. Set once, by the asker — see the upsert below.
	target_member: string | null
	target_name?: string
	text: string
	// How much the question asks of the answerer, 1–5. Null when nobody labelled
	// it; the client then reads it off the wording. See docs/ARCHITECTURE.md §12.
	level: number | null
	status: string
	// The telling that answered it. Sticky once set.
	answered_memory_id: string | null
	created_at: number
	deleted_at: number | null
	seq: number
}

export type RelationRow = {
	id: string
	from_subject: string
	to_subject: string
	kind: string
	confirmed: number
	created_at: number
	deleted_at: number | null
	seq: number
}

type PushPayload = {
	subjects?: Partial<SubjectRow>[]
	memories?: Partial<MemoryRow>[]
	questions?: Partial<QuestionRow>[]
	relations?: Partial<RelationRow>[]
}

const now = () => Math.floor(Date.now() / 1000)

/// A coordinate as the client sent it, or null.
///
/// Checked rather than trusted: this value is eventually drawn on a map, and a
/// NaN or an out-of-range number would put a family's summer cottage in the sea
/// with nothing on the screen to say where it came from.
function coordinate(value: unknown, max: number): number | null {
	return typeof value === 'number' && Number.isFinite(value) && Math.abs(value) <= max
		? value
		: null
}

/// An unrecognised precision is stored as null rather than rejected, the same
/// rule as a question's level: the qualifier is an optimisation, the point is
/// not. See docs/ARCHITECTURE.md §18.
const GEO_PRECISIONS = new Set(['exact', 'town', 'region', 'unknown'])

/// Reserves one ordering number for the family.
///
/// One statement: `RETURNING` reads the row the update itself wrote, so the
/// reservation is atomic. This used to be an UPDATE followed by a separate
/// SELECT, and two pushes arriving together could both read the counter after
/// both increments — one number shared between two devices' rows, and each
/// device's cursor then stepped past the other's work. Every row in a single
/// request gets the same number, which is enough, because the client always
/// asks for "everything above this" and the relative order of individual rows
/// does not matter.
async function nextSeq(env: Env, familyID: string): Promise<number> {
	const row = await env.DB.prepare(
		'UPDATE family SET sync_seq = sync_seq + 1 WHERE id = ? RETURNING sync_seq',
	)
		.bind(familyID)
		.first<{ sync_seq: number }>()
	return row?.sync_seq ?? 0
}

/// The highest seq a reply is complete up to, for one table — or null when the
/// table has no say because it did not fill its cap.
///
/// The reply's cursor must be the *minimum* of these, not the maximum seq in
/// the reply: each table is capped separately, so when one fills its cap while
/// another returns higher numbers, a cursor at the overall maximum would skip
/// the capped table's remaining rows on every later pull — silently, which for
/// the memory table means a telling that never reaches this device.
///
/// One more care for a capped table: a push stamps all its rows with one
/// number, so the cap can cut through the middle of such a group. The rows
/// above the cut would sit below the cursor and never be asked for again, so
/// the safe point is one *below* the last number — the next pull re-fetches
/// the whole group, and the idempotent upserts make the re-sent rows cost
/// bandwidth and nothing else. When the entire reply is a single group it is
/// necessarily complete, because a push accepts at most MAX_ROWS rows per
/// table; stopping below it would make no progress at all.
function completeUpTo(rows: { seq: number }[]): number | null {
	if (rows.length < MAX_ROWS) return null
	const first = rows[0].seq
	const last = rows[rows.length - 1].seq
	return first === last ? last : last - 1
}

// ---------------------------------------------------------------- pull

export async function pull(env: Env, session: Session, since: number) {
	const family = session.familyID

	// Prefixed throughout, because `member` has an `id` and a `created_at` of
	// its own and the join would make both ambiguous.
	const subjects = await env.DB.prepare(
		`SELECT s.id, s.kind, s.title, s.r2_key, s.lat, s.lon, s.geo_precision,
		        s.date_start, s.date_end, s.date_precision,
		        s.confirmed, s.merged_into, s.created_at, s.deleted_at, s.seq,
		        s.colour_r2_key, s.colour_confirmed_by, s.colour_confirmed_at,
		        s.portrait_subject_id, s.portrait_focus_x, s.portrait_focus_y, s.portrait_set_at,
		        s.geo_confirmed_by, s.geo_confirmed_at,
		        confirmer.display_name AS colour_confirmed_by_name,
		        placer.display_name AS geo_confirmed_by_name
		 FROM subject s
		 LEFT JOIN member confirmer ON confirmer.id = s.colour_confirmed_by
		 LEFT JOIN member placer ON placer.id = s.geo_confirmed_by
		 WHERE s.family_id = ? AND s.seq > ? ORDER BY s.seq LIMIT ?`,
	)
		.bind(family, since, MAX_ROWS)
		.all<SubjectRow>()

	const memories = await env.DB.prepare(
		`SELECT m.id, m.subject_id, m.author_id, m.body, m.raw_transcript,
		        m.audio_r2_key, m.audio_seconds, m.source, m.created_at,
		        m.deleted_at, m.seq, m.teller_subject_id, m.teller_hidden,
		        mem.display_name AS author_name
		 FROM memory m
		 LEFT JOIN member mem ON mem.id = m.author_id
		 WHERE m.family_id = ? AND m.seq > ? ORDER BY m.seq LIMIT ?`,
	)
		.bind(family, since, MAX_ROWS)
		.all<MemoryRow>()

	const questions = await env.DB.prepare(
		`SELECT q.id, q.subject_id, q.text, q.level, q.status, q.created_at,
		        q.deleted_at, q.seq, q.author_id, mem.display_name AS author_name,
		        q.target_member, target.display_name AS target_name,
		        q.answered_memory_id
		 FROM prompt_question q
		 LEFT JOIN member mem ON mem.id = q.author_id
		 LEFT JOIN member target ON target.id = q.target_member
		 WHERE q.family_id = ? AND q.seq > ? ORDER BY q.seq LIMIT ?`,
	)
		.bind(family, since, MAX_ROWS)
		.all<QuestionRow>()

	// Mentions travel with the memory rather than as rows of their own: they
	// change only when a memory is created or names are corrected, so syncing
	// them separately would be a third table with no benefit.
	// In batches, because D1 allows at most 100 bound parameters in one query
	// and the id list can be five times that on a first pull. Local SQLite does
	// not enforce the limit, which is how an unbatched IN(...) passed every
	// check here while refusing any real archive past a hundred memories: the
	// D1_ERROR became a 502, the cursor never advanced, and a joiner saw an
	// empty family forever — a failure that read like a dead network.
	const memoryRows = memories.results ?? []
	const byMemory = new Map<string, string[]>()
	const BATCH = 100
	for (let start = 0; start < memoryRows.length; start += BATCH) {
		const ids = memoryRows.slice(start, start + BATCH).map((m) => m.id)
		const placeholders = ids.map(() => '?').join(',')
		const mentions = await env.DB.prepare(
			`SELECT memory_id, subject_id FROM mention WHERE memory_id IN (${placeholders})`,
		)
			.bind(...ids)
			.all<{ memory_id: string; subject_id: string }>()
		for (const row of mentions.results ?? []) {
			const list = byMemory.get(row.memory_id) ?? []
			list.push(row.subject_id)
			byMemory.set(row.memory_id, list)
		}
	}
	for (const memory of memoryRows) memory.mentions = byMemory.get(memory.id) ?? []

	const relations = await env.DB.prepare(
		`SELECT id, from_subject, to_subject, kind, confirmed, created_at, deleted_at, seq
		 FROM relation WHERE family_id = ? AND seq > ? ORDER BY seq LIMIT ?`,
	)
		.bind(family, since, MAX_ROWS)
		.all<RelationRow>()

	const tables: { seq: number }[][] = [
		subjects.results ?? [],
		memoryRows,
		questions.results ?? [],
		relations.results ?? [],
	]
	// The cursor is the highest seq the reply is complete up to — held back by
	// any table that filled its cap. See `completeUpTo` for why the overall
	// maximum would lose rows.
	const caps = tables.map(completeUpTo).filter((cap): cap is number => cap !== null)
	const highest = tables.flat().reduce((max, row) => Math.max(max, row.seq), since)

	return {
		seq: caps.length > 0 ? Math.min(...caps) : highest,
		// If any table filled the limit, the client needs to fetch again.
		more: caps.length > 0,
		subjects: subjects.results ?? [],
		memories: memoryRows,
		questions: questions.results ?? [],
		relations: relations.results ?? [],
	}
}

// ---------------------------------------------------------------- push

export async function push(env: Env, session: Session, payload: PushPayload) {
	const family = session.familyID
	const seq = await nextSeq(env, family)
	const timestamp = now()
	const statements: D1PreparedStatement[] = []

	// Photographs first, whatever order the phone sent them in. A person's
	// face points at a photograph of the same family, and the statement below
	// looks that photograph up as it runs — so a person chosen a face from a
	// photograph that arrives in the same request has to find it already
	// there. The sort is stable, and nothing else here reads the order.
	const pushedSubjects = (payload.subjects ?? [])
		.slice(0, MAX_ROWS)
		.sort((a, b) => Number(a.kind !== 'photo') - Number(b.kind !== 'photo'))

	// Somebody else's word on where a place is can be carried on by any phone
	// that holds it -- a merge carries one to the surviving place that way --
	// but only a word the server already has, on the same place or on one
	// merged into it. The proof is the word's pair, the member and the moment, and the
	// point comes from the row that holds it rather than from the phone: a
	// relay can repeat what somebody said, never put words in their mouth.
	// Asked only when a push carries somebody else's pair at all.
	type Proof = {
		id: string
		merged_into: string | null
		geo_confirmed_by: string
		geo_confirmed_at: number
		lat: number | null
		lon: number | null
		geo_precision: string | null
	}
	const proofs = new Map<string, Proof[]>()
	const mergedHere = new Map<string, string>()
	for (const s of pushedSubjects) {
		if (typeof s.id === 'string' && typeof s.merged_into === 'string') mergedHere.set(s.id, s.merged_into)
	}
	if (
		pushedSubjects.some(
			(s) => s.kind === 'place' && typeof s.geo_confirmed_by === 'string' && s.geo_confirmed_by !== session.memberID,
		)
	) {
		const rows = await env.DB.prepare(
			`SELECT id, merged_into, geo_confirmed_by, geo_confirmed_at, lat, lon, geo_precision FROM subject
			 WHERE family_id = ? AND kind = 'place' AND geo_confirmed_at IS NOT NULL`,
		)
			.bind(family)
			.all<Proof>()
		for (const row of rows.results ?? []) {
			const pair = `${row.geo_confirmed_by} ${row.geo_confirmed_at}`
			proofs.set(pair, [...(proofs.get(pair) ?? []), row])
		}
	}

	for (const subject of pushedSubjects) {
		if (!subject.id || !subject.kind) continue
		// Both halves or neither. A lone latitude is not half a location, it is a
		// point off the coast of Ghana.
		const lat = coordinate(subject.lat, 90)
		const lon = coordinate(subject.lon, 180)
		const hasPoint = lat !== null && lon !== null
		let point = {
			lat: hasPoint ? lat : null,
			lon: hasPoint ? lon : null,
			precision:
				hasPoint && subject.geo_precision && GEO_PRECISIONS.has(subject.geo_precision)
					? subject.geo_precision
					: null,
		}
		// A place's point under somebody's word travels like a colouring: the
		// pusher's own member id, a moment that has already happened, and a
		// point for the word to be about -- 'unknown' among them, which is a
		// removal. Somebody else's travels only as a relay of a pair the server
		// holds, with the point that row proves. Anything short of that is sent
		// on as no word at all, and the rules below take the point for what it
		// then is, a lookup's answer.
		let placedBy: string | null = null
		let placedAt: number | null = null
		if (
			subject.kind === 'place' &&
			typeof subject.geo_confirmed_at === 'number' &&
			Number.isFinite(subject.geo_confirmed_at)
		) {
			const relay = (proofs.get(`${subject.geo_confirmed_by} ${subject.geo_confirmed_at}`) ?? []).find(
				(row) =>
					row.id === subject.id || row.merged_into === subject.id || mergedHere.get(row.id) === subject.id,
			)
			if (subject.geo_confirmed_by === session.memberID && point.precision !== null) {
				placedBy = session.memberID
				// Whole seconds, like the server's own clock. A relay is matched
				// on this number exactly, so it is better as an integer than as
				// whatever fraction a phone's clock carried.
				placedAt = Math.floor(Math.min(subject.geo_confirmed_at, timestamp))
			} else if (typeof subject.geo_confirmed_by === 'string' && relay) {
				placedBy = subject.geo_confirmed_by
				placedAt = subject.geo_confirmed_at
				point = { lat: relay.lat, lon: relay.lon, precision: relay.geo_precision }
			}
		}
		// A colouring travels only with its file, its own member's name and a
		// moment that has already happened. Anything short of that is sent on as
		// nothing, which the upsert reads as "no opinion": a member cannot put
		// somebody else's name on a yes, a key cannot point outside this family's
		// own objects, and a moment in the future cannot lock one colouring
		// against every later yes.
		const colour =
			subject.kind === 'photo' &&
			typeof subject.colour_r2_key === 'string' &&
			subject.colour_r2_key.startsWith(`${family}/`) &&
			subject.colour_confirmed_by === session.memberID &&
			typeof subject.colour_confirmed_at === 'number' &&
			Number.isFinite(subject.colour_confirmed_at)
		// A face is a choice under a moment, and only a person has one. The
		// choice may be no photograph at all -- that is a removal, and it needs
		// the moment to travel, because a phone that never saw the face sends
		// the same null photograph with no moment and must change nothing.
		// Whether the photograph is a live one of this family is the
		// statement's own question, asked as it runs; a focus outside the
		// picture is stored as none, and the phone draws the middle.
		const face =
			subject.kind === 'person' &&
			typeof subject.portrait_set_at === 'number' &&
			Number.isFinite(subject.portrait_set_at) &&
			(subject.portrait_subject_id == null || typeof subject.portrait_subject_id === 'string')
		const faceID = face && typeof subject.portrait_subject_id === 'string' ? subject.portrait_subject_id : null
		const faceAt = face ? Math.min(subject.portrait_set_at as number, timestamp) : null
		const focus = (value: unknown) =>
			faceID !== null && typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1
				? value
				: null
		statements.push(
			env.DB.prepare(
				`INSERT INTO subject (id, family_id, kind, title, r2_key,
				                      colour_r2_key, colour_confirmed_by, colour_confirmed_at,
				                      portrait_subject_id, portrait_focus_x, portrait_focus_y, portrait_set_at,
				                      lat, lon, geo_precision, geo_confirmed_by, geo_confirmed_at,
				                      date_start, date_end,
				                      date_precision, confirmed, merged_into, created_by,
				                      created_at, deleted_at, seq)
				 VALUES (?, ?, ?, ?, ?, ?, ?, ?,
				         -- The photograph a face points at has to be a live one of
				         -- this family, and the row is asked rather than the phone
				         -- believed: anything else becomes no photograph and, two
				         -- lines down, no moment either -- no opinion, which the
				         -- rules below leave alone. A removal has no photograph on
				         -- purpose and keeps its moment. Not a FOREIGN KEY, because
				         -- a rejected photograph keeps its row (soft deletion) and a
				         -- face already chosen from it stays on the row too: the
				         -- phone draws the initial when the picture is gone.
				         (SELECT p.id FROM subject p
				           WHERE p.id = ? AND p.family_id = ? AND p.kind = 'photo' AND p.deleted_at IS NULL),
				         ?, ?,
				         CASE WHEN ? IS NULL THEN ?
				              WHEN EXISTS (SELECT 1 FROM subject p
				                            WHERE p.id = ? AND p.family_id = ? AND p.kind = 'photo'
				                              AND p.deleted_at IS NULL)
				              THEN ? ELSE NULL END,
				         ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
				 ON CONFLICT(id) DO UPDATE SET
				   title = excluded.title,
				   r2_key = COALESCE(excluded.r2_key, subject.r2_key),
				   -- The newest yes wins, and it moves whole: the file, the name
				   -- and the moment together, and only when the pushed moment is
				   -- later than the stored one. A phone that never saw the
				   -- colouring pushes nulls, and a NULL is never later than
				   -- anything, so it changes nothing. SQLite reads every right-hand
				   -- side against the row as it was, so the three agree.
				   colour_r2_key = CASE WHEN excluded.colour_confirmed_at > COALESCE(subject.colour_confirmed_at, 0)
				                        THEN excluded.colour_r2_key ELSE subject.colour_r2_key END,
				   colour_confirmed_by = CASE WHEN excluded.colour_confirmed_at > COALESCE(subject.colour_confirmed_at, 0)
				                              THEN excluded.colour_confirmed_by ELSE subject.colour_confirmed_by END,
				   colour_confirmed_at = CASE WHEN excluded.colour_confirmed_at > COALESCE(subject.colour_confirmed_at, 0)
				                              THEN excluded.colour_confirmed_at ELSE subject.colour_confirmed_at END,
				   -- The face on a person's card, by the same rule: the newest
				   -- choice wins and moves whole, and a NULL moment is never
				   -- later than anything. That is what lets a removal travel --
				   -- a NULL photograph under a new moment -- while a phone that
				   -- never saw the face, sending the same NULL photograph with
				   -- no moment, changes nothing. The VALUES above have already
				   -- turned a photograph this family does not have into no
				   -- opinion, so nothing here needs to ask again.
				   portrait_subject_id = CASE WHEN excluded.portrait_set_at > COALESCE(subject.portrait_set_at, 0)
				                              THEN excluded.portrait_subject_id ELSE subject.portrait_subject_id END,
				   portrait_focus_x = CASE WHEN excluded.portrait_set_at > COALESCE(subject.portrait_set_at, 0)
				                           THEN excluded.portrait_focus_x ELSE subject.portrait_focus_x END,
				   portrait_focus_y = CASE WHEN excluded.portrait_set_at > COALESCE(subject.portrait_set_at, 0)
				                           THEN excluded.portrait_focus_y ELSE subject.portrait_focus_y END,
				   portrait_set_at = CASE WHEN excluded.portrait_set_at > COALESCE(subject.portrait_set_at, 0)
				                          THEN excluded.portrait_set_at ELSE subject.portrait_set_at END,
				   -- The coordinates answer the title, so they follow it. A device
				   -- that has not looked the name up sends null and must not wipe
				   -- what another one resolved — but when the title itself changes,
				   -- the old point stops being the answer to anything, and keeping
				   -- it would turn a corrected name into a wrong place on the map.
				   --
				   -- And a coarser point never displaces an exact one under the
				   -- same title (19 Sep 2026). A person can now move the mark to
				   -- where the place actually is -- the family's map on the phone --
				   -- and that is stored as exact; every other phone in the family
				   -- is still holding the municipality the gazetteer answered
				   -- with, and pushes it with the next thing anybody changes
				   -- about that place, a date or a confirmation. Without this the
				   -- family's own point would be silently replaced by the circle
				   -- it was placed to correct, and nothing on any screen would
				   -- say so. Re-placing the mark still works: that is exact over
				   -- exact, and excluded wins.
				   --
				   -- Both rules above are about a lookup's answer, and since
				   -- 25 Sep 2026 they come second. A point somebody in the family
				   -- confirmed is their word rather than a cache of anything, so
				   -- the first two questions are whether the push carries a newer
				   -- word -- then it moves whole, the colours' rule -- and whether
				   -- the row already holds one, which nothing but a newer word
				   -- moves: not a corrected title, not a gazetteer, not a phone
				   -- that has never heard of it, sending no moment at all.
				   --
				   -- No backtick anywhere in this string. The whole statement is
				   -- a JS template literal, so one would end it -- the build
				   -- fails at the next word with "Expected )", which names a
				   -- column in the SQL and not the quote that caused it.
				   lat = CASE WHEN excluded.geo_confirmed_at > COALESCE(subject.geo_confirmed_at, 0) THEN excluded.lat
				              WHEN subject.geo_confirmed_at IS NOT NULL THEN subject.lat
				              WHEN excluded.title IS NOT subject.title THEN excluded.lat
				              WHEN excluded.lat IS NULL THEN subject.lat
				              WHEN subject.geo_precision = 'exact'
				                   AND excluded.geo_precision IS NOT 'exact' THEN subject.lat
				              ELSE excluded.lat END,
				   lon = CASE WHEN excluded.geo_confirmed_at > COALESCE(subject.geo_confirmed_at, 0) THEN excluded.lon
				              WHEN subject.geo_confirmed_at IS NOT NULL THEN subject.lon
				              WHEN excluded.title IS NOT subject.title THEN excluded.lon
				              WHEN excluded.lon IS NULL THEN subject.lon
				              WHEN subject.geo_precision = 'exact'
				                   AND excluded.geo_precision IS NOT 'exact' THEN subject.lon
				              ELSE excluded.lon END,
				   geo_precision = CASE WHEN excluded.geo_confirmed_at > COALESCE(subject.geo_confirmed_at, 0)
				                        THEN excluded.geo_precision
				                        WHEN subject.geo_confirmed_at IS NOT NULL THEN subject.geo_precision
				                        WHEN excluded.title IS NOT subject.title
				                        THEN excluded.geo_precision
				                        WHEN excluded.geo_precision IS NULL THEN subject.geo_precision
				                        WHEN subject.geo_precision = 'exact'
				                             AND excluded.geo_precision IS NOT 'exact'
				                        THEN subject.geo_precision
				                        ELSE excluded.geo_precision END,
				   geo_confirmed_by = CASE WHEN excluded.geo_confirmed_at > COALESCE(subject.geo_confirmed_at, 0)
				                           THEN excluded.geo_confirmed_by ELSE subject.geo_confirmed_by END,
				   geo_confirmed_at = CASE WHEN excluded.geo_confirmed_at > COALESCE(subject.geo_confirmed_at, 0)
				                           THEN excluded.geo_confirmed_at ELSE subject.geo_confirmed_at END,
				   -- The same shape as the point above, and for the same reason.
				   -- A device pushes its whole local row, so one that has never
				   -- seen the date sends three nulls — and a plain assignment
				   -- turned "joskus viisikymmentäluvulla" into nothing the next
				   -- time somebody on an older copy renamed the subject or
				   -- confirmed it. Rule 5 says uncertainty is stored; it does
				   -- not survive being stored and then quietly overwritten.
				   --
				   -- date_precision is the signal that the pushing device has
				   -- an opinion about the date at all. Clearing one deliberately
				   -- sends 'unknown' rather than nothing, so a person who says
				   -- "en tiedä sittenkään" is still heard — that is a value,
				   -- not an absence.
				   date_start = CASE WHEN excluded.date_precision IS NOT NULL
				                     THEN excluded.date_start ELSE subject.date_start END,
				   date_end = CASE WHEN excluded.date_precision IS NOT NULL
				                   THEN excluded.date_end ELSE subject.date_end END,
				   date_precision = COALESCE(excluded.date_precision, subject.date_precision),
				   -- Confirmation is one-way: a device that has been offline for
				   -- a week must not turn a confirmed person back into a proposal.
				   confirmed = MAX(subject.confirmed, excluded.confirmed),
				   -- A merge is sticky for the same reason. Undoing one would
				   -- need its own operation, which does not exist yet.
				   merged_into = COALESCE(excluded.merged_into, subject.merged_into),
				   deleted_at = COALESCE(excluded.deleted_at, subject.deleted_at),
				   seq = excluded.seq
				 WHERE subject.family_id = excluded.family_id`,
			).bind(
				subject.id,
				family,
				subject.kind,
				subject.title ?? null,
				subject.r2_key ?? null,
				colour ? subject.colour_r2_key : null,
				colour ? session.memberID : null,
				colour ? Math.min(subject.colour_confirmed_at as number, timestamp) : null,
				// The face, in the order the VALUES ask: the photograph and the
				// family for the lookup, the point, then the photograph, the
				// moment, the photograph and the family again for the moment's
				// own lookup, and the moment.
				faceID,
				family,
				focus(subject.portrait_focus_x),
				focus(subject.portrait_focus_y),
				faceID,
				faceAt,
				faceID,
				family,
				faceAt,
				point.lat,
				point.lon,
				point.precision,
				placedBy,
				placedAt,
				subject.date_start ?? null,
				subject.date_end ?? null,
				subject.date_precision ?? null,
				subject.confirmed ?? 1,
				subject.merged_into ?? null,
				session.memberID,
				subject.created_at ?? timestamp,
				subject.deleted_at ?? null,
				seq,
			),
		)
	}

	for (const memory of (payload.memories ?? []).slice(0, MAX_ROWS)) {
		if (!memory.id || !memory.subject_id) continue
		// A memory with no text is not an empty memory. When the quota or the
		// network gives out, the audio is saved and the text follows later — the
		// audio is the product and the transcript is the replaceable part. See
		// docs/ARCHITECTURE.md §16.
		//
		// Refusing the row here was the quiet half of that bug: the client
		// cleared it from the outbox all the same, so the recording stayed on
		// one device and the family never saw it at all.
		//
		// A row with neither text nor audio really is nothing, and is skipped —
		// which is also why it must not be offered for push in the first place.
		if (!memory.body && !memory.audio_r2_key) continue
		statements.push(
			env.DB.prepare(
				`INSERT INTO memory (id, family_id, subject_id, author_id, body, raw_transcript,
				                     audio_r2_key, audio_seconds, source, teller_subject_id,
				                     teller_hidden, created_at, deleted_at, seq)
				 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
				 ON CONFLICT(id) DO UPDATE SET
				   -- The author may move a telling to another card: the AI's
				   -- placement is the most important piece of the result, and
				   -- until 5 Sep 2026 it was the one nobody could correct
				   -- (founder's-eye review, finding #27). The WHERE below keeps
				   -- it the author's alone. The author's other device pushing
				   -- an older row would move it back — the same shared-identity
				   -- edge the body already lives with.
				   subject_id = excluded.subject_id,
				   -- An empty body never overwrites a real one. The transcript
				   -- arrives after the audio, and the author's other device may
				   -- still hold the untranscribed version — the Keychain
				   -- identity syncs, so that device pushes as the same author
				   -- and would otherwise unwrite the text.
				   body = CASE WHEN excluded.body <> '' THEN excluded.body ELSE memory.body END,
				   -- Sticky for the same reason, and because rule 3 says the raw
				   -- transcript is always kept: it arrives with the late
				   -- completion, and nothing may strip it afterwards.
				   raw_transcript = COALESCE(excluded.raw_transcript, memory.raw_transcript),
				   audio_r2_key = COALESCE(excluded.audio_r2_key, memory.audio_r2_key),
				   -- Taken as sent, like subject_id above and unlike the two
				   -- sticky fields either side of it. The teller is an answer a
				   -- person gave on the result screen and may give again —
				   -- *"vaihda kertoja"*, and the second answer has to be able
				   -- to be a narrower one. COALESCE here would make a name
				   -- impossible to take off a telling once it was on, which is
				   -- the one direction this field must never fail in. The WHERE
				   -- below keeps it the author's alone, as everything else here
				   -- is.
				   teller_subject_id = excluded.teller_subject_id,
				   teller_hidden = excluded.teller_hidden,
				   deleted_at = COALESCE(excluded.deleted_at, memory.deleted_at),
				   seq = excluded.seq
				 -- Only the author edits their own. Nobody gets to tidy up what
				 -- grandmother said, not even accidentally through sync.
				 WHERE memory.author_id = ? AND memory.family_id = excluded.family_id`,
			).bind(
				memory.id,
				family,
				memory.subject_id,
				// The author is taken from the session rather than the payload:
				// a client must not be able to claim a memory was told by
				// someone else.
				session.memberID,
				memory.body,
				memory.raw_transcript ?? null,
				memory.audio_r2_key ?? null,
				memory.audio_seconds ?? null,
				memory.source ?? 'typed',
				// Kept as sent and never looked up. The card may not have
				// reached this database yet, and the column carries no foreign
				// key for that reason (schema.sql); a reader that cannot
				// resolve it shows the author instead.
				memory.teller_subject_id ?? null,
				memory.teller_hidden ? 1 : 0,
				memory.created_at ?? timestamp,
				memory.deleted_at ?? null,
				seq,
				session.memberID,
			),
		)

		// The mentions are a SET, so they are stored as one: what the push
		// does not name is removed. `INSERT OR IGNORE` alone made this half a
		// sync — a name could be added to a telling and never taken off it —
		// and the two corrections that exist to take one off both broke on it
		// (10 Sep 2026):
		//
		//   - "ei tuo Matti" (`MemoryStore.split`) points the telling at a
		//     fresh card. The server kept the old row, the pull handed back
		//     both, and `applyRemote` overwrote the local list with the pair.
		//     The telling then named the two people the correction exists to
		//     tell apart, on every phone including the one that corrected it.
		//   - A rename that merges two cards remaps the mention the same way
		//     and used to leave the memory naming the tombstone and the
		//     survivor at once.
		//
		// A missing `mentions` is left alone rather than read as "none": the
		// field is optional in the payload, and a client that does not send
		// it is not saying the telling names nobody.
		//
		// Only the author's own, like the row above it. `EXISTS` rather than
		// a read, so it stays one batch — and it sees the insert earlier in
		// this same batch, which is what makes a brand-new memory work. The
		// cap is D1's hundred bound parameters: the pull batches its `IN` at
		// 100 for the same reason, and no real telling names fifty people.
		if (memory.mentions) {
			const wanted = [
				...new Set(memory.mentions.filter((id) => typeof id === 'string' && id)),
			].slice(0, 50)
			const mine = 'SELECT 1 FROM memory WHERE id = ? AND author_id = ? AND family_id = ?'
			const keep = wanted.map(() => '?').join(',')
			statements.push(
				env.DB.prepare(
					`DELETE FROM mention WHERE memory_id = ?
					 ${wanted.length > 0 ? `AND subject_id NOT IN (${keep})` : ''}
					 AND EXISTS (${mine})`,
				).bind(memory.id, ...wanted, memory.id, session.memberID, family),
			)
			// The subject has to be there, and it has to be OURS.
			//
			// `mention.subject_id` is a foreign key, and SQLite's `ON
			// CONFLICT` clause does not cover one — `INSERT OR IGNORE` will
			// not swallow a violation the way it swallows a duplicate. So a
			// mention naming a subject the server has not got does not skip
			// a row, it aborts `env.DB.batch` and takes the whole push with
			// it: 502, nothing written, nothing cleared, and the identical
			// request rebuilt next round. A sync wedged for good behind one
			// stale id, with the screen saying only "waiting for the
			// network". The client no longer produces such an id (subjects
			// drain before the rows that point at them, `MemoryStore
			// .pendingPayload`); this is the half that does not depend on
			// the client being right.
			//
			// `family_id` in the same breath because it costs nothing here
			// and closes a gap of its own: nothing else stopped a payload
			// from hanging one family's memory on another family's subject.
			const knownSubject =
				'SELECT 1 FROM subject WHERE id = ? AND family_id = ?'
			for (const subjectID of wanted) {
				statements.push(
					env.DB.prepare(
						`INSERT OR IGNORE INTO mention (memory_id, subject_id)
						 SELECT ?, ? WHERE EXISTS (${mine}) AND EXISTS (${knownSubject})`,
					).bind(memory.id, subjectID, memory.id, session.memberID, family, subjectID, family),
				)
			}
		}
	}

	// The pushed questions as they stood before this push, so that a
	// notification fires on a change and never on a re-send: the outbox
	// retries, and a question pushed twice must not ring a phone twice.
	const pushedQuestions = (payload.questions ?? []).slice(0, MAX_ROWS)
	const questionIDs = pushedQuestions
		.filter((question) => typeof question.id === 'string' && question.text)
		.map((question) => question.id as string)
	const questionsBefore = await questionStates(env, family, questionIDs)

	for (const question of pushedQuestions) {
		if (!question.id || !question.text) continue
		// A client may claim itself as the asker, or nobody (a question the
		// extraction generated) — never another member. The same rule as a
		// memory's author, relaxed to allow the machine.
		const asker = question.author_id === session.memberID ? session.memberID : null
		statements.push(
			env.DB.prepare(
				`INSERT INTO prompt_question (id, family_id, subject_id, author_id, target_member,
				                              text, level, status, answered_memory_id,
				                              created_at, deleted_at, seq)
				 VALUES (?, ?, ?, ?,
				         (SELECT id FROM member WHERE id = ? AND family_id = ? AND left_at IS NULL),
				         ?, ?, ?,
				         (SELECT id FROM memory WHERE id = ? AND family_id = ?),
				         ?, ?, ?)
				 ON CONFLICT(id) DO UPDATE SET
				   status = excluded.status,
				   -- Authorship is sticky: an older device re-pushing the same
				   -- question without an asker must not strip the name off it.
				   author_id = COALESCE(prompt_question.author_id, excluded.author_id),
				   -- Aimed once, and only by the asker: anybody else aiming it
				   -- would send a notification carrying the asker's name on a
				   -- request the asker never made.
				   target_member = COALESCE(
				     prompt_question.target_member,
				     CASE WHEN prompt_question.author_id IS excluded.author_id
				          THEN excluded.target_member END),
				   -- The level is sticky for the same reason, and because only
				   -- the device that extracted the question ever knew it.
				   level = COALESCE(prompt_question.level, excluded.level),
				   -- The latest telling that answered it. Not sticky: an answer
				   -- taken back reopens the question (MemoryStore.reopen), and
				   -- the telling that answers it next is the one to record.
				   answered_memory_id = COALESCE(excluded.answered_memory_id,
				                                 prompt_question.answered_memory_id),
				   deleted_at = COALESCE(excluded.deleted_at, prompt_question.deleted_at),
				   seq = excluded.seq
				 WHERE prompt_question.family_id = excluded.family_id`,
			).bind(
				question.id,
				family,
				question.subject_id ?? null,
				asker,
				// Both references are looked up rather than bound: D1 enforces
				// foreign keys, and one id that does not resolve would fail the
				// whole batch — every row of this push, not just this one — on
				// every retry. A member who has left, another family's member or
				// a telling this Worker has never seen is stored as nothing.
				asker ? (question.target_member ?? null) : null,
				family,
				question.text,
				// Out of range or missing is stored as null rather than
				// rejected: the level is an optimisation, the question is not.
				typeof question.level === 'number' && question.level >= 1 && question.level <= 5
					? Math.round(question.level)
					: null,
				question.status ?? 'open',
				question.answered_memory_id ?? null,
				family,
				question.created_at ?? timestamp,
				question.deleted_at ?? null,
				seq,
			),
		)
	}

	for (const relation of (payload.relations ?? []).slice(0, MAX_ROWS)) {
		if (!relation.id || !relation.from_subject || !relation.to_subject || !relation.kind) continue
		statements.push(
			env.DB.prepare(
				`INSERT INTO relation (id, family_id, from_subject, to_subject, kind,
				                       confirmed, created_at, deleted_at, seq)
				 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
				 ON CONFLICT(id) DO UPDATE SET
				   -- Confirmation is one-way for relationships too: an old device
				   -- must not turn a confirmed relationship back into a guess.
				   confirmed = MAX(relation.confirmed, excluded.confirmed),
				   deleted_at = COALESCE(excluded.deleted_at, relation.deleted_at),
				   seq = excluded.seq
				 WHERE relation.family_id = excluded.family_id`,
			).bind(
				relation.id,
				family,
				relation.from_subject,
				relation.to_subject,
				relation.kind,
				relation.confirmed ?? 0,
				relation.created_at ?? timestamp,
				relation.deleted_at ?? null,
				seq,
			),
		)
	}

	if (statements.length > 0) await env.DB.batch(statements)

	await env.DB.prepare('UPDATE member SET last_seen_at = ? WHERE id = ?')
		.bind(timestamp, session.memberID)
		.run()

	const notices = noticesFor(
		session.memberID,
		questionsBefore,
		await questionStates(env, family, questionIDs),
	)
	return { seq, accepted: statements.length, notices }
}

// ---------------------------------------------------------------- notices

/// Somebody to tell, about one question. What the notification says is
/// decided in `apns.ts`; what it is allowed to know is only this.
export type Notice = {
	memberID: string
	kind: 'asked' | 'answered'
	questionID: string
	/// The asker's display name, for 'asked'. An answer names nobody: who
	/// told it is chosen on the result screen after the telling has been
	/// pushed, may be a person card whose name is sealed, and may be a
	/// teller who asked not to be named — so any name here could be wrong,
	/// and a wrong name is worse than none.
	askerName: string | null
}

type QuestionState = {
	id: string
	status: string
	author_id: string | null
	author_name: string | null
	target_member: string | null
	deleted_at: number | null
}

/// The stored state of the questions a push names, in batches for D1's
/// hundred-parameter limit (see `pull`) — ninety-nine ids and the family.
async function questionStates(env: Env, family: string, ids: string[]) {
	const states = new Map<string, QuestionState>()
	const BATCH = 99
	for (let start = 0; start < ids.length; start += BATCH) {
		const batch = ids.slice(start, start + BATCH)
		const rows = await env.DB.prepare(
			`SELECT q.id, q.status, q.author_id, mem.display_name AS author_name,
			        q.target_member, q.deleted_at
			 FROM prompt_question q
			 LEFT JOIN member mem ON mem.id = q.author_id
			 WHERE q.family_id = ? AND q.id IN (${batch.map(() => '?').join(',')})`,
		)
			.bind(family, ...batch)
			.all<QuestionState>()
		for (const row of rows.results ?? []) states.set(row.id, row)
	}
	return states
}

/// Who a push should notify, from the change it made. Two events and no
/// others: a question newly aimed at a member, who is told somebody asked
/// them; and a question with an asker newly answered, which tells the
/// asker. Nobody is told about their own push, and a deleted question tells
/// nobody anything.
function noticesFor(
	pusher: string,
	before: Map<string, QuestionState>,
	after: Map<string, QuestionState>,
): Notice[] {
	const notices: Notice[] = []
	for (const [id, row] of after) {
		if (row.deleted_at !== null || !row.author_id) continue
		const was = before.get(id)
		if (
			row.target_member &&
			!was?.target_member &&
			row.status === 'open' &&
			row.target_member !== pusher
		) {
			notices.push({
				memberID: row.target_member,
				kind: 'asked',
				questionID: id,
				askerName: row.author_name,
			})
		}
		if (row.status === 'answered' && was?.status !== 'answered' && row.author_id !== pusher) {
			notices.push({ memberID: row.author_id, kind: 'answered', questionID: id, askerName: null })
		}
	}
	return notices
}
