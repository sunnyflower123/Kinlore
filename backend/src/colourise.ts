/// The colours of an old photograph, painted by what the family told about it.
///
/// A black-and-white photograph holds no colours to bring back, and a model
/// that adds them is guessing. So this does not guess on its own: the route
/// refuses a photograph nobody has told anything about, the tellings are quoted
/// to the model verbatim, and what comes back is a proposal — the phone decides
/// what is kept, and only after a person has looked at it (rule 4).
///
/// Nothing is stored here. The photograph and the words pass through to the
/// model and back, the way a recording passes through transcription.

import { completeImage } from './openrouter.ts'
import type { Env } from './worker'

/// The instruction. In English whatever language the family spoke, because it
/// is addressed to the model; their own words go beneath it untranslated, since
/// a translation would be one more place for "tummanvihreä" to become something
/// else.
///
/// The first four sentences are what was measured on 13 Sep 2026 — one
/// synthetic photograph, a Finnish telling — where the told colours were
/// followed and the edges stayed where they were. The last was added after, for
/// the round that corrects a colour, and has not been measured.
const INSTRUCTION = [
	'Colourise this black-and-white photograph.',
	'Change only the colours: keep every shape, edge, face, position and the framing exactly as they are.',
	'Do not crop, zoom, reframe, add, remove or retouch anything. Use natural, realistic colours.',
	'The family remembers the details quoted below. Follow them exactly, and choose plausible colours for everything they do not mention.',
	'When two quotations disagree, the first one is the most recent and is the one to follow.',
].join(' ')

/// Bounds what a client can make the model read. Eight thousand characters is
/// several long tellings — about two thousand tokens, a twentieth of a cent at
/// the lite model's input price — and the colour in any of them is rarely more
/// than a sentence.
const MAX_TOLD_CHARACTERS = 8000

/// The aspect ratios the image model accepts, read from its OpenRouter endpoint
/// record on 13 Sep 2026. Anything else is dropped rather than forwarded, and no
/// ratio at all leaves the model to follow the photograph's own shape — which
/// it did on the measured run, 1200 × 896 in and out.
const ASPECT_RATIOS = new Set([
	'1:1', '1:4', '1:8', '2:3', '3:2', '3:4', '4:1', '4:3', '4:5', '5:4', '8:1', '9:16', '16:9', '21:9',
])

/// What was told, as the model reads it: each telling a quotation of its own,
/// trimmed, empty ones dropped, in the order the phone sent them — newest
/// first — and cut at the cap.
export function toldText(value: unknown): string {
	if (!Array.isArray(value)) return ''
	return value
		.filter((telling): telling is string => typeof telling === 'string')
		.map((telling) => telling.trim())
		.filter(Boolean)
		.map((telling) => `"${telling}"`)
		.join('\n\n')
		.slice(0, MAX_TOLD_CHARACTERS)
}

/// The ratio to ask for, when the phone sent one the model knows.
export function aspectRatio(value: unknown): string | undefined {
	return typeof value === 'string' && ASPECT_RATIOS.has(value) ? value : undefined
}

export async function colourise(
	env: Env,
	jpegBase64: string,
	told: string,
	aspect?: string,
): Promise<{ type: string; data: string }> {
	return completeImage(
		env,
		[
			{
				role: 'user',
				content: [
					{ type: 'text', text: `${INSTRUCTION}\n\n${told}` },
					{ type: 'image_url', image_url: { url: `data:image/jpeg;base64,${jpegBase64}` } },
				],
			},
		],
		{ model: env.MODEL_COLOURISE, aspectRatio: aspect },
	)
}
