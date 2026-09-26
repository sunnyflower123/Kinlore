/// Kinlore — Cloudflare Worker.
///
/// The Worker exists to keep the API key out of the app. Unpacking an IPA is
/// trivial, and a leaked key is a real bill on a student budget. That is why
/// audio and text always travel through here.

import { authenticate } from './auth.ts'
import { boundedSeconds } from './budget.ts'
import { aspectRatio, colourise, toldText } from './colourise.ts'
import {
	createFamily,
	createInvite,
	getFamily,
	joinFamily,
	leaveFamily,
	linkMember,
	removeMember,
	renameMember,
	revokeInvite,
} from './family.ts'
import { download, upload } from './media.ts'
import { extract, normaliseContext, type Lang } from './extract.ts'
import { handleWebhook, isAuthorizedWebhook, syncEntitlement } from './entitlement.ts'
import {
	checkAISeconds,
	checkColourisations,
	checkPhotoCount,
	recordAISeconds,
	recordColourisation,
	reserveColourisation,
	reserveExtraction,
	reserveTranscription,
	usage,
} from './quota.ts'
import { notify, registerToken, unregisterToken } from './apns.ts'
import { pull, push } from './sync.ts'
import { transcribe } from './transcribe.ts'

export interface Env {
	DB: D1Database
	MEDIA: R2Bucket
	OPENROUTER_API_KEY: string
	MODEL_EXTRACT: string
	MODEL_EXTRACT_FALLBACK: string
	MODEL_TRANSCRIBE: string
	MODEL_COLOURISE: string
	RC_SECRET_KEY: string
	RC_PROJECT_ID: string
	RC_WEBHOOK_SECRET: string
	FREE_PHOTO_LIMIT: string
	FREE_AI_SECONDS_PER_MONTH: string
	FREE_COLOURISATIONS_PER_MONTH: string
	/// What the whole free tier may spend upstream in a UTC day, per route —
	/// not per family, because a family costs nothing to make (`quota.ts`).
	FREE_TIER_AI_SECONDS_PER_DAY: string
	FREE_TIER_EXTRACTION_TOKENS_PER_DAY: string
	FREE_TIER_COLOURISATIONS_PER_DAY: string
	RC_ENTITLEMENT_ID: string
	/// The two unauthenticated writes, metered. Optional on purpose — see
	/// `withinRateLimit`.
	FAMILY_JOIN_LIMIT?: RateLimit
	FAMILY_CREATE_LIMIT?: RateLimit
	/// Apple push: the .p8 key's contents, its key id and the team id.
	/// Optional — without all three the Worker notifies nobody and everything
	/// else runs unchanged (`apns.ts`).
	APNS_KEY_P8?: string
	APNS_KEY_ID?: string
	APNS_TEAM_ID?: string
}

const json = (data: unknown, status = 200) =>
	new Response(JSON.stringify(data), {
		status,
		headers: { 'content-type': 'application/json; charset=utf-8' },
	})

/// Errors never leak the model's or OpenRouter's text to the client: it can
/// contain account details or echo back the memory that was just told.
///
/// The log gets the name and the message rather than the whole error, and that
/// puts a rule on the messages themselves: AN ERROR MESSAGE MUST NOT
/// INTERPOLATE CONTENT — not a title, not a transcript, not a name. `message`
/// is the one field of a thrown error that reaches Workers Logs, and that is a
/// store beside D1 and R2 (PLAN.md §10). Upstream messages are the exception
/// that proves it: D1 and fetch describe schemas and connections, never what
/// anybody said.
function failure(err: unknown, route: string): Response {
	const detail = err instanceof Error ? `${err.name}: ${err.message}` : typeof err
	console.error(`[${route}] ${detail}`)
	return json({ error: 'upstream_failed' }, 502)
}

async function readJSON<T>(request: Request): Promise<T | null> {
	try {
		return (await request.json()) as T
	} catch {
		return null
	}
}

/// Audio is not accepted without limit. 25 MB is about an hour and a half of the
/// app's own recording, which is 4.5 kB/s (measured, ARCHITECTURE §5) — this
/// said three hours until 21 Sep 2026, a figure from before the measurement.
/// Far beyond most memories, and it stops a misbehaving client from sending a
/// gigabyte. It is also the length the output ceilings in `budget.ts` are
/// sized against.
const MAX_AUDIO_BYTES = 25 * 1024 * 1024

