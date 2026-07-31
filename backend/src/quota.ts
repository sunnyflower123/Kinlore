/// Ilmaiskäytön rajat.
///
/// Kaksi periaatetta ohjaavat tätä:
///
/// 1. **Kertomista ei koskaan paywallata.** Kiintiö rajaa kuvia ja AI-minuutteja,
///    ei sitä että joku kirjoittaa muiston. Kirjoitettu muisto menee aina läpi.
/// 2. **Alkuperäinen ääni säilytetään aina.** Kiintiön täyttyminen ei hylkää
///    nauhoitusta vaan lykkää sen purkua — ääni on lopputuotetta, ei välivaihe.
///
/// Laskurit ovat palvelimella, koska asiakkaan laskuri on muokattavissa.

import type { Session } from './auth'
import type { Env } from './worker'

export type QuotaDenial = {
	error: 'quota_exceeded'
	kind: 'ai_seconds' | 'photos'
	used: number
	limit: number
}

/// Kuukausi UTC:ssä. Suomalaiselle perheelle rajan tarkka hetki ei merkitse
/// mitään, ja aikavyöhykkeen huomiointi toisi vain virhelähteen.
function period(): string {
	const now = new Date()
	return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`
}

async function isPaid(env: Env, familyID: string): Promise<boolean> {
	const row = await env.DB.prepare('SELECT entitlement FROM family WHERE id = ?')
		.bind(familyID)
		.first<{ entitlement: string }>()
	return row?.entitlement === 'archive'
}

// ---------------------------------------------------------------- AI-minuutit

/// Tarkistetaan ENNEN kallista kutsua. Palauttaa null jos saa jatkaa.
export async function checkAISeconds(
	env: Env,
	session: Session,
	seconds: number,
): Promise<QuotaDenial | null> {
	if (await isPaid(env, session.familyID)) return null

	const limit = Number(env.FREE_AI_SECONDS_PER_MONTH) || 600
	const row = await env.DB.prepare(
		'SELECT ai_seconds FROM usage_counter WHERE family_id = ? AND period = ?',
	)
		.bind(session.familyID, period())
		.first<{ ai_seconds: number }>()

	const used = row?.ai_seconds ?? 0
	// Tarkistus tehdään käytetyn määrän perusteella eikä käytetty+tuleva:
	// aloitettua nauhoitusta ei katkaista sen takia että se sattui olemaan
	// pitkä. Raja ylittyy hieman, ja se on halvempi kuin hylätty muisto.
	if (used >= limit) {
		return { error: 'quota_exceeded', kind: 'ai_seconds', used, limit }
	}
	return null
}

/// Kirjataan kutsun jälkeen. Onnistunut purku maksoi jo, joten se lasketaan
/// vaikka jäsennys myöhemmin epäonnistuisi.
export async function recordAISeconds(env: Env, session: Session, seconds: number): Promise<void> {
	const rounded = Math.max(0, Math.round(seconds))
	if (rounded === 0) return

	await env.DB.prepare(
		`INSERT INTO usage_counter (family_id, period, ai_seconds)
		 VALUES (?, ?, ?)
		 ON CONFLICT(family_id, period) DO UPDATE SET ai_seconds = ai_seconds + excluded.ai_seconds`,
	)
		.bind(session.familyID, period(), rounded)
		.run()
}

// ---------------------------------------------------------------- kuvat

/// Kuvamäärä lasketaan suoraan `subject`-taulusta eikä erillisestä laskurista.
///
/// Raja on kokonaismäärä eikä kuukausikohtainen, ja poistettu kuva vapauttaa
/// paikan. Erillinen laskuri ajautuisi väistämättä eri tahtiin todellisuuden
/// kanssa, ja perheen arkistossa rivejä on satoja — laskeminen on ilmaista.
export async function checkPhotoCount(env: Env, session: Session): Promise<QuotaDenial | null> {
	if (await isPaid(env, session.familyID)) return null

	const limit = Number(env.FREE_PHOTO_LIMIT) || 20
	const row = await env.DB.prepare(
		`SELECT count(*) AS n FROM subject
		 WHERE family_id = ? AND kind = 'photo' AND deleted_at IS NULL`,
	)
		.bind(session.familyID)
		.first<{ n: number }>()

	const used = row?.n ?? 0
	if (used >= limit) {
		return { error: 'quota_exceeded', kind: 'photos', used, limit }
	}
	return null
}

// ---------------------------------------------------------------- tila

/// Perheen käyttötilanne sovellukselle. Paywall tarvitsee tämän voidakseen
/// näyttää mitä on jäljellä ennen kuin raja tulee vastaan.
export async function usage(env: Env, session: Session) {
	const paid = await isPaid(env, session.familyID)
	const seconds = await env.DB.prepare(
		'SELECT ai_seconds FROM usage_counter WHERE family_id = ? AND period = ?',
	)
		.bind(session.familyID, period())
		.first<{ ai_seconds: number }>()
	const photos = await env.DB.prepare(
		`SELECT count(*) AS n FROM subject
		 WHERE family_id = ? AND kind = 'photo' AND deleted_at IS NULL`,
	)
		.bind(session.familyID)
		.first<{ n: number }>()

	return {
		entitlement: paid ? 'archive' : 'free',
		period: period(),
		aiSeconds: { used: seconds?.ai_seconds ?? 0, limit: paid ? null : Number(env.FREE_AI_SECONDS_PER_MONTH) || 600 },
		photos: { used: photos?.n ?? 0, limit: paid ? null : Number(env.FREE_PHOTO_LIMIT) || 20 },
	}
}
