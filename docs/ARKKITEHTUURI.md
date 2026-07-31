# Arkkitehtuuri — loppuosa

Tämä dokumentti suunnittelee sen mitä ei ole vielä rakennettu. Toteutettu osa on
kuvattu [PLAN.md](PLAN.md) §6:ssa ja koodissa.

---

## 1. Missä ollaan

Rehellinen inventaario, ei toivelista:

| Osa | Tila |
|-----|------|
| Sanelu, kirjoitus, jäsennys, nimien korjaus | **Valmis ja testattu** |
| Kuvien tuonti, galleria, henkilökortit | **Valmis** |
| `subject`, `memory`, `mention`, `prompt_question` | Käytössä |
| Identiteetti, perhe, kutsulinkit | **Valmis ja testattu** |
| Synkronointi (`/sync` veto ja työntö) | **Valmis ja testattu** |
| `relation`, `usage_counter`, `report`, `block` | **Skeemassa, ei käytössä** |
| Media R2:een (`/media`) | **Valmis ja testattu** |
| RevenueCat, kiintiöt, moderointi | Ei aloitettu |

Kriittinen polku on nyt auki: perhe ja synkronointi toimivat, joten media,
kiintiöt ja moderointi voidaan rakentaa niiden päälle. Jäljellä oleva työ on
rinnakkaista ja leikattavissa.

**Todennetut säännöt.** Vahvistus on yksisuuntainen, sulautus tarttuva, vain
kirjoittaja muokkaa omaansa, ja toinen perhe ei näe eikä voi kirjoittaa. Lähtevä
jono säilyy levyllä sovelluksen sulkemisen yli, eikä paikallisesti muuttunut rivi
huku etäversion alle.

## 2. Viisi päätöstä jotka ratkaisevat loput

### 2.1 Paikallinen ensin, ei palvelin ensin

**Päätös: jokainen kirjoitus menee ensin paikalliseen tallennukseen ja
synkronoituu taustalla.**

Vaihtoehto olisi ollut suora palvelinkutsu joka kirjoituksessa. Se on
yksinkertaisempi, mutta väärä tälle sovellukselle: 80-vuotias voi olla mökillä
ilman kenttää, ja muisto jonka hän juuri kertoi on korvaamaton. Puhuja ei ehkä
ole enää kysyttävissä.

Hinta on synkronointikoneisto ja ristiriitojen käsittely. Se on hyväksyttävä
hinta siitä että **mikään kerrottu ei koskaan katoa verkon takia**.

### 2.2 Perhekohtainen juokseva numero, ei aikaleimoja

Synkronoinnin järjestys tulee `family.sync_seq`-laskurista, jota palvelin
kasvattaa jokaisella kirjoituksella. Ei laitteiden kelloista.

Syy: laitteiden kellot ovat eri ajassa, ja iäkkään käyttäjän puhelimessa
aikavyöhyke voi olla väärä vuosikausia. Aikaleimapohjainen järjestys tuottaisi
satunnaisia hävinneitä kirjoituksia joita on mahdoton jäljittää. Perheen arkisto
on satoja rivejä, joten yksi laskuri riittää mainiosti.

### 2.3 Muistot ovat lisättäviä, eivät muokattavia

`memory` on käytännössä append-only. Vain kirjoittaja itse voi muokata tai
poistaa omansa, ja ainoa automaattinen muokkaus on nimenkorjauksen tekemä
tekstin päivitys.

Tämä poistaa ristiriidat lähes kokonaan: kaksi ihmistä ei voi muokata samaa
muistoa. Se on myös oikea tuotesääntö — kukaan ei saa siivota isoäidin kertomaa.

### 2.4 Vahvistus on yksisuuntainen

`confirmed = 1` ei koskaan palaudu nollaksi synkronoinnissa.

Ilman tätä sääntöä vanha laite joka tulee verkkoon viikon jälkeen voisi
"palauttaa" vahvistetun henkilön takaisin ehdotukseksi. Sama koskee
`relation.confirmed`ia.

### 2.5 Sulautus ei poista, se ohjaa

**Tämä on korjaus jo tehtyyn koodiin.** `MemoryStore.rename` poistaa nyt
sulautetun kohteen. Yhdellä laitteella se toimii, mutta synkronoinnissa se
rikkoo: jos laite A sulauttaa *Aune → Aino* samaan aikaan kun laite B on offline
lisäämässä muistoja Aunelle, B:n muistot osoittavat kadonneeseen kohteeseen.

Ratkaisu on hautakivi jossa on osoite:

```sql
ALTER TABLE subject ADD COLUMN merged_into TEXT REFERENCES subject(id);
```

