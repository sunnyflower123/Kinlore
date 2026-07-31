# The mark

The chosen mark is **C — the locket**. A closed disc with a waveform inside and
a bail on top.

The mark is deliberately *nameless*: `Memorize` is a working title (PLAN.md §10),
and a locket still works after the name changes. Only the lockup files carry the
name.

## Why a locket

A locket is an object a grandmother has worn round her neck for decades and
which opens to show a face. It is the app's promise as an object: a family
memory, carried with you. Inside is a waveform rather than a photograph, because
rule 3 says the original audio is always kept — the speaker may no longer be
around to ask. The middle bar is amber: it is the living voice.

## Why A was rejected

Concept A (growth rings, `concept-a-rings.svg`) was the first recommendation. It
was rejected only once the icon had been seen on the simulator's home screen,
for two reasons:

1. **Collision.** The ConnectFul and Hetkio icons are both a broken ring with a
   centre point. Growth rings were the same idea with inverted colours, and
   Memorize did not read as its own app on the same screen.
2. **Liquid Glass.** iOS 26 draws a reflection over the icon that darkens and
   muddies a dark background. Espresso went almost black and parchment dimmed to
   grey. A light background survives the same treatment brightly.

Neither could have been deduced from the source artwork. **An icon has to be
looked at on the home screen before it is finished** — the same rule as looking
at a screen at the largest text size.

The file is kept in the repo so the reasoning stays traceable.

## Palette

| | Hex | Use |
|---|---|---|
| Parchment | `#FBF1E2` | Icon background |
| Ink | `#241A14` | Mark and text |
| Amber | `#E8A33C` | Middle bar in the icon and in the light lockup |
| Terracotta | `#C4552C` | Middle bar in the dark lockup |
| Espresso | `#2E1D16` | Reserved for dark surfaces |

Ink on parchment is 14:1, amber on ink 7.3:1. The figures come from the source
artwork; the operating system's own processing changes the result, see above.
The primary user is 80 years old, and the mark is no exception to that rule.

## Files

| File | What for |
|---|---|
| `concept-c-locket.svg` | The chosen mark, in icon form (512, full background) |
| `icon-tinted.svg` | Tinted variant for iOS 18+ (greyscale, transparent) |
| `mark-mono.svg` | The mark alone, `currentColor` — README, favicon, UI |
| `lockup.svg` | Mark + name, horizontal, for light surfaces |
| `lockup-dark.svg` | The same for dark surfaces — the root README switches between them |
| `concept-b-bubble.svg` | Alternative: the talking photo |
| `concept-a-rings.svg` | Rejected, see above |

## Export

The icon is wired up: `ios/Memorize/Assets.xcassets/AppIcon.appiconset`.
When the SVG changes, regenerate the PNGs:

```bash
qlmanage -t -s 1024 -o . docs/logo/concept-c-locket.svg
```

The tinted variant is a separate file, because without it iOS generates a tinted
version automatically and the result is a grey blob.

## The wordmark

The name is set in Charter Bold and converted to outlines, so the lockup does
not depend on the fonts a reader happens to have. It used to be a `<text>`
element asking for `New York, Charter, Georgia, serif`. On this Mac that looked
right; with Georgia — the likely fallback on Windows — the last letter clipped
at the edge of the viewBox. The README is read mostly on machines without
Apple's fonts, so the bug was live on GitHub and invisible here.

Charter rather than New York because Bitstream Charter's licence allows its
letterforms to be used this way, while Apple's fonts are licensed for user
interface mock-ups.

`Memorize` is still a working title, so the wordmark will need regenerating:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/outline-wordmark.swift Memorize Charter 0.4 92 -1 178 132
```

The script prints the bounding box to stderr. The viewBox has to be wide enough
for its right edge, or the name clips again.
