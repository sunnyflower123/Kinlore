/// OpenRouter client.
///
/// One key covers transcription, extraction and colourisation: OpenRouter
/// accepts audio as `input_audio` parts and photographs as `image_url` parts of
/// chat completions, and an image model answers in the same reply shape, so no
/// separate ASR or image service is needed.

import type { Env } from './worker'

const API_URL = 'https://openrouter.ai/api/v1/chat/completions'

/// An upstream error that knows whether retrying is worth it.
///
/// The distinction matters: running out of credits (402) or a bad key (401) does
/// not fix itself by waiting, and three attempts only make the failure three
/// times slower. Rate limiting (429) and server errors do recover.
export class UpstreamError extends Error {
	readonly status: number
	readonly retryable: boolean

	constructor(status: number, retryable?: boolean) {
		super(`OpenRouter HTTP ${status}`)
		this.status = status
		this.retryable = retryable ?? (status === 429 || status >= 500)
	}
}

export type Message = {
	role: 'system' | 'user'
	content: string | ContentPart[]
}

type ContentPart =
	| { type: 'text'; text: string }
	| { type: 'input_audio'; input_audio: { data: string; format: string } }
	| { type: 'image_url'; image_url: { url: string } }

type CallOptions = {
	model: string
	temperature?: number
	/// JSON Schema. When given, the model is forced into the structure.
	schema?: { name: string; schema: unknown }
	/// Without this the route's default is used, which can be surprisingly low.
	/// A truncated response looks like invalid JSON, which sends you the wrong way.
	maxTokens?: number
	/// A ceiling on the model's hidden reasoning, which `maxTokens` counts
	/// too. Without it a thinking model can spend the whole budget before
	/// writing a word (`REASONING_BUDGET` in budget.ts).
	reasoningTokens?: number
}

export async function complete(env: Env, messages: Message[], opts: CallOptions): Promise<string> {
	const body: Record<string, unknown> = {
		model: opts.model,
		messages,
		temperature: opts.temperature ?? 0.3,
	}

	if (opts.maxTokens) body.max_tokens = opts.maxTokens
	if (opts.reasoningTokens) body.reasoning = { max_tokens: opts.reasoningTokens }

	if (opts.schema) {
		body.response_format = {
			type: 'json_schema',
			json_schema: { name: opts.schema.name, strict: true, schema: opts.schema.schema },
		}
	}

	// A schema also asks for `require_parameters`: without it the request can be
	// routed to a provider that does not support structured output, in which
	// case the reply is free text and parsing fails at random.
	const data = (await send(env, body, { requireParameters: Boolean(opts.schema) })) as {
		choices?: { message?: { content?: string }; finish_reason?: string }[]
	}
	const choice = data.choices?.[0]
	const content = choice?.message?.content
	if (!content?.trim()) throw new UpstreamError(502, true)

	// A partial response is recognisably broken, so it is rejected outright
	// rather than parsed. "error" means the provider crashed mid-generation,
	// "length" that the token limit cut it off. In both cases the content is
	// incomplete — without this check the fault looks like a schema violation
	// and sends you looking in the wrong place.
	const reason = choice?.finish_reason
	if (reason && reason !== 'stop') {
		console.warn(`[openrouter] ${opts.model} finish_reason=${reason} — response rejected`)
		throw new UpstreamError(503, true)
	}

	return content
}

/// A photograph and an instruction in, a photograph out.
///
/// The image comes back in the same chat-completions reply that words do, as a
/// data URL under `message.images` with `content` null — measured 13 Sep 2026
/// on four image models through this endpoint, all four in that one shape. The
/// reply also carries a reasoning signature of about two megabytes, which
/// nothing here reads.
export async function completeImage(
	env: Env,
	messages: Message[],
	opts: { model: string; aspectRatio?: string },
): Promise<{ type: string; data: string }> {
	const body: Record<string, unknown> = {
		model: opts.model,
		messages,
		modalities: ['image', 'text'],
	}
	if (opts.aspectRatio) body.image_config = { aspect_ratio: opts.aspectRatio }

	return imageFromReply(await send(env, body), opts.model)
}