Sulautettu rivi jää paikalleen `merged_into`-viitteellä, ja kaikki viittaukset
seuraavat ketjua. Mikään ei osoita tyhjään, ja sulautuksen voi jopa perua.

## 3. Synkronointi

### Reitit

```
GET  /sync?since=<seq>     → muuttuneet rivit + uusi kursori
POST /sync                 → paikalliset muutokset, palauttaa myönnetyt seq:t
```

Molemmat vaativat jäsentunnisteen (§4). Palvelin palauttaa vain pyytäjän oman
perheen rivit — perhe on eristysraja, ja se tarkistetaan jokaisessa kyselyssä
eikä vain liittymisessä.

### Rivien lisäkentät

Jokainen synkronoituva taulu saa:

```sql
seq         INTEGER NOT NULL   -- palvelimen myöntämä, perhekohtainen
deleted_at  INTEGER            -- pehmeä poisto, jotta poisto leviää
```

Pehmeä poisto on pakollinen: kova poisto ei koskaan päädy toiselle laitteelle,
joka jatkaisi poistetun rivin näyttämistä ikuisesti.

### Asiakkaan lähtevä jono

Paikalliset muutokset kirjataan `outbox`-jonoon: operaatio, kohde-id ja hyötykuorma.
Jono puretaan taustalla eksponentiaalisella odotuksella.

Operaatiot ovat **idempotentteja**: kaikki on upsert asiakkaan generoimalla
UUID:llä. Sama operaatio kahdesti ei riko mitään, mikä tekee uudelleenyrityksestä
turvallista ilman koordinaatiota.

### Ristiriitasäännöt

| Tilanne | Ratkaisu |
|---------|----------|
| Kaksi muistoa samaan kohteeseen | Ei ristiriitaa, molemmat säilyvät |
| Sama muisto muokattu kahdella laitteella | Ei mahdollista: vain kirjoittaja muokkaa |
| Kohteen nimi muutettu kahdella | Suurempi `seq` voittaa |
| Toinen vahvistaa, toinen ei | Vahvistus voittaa aina (§2.4) |
| Toinen sulauttaa, toinen lisää | Sulautus ohjaa, mitään ei katoa (§2.5) |
| Toinen poistaa muiston, toinen lukee | Vain kirjoittaja voi poistaa |

Loput ratkeaa suuremmalla `seq`:llä. Sääntöjä on tarkoituksella vähän — jokainen
lisäsääntö on kohta jossa data voi hiljaa vääristyä.

### Miksi JSON eikä SQLite

Paikallinen tallennus pysyy JSON-tiedostona myös synkronoinnin jälkeen.

Perheen arkisto on satoja rivejä, ei satojatuhansia. Koko tiedosto mahtuu
muistiin, ja kirjoitus on atominen. SQLite toisi indeksit ja osittaiset
päivitykset, mutta myös riippuvuuden, migraatiot ja enemmän koodia arvioitavaksi.

**Vaihda vasta jos mittaat ongelman.** Puolivalmis SQLite-kerros on huonompi
kuin toimiva JSON, ja tämä repo tuomaroidaan luettavuudesta.

## 4. Identiteetti ja perhe

### Ei kirjautumisruutua

Ensimmäisellä käynnistyksellä luodaan Keychainiin
(`kSecAttrSynchronizable`, synkronoituu iCloudin kautta käyttäjän laitteille):

- `member_id` — UUID
- `device_secret` — 32 satunnaista tavua

Palvelin tallentaa salaisuudesta vain tiivisteen, kuten salasanasta. Pyynnöt
tunnistautuvat `Authorization: Bearer <member_id>.<device_secret>`.

80-vuotias ei näe tästä mitään. Hän saa linkin lapsenlapselta ja on sisällä.

### Kutsu

```
POST /family              → luo perhe, kutsuja on omistaja
POST /family/invite       → luo kutsukoodi, voimassa 7 vrk
POST /family/join         → { code } liittää jäsenen
GET  /family              → jäsenet, oma rooli, kutsulinkin tila
DELETE /family/invite/:id → mitätöi linkki
```

**Kutsulinkki on koko turvallisuusraja.** Kuka tahansa linkin saanut näkee
perheen kaikki muistot. Siksi:

- Koodi on pitkä ja satunnainen, ei ihmisen luettavaksi tarkoitettu
- Voimassaolo umpeutuu, ja omistaja voi mitätöidä sen milloin tahansa
- Liittymisyritykset rajoitetaan (Cloudflaren `ratelimits`, kuten Hetkiossa)
- Perheen näkymässä näkyy kuka on liittynyt ja milloin

Tämä on kohta jossa yksinkertaisuus ja turvallisuus ovat oikeasti ristiriidassa,
ja valinta on tietoinen: helppous voittaa, koska kirjautumismuuri karkottaisi
juuri sen käyttäjän jota varten sovellus on olemassa.

