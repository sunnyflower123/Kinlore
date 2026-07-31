/// OpenRouter-klientti.
///
/// Yksi avain kattaa sekä puheen purun että jäsennyksen: OpenRouter tukee
/// äänisyötettä chat completionsin `input_audio`-osina, joten erillistä
/// ASR-palvelua ei tarvita.

import type { Env } from './worker'

const API_URL = 'https://openrouter.ai/api/v1/chat/completions'

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
	/// JSON Schema. Kun annettu, malli pakotetaan rakenteeseen.
	schema?: { name: string; schema: unknown }
	/// Ilman tätä käytetään reitin oletusta, joka voi olla yllättävän matala.
	/// Katkennut vastaus näkyy kelvottomana JSONina, mikä johtaa harhaan.
	maxTokens?: number
}

export async function complete(env: Env, messages: Message[], opts: CallOptions): Promise<string> {
	const key = env.OPENROUTER_API_KEY
	if (!key) throw new Error('OPENROUTER_API_KEY puuttuu')

	const body: Record<string, unknown> = {
		model: opts.model,
		messages,
		temperature: opts.temperature ?? 0.3,
		// Keruunesto on EHDOTON, ei kutsukohtainen valinta. Tämä on perheen
		// muistoja kuolleista sukulaisista — sisältö on arkaluontoisempaa kuin
		// lähes mikään muu mitä käyttäjä voisi kirjoittaa. Lippuna se unohtuisi.
		provider: { data_collection: 'deny' },
	}

	if (opts.maxTokens) body.max_tokens = opts.maxTokens

	if (opts.schema) {
		body.response_format = {
			type: 'json_schema',
			json_schema: { name: opts.schema.name, strict: true, schema: opts.schema.schema },
		}
		// Ilman tätä pyyntö voi reitittyä tarjoajalle joka ei tue rakennetta,
		// jolloin vastaus on vapaata tekstiä ja jäsennys kaatuu satunnaisesti.
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
		// Runko VAIN lokiin: se voi sisältää tilin saldon tai mallin tulostetta
		// joka toistaa käyttäjän kertoman muiston. Kutsuja saa vain statuksen.
		const text = await res.text().catch(() => '')
		console.error(`[openrouter] ${opts.model} HTTP ${res.status}: ${text.slice(0, 300)}`)
		throw new Error(`OpenRouter HTTP ${res.status}`)
	}

	const data = (await res.json()) as {
		choices?: { message?: { content?: string }; finish_reason?: string }[]
	}
	const choice = data.choices?.[0]
	const content = choice?.message?.content
	if (!content?.trim()) throw new Error('OpenRouter palautti tyhjän vastauksen')

	// Osittainen vastaus on tunnistettavasti rikki, joten se hylätään heti sen
	// sijaan että sitä yritettäisiin jäsentää. "error" tarkoittaa että tarjoaja
	// kaatui kesken generoinnin, "length" että tokenraja katkaisi. Molemmissa
	// sisältö on keskeneräistä — ilman tätä tarkistusta vika näyttää skeeman
	// rikkomiselta ja johtaa etsimään sitä väärästä paikasta.
	const reason = choice?.finish_reason
	if (reason && reason !== 'stop') {
		console.warn(`[openrouter] ${opts.model} finish_reason=${reason} — vastaus hylätään`)
		throw new Error(`OpenRouter keskeytti: ${reason}`)
	}

	return content
}
