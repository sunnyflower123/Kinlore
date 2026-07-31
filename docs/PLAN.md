# Suunnitelma — Shipaton 2026 / Next Gen

Työnimi: **Memorize**
Kilpailu: RevenueCat Shipaton 2026, 1.8.–30.9.2026
**Kohdesarja: Next Gen Award** (opiskelijasarja, $15 000). Ei muita.

---

## 1. Mitä tämä on

Perheen jaettu muistiarkisto, jossa vanha ihminen saa kertoa rönsyillen ja
tekoäly tekee siitä rakennetta.

Ongelma: **isovanhemmat tietävät, mutta eivät osaa selittää jäsennellysti.** He
eivät täytä lomakkeita, eivät tagita kuvia eivätkä piirrä sukupuuta. He puhuvat.
Nykyiset albumi- ja sukututkimussovellukset vaativat jäsenneltyä syötettä
ihmiseltä joka ei sitä tuota, ja siksi tieto katoaa hautajaisissa.

## 2. Miksi vain Next Gen

App Storeen julkaisu olisi avannut Peace Prizen ja Design Awardin, mutta se
maksaisi: App Store Connect -tietue, Paid Applications Agreement (pankki- ja
verotiedot), oikeat tilaustuotteet, kuvakaappaukset, tietosuojaseloste,
App Review ja hylkäyskierros — ja deadline kiristyisi 28.9:stä 18.9:ään.

Lukion aloituksen ja toisen projektin päälle se on väärä kauppa. **Store-reitti
on pudotettu.** Se ei ole tinkimistä vaan ainoa tapa saada §4:n taikahetki
oikeasti hyväksi.

Mitä tämä säästää:

| Poistuu | Vaikutus |
|---------|----------|
| App Store Connect, Paid Applications Agreement | ~1 viikko + tuntematon odotusaika |
| Oikeat tilaustuotteet | RevenueCat **Test Store** riittää — se on suunniteltu juuri tähän |
| Kuvakaappaukset, tietosuojaseloste, ikäraja, tukisivu | ~1 päivä |
| App Review + hylkäyskierros | Poistaa aikataulun suurimman epävarmuuden |
| Apple 1.2 UGC-pakko | Raportointi ja esto siirtyvät "hyvä olla" -listalle |
| Deadline 18.9. → **28.9.** | +10 päivää |

Yhteensä noin **kaksi viikkoa työtä pois ja kymmenen päivää lisää.** Nimeäkään ei
tarvitse lukita etukäteen, koska App Store Connect -tietuetta ei luoda.

## 3. Aikataulu on rakennettu koulun ympärille

Ratkaiseva tosiasia: **lukio alkaa noin 11.8.** Sitä ennen on täysi kapasiteetti,
sen jälkeen illat ja viikonloput. Yksi lomaviikko vastaa karkeasti kolmea
kouluviikkoa.

Siksi **raskain työ tehdään ennen koulun alkua**, ei sen jälkeen. Aiempi versio
tästä suunnitelmasta ajoitti taikahetken juuri koulun alkamisviikolle — se oli
väärin päin.

| Jakso | Päivät | Tavoite | Kapasiteetti |
|-------|--------|---------|--------------|
| **A** | 31.7.–3.8. | **Riskien tappo.** ASR-testi oikealla vanhuksen puheella. Swot-tarkistus. RevenueCat-tili + Test Store. GitHub julkiseksi + lisenssi. | loma |
| **B** | 4.–10.8. | **Selkäranka + taikahetki.** Kuvan valinta, muistot, sanelu → purku → jäsennys → jatkokysymykset. Loman viimeinen viikko käytetään vaikeimpaan. | loma, täysi |
| — | **~11.8.** | **Lukio alkaa** | |
| **C** | 11.–31.8. | Henkilökortit + suhteet. Ehdotusten vahvistus-UI. | illat |
| **D** | 1.–14.9. | RevenueCat Test Store + paywall. Käsityö: animaatiot, ääniaalto, tyhjät tilat, saavutettavuus. | illat |
| **E** | 15.–24.9. | Testaus oikealla isovanhemmalla (TestFlight). Korjaukset. **Repo englanniksi.** | illat |
| **F** | 25.–28.9. | **Demovideo** ja Devpost-submissio. | viikonloppu |

Jos jakso B onnistuu, loppu on alamäkeä. Jos se ei onnistu, kaikki muu on turhaa
— siksi se on lomalla eikä koulun ohessa.

## 4. Taikahetki — se yksi asia

> Isoäiti painaa isoa nappia ja puhuu 90 sekuntia rönsyillen vanhasta kuvasta.
> Sovellus palauttaa: jäsennelty muisto kiinnitettynä kuvaan, henkilökortit
> mainituille sukulaisille, vuosi- ja paikkatiedot — ja kolme jatkokysymystä
> takaisin.

Demovideon pitää olla käytännössä tämä yksi ruutu. Arviointikriteeri sanoo
*"merkityksellinen edistymä toimivaa sovellusta kohti selkeällä
ydintoiminnallisuudella"* — kapea ja erinomainen voittaa leveän ja puolivalmiin.

**Alkuperäinen ääni säilytetään aina ja on soitettavissa muistokortissa.**
Isoäidin ääni on itsessään perintö, ei välivaihe kohti tekstiä.

## 5. Leikkausjärjestys kun aika loppuu

Se loppuu. Tämä on päätetty etukäteen, jotta väsyneenä ei tarvitse valita.

**Ei koskaan leikata:**
1. Taikahetki (sanelu → jäsennys → jatkokysymykset)
2. RevenueCat Test Store + paywall — sääntövaatimus, mutta pieni työ
3. Demovideo
4. Repo englanniksi + OSS-lisenssi näkyvissä GitHubin About-osiossa