### Kutsulinkin muoto — tiedostettu puute

Linkki on `memorize://join?code=...`. **iOS näyttää mukautetulle URL-skeemalle
vahvistusdialogin** ("Open in Memorize?"), joka on englanninkielinen ja
ylimääräinen askel juuri sille käyttäjälle joka hämmentyy helpoiten.

Universal link (`https://…`) avautuisi suoraan ilman dialogia, mutta se vaatii
verkkotunnuksen ja AASA-tiedoston — eli store-julkaisun infrastruktuuria.

Lievennys on jo paikallaan: jaettava teksti sisältää **sekä linkin että
koodin**, ja liittymislomakkeessa on liittämiskenttä. Isoäiti pääsee perheeseen
vaikka linkki ei aukeaisi lainkaan. Jos verkkotunnus joskus hankitaan, tämä on
ensimmäinen asia joka kannattaa vaihtaa.

### Identiteetti kestää sovelluksen poiston

Keychain-merkinnät säilyvät sovelluksen poiston yli, ja
`kSecAttrSynchronizable` vie ne iCloudin kautta käyttäjän muille laitteille.
Todennettu: sama jäsentunnus kolmella käynnistyksellä, myös poiston ja
uudelleenasennuksen jälkeen.

Se on oikea käytös tälle käyttäjäryhmälle. Vahingossa poistettu sovellus ei saa
tarkoittaa perheen menettämistä.

## 5. Media

Kuvat ja äänet menevät R2:een, metatieto D1:een.

```
POST /media          → lataa tiedosto, palauttaa r2_key
GET  /media/:key     → lataa (tarkistaa perheen jäsenyyden)
```

Paikallinen tiedostonimi ja R2-avain ovat **eri kenttiä** (`imageFilename` ja
`r2Key`). Sama kuva on eri laitteilla eri tiedostonimellä mutta samalla
avaimella, joten yksi kenttä ei riittäisi.

Lataus tapahtuu **ennen työntöä**, jotta rivit kulkevat avaimineen. Muuten
toinen laite näkisi muiston mutta ei kuvaa johon se liittyy.

Nouto on **tarvepohjainen**: perheellä voi olla satoja kuvia, eikä niitä haeta
käynnistyksessä. Ruudukko noutaa vain sen mitä näkyy.

**MVP:ssä tiedosto kulkee Workerin läpi.** Kuvat ovat noin 300 kt (pienennetty
2048 pikseliin) ja 90 sekunnin ääni noin 200 kt, joten se on täysin riittävää.
Esiallekirjoitetut URL:t ovat oikea ratkaisu isommilla tiedostoilla, mutta ne
lisäisivät nyt vain liikkuvia osia.

Lataus on osa lähtevää jonoa: kuva näkyy heti paikallisesti, ja muut perheen
jäsenet näkevät sen kun synkronointi ehtii. Offline lisätty kuva ei katoa.

**Alkuperäinen ääni ladataan aina**, myös ilmaisella tasolla. Se on tuotteen
ydin eikä lisäominaisuus.

## 6. Raha

### Malli

Maksaja ei ole hyötyjä: lapsenlapsi ostaa, koko perhe saa. RevenueCat antaa
oikeuden ostajalle, backend levittää sen perheelle.

```
POST /entitlement/sync   → asiakas kertoo ostaneensa, palvelin VARMISTAA
POST /webhook/revenuecat → uusinta, peruutus, hyvitys
```

**Asiakkaan sanaan ei luoteta.** `/entitlement/sync` ei ota vastaan tilaa vaan
vihjeen: palvelin kysyy totuuden RevenueCatin REST-rajapinnasta
`RC_SECRET_KEY`:llä ja kirjoittaa `family.entitlement`in sen perusteella.
Webhook pitää sen ajan tasalla ilman että sovellusta tarvitsee avata.

### Reunatapaukset joita ei saa unohtaa

| Tilanne | Käytös |
|---------|--------|
| Tilaus päättyy | Perhe palaa ilmaistasolle. **Mitään ei poisteta.** Vanhat kuvat ja äänet säilyvät ja ovat luettavissa; rajat koskevat vain uutta. |
| Maksaja poistuu perheestä | Oikeus raukeaa seuraavassa webhookissa. Toinen jäsen voi ostaa. |
| Kaksi maksajaa | Pisin voimassaolo voittaa. Molemmat näkyvät perheen näkymässä. |
| Hyvitys | Webhook laskee oikeuden heti. |

Sääntö **"alennus ei koskaan poista"** on ehdoton. Perhe joka menettää muistoja
maksun päätyttyä ei palaa koskaan, eikä sellaista tuotetta pidä tehdä.

