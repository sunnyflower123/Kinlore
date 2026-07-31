/// Synkronointi.
///
/// Paikallinen ensin: asiakas kirjoittaa aina omaan tallennukseensa ja työntää
/// muutokset taustalla. Muisto ei saa kadota verkon takia — puhuja ei ehkä ole
/// enää kysyttävissä. Ks. docs/ARKKITEHTUURI.md §3.

import type { Session } from './auth'
import type { Env } from './worker'

/// Yhden pyynnön yläraja. Perheen koko arkisto on satoja rivejä, joten tämä
/// riittää ensimmäiseen täyteen hakuun ja estää silti väärin toimivaa
/// asiakasta lähettämästä megatavun kerralla.
const MAX_ROWS = 500

export type SubjectRow = {
	id: string
	kind: string
	title: string | null
	r2_key: string | null
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
	text: string
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

/// Varaa yhden järjestysluvun perheelle.
///
/// D1:ssä ei ole pitkiä transaktioita, joten varaus tehdään ehdollisella
/// päivityksellä: `sync_seq = sync_seq + 1` on atominen yhdellä rivillä.
/// Kaikki yhden pyynnön rivit saavat saman luvun — se riittää, koska asiakas
/// kysyy aina "kaikki tätä suuremmat" eikä yksittäisten rivien keskinäisellä
/// järjestyksellä ole merkitystä.
async function nextSeq(env: Env, familyID: string): Promise<number> {
	await env.DB.prepare('UPDATE family SET sync_seq = sync_seq + 1 WHERE id = ?')
		.bind(familyID)
		.run()
	const row = await env.DB.prepare('SELECT sync_seq FROM family WHERE id = ?')
		.bind(familyID)
		.first<{ sync_seq: number }>()
	return row?.sync_seq ?? 0
}

// ---------------------------------------------------------------- veto

export async function pull(env: Env, session: Session, since: number) {
	const family = session.familyID

	const subjects = await env.DB.prepare(
		`SELECT id, kind, title, r2_key, date_start, date_end, date_precision,
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
		`SELECT id, subject_id, text, status, created_at, deleted_at, seq
		 FROM prompt_question WHERE family_id = ? AND seq > ? ORDER BY seq LIMIT ?`,
	)
		.bind(family, since, MAX_ROWS)
		.all<QuestionRow>()

	// Maininnat kulkevat muiston mukana eivätkä omina riveinään: ne muuttuvat
	// vain kun muisto syntyy tai kun nimet korjataan, joten erillinen
	// synkronointi olisi kolmas taulu ilman hyötyä.
	const memoryRows = memories.results ?? []
	if (memoryRows.length > 0) {
		const ids = memoryRows.map((m) => m.id)
		const placeholders = ids.map(() => '?').join(',')
		const mentions = await env.DB.prepare(
			`SELECT memory_id, subject_id FROM mention WHERE memory_id IN (${placeholders})`,
		)
			.bind(...ids)
			.all<{ memory_id: string; subject_id: string }>()

		const byMemory = new Map<string, string[]>()
		for (const row of mentions.results ?? []) {
			const list = byMemory.get(row.memory_id) ?? []
			list.push(row.subject_id)
			byMemory.set(row.memory_id, list)
		}
		for (const memory of memoryRows) memory.mentions = byMemory.get(memory.id) ?? []
	}

	const relations = await env.DB.prepare(
		`SELECT id, from_subject, to_subject, kind, confirmed, created_at, deleted_at, seq
		 FROM relation WHERE family_id = ? AND seq > ? ORDER BY seq LIMIT ?`,
	)
		.bind(family, since, MAX_ROWS)
		.all<RelationRow>()

	const rows = [
		...(subjects.results ?? []),
		...memoryRows,
		...(questions.results ?? []),
		...(relations.results ?? []),
	]
	const highest = rows.reduce((max, row) => Math.max(max, row.seq), since)

	return {
		seq: highest,
		// Jos jokin taulu täytti rajan, asiakkaan pitää hakea uudelleen.
		more:
			(subjects.results?.length ?? 0) === MAX_ROWS ||
			memoryRows.length === MAX_ROWS ||
			(questions.results?.length ?? 0) === MAX_ROWS ||
			(relations.results?.length ?? 0) === MAX_ROWS,
		subjects: subjects.results ?? [],
		memories: memoryRows,
		questions: questions.results ?? [],
		relations: relations.results ?? [],
	}
}

// ---------------------------------------------------------------- työntö

export async function push(env: Env, session: Session, payload: PushPayload) {
	const family = session.familyID
	const seq = await nextSeq(env, family)
	const timestamp = now()
	const statements: D1PreparedStatement[] = []

	for (const subject of (payload.subjects ?? []).slice(0, MAX_ROWS)) {
		if (!subject.id || !subject.kind) continue
		statements.push(
			env.DB.prepare(
				`INSERT INTO subject (id, family_id, kind, title, r2_key, date_start, date_end,
				                      date_precision, confirmed, merged_into, created_by,
				                      created_at, deleted_at, seq)
				 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
				 ON CONFLICT(id) DO UPDATE SET
				   title = excluded.title,
				   r2_key = COALESCE(excluded.r2_key, subject.r2_key),
				   date_start = excluded.date_start,
				   date_end = excluded.date_end,
				   date_precision = excluded.date_precision,
				   -- Vahvistus on yksisuuntainen: viikon offline ollut laite ei
				   -- saa palauttaa vahvistettua henkilöä takaisin ehdotukseksi.
				   confirmed = MAX(subject.confirmed, excluded.confirmed),
				   -- Sulautus on tarttuva samasta syystä. Perumiseen tarvittaisiin
				   -- oma operaationsa, jota ei vielä ole.
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
		if (!memory.id || !memory.subject_id || !memory.body) continue
		statements.push(
			env.DB.prepare(
				`INSERT INTO memory (id, family_id, subject_id, author_id, body, raw_transcript,
				                     audio_r2_key, audio_seconds, source, created_at, deleted_at, seq)
				 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
				 ON CONFLICT(id) DO UPDATE SET
				   body = excluded.body,
				   audio_r2_key = COALESCE(excluded.audio_r2_key, memory.audio_r2_key),
				   deleted_at = COALESCE(excluded.deleted_at, memory.deleted_at),
				   seq = excluded.seq
				 -- Vain kirjoittaja muokkaa omaansa. Kukaan ei saa siivota
				 -- isoäidin kertomaa, ei edes vahingossa synkronoinnin kautta.
				 WHERE memory.author_id = ? AND memory.family_id = excluded.family_id`,
			).bind(
				memory.id,
				family,
				memory.subject_id,
				// Kirjoittaja otetaan istunnosta eikä hyötykuormasta: asiakas ei
				// saa väittää muistoa jonkun toisen kertomaksi.
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
				`INSERT INTO prompt_question (id, family_id, subject_id, text, status,
				                              created_at, deleted_at, seq)
				 VALUES (?, ?, ?, ?, ?, ?, ?, ?)
				 ON CONFLICT(id) DO UPDATE SET
				   status = excluded.status,
				   deleted_at = COALESCE(excluded.deleted_at, prompt_question.deleted_at),
				   seq = excluded.seq
				 WHERE prompt_question.family_id = excluded.family_id`,
			).bind(
				question.id,
				family,
				question.subject_id ?? null,
				question.text,
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
				   -- Vahvistus on yksisuuntainen myös suhteille: vanha laite ei
				   -- saa palauttaa vahvistettua sukulaisuutta arvaukseksi.
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
