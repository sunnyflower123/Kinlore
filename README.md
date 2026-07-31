# Memorize

> Työnimi. Vaihdetaan ennen julkaisua — ks. [docs/PLAN.md](docs/PLAN.md) §8.

Perheen jaettu muistiarkisto. Vanha ihminen kertoo rönsyillen, tekoäly tekee
siitä rakennetta: muistot kiinnittyvät kuviin ja henkilöihin, sukupuu kasvaa
kertomuksista, ja avoimet kysymykset palaavat kysyttäviksi.

Ratkaistava ongelma: isovanhemmat *tietävät*, mutta eivät osaa selittää
jäsennellysti. He eivät täytä lomakkeita eivätkä tagita kuvia — he puhuvat.
Nykyiset albumi- ja sukututkimussovellukset vaativat jäsenneltyä syötettä
ihmiseltä joka ei sitä tuota, ja siksi tieto katoaa hautajaisissa.

Sivuprojekti [RevenueCat Shipaton 2026](https://revenuecat-shipaton-2026.devpost.com/)
-kilpailuun. Tavoitesarjat: Peace Prize ja Design Award.

## Rakenne

| Kansio | Sisältö |
|--------|---------|
| `ios/` | SwiftUI-sovellus. Projekti generoidaan `project.yml`:stä XcodeGenillä. |
| `backend/` | Cloudflare Worker + D1 (metadata) + R2 (kuvat ja äänet). |
| `scripts/` | `asr-bench.mjs` — suomen puheentunnistuksen vertailu. |
| `docs/` | `PLAN.md` — laajuus, aikataulu, riskit. |

## Kehitysympäristö

```bash
# iOS
cd ios && xcodegen generate && open Memorize.xcodeproj

# Backend
cd backend && npm install
npx wrangler d1 execute memorize --local --file=schema.sql
npx wrangler dev
```

Komentoriviltä kääntäessä `DEVELOPER_DIR` on pakollinen, koska koneen
`xcode-select` osoittaa CommandLineToolsiin:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/Memorize.xcodeproj -scheme Memorize -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Ennen ensimmäistä pilvideployta luo resurssit ja päivitä `database_id`
tiedostoon `backend/wrangler.jsonc`:

```bash
npx wrangler d1 create memorize && npx wrangler r2 bucket create memorize-media
```

## Tietomallin ydin

Yksi `subject`-taulu kattaa kuvat, henkilöt, paikat ja tapahtumat; `memory`
kiinnittyy mihin tahansa subjectiin. Siksi *"kirjoita muisto kuvaan"* ja
*"kerro millainen isoäiti oli"* ovat sama ruutu ja sama reitti.
Skeema: [backend/schema.sql](backend/schema.sql).
