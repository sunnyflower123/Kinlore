/// Kinlore — Cloudflare Worker.
///
/// The Worker exists to keep the API key out of the app. Unpacking an IPA is
/// trivial, and a leaked key is a real bill on a student budget. That is why
/// audio and text always travel through here.

import { authenticate } from './auth'
import {
	createFamily,
	createInvite,
	getFamily,
	joinFamily,
	leaveFamily,
	revokeInvite,
} from './family'
import { download, upload } from './media'
import { extract } from './extract'
import { handleWebhook, isAuthorizedWebhook, syncEntitlement } from './entitlement'
import { checkAISeconds, checkPhotoCount, recordAISeconds, usage } from './quota'
import { pull, push } from './sync'
import { transcribe } from './transcribe'

export interface Env {
	DB: D1Database
	MEDIA: R2Bucket
	OPENROUTER_API_KEY: string
	MODEL_EXTRACT: string
	MODEL_EXTRACT_FALLBACK: string
	MODEL_TRANSCRIBE: string
	RC_SECRET_KEY: string
	RC_PROJECT_ID: string
	RC_WEBHOOK_SECRET: string
	FREE_PHOTO_LIMIT: string
	FREE_AI_SECONDS_PER_MONTH: string
	RC_ENTITLEMENT_ID: string
	/// The two unauthenticated writes, metered. Optional on purpose — see
	/// `withinRateLimit`.
	FAMILY_JOIN_LIMIT?: RateLimit
	FAMILY_CREATE_LIMIT?: RateLimit
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

/// Audio is not accepted without limit. 25 MB is about 3 hours of speech at this
/// compression — far beyond any single memory, but it stops a misbehaving client
/// from sending a gigabyte.
const MAX_AUDIO_BYTES = 25 * 1024 * 1024

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

export default {
	async fetch(request: Request, env: Env): Promise<Response> {
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
			}>(request)
			if (!body) return json({ error: 'invalid_json' }, 400)
			if (!body.memberID || !body.secret) return json({ error: 'missing_identity' }, 400)

			const result = await createFamily(env, {
				memberID: body.memberID,
				secret: body.secret,
				displayName: body.displayName ?? '',
				familyName: body.familyName ?? '',
			})
			return 'error' in result ? json(result, 409) : json(result)
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
			}>(request)
			if (!body) return json({ error: 'invalid_json' }, 400)
			if (!body.memberID || !body.secret || !body.code) {
				return json({ error: 'missing_fields' }, 400)
			}

			const result = await joinFamily(env, {
				memberID: body.memberID,
				secret: body.secret,
				displayName: body.displayName ?? '',
				code: body.code,
			})
			if ('error' in result) {
				return json(result, result.error === 'invalid_invite' ? 404 : 409)
			}
			return json(result)
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

		const session = await authenticate(request, env)

		if (url.pathname === '/family' && request.method === 'GET') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			const result = await getFamily(env, session)
			return 'error' in result ? json(result, 404) : json(result)
		}

		if (url.pathname === '/family/invite' && request.method === 'POST') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			return json(await createInvite(env, session))
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
			return json(await usage(env, session))
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
				return json(await push(env, session, body))
			} catch (err) {
				return failure(err, 'sync-push')
			}
		}

		if (url.pathname === '/media' && request.method === 'POST') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			const kind = url.searchParams.get('kind') ?? 'photo'
			if (kind === 'photo') {
				const denial = await checkPhotoCount(env, session)
				if (denial) return json(denial, 402)
			}
			// Audio is not subject to the photo limit: the original audio is
			// always uploaded, free tier included, because it is the core of
			// the product.
			try {
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
			const result = await leaveFamily(env, session)
			return 'error' in result ? json(result, 409) : json(result)
		}

		if (url.pathname === '/family/invite' && request.method === 'DELETE') {
			if (!session) return json({ error: 'unauthorized' }, 401)
			const code = url.searchParams.get('code')
			if (!code) return json({ error: 'missing_code' }, 400)
			return json(await revokeInvite(env, session, code))
		}

		if (request.method !== 'POST') return json({ error: 'not_found' }, 404)

		switch (url.pathname) {
			case '/transcribe': {
				let payload: { audio?: string; format?: string; seconds?: number }
				try {
					payload = await request.json()
				} catch {
					return json({ error: 'invalid_json' }, 400)
				}
				if (!payload.audio) return json({ error: 'missing_audio' }, 400)

				// Base64 inflates the size by roughly a third.
				if (payload.audio.length > MAX_AUDIO_BYTES * 1.37) {
					return json({ error: 'audio_too_large' }, 413)
				}

				if (!session) return json({ error: 'unauthorized' }, 401)

				// The quota is checked BEFORE the expensive call. If the limit
				// is reached, the app saves the audio anyway and transcribes it
				// later — the recording is never discarded.
				const denial = await checkAISeconds(env, session, payload.seconds ?? 0)
				if (denial) return json(denial, 402)

				try {
					const text = await transcribe(
						env,
						payload.audio,
						payload.format ?? 'm4a',
						payload.seconds,
					)
					await recordAISeconds(env, session, payload.seconds ?? 0)
					return json({ text })
				} catch (err) {
					return failure(err, 'transcribe')
				}
			}

			case '/extract': {
				let payload: {
					transcript?: string
					corrections?: { from?: string; to?: string }[]
					level?: number
				}
				try {
					payload = await request.json()
				} catch {
					return json({ error: 'invalid_json' }, 400)
				}
				const transcript = payload.transcript?.trim()
				if (!transcript) return json({ error: 'missing_transcript' }, 400)

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

				try {
					return json(await extract(env, transcript, corrections, level))
				} catch (err) {
					return failure(err, 'extract')
				}
			}

			default:
				return json({ error: 'not_found' }, 404)
		}
	},
} satisfies ExportedHandler<Env>