type ImageReply = {
	choices?: {
		message?: { content?: unknown; images?: { image_url?: { url?: unknown } }[] }
		finish_reason?: string
	}[]
}

/// What the Worker is willing to believe an image model returned: one image, of
/// an image type, from a generation that finished.
///
/// A refusal arrives as words instead of a picture, and those words can quote
/// what the family told — so the log gets how many characters there were and
/// the finish reason, which is a fixed vocabulary, and never the words.
export function imageFromReply(reply: unknown, model: string): { type: string; data: string } {
	const choice = (reply as ImageReply | null)?.choices?.[0]
	const url = choice?.message?.images?.[0]?.image_url?.url
	const reason = choice?.finish_reason

	if (typeof url === 'string' && (!reason || reason === 'stop')) {
		const comma = url.indexOf(',')
		const type = comma > 0 ? /^data:(image\/(?:jpeg|png|webp));base64$/.exec(url.slice(0, comma))?.[1] : undefined
		const data = url.slice(comma + 1)
		if (type && data) return { type, data }
	}

	const text = choice?.message?.content
	console.error(
		`[openrouter] ${model} returned no usable image — finish_reason=${reason ?? 'none'}, ` +
			`${typeof text === 'string' ? text.length : 0} characters of text`,
	)
	throw new UpstreamError(502)
}

/// The one door every request leaves through, so that the key, the headers and
/// rule 8 exist once.
///
/// Opting out of data collection is UNCONDITIONAL, not a per-call choice. This
/// is a family's memories of dead relatives — the content is more sensitive
/// than almost anything else a user could write. As a flag it would be
/// forgotten somewhere, and since 13 Sep 2026 there are two request shapes
/// rather than one, so it lives here and in neither of them. It is built fresh
/// for every request and set after the body, which is what keeps a caller's own
/// `provider` from being sent and one call's `require_parameters` from riding
/// along on the next.
async function send(
	env: Env,
	body: Record<string, unknown>,
	options: { requireParameters?: boolean } = {},
): Promise<unknown> {
	const key = env.OPENROUTER_API_KEY
	if (!key) throw new UpstreamError(401, false)

	const provider: Record<string, unknown> = { data_collection: 'deny' }
	if (options.requireParameters) provider.require_parameters = true

	const res = await fetch(API_URL, {
		method: 'POST',
		headers: {
			Authorization: `Bearer ${key}`,
			'Content-Type': 'application/json',
			'HTTP-Referer': 'https://github.com/sunnyflower123/Kinlore',
			'X-Title': 'Kinlore',
		},
		body: JSON.stringify({ ...body, provider }),
	})

	if (!res.ok) {
		// Not the body, in either direction. It was going to the log only, so
		// nothing leaked to the client — but it can carry the account balance,
		// and on several provider errors it quotes the request back, which here
		// is the audio, the photograph or the memory that was just told. Workers
		// Logs is a store beside D1 and R2 (PLAN.md §10), so the log gets the
		// status and the provider's own error code and stops there.
		const code = await errorCode(res)
		console.error(`[openrouter] ${String(body.model)} HTTP ${res.status}${code ? ` ${code}` : ''}`)
		throw new UpstreamError(res.status)
	}

	return res.json()
}

/// The provider's own error code, when the body is the documented error shape.
///
/// The code is a fixed vocabulary and says what went wrong; the `message` beside
/// it is free text and is the field that quotes the request back, so it is read
/// past rather than logged. A body that is not that shape yields nothing at all,
/// because the status alone is a truer signal than a guess at what is in it.
async function errorCode(res: Response): Promise<string | null> {
	try {
		const body = (await res.json()) as { error?: { code?: unknown; type?: unknown } }
		const code = body.error?.code ?? body.error?.type
		return typeof code === 'string' || typeof code === 'number' ? String(code) : null
	} catch {
		return null
	}
}
