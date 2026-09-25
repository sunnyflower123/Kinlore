// Apple push, sent from the Worker.
//
// Two notifications exist and nothing else rings a phone: "somebody asked you
// something" to the member a question is aimed at, and "your question was
// answered" to its asker. Which pushes produce them is `sync.ts`'s decision
// (`noticesFor`); this file only delivers.
//
// Neither notification can say what was asked or told, and that is not a
// choice made here: the question and the telling are sealed on the phone
// (lever 3), so the Worker has no words to put in one. The asker's display
// name is the one thing it can carry, and it is plaintext on `member`
// already. The text itself is a `loc-key`, looked up on the phone in its own
// Localizable.strings, so a Finnish phone and an English one each read their
// own language and the Worker never needs to know which.
//
// Delivery is best effort by design. A notification that does not arrive
// loses nothing — the question is on the card and in the Kerro tab either
// way — so nothing here retries, and nothing here can fail a sync: it runs
// after the reply, under `waitUntil`.
//
// Rule 9 holds in the log as everywhere: status, APNs's own reason code and
// counts. Never a token, never a name.
//
// APNs speaks only HTTP/2. A deployed Worker's `fetch` does; `wrangler dev` on
// macOS does not (workerd issue #4841), so a notification cannot be sent from
// a local Worker at all. `scripts/apns-check.mjs` checks everything up to the
// wire with `fetch` replaced, and the wire itself is checked once, deployed.

import type { Session } from './auth'
import type { Notice } from './sync'
import type { Env } from './worker'

/// The bundle id. APNs routes on it, and the key is the team's, so this is
/// the one line that ties a notification to this app rather than another.
const TOPIC = 'com.kinlore.app'

const HOSTS: Record<string, string> = {
	sandbox: 'api.sandbox.push.apple.com',
	production: 'api.push.apple.com',
}

/// A question aimed at somebody is still worth hearing about days later; one
/// older than a week has been seen in the app or has stopped mattering.
const EXPIRY_SECONDS = 7 * 86_400

/// APNs refuses a provider token older than an hour and throttles one renewed
/// more often than every twenty minutes, so one signature serves fifty
/// minutes. Per isolate, which is the only memory a Worker has.
const TOKEN_LIFETIME_SECONDS = 50 * 60
let provider: { jwt: string; issuedAt: number; keyID: string } | null = null

const encoder = new TextEncoder()

function base64url(bytes: Uint8Array): string {
	let binary = ''
	for (const byte of bytes) binary += String.fromCharCode(byte)
	return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

/// The .p8 file as Apple issues it, armour and all, or only its body: both
/// are what `npx wrangler secret put APNS_KEY_P8 < AuthKey_XXXX.p8` can leave.
function pkcs8(p8: string): Uint8Array {
	const body = p8.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\s+/g, '')
	return Uint8Array.from(atob(body), (char) => char.charCodeAt(0))
}

/// The ES256 provider token. WebCrypto's ECDSA signature is already the
/// 64-byte r‖s form a JWT wants, so there is nothing to convert.
async function providerToken(env: Env, at: number): Promise<string> {
	const keyID = env.APNS_KEY_ID as string
	if (provider && provider.keyID === keyID && at - provider.issuedAt < TOKEN_LIFETIME_SECONDS) {
		return provider.jwt
	}
	const header = base64url(encoder.encode(JSON.stringify({ alg: 'ES256', kid: keyID })))
	const claims = base64url(encoder.encode(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: at })))
	const key = await crypto.subtle.importKey(
		'pkcs8',
		pkcs8(env.APNS_KEY_P8 as string),
		{ name: 'ECDSA', namedCurve: 'P-256' },
		false,
		['sign'],
	)
	const signature = await crypto.subtle.sign(
		{ name: 'ECDSA', hash: 'SHA-256' },
		key,
		encoder.encode(`${header}.${claims}`),
	)
	const jwt = `${header}.${claims}.${base64url(new Uint8Array(signature))}`
	provider = { jwt, issuedAt: at, keyID }
	return jwt
}

/// What the phone shows. The keys are Finnish because the app's keys are
/// (CLAUDE.md, Language); both .strings tables carry them.
export function payload(notice: Notice) {
	const name = notice.askerName?.trim() ?? ''
	const alert =
		notice.kind === 'answered'
			? { 'loc-key': 'Kysymykseesi tuli vastaus.' }
			: name
				? { 'loc-key': '%@ kysyi sinulta jotain.', 'loc-args': [name] }
				: // An empty display name is possible (`createFamily` accepts
					// one), and "%@" filled with nothing reads as a sentence
					// with its subject missing.
					{ 'loc-key': 'Sinulle on uusi kysymys.' }
	return {
		aps: { alert, sound: 'default' },
		// Where a tap should lead. An id, never content.
		kinlore: { kind: notice.kind, question: notice.questionID },
	}
}

type TokenRow = { token: string; member_id: string; environment: string }