**Leikataan tässä järjestyksessä, alhaalta ylös:**

| # | Kohde | Miten |
|---|-------|-------|
| 7 | Sukupuu / suhteet | Henkilökortit ilman kaaria |
| 6 | Raportointi ja esto | Ei enää pakollisia ilman App Reviewia |
| 5 | **Oikea kutsulinkki ja liittymisvirta** | **Ensimmäinen simplistettävä.** Syvälinkit ja liittymisruudut ovat kallis osa. Tietomalli tukee jo useaa jäsentä (`memory.author_id`), joten **demoperheen voi siementää** — video näyttää usean sukulaisen muistot samassa kuvassa ilman että liittymisvirtaa on rakennettu |
| 4 | Henkilökortit | Muistot vain kuviin |
| 3 | Kuvien lataus pilveen | Paikallinen kuvavalinta riittää videolle |

Huomaa ero: **konseptia ei leikata, toteutusta leikataan.** Jaettu perhemuisti
näkyy videolla vaikka liittymisvirta olisi siemennetty — mutta jos taikahetki
puuttuu, ei ole mitään näytettävää.

## 6. Suunnitteluperiaatteet

1. **Ensisijainen käyttäjä on 80-vuotias.** Dynamic Type XXL asti, VoiceOver,
   isot kosketuskohteet. Saavutettavuus *on* tämän sovelluksen design.
2. **Älä koskaan paywallaa kertomista.** Maksumuuri rajaa kuvia ja AI-minuutteja.
3. **Epävarmuus on ensiluokkainen tila.** "Joskus 50-luvulla" tallennetaan välinä.
4. **AI ehdottaa, ihminen vahvistaa.** Väärä sukulaisuussuhde on pahempi kuin
   puuttuva.
5. **Aukot näytetään.** Tyhjä henkilökortti on kutsu, ei tyhjä tila.
6. **Ei kirjautumisruutua.** Ks. `SETUP.md`.

## 7. Arkkitehtuuri

**SwiftUI + XcodeGen** ‖ **Cloudflare Workers + D1 + R2**.

Yksi **`subject`**-taulu jolla on `kind` (photo | person | place | event), ja
**`memory`** joka kiinnittyy mihin tahansa subjectiin. Silloin *"kirjoita muisto
kuvaan"* ja *"kerro millainen isoäiti oli"* ovat sama ruutu ja sama reitti.
Sukupuu on person-subjectien väliset kaaret. Skeema:
[`backend/schema.sql`](../backend/schema.sql).

Tämä on repon paras yksittäinen argumentti kriteerissä "tekniset valinnat" —
kirjoita se auki englanniksi jaksossa E.

```
ääni → ASR (suomi) → raw_transcript (säilytetään sellaisenaan)
                          ↓
                     LLM-purku (structured output)
                          ↓
     ┌────────────────────┼────────────────────┐
memory.body        mainitut subjectit      jatkokysymykset
(siivottu teksti)  (confirmed = 0)         (prompt_question)
```

## 8. Riskit

| # | Riski | Toimenpide |
|---|-------|-----------|
| 2 | **Suomenkielinen ASR vanhuksen puheesta.** Koko sovellus seisoo tämän varassa. | `node scripts/asr-bench.mjs samples/` ennen muuta koodia. Alle ~80 % erisnimistä → konsepti uusiksi. |
| 3 | **Opiskelijasähköposti tulee vasta koulun alkaessa** | Domain tarkistettavissa jo nyt: `./scripts/check-swot.sh <domain>`. Lukioiden domainit ovat listalla kuntakohtaisissa kansioissa. |
| 4 | **Lukio vie enemmän aikaa kuin arvaa** | §5:n leikkausjärjestys on päätetty etukäteen. Raskain työ on lomalla. |
| 5 | **Demovideo jää viimeiselle illalle** | Oma jaksonsa (F). Video on tuotos, ei jälkikirjaus. |
| 6 | **Repo jää suomeksi** | Jakso E. Suoraan pisteytettävä, helppo tinkimiskohde. |

## 9. Monetisaation ydin

**Maksaja ei ole hyötyjä.** Isoäiti ei osta tilausta — lapsenlapsi ostaa, ja koko
perhekanava aukeaa kaikille jäsenille. RevenueCat antaa entitlementin ostajalle,
backend mappaa sen kanavatason oikeudeksi (`family.entitlement`).

Selitä tämä Devpost-kuvauksessa: kriteeri sanoo "harkittu RevenueCat-toteutus",
ei "paywall on olemassa". Maksukyky on eri henkilössä kuin arvon tuottaja — se on
tämän kohderyhmän ainoa toimiva malli, ei kilpailutemppu.

Paywallin oikea hetki: **heti kun ensimmäinen AI-jäsennelty muisto valmistuu.**

## 10. Avoimet päätökset

- **Lisenssi.** MIT on yksinkertaisin; **AGPL-3.0** täyttää vaatimuksen mutta
  tekee kaupallisesta kopioinnista epähoukuttelevaa. Kanoninen teksti GitHubin
  lisenssivalitsimesta, muuten About-osion tunnistus ei osu.
- **Nimi.** Ei enää kiireellinen ilman App Store Connectia. `Memorize` on
  App Store -haussa täynnä kertauskorttisovelluksia; ehdotuksia: *Heirloom*,
  *Kinfolk*, *Storykeeper*, *Rootline*, *Perennial*.
- **ASR-toteutus.** Ratkeaa jakson A testissä.
- **Hinnat.** Ilmainen 1 perhe / ~20 kuvaa / ~10 AI-min kk. Maksullinen
  ~9,99 €/kk tai 59,99 €/v. Test Storessa nimellisiä, mutta harkittuja.