/// The same bound for a photograph sent to be coloured. The phone keeps its
/// photographs at 2048 px, measured at 340–990 kB (`media.ts`), so this is far
/// past any real one and exists for the misbehaving client.
const MAX_IMAGE_BYTES = 8 * 1024 * 1024

/// Meters the two routes that write without a member identity.
///
/// Every other route in this Worker needs one, so creating a family and joining
/// one are the only doors somebody who was never invited can knock on — and both
/// of them insert rows. The invite code carries 128 bits of entropy and is the
/// real protection against guessing (docs/ARCHITECTURE.md §4); this is the layer
/// above it, and it is aimed at the unmetered database write rather than at the
/// guess.
///
/// **A missing binding allows the request, loudly.** That is a deliberate choice
/// and the arguable one: failing closed would mean a single configuration
/// mistake stops every new family from being created, and the app is
/// deliberately vague about causes (rule 9 in CLAUDE.md) so nobody would ever
/// diagnose it from the phone. A rate limit that is off and says so beats an
/// archive nobody can join.
async function withinRateLimit(
	limiter: RateLimit | undefined,
	request: Request,
	what: string,
): Promise<boolean> {
	if (!limiter) {
		console.warn(`[ratelimit] no binding for ${what} — allowing the request unmetered`)
		return true
	}
	// Behind a home router the whole family shares one address, which is exactly
	// the case the limits are set generously enough for: a grandchild and a
	// grandmother joining from the same sofa are two of ten.
	const key = request.headers.get('CF-Connecting-IP') ?? 'unknown'
	const { success } = await limiter.limit({ key })
	return success
}

/// The language being SPOKEN, as the client reports it.
///
/// Not the language the app is being read in: an English-reading grandchild can
/// hold the phone while a Finnish grandmother talks into it, and what the prompt
/// and the hallucination ceiling need to know is who is talking. The app sends
/// its own answer to that; anything else is dropped rather than rejected, the
/// same way an out-of-range question level is, because losing a telling over a
/// bad field would be absurd. Absent means Finnish, so a client built before
/// this existed behaves exactly as it did.
function spokenLanguage(value: unknown): Lang {
	return value === 'en' ? 'en' : 'fi'
}

/// A subject id as the app sends one — a UUID the phone made — so a short
/// string and nothing else. Only the shape is checked here: whether a card by
/// that id exists, and whose it is, the family routes ask inside the very
/// statements that use it (`family.ts`).
function isSubjectID(value: unknown): value is string {
	return typeof value === 'string' && value.length > 0 && value.length <= 64
}