/// Sends every notice to every phone of its member, and forgets the tokens
/// APNs says are dead. Without the three secrets it sends nothing and says
/// so once — a Worker nobody has given a key is not a broken one.
export async function notify(env: Env, family: string, notices: Notice[]): Promise<void> {
	if (notices.length === 0) return
	if (!env.APNS_KEY_P8 || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) {
		console.log(`[apns] ${notices.length} notices, not sent: no key`)
		return
	}

	// Members of this family who have not left. The notice came from this
	// family's own rows, and the join says so again rather than trusting it.
	// At most 98 of them, for D1's hundred-parameter limit — a family is tens.
	const members = [...new Set(notices.map((notice) => notice.memberID))].slice(0, 98)
	const tokens = await env.DB.prepare(
		`SELECT t.token, t.member_id, t.environment
		 FROM push_token t JOIN member m ON m.id = t.member_id
		 WHERE m.family_id = ? AND m.left_at IS NULL
		   AND t.member_id IN (${members.map(() => '?').join(',')})`,
	)
		.bind(family, ...members)
		.all<TokenRow>()
	const byMember = new Map<string, TokenRow[]>()
	for (const row of tokens.results ?? []) {
		byMember.set(row.member_id, [...(byMember.get(row.member_id) ?? []), row])
	}

	const at = Math.floor(Date.now() / 1000)
	let jwt: string
	try {
		jwt = await providerToken(env, at)
	} catch (err) {
		// A key that does not import. The message is WebCrypto's, about the
		// key's shape; the key itself is never in it.
		console.error(`[apns] provider token: ${err instanceof Error ? err.name : typeof err}`)
		return
	}

	const outcomes: string[] = []
	const dead: string[] = []
	const sends = notices.flatMap((notice) =>
		(byMember.get(notice.memberID) ?? []).map(async (row) => {
			const host = HOSTS[row.environment]
			if (!host) return
			try {
				const response = await fetch(`https://${host}/3/device/${row.token}`, {
					method: 'POST',
					headers: {
						authorization: `bearer ${jwt}`,
						'apns-topic': TOPIC,
						'apns-push-type': 'alert',
						'apns-priority': '10',
						'apns-expiration': String(at + EXPIRY_SECONDS),
						// A re-sent notice replaces the earlier one on the
						// phone rather than stacking beside it.
						'apns-collapse-id': `${notice.kind}-${notice.questionID}`.slice(0, 64),
					},
					body: JSON.stringify(payload(notice)),
					signal: AbortSignal.timeout(10_000),
				})
				if (response.status === 200) {
					outcomes.push('200')
					return
				}
				const reason = await response
					.json<{ reason?: string }>()
					.then((body) => (typeof body.reason === 'string' ? body.reason : ''))
					.catch(() => '')
				outcomes.push(`${response.status} ${reason}`.trim())
				// 410 is a phone that uninstalled the app or turned
				// notifications off. BadDeviceToken is a token this endpoint
				// does not know — dropped too, because the app registers again
				// on every launch and the next registration puts it back.
				if (
					response.status === 410 ||
					reason === 'BadDeviceToken' ||
					reason === 'DeviceTokenNotForTopic'
				) {
					dead.push(row.token)
				}
				if (reason === 'ExpiredProviderToken' || reason === 'InvalidProviderToken') {
					provider = null
				}
			} catch (err) {
				outcomes.push(err instanceof Error ? err.name : 'error')
			}
		}),
	)
	await Promise.all(sends)

	if (dead.length > 0) {
		await env.DB.batch(
			dead.map((token) => env.DB.prepare('DELETE FROM push_token WHERE token = ?').bind(token)),
		)
	}

	const tally = new Map<string, number>()
	for (const outcome of outcomes) tally.set(outcome, (tally.get(outcome) ?? 0) + 1)
	const summary = [...tally].map(([outcome, count]) => `${count}× ${outcome}`).join(', ')
	console.log(
		`[apns] ${notices.length} notices, ${outcomes.length} sends${summary ? `: ${summary}` : ''}` +
			(dead.length > 0 ? `, ${dead.length} tokens dropped` : ''),
	)
}

/// A phone's token, hex as iOS hands it over. Apple says not to assume a
/// length, so the bound is generous and exists only for a misbehaving client.
const TOKEN = /^[0-9a-f]{32,200}$/

/// Records that this member's phone may be notified. A token is one phone,
/// so a phone that changes hands inside the family moves with it.
export async function registerToken(
	env: Env,
	session: Session,
	token: unknown,
	environment: unknown,
) {
	if (typeof token !== 'string' || !TOKEN.test(token.toLowerCase())) {
		return { error: 'invalid_token' as const }
	}
	if (environment !== 'sandbox' && environment !== 'production') {
		return { error: 'invalid_environment' as const }
	}
	const at = Math.floor(Date.now() / 1000)
	await env.DB.prepare(
		`INSERT INTO push_token (token, member_id, environment, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?)
		 ON CONFLICT(token) DO UPDATE SET
		   member_id = excluded.member_id,
		   environment = excluded.environment,
		   updated_at = excluded.updated_at`,
	)
		.bind(token.toLowerCase(), session.memberID, environment, at, at)
		.run()
	return { registered: true as const }
}

/// Forgets this member's phone — the switch in Settings turned off. Only the
/// member's own token: another member's is not theirs to remove.
export async function unregisterToken(env: Env, session: Session, token: unknown) {
	if (typeof token !== 'string') return { error: 'invalid_token' as const }
	await env.DB.prepare('DELETE FROM push_token WHERE token = ? AND member_id = ?')
		.bind(token.toLowerCase(), session.memberID)
		.run()
	return { unregistered: true as const }
}
