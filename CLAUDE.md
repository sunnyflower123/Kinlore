# Memorize

Perheen jaettu muistiarkisto. Vanha ihminen kertoo rönsyillen, tekoäly tekee
rakennetta. Sivuprojekti RevenueCat Shipaton 2026:een.

**Kohdesarja: Next Gen** (opiskelijasarja). **Ei App Store -julkaisua** — se
pudotettiin, koska lukio alkaa ~11.8. eikä aika riitä App Store Connectiin.
Deadline: Devpost-submissio 28.9.2026. Ostot RevenueCat Test Storella.

Koska sarja tuomaroi **julkisen lähdekoodin**, repo on näyteikkuna eikä vain
työkalu: README ja koodikommentit kirjoitetaan lopulta englanniksi (jakso E),
sovelluksen käyttöliittymä pysyy suomena.

**Aikataulu on rakennettu koulun ympärille:** raskain työ (selkäranka +
taikahetki) tehdään 4.–10.8. lomalla, ei koulun ohessa. Kun aika loppuu, leikkaa
PLAN.md §5:n järjestyksessä — se on päätetty etukäteen jottei väsyneenä tarvitse
valita.

Suunnitelma ja laajuus: [docs/PLAN.md](docs/PLAN.md). **Lue se ennen kuin lisäät
ominaisuuksia** — laajuus on tarkoituksella leikattu, ja jokainen lisäys vaatii
jonkin poiston.

## Rakenne

```
ios/       SwiftUI-sovellus, XcodeGen (project.yml → .xcodeproj)
backend/   Cloudflare Worker + D1 (metadata) + R2 (kuvat ja äänet)
scripts/   asr-bench.mjs — suomen puheentunnistuksen vertailu
docs/      PLAN.md
```

## Tietomalli

Yksi `subject`-taulu kattaa kuvat, henkilöt, paikat ja tapahtumat. `memory`
kiinnittyy mihin tahansa subjectiin. Siksi "kirjoita muisto kuvaan" ja "kerro
millainen isoäiti oli" ovat sama ruutu ja sama reitti — älä hajota näitä
erillisiksi toteutuksiksi, se on koko arkkitehtuurin ydin.
Skeema: [backend/schema.sql](backend/schema.sql).

## Säännöt jotka eivät jousta

1. **Ensisijainen käyttäjä on 80-vuotias.** Dynamic Type XXL asti, VoiceOver,
   isot kosketuskohteet. Jos uusi ruutu ei toimi suurimmalla tekstikoolla, se ei
   ole valmis. Tämä ei ole compliance-lista vaan tuotteen ydin.
2. **Kertomista ei koskaan paywallata.** Maksumuuri rajaa kuvia ja AI-minuutteja,
   ei sitä että joku kirjoittaa tai sanelee muiston.
3. **Alkuperäinen ääni ja raakapurku säilytetään aina.** Puhuja ei ehkä ole enää
   kysyttävissä. `memory.audio_r2_key` ja `memory.raw_transcript` eivät ole
   välivaiheita vaan lopputuotetta.
4. **AI ehdottaa, ihminen vahvistaa.** Tekoälyn päättelemä henkilö tai
   sukulaisuussuhde syntyy `confirmed = 0` -tilassa. Vahvistamaton ei näy
   sukupuussa faktana. Väärä suhde on pahempi kuin puuttuva.
5. **Epävarmuus tallennetaan, ei pyöristetä.** "Joskus 50-luvulla" menee
   `date_start`/`date_end`-välinä tarkkuudella `decade`. Älä pakota
   päivämäärään.
6. **Ei kirjautumisruutua.** Identiteetti on Keychainissa oleva UUID
   (`kSecAttrSynchronizable`), perheeseen liitytään kutsulinkillä. Maksullinen
   Apple-tili on olemassa, joten Sign in with Apple *olisi* mahdollinen — sitä
   ei silti käytetä porttina, korkeintaan maksavan jäsenen vapaaehtoisena tilin
   palautuksena v1.1:ssä. Ks. [docs/SETUP.md](docs/SETUP.md).
7. **`OPENROUTER_API_KEY` vain Worker-salaisuutena.** Sovellus lataa äänen ja
   tekstin Workerille, Worker kutsuu OpenRouteria. Repo on julkinen — tarkista
   `.dev.vars` ennen jokaista pushia.
8. **`provider: { data_collection: "deny" }` on ehdoton**, ei kutsukohtainen
   lippu. Sisältö on perheen muistoja kuolleista sukulaisista. Lippuna se
   unohtuisi jostain kutsusta.
9. **Virheen syy ei koskaan vuoda asiakkaalle.** Upstream-rungot menevät vain
   `console.error`iin: ne voivat sisältää tilin tietoja tai toistaa käyttäjän
   kertoman muiston. Sovellus saa `{ error: "upstream_failed" }`.

## Komennot

```bash
# iOS-projektin generointi (aja aina project.yml-muutoksen jälkeen)
cd ios && xcodegen generate

# iOS-build. DEVELOPER_DIR on pakollinen: koneen xcode-select osoittaa
# CommandLineToolsiin, ja sen vaihto vaatisi sudon. Tämä ohittaa sen.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/Memorize.xcodeproj -scheme Memorize -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Backend paikallisesti
cd backend && npx wrangler dev

# D1-skeema paikalliseen kantaan
cd backend && npx wrangler d1 execute memorize --local --file=schema.sql

# ASR-vertailu
node scripts/asr-bench.mjs samples/
```

## Ympäristön huomiot

- **`sudo`a ei ole käytettävissä.** Älä ehdota `xcode-select -s`:ää — käytä
  `DEVELOPER_DIR`-muuttujaa yllä olevan komennon tapaan. Xcode 26.6,
  iOS 26.5 -simulaattori-SDK.
- Sovelluksen nimi ja bundle ID ovat vielä väliaikaiset (`app.memorize.Memorize`),
  ks. PLAN.md §11.
- Ostot tehdään **RevenueCat Test Storella**, ei App Store Connectin tuotteilla.
  Maksullista Apple-kehittäjätiliä ei tarvita.
