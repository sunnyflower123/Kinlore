# Tilit ja API-avaimet

Yhteenveto: **kolme salaisuutta backendiin, yksi julkinen avain sovellukseen,
nolla Applelta.** Kehityskulut jäävät kahdessa kuukaudessa muutamaan kymmeneen
euroon.

## Perussääntö

**ASR- ja LLM-avaimet elävät vain Workerin salaisuuksissa, eivät koskaan
iOS-sovelluksessa.** IPA-tiedoston purkaminen on triviaalia, ja vuotanut avain on
opiskelijan budjetilla oikea lasku. Tästä seuraa arkkitehtuuriin:

```
iOS  ──ääni──▶  Worker  ──▶  ASR-palvelu
                   │
                   └────────▶  LLM (jäsennys)
```

Sovellus ei koskaan puhu suoraan OpenAI:lle tai vastaavalle. Tämä on syy miksi
äänen lataus Workerille on viikon 2 kriittisellä polulla.

## Tarvittavat avaimet

### Backend — Worker-salaisuuksina

| Avain | Mihin |
|-------|-------|
| **`OPENROUTER_API_KEY`** | **Sekä puheen purku että jäsennys.** OpenRouterilla ei ole erillistä transcriptions-päätepistettä — ääni menee chat completionsin `input_audio`-osana base64:nä, joten yksi avain riittää molempiin. |
| `RC_SECRET_KEY` | RevenueCatin v2 REST API. Backend varmistaa maksajan oikeuden ja mappaa sen koko perheelle. |
| `RC_WEBHOOK_SECRET` | Tilaustapahtumien (uusinta, peruutus) autentikointi → `family.entitlement`. Ilman tätä kuka tahansa voisi väärentää tilauksen. |

```bash
cd backend
npx wrangler secret put OPENROUTER_API_KEY
```

Mallit valitaan `wrangler.jsonc`:n vareissa, ei koodissa:
`MODEL_EXTRACT` ja `MODEL_TRANSCRIBE`, oletuksena `google/gemini-2.5-flash`.
Purkumalli on erillinen muuttuja, koska se voi vaihtua omistettuun ASR:ään jos
vertailu osoittaa sen paremmaksi.

**Paikalliskehitys.** Luo `backend/.dev.vars`:

```
OPENROUTER_API_KEY=sk-or-...
```

Se on jo `.gitignore`ssa — **tarkista silti ennen ensimmäistä pushia**, koska
repo on julkinen. Sen jälkeen:

```bash
cd backend && npx wrangler dev
```

Sovellus käyttää stubeja kunnes sille kerrotaan backendin osoite. Kytke oikeat
palvelut käynnistysargumentilla:

```
-api http://localhost:8787
```

Ilman sitä sovellus toimii yhä täysin — se on tarkoituksellista, jotta kehitys
ei pysähdy silloin kun Worker on rikki tai verkkoa ei ole.

### Terveystarkistus

```bash
curl -s http://localhost:8787/health
```

Palauttaa `{"ok":true,"hasKey":true}` kun avain on paikallaan. Jos `hasKey` on
`false`, jäsennys vastaa `502 upstream_failed` — virheen syy menee vain
Workerin lokiin, ei koskaan sovellukselle, koska se voi sisältää tilin tietoja
tai toistaa käyttäjän kertoman muiston.

### iOS-sovellus — julkinen

| Avain | Huom |
|-------|------|
| RevenueCat **Test Store API key** | Suunniteltu asiakaspuolelle, turvallinen upottaa. Vaihdetaan alustakohtaiseksi vasta jos joskus julkaistaan storeen. |

### Cloudflare

Ei manuaalista avainta. `npx wrangler login` hoitaa OAuthilla.
`CLOUDFLARE_API_TOKEN` tarvitaan vain jos joskus pystytetään CI.

## Mitä EI tarvita

- **Apple: ei mitään.** Ei 99 $ tiliä, ei Sign in with Applea, ei APNs-sertifikaattia.
- **Google / Firebase:** ei mitään.
- **Sähköpostipalvelu:** ei mitään, koska tunnistautuminen on laitepohjainen.
- **OneSignal:** poistui push-ilmoitusten mukana laajuudesta.

## Tunnistautuminen ilman kirjautumisruutua

Käytössä on maksullinen Apple Developer -tili, joten Sign in with Apple, push,
iCloud ja App Groups **olisivat** teknisesti mahdollisia. Silti tunnistautuminen
tehdään ilman niitä — ei rajoitteen takia vaan koska se on tälle käyttäjäryhmälle
parempi:

1. Ensimmäisellä käynnistyksellä luodaan UUID ja tallennetaan se Keychainiin
   `kSecAttrSynchronizable`-lipulla. iCloud Keychain synkronoi sen käyttäjän
   laitteiden välillä — se ei vaadi iCloud-entitlementtiä, joten se toimii
   ilmaisella tilillä.
2. Backend myöntää jäsentunnisteen tälle identiteetille.
3. Perheeseen liitytään kutsulinkillä. Ei sähköpostia, ei salasanaa, ei
   kirjautumisruutua.

**80-vuotias ei törmää kirjautumismuuriin lainkaan** — hän saa linkin
lapsenlapselta ja on sisällä. Se on juuri se kohta jossa tämä käyttäjäryhmä
tavallisesti putoaa pois.

Rehellinen haitta: laitteen katoaminen vie identiteetin, jos iCloud Keychain ei
ole päällä. Lieventäjä: perheen omistaja voi kutsua uudelleen, eikä kukaan menetä
muistoja — ne kuuluvat perheelle, eivät jäsenelle.

**Sign in with Apple otetaan käyttöön vain vapaaehtoisena tilin palautuksena
maksavalle jäsenelle**, ei kenenkään porttina sisään. Lapsenlapsi joka ostaa
tilauksen haluaa perustellusti sitoa sen johonkin pysyvään; isoäiti ei halua
kirjautua mihinkään. Nämä ovat eri tarpeita eikä niitä pidä ratkaista samalla
ruudulla. Tämä on v1.1:n asia, ei MVP:n.

## Kustannusarvio kehitysvaiheessa

Suuruusluokat, tarkista ajantasaiset hinnat itse:

| Palvelu | Arvio |
|---------|-------|
| OpenRouter, purku (Gemini Flash, äänisyöte) | Ääni maksaa tokeneina ja on kalliimpaa kuin teksti — tämä on suurin yksittäinen erä |
| OpenRouter, jäsennys | 90 s muisto ≈ 300 tokenia sisään, 500 ulos — selvästi alle sentin per muisto |
| Vaihtoehto purkuun: Groq whisper-large-v3 | Ilmaistaso kattaa kehityksen. Kannattaa vertailla, jos äänen tokenihinta yllättää |
| Cloudflare Workers + D1 + R2 | Ilmaistaso riittää hackathoniin. R2:ssa ei egress-maksuja, mikä on tälle olennaista koska äänet säilytetään pysyvästi |
| RevenueCat | Ilmainen alle 2 500 $ kuukausittaisella liikevaihdolla |

**Realistinen kokonaiskulu kahdelta kuukaudelta: alle 20 €.** Suurin yksittäinen
erä on ASR, ja sekin vain jos testaat paljon pitkiä nauhoituksia.

## Järjestys viikolle 0

1. Cloudflare-tili + `wrangler login`, `d1 create`, `r2 bucket create`
2. Yksi ASR-avain → aja `scripts/asr-bench.mjs`
3. RevenueCat-tili → projekti → Test Store → testiavain
4. LLM-avain (voi olla sama kuin ASR)
