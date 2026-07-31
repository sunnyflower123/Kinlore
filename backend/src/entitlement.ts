/// RevenueCat: maksaja ei ole hyötyjä.
///
/// Lapsenlapsi ostaa tilauksen, ja koko perhekanava aukeaa kaikille jäsenille.
/// RevenueCat antaa oikeuden ostajalle, backend levittää sen perheelle.
///
/// Tämä ei ole kilpailutemppu vaan ainoa toimiva malli tälle kohderyhmälle:
/// maksukyky on eri henkilössä kuin arvon tuottaja. 80-vuotias ei osta
/// tilausta, mutta hän on se joka kertoo muistot.

import type { Session } from './auth'
import type { Env } from './worker'

const now = () => Math.floor(Date.now() / 1000)

// ---------------------------------------------------------------- ydin

/// Asettaa perheen oikeuden. Ainoa paikka joka kirjoittaa `family.entitlement`.
///
/// **Alennus ei koskaan poista mitään.** Tilauksen päättyessä perhe palaa
/// ilmaistasolle: vanhat kuvat ja äänet säilyvät ja ovat luettavissa, rajat
/// koskevat vain uutta. Perhe joka menettää muistoja maksun päätyttyä ei palaa
/// koskaan, eikä sellaista tuotetta pidä tehdä.
export async function applyEntitlement(
	env: Env,
	familyID: string,
	payerID: string | null,
	expiresAt: number | null,
): Promise<{ entitlement: string; expiresAt: number | null }> {
	const current = await env.DB.prepare(
		'SELECT payer_id, entitlement_expires_at FROM family WHERE id = ?',
	)
		.bind(familyID)
		.first<{ payer_id: string | null; entitlement_expires_at: number | null }>()

	// Kaksi maksajaa: pisin voimassaolo voittaa. Perhe ei saa menettää
	// oikeutta siksi että toinen jäsen peruu omansa aiemmin.
	const existing = current?.entitlement_expires_at ?? null
	const keepExisting =
		existing !== null &&
		existing > now() &&
		(expiresAt === null || existing > expiresAt) &&
		current?.payer_id !== payerID

	const winner = keepExisting
		? { payer: current?.payer_id ?? null, expires: existing }
		: { payer: payerID, expires: expiresAt }

	const active = winner.expires !== null && winner.expires > now()
	const entitlement = active ? 'archive' : 'free'

	await env.DB.prepare(
		`UPDATE family SET entitlement = ?, payer_id = ?, entitlement_expires_at = ? WHERE id = ?`,
	)
		.bind(entitlement, active ? winner.payer : null, winner.expires, familyID)
		.run()

	return { entitlement, expiresAt: winner.expires }
}

// ---------------------------------------------------------------- varmistus

type ActiveEntitlement = { entitlement_id: string; expires_at: number | null }

/// Kysyy RevenueCatilta mitä asiakas oikeasti omistaa.
///
/// Asiakkaan sanaan ei luoteta: sovellus voi väittää mitä tahansa, ja
/// entitlement on se mikä avaa maksullisen tason koko perheelle.
async function fetchActiveEntitlements(env: Env, customerID: string): Promise<ActiveEntitlement[]> {
	const url =
		`https://api.revenuecat.com/v2/projects/${env.RC_PROJECT_ID}` +
		`/customers/${encodeURIComponent(customerID)}/active_entitlements`

	const res = await fetch(url, {
		headers: { Authorization: `Bearer ${env.RC_SECRET_KEY}` },
	})

	if (!res.ok) {
		const text = await res.text().catch(() => '')
		console.error(`[entitlement] RevenueCat HTTP ${res.status}: ${text.slice(0, 200)}`)
		throw new Error(`RevenueCat HTTP ${res.status}`)
	}

	const data = (await res.json()) as { items?: ActiveEntitlement[] }
	return data.items ?? []
}