### Paywallin paikka

Heti kun ensimmäinen AI-jäsennelty muisto valmistuu. Silloin koettu arvo on
huipussaan. Ei onboardingissa, ei asetuksissa.

**Kertomista ei paywallata koskaan.** Rajat koskevat kuvamäärää ja AI-minuutteja.

## 7. Kiintiöt ja moderointi

### Kiintiöt palvelimella

`usage_counter` tarkistetaan **ennen** OpenRouter-kutsua ja kasvatetaan sen
jälkeen. Asiakkaan laskuriin ei luoteta — se on muokattavissa.

Kahden laitteen yhtäaikainen kutsu voi ylittää rajan hieman. Se on hyväksyttävää:
vaihtoehto olisi lukitus, joka maksaisi enemmän kuin muutama ylimääräinen
sekunti puhetta.

Kun raja tulee vastaan, sanelu estyy mutta **kirjoittaminen ei** — muuten
maksumuuri estäisi kertomista, mikä on säännön 2 vastaista.

### Moderointi

`report` ja `block` ovat skeemassa, koska Applen sääntö 1.2 vaatii ne
käyttäjäsisältöä sisältävältä sovellukselta. Toteutus on pieni:

- Muiston voi raportoida (kirjaus `report`-tauluun)
- Jäsenen voi estää, jolloin hänen muistonsa piiloutuvat estäjältä
- Perheen omistaja voi poistaa jäsenen

**Tämä on kuitenkin perheen yksityinen kanava, ei julkinen verkosto.** Todellinen
väärinkäyttöriski on pieni, ja ratkaisu on sen mukainen: ei ilmoituskeskusta eikä
moderointijonoa, vain vaadittu minimi. Jos julkaisu jää tekemättä, tämän voi
leikata kokonaan (PLAN.md §5, kohta 6).

## 8. Jäljellä olevat ruudut

Järjestyksessä, tärkein ensin:

1. **Aloitus** — kaksi vaihtoehtoa: "Aloita perheen arkisto" tai "Liity linkillä".
   Ei muuta. Yksi ruutu.
2. **Perhe** — jäsenet, kutsulinkin jakaminen, poistuminen.
3. **Äänen toisto** — muistokortin "Kuuntele omalla äänellä" on tällä hetkellä
   pelkkä merkintä. Tämä on emotionaalisesti tuotteen vahvin yksityiskohta ja
   toteutuksena pieni.
4. **Avoimet kysymykset** — koottu näkymä `prompt_question`ista. Tämä on
   retention-moottori: avoin kysymys on syy palata.
5. **Suhteet** — henkilökortista "lisää vanhempi / puoliso / sisarus".
   Vahvistamaton suhde näkyy ehdotuksena.
6. **Paywall** — RevenueCatin oma paywall riittää, ei omaa toteutusta.
7. **Asetukset** — vienti, tilin poisto, raportointi ja esto.
8. **Sukupuu** — piirretty graafi. **Ansa.** Tehdään vain jos kaikki muu on
   valmista ja kiillotettua.

## 9. Rakennusjärjestys

Kiinnitetty PLAN.md §8:n jaksoihin.

| Jakso | Sisältö |
|-------|---------|
| **C** (11.–31.8.) | Identiteetti, perhe, kutsulinkki, synkronoinnin runko. `merged_into` -korjaus ennen kuin synkronointi rakennetaan sen päälle. |
| **D** (1.–14.9.) | Media R2:een, RevenueCat, kiintiöt, paywall. Käsityö ja saavutettavuus. |
| **E** (15.–24.9.) | Äänen toisto, avoimet kysymykset, suhteet. Testaus isovanhemmalla. Repo englanniksi. |
| **F** (25.–28.9.) | Demovideo, submissio. |

### Kriittinen polku

Synkronointi on ainoa asia joka **estää** muita: media, kiintiöt ja moderointi
kaikki olettavat jäsenyyden ja perheen. Se pitää saada toimimaan jakson C aikana
tai loput valuu.

Kaikki muu on rinnakkaista ja leikattavissa.

### Mitä leikataan ensin

PLAN.md §5:n järjestys pätee edelleen, ja tämä suunnitelma tarkentaa sen
ykköskohdan: **jos synkronointi ei valmistu, siemennetään demoperhe.**

Tietomalli tukee jo useaa jäsentä (`memory.author_id`), joten video voi näyttää
usean sukulaisen muistot samassa kuvassa vaikka liittymisvirtaa ei olisi
rakennettu. Konsepti näkyy, toteutus on kesken — ja se on rehellisempi
lopputulos kuin puolivalmis synkronointi joka hukkaa dataa demossa.
