/// Kuvien ja äänten tallennus R2:een.
///
/// Tiedosto kulkee Workerin läpi. Kuva on pienennettynä noin 300 kt ja 90
/// sekunnin ääni noin 200 kt, joten esiallekirjoitetut URL:t toisivat vain
/// liikkuvia osia ilman hyötyä. Ks. docs/ARKKITEHTUURI.md §5.

import type { Session } from './auth'
import type { Env } from './worker'

/// Yksittäisen tiedoston yläraja. Kuvat pienennetään asiakkaassa 2048
/// pikseliin, ja pisinkin muisto mahtuu tähän moninkertaisesti.
const MAX_BYTES = 10 * 1024 * 1024

const TYPES: Record<string, { ext: string; contentType: string }> = {
	photo: { ext: 'jpg', contentType: 'image/jpeg' },
	audio: { ext: 'm4a', contentType: 'audio/mp4' },
}

/// Avain alkaa aina perheen tunnisteella. Pääsy tarkistetaan silti istunnosta
/// eikä avaimesta — etuliite tekee tarkistuksesta yksinkertaisen, mutta se ei
/// ole se mikä turvaa: pyytäjän perhe ratkaisee.
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
	// Perheen etuliite tarkistetaan ennen R2-kutsua: toisen perheen avaimen
	// arvaaminen ei saa edes aiheuttaa hakua.
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
			// Muistot eivät muutu, ja avain on kertakäyttöinen UUID. Pitkä
			// välimuisti säästää sekä siirtoa että akkua vanhassa puhelimessa.
			'cache-control': 'private, max-age=31536000, immutable',
			etag: object.httpEtag,
		},
	})
}
