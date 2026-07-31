/// Storing photos and audio in R2.
///
/// The file passes through the Worker. A downscaled photo is about 300 kB and 90
/// seconds of audio about 200 kB, so presigned URLs would add moving parts
/// without benefit. See docs/ARCHITECTURE.md §5.

import type { Session } from './auth'
import type { Env } from './worker'

/// Upper bound for a single file. Photos are downscaled to 2048 px on the
/// client, and even the longest memory fits into this many times over.
const MAX_BYTES = 10 * 1024 * 1024

const TYPES: Record<string, { ext: string; contentType: string }> = {
	photo: { ext: 'jpg', contentType: 'image/jpeg' },
	audio: { ext: 'm4a', contentType: 'audio/mp4' },
}

/// The key always starts with the family id. Access is still checked from the
/// session rather than the key — the prefix makes the check simple, but it is
/// not what provides the security: the caller's family decides.
function keyFor(familyID: string, kind: string): string {
	return `${familyID}/${crypto.randomUUID()}.${TYPES[kind].ext}`
}

export async function upload(
	env: Env,
	session: Session,
	kind: string,
	body: ArrayBuffer,
): Promise<Response> {
	const type = TYPES[kind]
	if (!type) {
		return new Response(JSON.stringify({ error: 'unknown_kind' }), { status: 400 })
	}
	if (body.byteLength === 0 || body.byteLength > MAX_BYTES) {
		return new Response(JSON.stringify({ error: 'bad_size' }), { status: 413 })
	}

	const key = keyFor(session.familyID, kind)
	await env.MEDIA.put(key, body, {
		httpMetadata: { contentType: type.contentType },
		customMetadata: { familyID: session.familyID, uploadedBy: session.memberID },
	})

	return new Response(JSON.stringify({ key }), {
		headers: { 'content-type': 'application/json; charset=utf-8' },
	})
}

export async function download(env: Env, session: Session, key: string): Promise<Response> {
	// The family prefix is checked before the R2 call: guessing another family's
	// key must not even cause a lookup.
	if (!key.startsWith(`${session.familyID}/`)) {
		return new Response(JSON.stringify({ error: 'not_found' }), { status: 404 })
	}

	const object = await env.MEDIA.get(key)
	if (!object) {
		return new Response(JSON.stringify({ error: 'not_found' }), { status: 404 })
	}

	return new Response(object.body, {
		headers: {
			'content-type': object.httpMetadata?.contentType ?? 'application/octet-stream',
			// Memories do not change, and the key is a single-use UUID. A long
			// cache saves both transfer and battery on an old phone.
			'cache-control': 'private, max-age=31536000, immutable',
			etag: object.httpEtag,
		},
	})
}
