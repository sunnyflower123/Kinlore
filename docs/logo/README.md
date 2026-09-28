# The mark

The chosen mark is **C — the locket**. A closed disc with a waveform inside and
a bail on top.

The mark is deliberately *nameless*, and it earned that on 15 Aug 2026 when
`Memorize` became **Kinlore** (PLAN.md §10): the locket needed no redrawing at
all, and only the two lockup files carried the name.

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
   the app did not read as its own on the same screen.
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
Whoever tells is often an older person, and the mark is no exception to rule 1.

## Files

| File | What for |
|---|---|
| `concept-c-locket.svg` | The chosen mark, in icon form (512, full background) |
| `mark.svg` | The same mark without the background — source of the launch screen PNGs |
| `icon-tinted.svg` | Tinted variant for iOS 18+ (greyscale, transparent) |
| `mark-mono.svg` | The mark alone, `currentColor` — UI and one-colour contexts |
| `favicon.svg` | Redrawn for 16 px, see below |
| `favicon-16.png`, `favicon-32.png` | Raster fallbacks for browsers that want them |
| `lockup.svg` | Mark + name, horizontal, for light surfaces |
| `lockup-dark.svg` | The same for dark surfaces — DETAILS.md and simple.html switch between them |
| `title-plate.svg` | The lockup on a parchment plate with a double rule, the root README's title |
| `title-plate-dark.svg` | The same on espresso with amber rules, for GitHub's dark theme |
| `divider.svg`, `divider-dark.svg` | The mark between two hairlines, where the root README's pictures end |
| `concept-b-bubble.svg` | Alternative: the talking photo |
| `concept-a-rings.svg` | Rejected, see above |

## Export

The icon is wired up: `ios/Kinlore/Assets.xcassets/AppIcon.appiconset`.
When the SVG changes, regenerate the PNGs:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/render-svg.swift docs/logo/concept-c-locket.svg ios/Kinlore/Assets.xcassets/AppIcon.appiconset/icon-1024.png 1024
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/render-svg.swift docs/logo/icon-tinted.svg ios/Kinlore/Assets.xcassets/AppIcon.appiconset/icon-1024-tinted.png 1024
```

The launch screen mark comes from `mark.svg`, which is the locket without the
parchment rectangle, at the three scales the asset catalog expects:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/render-svg.swift docs/logo/mark.svg ios/Kinlore/Assets.xcassets/LaunchMark.imageset/mark.png 120
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/render-svg.swift docs/logo/mark.svg ios/Kinlore/Assets.xcassets/LaunchMark.imageset/mark@2x.png 240
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/render-svg.swift docs/logo/mark.svg ios/Kinlore/Assets.xcassets/LaunchMark.imageset/mark@3x.png 360
```

Do not use `qlmanage -t` for this. Quick Look composites onto white, so the
tinted variant shipped as an opaque white square rather than a transparent
greyscale mark. Every preview looked correct; the bug only surfaced when the
pixels were read back. `render-svg.swift` prints the corner alpha for exactly
that reason.

The tinted variant is a separate file, because without it iOS derives one from
the default icon and the result is a grey blob.

Verified on a home screen in tinted appearance: the locket reads as a light disc
with the three bars cut out of it, the bail intact and distinct from ConnectFul
and Hetkio beside it.

## Launch screen

Parchment with the mark centred on it (`UILaunchScreen`, see `ios/project.yml`).
The app used to open on a white flash, which is also how the demo video would
have started.

This is not a splash screen. Nothing is held for effect: the frame appears only
for as long as the app takes to draw, and making an older teller wait to admire
a logo would be the opposite of what this app is for.

### The launch screen lies to you

**iOS caches a snapshot of the launch screen and keeps serving it after the
launch screen has changed.** The cache survives rebuilding, reinstalling, and
even deleting the app — and it is why the mark first appeared to sit on a white
card, and then, once restored, appeared not to render at all.

The white card was blamed on iOS compositing the image onto an opaque plate.
That is wrong. Measured on a cleared cache, a transparent PNG and an opaque
parchment one render identically, and neither has a plate: the pixel beside the
mark reads `(251, 241, 226)`, the background colour exactly.

So the rule about looking at the icon on the home screen has a second half:

```bash
xcrun simctl shutdown <udid>
find ~/Library/Developer/CoreSimulator/Devices/<udid>/data -type d -name SplashBoard -exec rm -rf {} +
xcrun simctl boot <udid>
```

Purge, restart, *then* believe what you see. Deleting only the app's own
`Library/SplashBoard` is not enough; the device keeps snapshots of its own.

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

The wordmark was regenerated for **Kinlore** on 16 Aug 2026. Both lockups carry
the new outline, and the viewBox went from 614 to 501 — the name is shorter, and
the width is its right edge plus the same 20.78 margin the old one had:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/outline-wordmark.swift Kinlore Charter 0.4 92 -1 178 132
```

The script prints the bounding box to stderr. The viewBox has to be wide enough
for its right edge, or the name clips again. The two title plates carry the
same path inside a scaled group, so a new outline goes into all four files.

## Favicon

`favicon.svg` is drawn separately rather than scaled down from the icon, and it
is a different drawing on purpose: **the bail is gone and the disc fills the
square.**

Shrinking the real icon to 16 px turns the bail into a grey smudge and squeezes
the two parchment bars until they disappear — and it wastes a fifth of the
square on the margin the app icon needs. Drawn with the bail kept and the disc
made smaller to fit it, the result was worse still. At 16 px nothing reads as a
locket anyway; what survives is a dark disc with three bars and an amber centre,
so that is what the favicon is.

It is authored on a 16-unit grid so the edges land on whole pixels. Regenerate
the rasters after editing it:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/render-svg.swift docs/logo/favicon.svg docs/logo/favicon-16.png 16
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/render-svg.swift docs/logo/favicon.svg docs/logo/favicon-32.png 32
```

Nothing consumes these yet. **A GitHub repository page cannot have a favicon** —
the tab always shows GitHub's own. They are here for the first page that is
actually ours: a GitHub Pages site, or a landing page for the Devpost entry.

```html
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<link rel="icon" href="favicon-32.png" sizes="32x32">
```
