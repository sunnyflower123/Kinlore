# Tunnus

Valittu merkki on **C — medaljonki**. Umpinainen kiekko, jonka sisällä on
ääniaalto, ja päällä ripustin.

Merkki on tarkoituksella *nimetön*: `Memorize` on työnimi (PLAN.md §10), ja
medaljonki toimii myös nimen vaihduttua. Vain `lockup.svg` sisältää nimen.

## Miksi medaljonki

Medaljonki on esine jota isoäiti on pitänyt kaulassaan vuosikymmeniä ja joka
aukeaa näyttämään kasvot. Se on sovelluksen lupaus esineenä: perheen muisto,
jota kannetaan mukana. Sisällä on ääniaalto eikä valokuva, koska sääntö 3 sanoo
että alkuperäinen ääni säilytetään aina — puhuja ei ehkä ole enää
kysyttävissä. Keskimmäinen palkki on meripihkan värinen: se on elävä ääni.

## Miksi A hylättiin

Konsepti A (vuosirenkaat, `concept-a-rings.svg`) oli ensimmäinen suositus.
Se hylättiin vasta kun ikoni nähtiin simulaattorin kotinäytöllä, ja kahdesta
syystä:

1. **Törmäys.** ConnectFulin ja Hetkion ikonit ovat molemmat katkaistu rengas
   ja keskipiste. Vuosirenkaat olivat sama idea käänteisin värein, eikä
   Memorize erottunut omaksi sovelluksekseen samalla ruudulla.
2. **Liquid Glass.** iOS 26 piirtää ikonin päälle heijastuksen, joka tummentaa
   ja mudentaa tumman taustan. Espresso meni lähes mustaksi ja pergamentti
   himmeni harmaaksi. Vaalea tausta selviää samasta käsittelystä kirkkaana.

Kumpaakaan ei olisi voinut päätellä lähdeaineistosta. **Ikoni pitää katsoa
kotinäytöltä ennen kuin se on valmis** — sama sääntö kuin ruudun katsominen
suurimmalla tekstikoolla.

Tiedosto on jätetty repoon, jotta perustelu on jäljitettävissä.

## Väripaletti

| | Hex | Käyttö |
|---|---|---|
| Pergamentti | `#FBF1E2` | Ikonin tausta |
| Muste | `#241A14` | Merkki ja teksti |
| Meripihka | `#E8A33C` | Keskimmäinen palkki ikonissa |
| Terrakotta | `#C4552C` | Keskimmäinen palkki lockupissa |
| Espresso | `#2E1D16` | Varalla tummiin pintoihin |

Muste pergamentin päällä on 14:1, meripihka musteen päällä 7,3:1. Luvut ovat
lähdeaineistosta; käyttöjärjestelmän oma käsittely muuttaa lopputulosta, ks.
yllä. Ensisijainen käyttäjä on 80-vuotias, eikä tunnus ole poikkeus siitä
säännöstä.

## Tiedostot

| Tiedosto | Mihin |
|---|---|
| `concept-c-locket.svg` | Valittu merkki, ikonimuodossa (512, täysi tausta) |
| `icon-tinted.svg` | Sävytetty variantti iOS 18+ (harmaasävy, läpinäkyvä) |
| `mark-mono.svg` | Pelkkä merkki, `currentColor` — README, favicon, UI |
| `lockup.svg` | Merkki + nimi vaakasuunnassa |
| `concept-b-bubble.svg` | Vaihtoehto: puhuva kuva |
| `concept-a-rings.svg` | Hylätty, ks. yllä |

## Vienti

Ikoni on kytketty: `ios/Memorize/Assets.xcassets/AppIcon.appiconset`.
Kun SVG muuttuu, PNG:t generoidaan uudelleen:

```bash
qlmanage -t -s 1024 -o . docs/logo/concept-c-locket.svg
```

Sävytetty variantti on erillinen tiedosto, koska ilman sitä iOS tekee
sävytetyn version automaattisesti ja lopputulos on harmaa möykky.

`lockup.svg` käyttää järjestelmän serif-fonttia. Ennen kuin nimi menee videoon
tai READMEen, teksti pitää muuttaa poluiksi — muuten se renderöityy eri fontilla
joka koneella.
