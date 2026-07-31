/// OpenRouter client.
///
/// One key covers both transcription and extraction: OpenRouter accepts audio
/// input as `input_audio` parts of chat completions, so no separate ASR service
/// is needed.

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

type CallOptions = {
	model: string
	temperature?: number
	/// JSON Schema. When given, the model is forced into the structure.
	schema?: { name: string; schema: unknown }
	/// Without this the route's default is used, which can be surprisingly low.
	/// A truncated response looks like invalid JSON, which sends you the wrong way.
	maxTokens?: number
}

export async function complete(env: Env, messages: Message[], opts: CallOptions): Promise<string> {
	const key = env.OPENROUTER_API_KEY
	if (!key) throw new UpstreamError(401, false)

	const body: Record<string, unknown> = {
		model: opts.model,
		messages,
		temperature: opts.temperature ?? 0.3,
		// Opting out of data collection is UNCONDITIONAL, not a per-call choice.
		// This is a family's memories of dead relatives — the content is more
		// sensitive than almost anything else a user could write. As a flag it
		// would be forgotten somewhere.
		provider: { data_collection: 'deny' },
	}

	if (opts.maxTokens) body.max_tokens = opts.maxTokens

	if (opts.schema) {
		body.response_format = {
			type: 'json_schema',
			json_schema: { name: opts.schema.name, strict: true, schema: opts.schema.schema },
		}
		// Without this the request can be routed to a provider that does not
		// support structured output, in which case the reply is free text and
		// parsing fails at random.
		;(body.provider as Record<string, unknown>).require_parameters = true
	}

	const res = await fetch(API_URL, {
		method: 'POST',
		headers: {
			Authorization: `Bearer ${key}`,
			'Content-Type': 'application/json',
			'HTTP-Referer': 'https://github.com/memorize-app',
			'X-Title': 'Memorize',
		},
		body: JSON.stringify(body),
	})

	if (!res.ok) {
		// The body goes to the LOG ONLY: it can contain the account balance or
		// model output echoing back the memory the user just told. The caller
		// gets nothing but the status.
		const text = await res.text().catch(() => '')
		console.error(`[openrouter] ${opts.model} HTTP ${res.status}: ${text.slice(0, 300)}`)
		throw new UpstreamError(res.status)
	}

	const data = (await res.json()) as {
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