export default {
	async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
		const url = new URL(request.url)

		if (url.pathname === '/health') {
			return json({ ok: true, hasKey: Boolean(env.OPENROUTER_API_KEY) })
		}

		// --- Family and identity ---------------------------------------------
		//
		// These are checked before authentication, because they are precisely
		// the point where a member is created: the caller has no id yet.

		if (url.pathname === '/family' && request.method === 'POST') {
			if (!(await withinRateLimit(env.FAMILY_CREATE_LIMIT, request, 'family creation'))) {
				return json({ error: 'too_many_requests' }, 429)
			}
			const body = await readJSON<{
				memberID?: string
				secret?: string
				displayName?: string
				familyName?: string
				lang?: string
			}>(request)
			if (!body) return json({ error: 'invalid_json' }, 400)
			if (!body.memberID || !body.secret) return json({ error: 'missing_identity' }, 400)

			// Wrapped like every route with database work behind it: rule 9's
			// uniform shape holds only if a D1 exception cannot escape as a raw
			// Worker error. The same wrapper repeats on the family, usage and
			// quota routes below for the same reason.
			try {
				const result = await createFamily(env, {
					memberID: body.memberID,
					secret: body.secret,
					displayName: body.displayName ?? '',
					familyName: body.familyName ?? '',
					lang: spokenLanguage(body.lang),
				})
				return 'error' in result ? json(result, 409) : json(result)
			} catch (err) {
				return failure(err, 'family-create')
			}
		}

		if (url.pathname === '/family/join' && request.method === 'POST') {
			// Metered before the code is even read: the point is to stop the
			// database being written to by somebody who is guessing, and a guess
			// that gets as far as the lookup has already cost a query.
			if (!(await withinRateLimit(env.FAMILY_JOIN_LIMIT, request, 'joining a family'))) {
				return json({ error: 'too_many_requests' }, 429)
			}
			const body = await readJSON<{
				memberID?: string
				secret?: string
				displayName?: string
				code?: string
				lang?: string
			}>(request)
			if (!body) return json({ error: 'invalid_json' }, 400)
			if (!body.memberID || !body.secret || !body.code) {
				return json({ error: 'missing_fields' }, 400)
			}

			try {
				const result = await joinFamily(env, {
					memberID: body.memberID,
					secret: body.secret,
					displayName: body.displayName ?? '',
					code: body.code,
					lang: spokenLanguage(body.lang),
				})
				if ('error' in result) {
					return json(result, result.error === 'invalid_invite' ? 404 : 409)
				}
				return json(result)
			} catch (err) {
				return failure(err, 'family-join')
			}
		}

		// The webhook authenticates with its own secret rather than a member
		// identity: it comes from RevenueCat, not from a device.
		if (url.pathname === '/webhook/revenuecat' && request.method === 'POST') {
			if (!isAuthorizedWebhook(env, request)) return json({ error: 'unauthorized' }, 401)
			const body = await readJSON<{ event?: Record<string, unknown> }>(request)
			if (!body?.event) return json({ error: 'invalid_json' }, 400)
			try {
				return json(await handleWebhook(env, body.event))
			} catch (err) {
				return failure(err, 'webhook')
			}
		}

		// --- Routes that require authentication ------------------------------

		// Wrapped like everything downstream of it: this is the one D1 call
		// that runs before every route's own wrapper, and a database
		// exception here would escape as a raw Worker error ahead of rule
		// 9's uniform shape.
		let session: Awaited<ReturnType<typeof authenticate>>
		try {
			session = await authenticate(request, env)
		} catch (err) {
			return failure(err, 'auth')
		}

		if (url.pathname === '/family' && request.method === 'GET') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			try {
				const result = await getFamily(env, session)
				return 'error' in result ? json(result, 404) : json(result)
			} catch (err) {
				return failure(err, 'family-get')
			}
		}

		if (url.pathname === '/family/invite' && request.method === 'POST') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			// Optional, and a missing body is not an error: an invitation with
			// nobody's name on it is what this route made until now. The card it
			// is made for is optional the same way (13 Sep 2026).
			const body = await readJSON<{ displayName?: string; personSubjectID?: unknown }>(request)
			const card = body?.personSubjectID
			if (card !== undefined && card !== null && !isSubjectID(card)) {
				return json({ error: 'bad_request' }, 400)
			}
			try {
				const result = await createInvite(
					env,
					session,
					body?.displayName,
					isSubjectID(card) ? card : undefined,
				)
				return 'error' in result ? json(result, 400) : json(result)
			} catch (err) {
				return failure(err, 'invite-create')
			}
		}

		if (url.pathname === '/entitlement/sync' && request.method === 'POST') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			const body = await readJSON<{ customerID?: string }>(request)
			if (!body?.customerID) return json({ error: 'missing_customer' }, 400)
			try {
				const result = await syncEntitlement(env, session, body.customerID)
				if ('error' in result) {
					// A customer id that belongs to another family is a refused
					// claim, not an outage: 503 would invite the app to keep
					// retrying something that will never succeed.
					const conflict = result.error === 'customer_belongs_to_another_family'
					return json(result, conflict ? 409 : 503)
				}
				return json(result)
			} catch (err) {
				return failure(err, 'entitlement')
			}
		}

		if (url.pathname === '/usage' && request.method === 'GET') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			try {
				return json(await usage(env, session))
			} catch (err) {
				return failure(err, 'usage')
			}
		}

		if (url.pathname === '/sync' && request.method === 'GET') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			const since = Number(url.searchParams.get('since') ?? '0')
			try {
				return json(await pull(env, session, Number.isFinite(since) ? since : 0))
			} catch (err) {
				return failure(err, 'sync-pull')
			}
		}

		if (url.pathname === '/sync' && request.method === 'POST') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			const body = await readJSON<Parameters<typeof push>[2]>(request)
			if (!body) return json({ error: 'invalid_json' }, 400)
			try {
				const { notices, ...reply } = await push(env, session, body)
				// After the reply, never before it: a notification is a
				// courtesy, and APNs being slow or down must not hold up a sync.
				if (notices.length > 0) ctx.waitUntil(notify(env, session.familyID, notices))
				return json(reply)
			} catch (err) {
				return failure(err, 'sync-push')
			}
		}

		if (url.pathname === '/push/token' && (request.method === 'POST' || request.method === 'DELETE')) {
			if (!session) return json({ error: 'unauthorized' }, 401)
			const body = await readJSON<{ token?: unknown; environment?: unknown }>(request)
			if (!body) return json({ error: 'invalid_json' }, 400)
			try {
				const result =
					request.method === 'POST'
						? await registerToken(env, session, body.token, body.environment)
						: await unregisterToken(env, session, body.token)
				return 'error' in result ? json(result, 400) : json(result)
			} catch (err) {
				return failure(err, 'push-token')
			}
		}

		if (url.pathname === '/media' && request.method === 'POST') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			const kind = url.searchParams.get('kind') ?? 'photo'
			try {
				if (kind === 'photo') {
					const denial = await checkPhotoCount(env, session)
					if (denial) return json(denial, 402)
				}
				// Audio is not subject to the photo limit: the original audio
				// is always uploaded, free tier included, because it is the
				// core of the product. Nor is a confirmed colouring, whose
				// rounds were already counted on their way (`checkColourisations`).
				return await upload(env, session, kind, await request.arrayBuffer())
			} catch (err) {
				return failure(err, 'media-upload')
			}
		}

		if (url.pathname.startsWith('/media/') && request.method === 'GET') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			try {
				return await download(env, session, decodeURIComponent(url.pathname.slice('/media/'.length)))
			} catch (err) {
				return failure(err, 'media-download')
			}
		}

		// Leaving is not deletion: the memories stay with the family. The route
		// is on /family/me rather than /member, because what ends is the
		// membership and not the identity — that lives in the Keychain and is
		// cleared on the device.
		if (url.pathname === '/family/me' && request.method === 'DELETE') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			try {
				const result = await leaveFamily(env, session)
				return 'error' in result ? json(result, 409) : json(result)
			} catch (err) {
				return failure(err, 'family-leave')
			}
		}

		// One's own name, or one's own card in the tree (13 Sep 2026), changed.
		// The reply carries what was stored, so the app shows what the family
		// will see rather than what was sent.
		if (url.pathname === '/family/me' && request.method === 'PATCH') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			const body = await readJSON<{ displayName?: unknown; personSubjectID?: unknown }>(request)
			const name = body?.displayName
			const card = body?.personSubjectID
			// The key counts, not its value: `"personSubjectID": null` is how
			// unlinking is said, and it must not read as "no card sent".
			const linking = typeof body === 'object' && body !== null && 'personSubjectID' in body
			if (typeof name !== 'string' && !linking) return json({ error: 'bad_request' }, 400)
			if (linking && card !== null && !isSubjectID(card)) {
				return json({ error: 'bad_request' }, 400)
			}
			// Refused before anything is written, so a request carrying both
			// cannot come back 400 with the card already moved. The app sends one
			// at a time; the route does not lean on that.
			if (typeof name === 'string' && !name.trim()) return json({ error: 'empty_name' }, 400)
			try {
				const reply: { displayName?: string; personSubjectID?: string | null } = {}
				if (linking) {
					const linked = await linkMember(env, session, isSubjectID(card) ? card : null)
					if ('error' in linked) return json(linked, 400)
					reply.personSubjectID = linked.personSubjectID
				}
				if (typeof name === 'string') {
					const renamed = await renameMember(env, session, name)
					if ('error' in renamed) return json(renamed, 400)
					reply.displayName = renamed.displayName
				}
				return json(reply)
			} catch (err) {
				return failure(err, 'family-me')
			}
		}

		// The owner's remedy for an invitation that reached the wrong person.
		// Like leaving, it ends a membership and not an identity, and the
		// memories stay — see `removeMember`.
		if (url.pathname === '/family/member' && request.method === 'DELETE') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			const id = url.searchParams.get('id')
			if (!id) return json({ error: 'missing_id' }, 400)
			try {
				const result = await removeMember(env, session, id)
				return 'error' in result
					? json(result, result.error === 'not_owner' ? 403 : 404)
					: json(result)
			} catch (err) {
				return failure(err, 'member-remove')
			}
		}

		if (url.pathname === '/family/invite' && request.method === 'DELETE') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			const code = url.searchParams.get('code')
			if (!code) return json({ error: 'missing_code' }, 400)
			try {
				return json(await revokeInvite(env, session, code))
			} catch (err) {
				return failure(err, 'invite-revoke')
			}
		}

		if (request.method !== 'POST') return json({ error: 'not_found' }, 404)

		switch (url.pathname) {
			case '/transcribe': {
				let payload: { audio?: string; format?: string; seconds?: number; lang?: string }
				try {
					payload = await request.json()
				} catch {
					return json({ error: 'invalid_json' }, 400)
				}
				// `typeof`, not truthiness. The field is typed `string` and
				// arrives from `request.json()`, so a number gets through the
				// old check with `.length` undefined — and `boundedSeconds`
				// then divides by undefined and hands back the NaN that turns
				// the hallucination ceiling off. Both halves of that hole are
				// closed, here and in `budget.ts`.
				if (typeof payload.audio !== 'string' || !payload.audio) {
					return json({ error: 'missing_audio' }, 400)
				}

				// Base64 inflates the size by roughly a third.
				if (payload.audio.length > MAX_AUDIO_BYTES * 1.37) {
					return json({ error: 'audio_too_large' }, 413)
				}

				if (!session) return json({ error: 'unauthorized' }, 401)

				// The duration the client claims, clamped to what the bytes can
				// hold. Used for all three of the things that trusted the raw
				// field — the meter, the hallucination ceiling and the token
				// budget — so there is one number and no way to charge one
				// duration while budgeting another. See `boundedSeconds`.
				const seconds = boundedSeconds(payload.seconds, payload.audio.length)

				try {
					// The quota is checked BEFORE the expensive call. If the
					// limit is reached, the app saves the audio anyway and
					// transcribes it later — the recording is never discarded.
					//
					// Inside the wrapper, like `/media`'s `checkPhotoCount`
					// and unlike its own previous self. Two D1 reads live in
					// here, and outside the `try` a database hiccup escaped
					// the handler entirely: the runtime answered a bare 500
					// instead of rule 9's one shape, which is the shape the
					// app, `RemoteError` and the rule are all written against.
					const denial = await checkAISeconds(env, session, seconds)
					if (denial) return json(denial, 402)

					// The free tier's day, after the family's own month and
					// before the model: a family whose month is spent is told
					// so by its meter and spends none of anybody's day. A
					// refusal keeps the audio like any moment's failure does,
					// and the text follows on a later day (`reserveTranscription`).
					if (!(await reserveTranscription(env, session, payload.audio.length))) {
						return json({ error: 'too_many_requests' }, 429)
					}

					const text = await transcribe(
						env,
						payload.audio,
						payload.format ?? 'm4a',
						seconds,
						spokenLanguage(payload.lang),
					)

					// The meter is written with the words already in hand, and
					// it is not allowed to take them away.
					//
					// It used to be an ordinary `await` inside this try, so a
					// D1 failure on the counter turned a transcription that
					// had SUCCEEDED — and had already been paid for upstream —
					// into a 502 with the text discarded. The app then counted
					// that against the recording (`isAboutTheMoment` puts a
					// 5xx on the recording's side), uploaded the same audio
					// again, paid again, and after three rounds gave up on a
					// transcript it had held twice.
					//
					// So the failure is recorded and swallowed. Under-counting
					// a family's minutes is a cost this project can carry;
					// losing what somebody just said is the one it cannot.
					try {
						await recordAISeconds(env, session, seconds)
					} catch (err) {
						const detail = err instanceof Error ? `${err.name}: ${err.message}` : typeof err
						console.error(`[transcribe] the meter refused the seconds — ${detail}`)
					}

					return json({ text })
				} catch (err) {
					return failure(err, 'transcribe')
				}
			}

			case '/extract': {
				let payload: {
					lang?: string
					transcript?: string
					corrections?: { from?: string; to?: string }[]
					level?: number
					context?: unknown
					image?: unknown
				}
				try {
					payload = await request.json()
				} catch {
					return json({ error: 'invalid_json' }, 400)
				}
				const transcript = payload.transcript?.trim()
				if (!transcript) return json({ error: 'missing_transcript' }, 400)

				// The one route that had no identity check at all — which, on a
				// public URL, is an open model call billed to rule 7's key. No
				// family's meter counts it, on purpose (a typed memory must
				// always save, quota or not); unmetered and unauthenticated are
				// different promises, and only the first was meant. The free
				// tier's day below bounds the bill without touching that
				// promise: the memory is saved through `/sync` whatever this
				// route answers.
				if (!session) return json({ error: 'unauthorized' }, 401)

				// Empty and no-op corrections are stripped so that no noise
				// reaches the prompt and merely confuses the model.
				const corrections = (payload.corrections ?? [])
					.map((c) => ({ from: (c.from ?? '').trim(), to: (c.to ?? '').trim() }))
					.filter((c) => c.from && c.to && c.from !== c.to)
					.slice(0, 20)

				// Where the teller is on the question ladder. Nonsense is
				// dropped rather than rejected: an unaimed question is still a
				// question, and losing the memory over it would be absurd.
				const level =
					typeof payload.level === 'number' && payload.level >= 1 && payload.level <= 5
						? Math.round(payload.level)
						: undefined

				// What the archive already holds, so a follow-up question can aim
				// at a hole rather than at the speech. Shaped and capped in
				// `normaliseContext`; anything unrecognised is dropped rather
				// than repaired, because a context that cannot be trusted is
				// still an extraction that must succeed.
				const context = normaliseContext(payload.context)

				// The photograph, on the same call. Same two guards as
				// `/colourise`: the JPEG magic bytes, which are "/9j/" in
				// base64, and the size cap. A picture that fails either is
				// dropped rather than refused — the memory has already been
				// spoken, and losing it over a thumbnail would be absurd.
				if (
					typeof payload.image === 'string' &&
					payload.image.startsWith('/9j/') &&
					payload.image.length <= MAX_IMAGE_BYTES * 1.37
				) {
					context.image = payload.image
				}

				try {
					// The free tier's day, charged by what this call may read
					// and write (`reserveExtraction`). Refused, the telling
					// lands in its teller's own words — the road an outage
					// already takes on the phone.
					if (!(await reserveExtraction(env, session, transcript, corrections, spokenLanguage(payload.lang)))) {
						return json({ error: 'too_many_requests' }, 429)
					}
					return json(
						await extract(env, transcript, corrections, level, spokenLanguage(payload.lang), context),
					)
				} catch (err) {
					return failure(err, 'extract')
				}
			}

			case '/colourise': {
				let payload: { image?: unknown; told?: unknown; aspect?: unknown }
				try {
					payload = await request.json()
				} catch {
					return json({ error: 'invalid_json' }, 400)
				}
				// A JPEG, recognised by its first bytes: FF D8 FF is "/9j/" in
				// base64. Every photograph is stored as one (`media.ts`), and the
				// data URL this becomes has to name the type it carries.
				if (typeof payload.image !== 'string' || !payload.image.startsWith('/9j/')) {
					return json({ error: 'missing_image' }, 400)
				}
				if (payload.image.length > MAX_IMAGE_BYTES * 1.37) {
					return json({ error: 'image_too_large' }, 413)
				}
				// Coloured by what was told, or not at all. A photograph nobody has
				// said anything about would be painted by the model's guess alone,
				// and a guess in the shape of a photograph is the one thing rule 4
				// cannot let this route make.
				const told = toldText(payload.told)
				if (!told) return json({ error: 'missing_told' }, 400)

				if (!session) return json({ error: 'unauthorized' }, 401)

				try {
					const denial = await checkColourisations(env, session)
					if (denial) return json(denial, 402)

					// The free tier's day, after the month for the reason
					// `/transcribe` gives (`reserveColourisation`).
					if (!(await reserveColourisation(env, session))) {
						return json({ error: 'too_many_requests' }, 429)
					}

					const image = await colourise(env, payload.image, told, aspectRatio(payload.aspect))

					// Counted with the image in hand and not allowed to take it
					// away, for the transcription meter's reason above: the round
					// is already paid for upstream, and asking the app to repeat
					// it would pay for it twice.
					try {
						await recordColourisation(env, session)
					} catch (err) {
						const detail = err instanceof Error ? `${err.name}: ${err.message}` : typeof err
						console.error(`[colourise] the meter refused the round — ${detail}`)
					}

					return json({ image: image.data, type: image.type })
				} catch (err) {
					return failure(err, 'colourise')
				}
			}

			default:
				return json({ error: 'not_found' }, 404)
		}
	},
} satisfies ExportedHandler<Env>
