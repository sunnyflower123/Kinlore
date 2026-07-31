# Tunnus

Kolme konseptia. Suositus on **A — vuosirenkaat ja aukko**.

Merkki on tarkoituksella *nimetön*: `Memorize` on työnimi (PLAN.md §10), ja
renkaat toimivat myös nimen vaihduttua. Vain `lockup.svg` sisältää nimen.

## A — vuosirenkaat ja aukko

Puun vuosirenkaat, joissa jokainen rengas on eri paksuinen — vuodet eivät ole
samanmittaisia. Renkaat luetaan myös ääniaaltoina, jotka lähtevät keskipisteestä.
Keskipiste on kertoja, keltainen ja elävä.

Kiila renkaiden läpi on **aukko**, ei virhe. Suunnitteluperiaate 5 sanoo:
*aukot näytetään, tyhjä henkilökortti on kutsu.* Tunnuksessa on reikä, ja se on
osa muotoa.

## Väripaletti

| | Hex | Käyttö |
|---|---|---|
| Espresso | `#2E1D16` | Ikonin tausta |
| Pergamentti | `#FBF1E2` | Merkki tummalla |
| Meripihka | `#E8A33C` | Keskipiste ikonissa |
| Terrakotta | `#C4552C` | Keskipiste vaalealla |
| Muste | `#241A14` | Merkki ja teksti vaalealla |

Pergamentti espresson päällä on kontrastisuhteeltaan 14:1, meripihka 6,9:1.
Molemmat ylittävät WCAG AA:n reilusti — ensisijainen käyttäjä on 80-vuotias,
eikä tunnus ole poikkeus siitä säännöstä.

## Tiedostot

| Tiedosto | Mihin |
|---|---|
| `concept-a-rings.svg` | Suositus, ikonimuodossa (512, täysi tausta) |
| `concept-b-bubble.svg` | Vaihtoehto: puhuva kuva |
| `concept-c-locket.svg` | Vaihtoehto: medaljonki |
| `mark-mono.svg` | Pelkkä merkki, `currentColor` — README, favicon, UI |
| `lockup.svg` | Merkki + nimi vaakasuunnassa |

## Vienti

Sovelluksessa ei ole vielä `.xcassets`-luetteloa. 1024×1024 PNG ikonia varten:

```bash
qlmanage -t -s 1024 -o . docs/logo/concept-a-rings.svg
```

`lockup.svg` käyttää järjestelmän serif-fonttia. Ennen kuin nimi menee videoon
tai READMEen, teksti pitää muuttaa poluiksi — muuten se renderöityy eri fontilla
joka koneella.