/// Sovelluksen kertoma osto varmistetaan ja levitetään perheelle.
export async function syncEntitlement(env: Env, session: Session, customerID: string) {
	if (!env.RC_SECRET_KEY || !env.RC_PROJECT_ID) {
		return { error: 'revenuecat_not_configured' as const }
	}

	const items = await fetchActiveEntitlements(env, customerID)

	// Mikä tahansa voimassa oleva oikeus avaa arkiston. Sovelluksessa on yksi
	// maksullinen taso, joten tunnisteen muotoon ei kannata sitoutua —
	// RevenueCatin v2 palauttaa sisäisen tunnisteen eikä hakuavainta.
	const furthest = items.reduce<number | null>((max, item) => {
		// expires_at on millisekunteina, ja null tarkoittaa ikuista oikeutta.
		if (item.expires_at === null) return Number.MAX_SAFE_INTEGER
		const seconds = Math.floor(item.expires_at / 1000)
		return max === null ? seconds : Math.max(max, seconds)
	}, null)

	// Maksaja sidotaan jäseneen, jotta webhook löytää perheen ilman sovellusta.
	await env.DB.prepare('UPDATE member SET rc_app_user_id = ? WHERE id = ?')
		.bind(customerID, session.memberID)
		.run()

	const result = await applyEntitlement(env, session.familyID, session.memberID, furthest)
	return { ...result, verified: true }
}

// ---------------------------------------------------------------- webhook

type WebhookEvent = {
	type?: string
	app_user_id?: string
	expiration_at_ms?: number | null
	product_id?: string
}

/// Tapahtumat jotka päättävät oikeuden heti riippumatta voimassaolosta.
/// Hyvitys ja siirto pois eivät odota vanhenemista.
const REVOKING = new Set(['CANCELLATION', 'EXPIRATION', 'REFUND', 'TRANSFER', 'SUBSCRIPTION_PAUSED'])

/// Pitää oikeuden ajan tasalla ilman että sovellusta avataan.
///
/// Ilman webhookia uusiutunut tilaus näkyisi vasta kun maksaja seuraavan
/// kerran käynnistää sovelluksen — ja hän ei ole se joka sitä eniten käyttää.
export async function handleWebhook(env: Env, event: WebhookEvent) {
	const customerID = event.app_user_id
	if (!customerID) return { ignored: 'missing_app_user_id' as const }

	const member = await env.DB.prepare(
		'SELECT id, family_id FROM member WHERE rc_app_user_id = ?',
	)
		.bind(customerID)
		.first<{ id: string; family_id: string }>()

	// Tuntematon asiakas: osto tehtiin ennen kuin sovellus ehti kertoa
	// tunnisteen. Ei virhe — seuraava /entitlement/sync korjaa tilanteen.
	if (!member) return { ignored: 'unknown_customer' as const }

	const revoking = REVOKING.has(event.type ?? '')
	const expires = revoking
		? null
		: event.expiration_at_ms
			? Math.floor(event.expiration_at_ms / 1000)
			: null

	const result = await applyEntitlement(env, member.family_id, member.id, expires)
	console.log(`[entitlement] ${event.type} → ${member.family_id} = ${result.entitlement}`)
	return result
}

/// Webhookin tunnistautuminen on RevenueCatin hallintapaneelissa asetettu
/// Authorization-otsake. Ilman tarkistusta kuka tahansa voisi avata perheen
/// maksullisen tason lähettämällä väärennetyn tapahtuman.
export function isAuthorizedWebhook(env: Env, request: Request): boolean {
	if (!env.RC_WEBHOOK_SECRET) return false
	const header = request.headers.get('Authorization') ?? ''
	if (header.length !== env.RC_WEBHOOK_SECRET.length) return false
	let diff = 0
	for (let i = 0; i < header.length; i++) {
		diff |= header.charCodeAt(i) ^ env.RC_WEBHOOK_SECRET.charCodeAt(i)
	}
	return diff === 0
}
