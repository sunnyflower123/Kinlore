/// Memorize — Cloudflare Worker.
///
/// Workerin tehtävä on pitää API-avain poissa sovelluksesta. IPA-tiedoston
/// purkaminen on triviaalia, ja vuotanut avain on opiskelijan budjetilla oikea
/// lasku. Siksi ääni ja teksti kulkevat aina täältä.

import { extract } from './extract'
import { transcribe } from './transcribe'

export interface Env {
	DB: D1Database
	MEDIA: R2Bucket
	OPENROUTER_API_KEY: string
	MODEL_EXTRACT: string
	MODEL_EXTRACT_FALLBACK: string
	MODEL_TRANSCRIBE: string
	FREE_PHOTO_LIMIT: string
	FREE_AI_SECONDS_PER_MONTH: string
	RC_ENTITLEMENT_ID: string
}

const json = (data: unknown, status = 200) =>
	new Response(JSON.stringify(data), {
		status,
		headers: { 'content-type': 'application/json; charset=utf-8' },
	})

/// Virheet eivät koskaan vuoda mallin tai OpenRouterin tekstiä asiakkaalle:
/// se voi sisältää tilin tietoja tai toistaa käyttäjän kertoman muiston.
function failure(err: unknown, route: string): Response {
	console.error(`[${route}]`, err)
	return json({ error: 'upstream_failed' }, 502)
}

/// Ääntä ei oteta rajattomasti vastaan. 25 MB on noin 3 tuntia puhetta tällä
/// pakkauksella — reilusti yli minkään yksittäisen muiston, mutta estää sen
/// että väärin toiminut asiakas lähettää gigatavun.
const MAX_AUDIO_BYTES = 25 * 1024 * 1024

export default {
	async fetch(request: Request, env: Env): Promise<Response> {
		const url = new URL(request.url)

		if (url.pathname === '/health') {
			return json({ ok: true, hasKey: Boolean(env.OPENROUTER_API_KEY) })
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

				// Base64 kasvattaa kokoa noin kolmanneksella.
				if (payload.audio.length > MAX_AUDIO_BYTES * 1.37) {
					return json({ error: 'audio_too_large' }, 413)
				}

				try {
					const text = await transcribe(
						env,
						payload.audio,
						payload.format ?? 'm4a',
						payload.seconds,
					)
					return json({ text })
				} catch (err) {
					return failure(err, 'transcribe')
				}
			}

			case '/extract': {
				let payload: {
					transcript?: string
					corrections?: { from?: string; to?: string }[]
				}
				try {
					payload = await request.json()
				} catch {
					return json({ error: 'invalid_json' }, 400)
				}
				const transcript = payload.transcript?.trim()
				if (!transcript) return json({ error: 'missing_transcript' }, 400)

				// Tyhjät ja muuttumattomat korjaukset siivotaan pois, jottei
				// promptiin päädy kohinaa joka vain sekoittaa mallia.
				const corrections = (payload.corrections ?? [])
					.map((c) => ({ from: (c.from ?? '').trim(), to: (c.to ?? '').trim() }))
					.filter((c) => c.from && c.to && c.from !== c.to)
					.slice(0, 20)

				try {
					return json(await extract(env, transcript, corrections))
				} catch (err) {
					return failure(err, 'extract')
				}
			}

			default:
				return json({ error: 'not_found' }, 404)
		}
	},
} satisfies ExportedHandler<Env>
