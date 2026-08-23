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
	// Where a place is, once its name has been looked up on a device. Null until
	// something resolved it, and null again when the name is corrected.
	lat: number | null
	lon: number | null
	geo_precision: string | null
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
	text: string
	// How much the question asks of the answerer, 1–5. Null when nobody labelled
	// it; the client then reads it off the wording. See docs/ARCHITECTURE.md §12.
	level: number | null
	status: string
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

	const subjects = await env.DB.prepare(
		`SELECT id, kind, title, r2_key, lat, lon, geo_precision,
		        date_start, date_end, date_precision,
		        confirmed, merged_into, created_at, deleted_at, seq
		 FROM subject WHERE family_id = ? AND seq > ? ORDER BY seq LIMIT ?`,
	)
		.bind(family, since, MAX_ROWS)
		.all<SubjectRow>()

	const memories = await env.DB.prepare(
		`SELECT m.id, m.subject_id, m.author_id, m.body, m.raw_transcript,
		        m.audio_r2_key, m.audio_seconds, m.source, m.created_at,
		        m.deleted_at, m.seq, mem.display_name AS author_name
		 FROM memory m
		 LEFT JOIN member mem ON mem.id = m.author_id
		 WHERE m.family_id = ? AND m.seq > ? ORDER BY m.seq LIMIT ?`,
	)
		.bind(family, since, MAX_ROWS)
		.all<MemoryRow>()

	const questions = await env.DB.prepare(
		`SELECT q.id, q.subject_id, q.text, q.level, q.status, q.created_at,
		        q.deleted_at, q.seq, q.author_id, mem.display_name AS author_name
		 FROM prompt_question q
		 LEFT JOIN member mem ON mem.id = q.author_id
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

	for (const subject of (payload.subjects ?? []).slice(0, MAX_ROWS)) {
		if (!subject.id || !subject.kind) continue
		// Both halves or neither. A lone latitude is not half a location, it is a
		// point off the coast of Ghana.
		const lat = coordinate(subject.lat, 90)
		const lon = coordinate(subject.lon, 180)
		const hasPoint = lat !== null && lon !== null
		statements.push(
			env.DB.prepare(
				`INSERT INTO subject (id, family_id, kind, title, r2_key, lat, lon, geo_precision,
				                      date_start, date_end,
				                      date_precision, confirmed, merged_into, created_by,
				                      created_at, deleted_at, seq)
				 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
				 ON CONFLICT(id) DO UPDATE SET
				   title = excluded.title,
				   r2_key = COALESCE(excluded.r2_key, subject.r2_key),
				   -- The coordinates answer the title, so they follow it. A device
				   -- that has not looked the name up sends null and must not wipe
				   -- what another one resolved — but when the title itself changes,
				   -- the old point stops being the answer to anything, and keeping
				   -- it would turn a corrected name into a wrong place on the map.
				   lat = CASE WHEN excluded.title IS NOT subject.title
				              THEN excluded.lat ELSE COALESCE(excluded.lat, subject.lat) END,
				   lon = CASE WHEN excluded.title IS NOT subject.title
				              THEN excluded.lon ELSE COALESCE(excluded.lon, subject.lon) END,
				   geo_precision = CASE WHEN excluded.title IS NOT subject.title
				                        THEN excluded.geo_precision
				                        ELSE COALESCE(excluded.geo_precision, subject.geo_precision) END,
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
				hasPoint ? lat : null,
				hasPoint ? lon : null,
				hasPoint && subject.geo_precision && GEO_PRECISIONS.has(subject.geo_precision)
					? subject.geo_precision
					: null,
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
				                     audio_r2_key, audio_seconds, source, created_at, deleted_at, seq)
				 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
				 ON CONFLICT(id) DO UPDATE SET
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
				memory.created_at ?? timestamp,
				memory.deleted_at ?? null,
				seq,
				session.memberID,
			),
		)

		for (const subjectID of memory.mentions ?? []) {
			statements.push(
				env.DB.prepare(
					'INSERT OR IGNORE INTO mention (memory_id, subject_id) VALUES (?, ?)',
				).bind(memory.id, subjectID),
			)
		}
	}

	for (const question of (payload.questions ?? []).slice(0, MAX_ROWS)) {
		if (!question.id || !question.text) continue
		statements.push(
			env.DB.prepare(
				`INSERT INTO prompt_question (id, family_id, subject_id, author_id, text, level, status,
				                              created_at, deleted_at, seq)
				 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
				 ON CONFLICT(id) DO UPDATE SET
				   status = excluded.status,
				   -- Authorship is sticky: an older device re-pushing the same
				   -- question without an asker must not strip the name off it.
				   author_id = COALESCE(prompt_question.author_id, excluded.author_id),
				   -- The level is sticky for the same reason, and because only
				   -- the device that extracted the question ever knew it.
				   level = COALESCE(prompt_question.level, excluded.level),
				   deleted_at = COALESCE(excluded.deleted_at, prompt_question.deleted_at),
				   seq = excluded.seq
				 WHERE prompt_question.family_id = excluded.family_id`,
			).bind(
				question.id,
				family,
				question.subject_id ?? null,
				// A client may claim itself as the asker, or nobody (a question
				// the extraction generated) — never another member. The same
				// rule as a memory's author, relaxed to allow the machine.
				question.author_id === session.memberID ? session.memberID : null,
				question.text,
				// Out of range or missing is stored as null rather than
				// rejected: the level is an optimisation, the question is not.
				typeof question.level === 'number' && question.level >= 1 && question.level <= 5
					? Math.round(question.level)
					: null,
				question.status ?? 'open',
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

	return { seq, accepted: statements.length }
}
