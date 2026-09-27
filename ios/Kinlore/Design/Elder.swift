import SwiftUI

/// Design constants that keep the app usable for an 80-year-old.
///
/// These are not style preferences but the core of the product: if a screen does
/// not work at the largest text size, it is not done. Apple's minimum tap target
/// is 44 pt, but that is designed for a steady hand — we use 60 pt.
enum Elder {
    /// The smallest tap target. Never below this, not even for secondary
    /// actions.
    static let minTapTarget: CGFloat = 60

    /// The diameter of the record button. It is the app's most important
    /// control, and it has to be findable without reading.
    static let recordButtonSize: CGFloat = 200

    /// Body text leading. Generous line spacing helps a person with poor
    /// eyesight keep their place on the line.
    static let lineSpacing: CGFloat = 6

    /// "This phone belongs to the person this app was designed for."
    ///
    /// Read straight out of `UserDefaults` by `@AppStorage`, so it is device
    /// state and never family data — like the question ladder's comfort, and for
    /// the same reason: it describes whoever is holding the phone.
    ///
    /// Apple's advice is to take the system text size as given, and that advice
    /// assumes the person holding the phone is the person who set it up. Here
    /// they are usually two different people: the setting up is done by a
    /// grandchild in a few minutes, and the one who cannot read the screen is
    /// the one who has never opened iOS Settings. So the app asks, once, in the
    /// only place where the grandchild is already answering questions.
    static let largerTextKey = "elder.largerText"

    /// Part of emptying the device, beside the ladder's comfort and the deck's
    /// skips — and for the identical reason: this is an answer about *whose
    /// phone this is*, and an emptied device has not been asked yet. It was the
    /// last piece of device state the wipe left behind, so the returning
    /// onboarding fork met its own question with the previous household's
    /// answer already filled in.
    ///
    /// Cheap to lose and cheap to give back: `textFloor` is a floor and never a
    /// ceiling, so anybody who enlarged iOS's own text keeps every notch of it,
    /// and the question is re-asked two screens later on either path.
    ///
    /// Named `forgetLargerText` and not `reset`, which is what every other
    /// device-local store here is called. `Elder.reset()` would read as
    /// resetting the design tokens; this touches exactly one key.
    static func forgetLargerText() {
        UserDefaults.standard.removeObject(forKey: largerTextKey)
    }

    /// The smallest text the app will draw once that question is answered
    /// "grandmother's".
    ///
    /// A floor and never a ceiling: iOS's own setting stays in charge above it,
    /// so somebody who has already enlarged their text keeps the size they
    /// chose. One notch and not three — every screen is audited to XXXL, so
    /// bigger would be *safe*, but each notch is a line less of the memory or
    /// the question on screen, and taking that away from somebody who did not
    /// ask for it is its own kind of failure.
    static let textFloor: DynamicTypeSize = .xLarge

    static let screenPadding: CGFloat = 24

    // MARK: - The surface
    //
    // Warm paper instead of white. Every ratio below is WCAG 2.1, measured
    // 9 Sep 2026 against the surface named — the same arithmetic the
    // accessibility audit applies, and the reason these are seven asset
    // entries rather than seven hex literals in Swift: a colour that lives in
    // one place can be re-measured, and one that is typed at fourteen call
    // sites cannot.
    //
    // **They carry no dark variant, and that is a decision rather than an
    // omission.** The app pins `.preferredColorScheme(.light)` for all of v1
    // (KinloreApp.swift) because `destructive` lands at ≈2.6:1 and the accent
    // at ≈2.7:1 on a dark ground — ≈2.9:1 since the accent became `wax` —
    // under the minimum on exactly the labels rule 1 exists for. Half a dark system, surfaces done and controls not,
    // is the unmeasured second appearance that comment rejects. The pair to
    // start from when somebody does the whole piece of work, measured the same
    // day: paper `#17120F`, card `#221B16`, text `cream` (16.1:1 on that
    // card), proposal `#E8734A` (5.65:1), affirmative `#5FBE7E` (7.40:1).

    /// The screen behind everything. 15.17:1 under primary text.
    static let paper = Color("Paper")

    /// Cards, sheets and rows — a shade lighter than the paper they sit on, so
    /// the edge is visible without a border doing the work. 16.81:1 under
    /// primary text.
    static let card = Color("Card")

    /// A hairline, and only ever a hairline: ink at 16 % measures **1.39:1**.
    /// Never text, and never the only edge of a control — a border this quiet
    /// is a suggestion of a boundary, not a boundary.
    static let rule = Color("Rule")

    /// The recording control's fill. Sealing wax rather than iOS's red, and
    /// the swap is a contrast *gain*: `cream` on this measures **5.59:1**,
    /// where white on the system red measures ~3.55:1. That clears the text
    /// minimum and not merely the 3:1 a graphic is judged by, so the disc
    /// could carry a word if it ever had to. It measures 5.12:1 against
    /// `paper` itself, so the disc is also plainly an object on the page.
    ///
    /// The glyph still says it: a mic is a mic and a stop is a stop whatever
    /// the colour does.
    ///
    /// **And the accent, since 26 Sep 2026.** `AccentColor` carries the same
    /// value — `palette-contrast-check.mjs` fails if the two part — so the
    /// selected tab, the one prominent button and whatever starts a telling
    /// are this red. As words it measures **5.67:1 on `card`** and the 5.12:1
    /// above on paper, so a word in wax reads on both grounds the app has.
    /// What it cannot do is differ from `destructive`: the two are 1.11:1
    /// apart, one red to the eye. A removal says so in its word, its icon and
    /// its place on the screen, never in its colour alone — and a secondary
    /// action is ink on `honey` (`elderSecondary`), not wax.
    ///
    /// **So a text button is ink as well**, and says so where it stands:
    /// `.foregroundStyle(Color.primary)` on one, `.tint(Color.primary)` on a
    /// sheet or a form made of them. Left to the accent, every *Peruuta*,
    /// *Valmis* and *Sulje* in the app turned the red of the *Poista* beside
    /// it on the day wax became the accent. One kind keeps the accent: a
    /// form's own action row — *Luo arkisto*, *Tallenna* under a name, *Hae*
    /// — which stands where a prominent button would, on a form with nothing
    /// to remove. Where a removal shares the form, as on a person's facts,
    /// the removal is the only colour on it. The alerts are the system's, and
    /// are left to it.
    static let wax = Color("Wax")

    /// What goes on top of `wax` or ink. 16.56:1 on ink, 5.59:1 on wax.
    static let cream = Color("Cream")

    /// The warm surface: the secondary button (`elderSecondary`), and a card
    /// that holds what somebody said.
    ///
    /// **13.74:1 under primary text**, so anything written in ink may sit on
    /// it. Coloured words may not, and that is the line to keep: `wax` on it
    /// measures **4.63:1** and `proposal` **4.65:1**, over the minimum by a
    /// hair that the next change of ground would spend. On honey either is a
    /// glyph or a shape — judged at 3:1 — and never a sentence.
    ///
    /// Against `paper` it measures **1.10:1**: no edge at all. So a honey
    /// surface carries `rule` round it, and the fill is warmth rather than
    /// the boundary — the same argument as `elderCard`'s hairline, one step
    /// warmer. The button adds a shadow under it because it is pressed; a
    /// card is read, and carries none.
    static let honey = Color("Honey")

    /// Every card's corner, and the secondary button's: 22 points on a
    /// continuous curve, the squircle iOS draws its own icons with, rather
    /// than a circular arc. One number since 26 Sep 2026; until then cards
    /// were drawn at four radii from 14 to 20, each chosen where it was
    /// written.
    static let cardRadius: CGFloat = 22

    /// The shape of something somebody said: `cardRadius` on three corners
    /// and 6 points on the one nearest the speaker, the way a speech bubble
    /// points without a tail to draw. `elderBubble` draws it, and the result
    /// screen's memory stands on a slab of the same shape.
    static var bubble: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: cardRadius,
            bottomLeadingRadius: 6,
            bottomTrailingRadius: cardRadius,
            topTrailingRadius: cardRadius,
            style: .continuous
        )
    }

    /// The slab a card sits on: the same cream, two steps darker, offset down
    /// and to the right with no blur at all.
    ///
    /// A printed thing has thickness, and this is the whole of it. It is
    /// decoration and nothing rests on it — the card's own hairline is still
    /// what draws the edge (`elderCard`), because a shadow is not a boundary
    /// for somebody looking through cataracts. So these two are the only
    /// colours here with no contrast ratio beside them: no text is ever drawn
    /// on either.
    static let block = Color("Block")

    /// Text that is quieter than the main line but still meant to be read.
    ///
    /// Not `.secondary`. iOS's secondary label is 60 % of a label that is itself
    /// 85 % black, which lands at about 4.2:1 against white — under the 4.5:1
    /// minimum, and the accessibility audit flagged it on nearly every
    /// instruction in the app. These are not decorative captions: "Puhu ihan
    /// rauhassa ja vapaasti" is the sentence that makes an 80-year-old willing
    /// to start talking, and it was the faintest text on the screen.
    ///
    /// 75 % of the primary colour measures about 6.6:1 and still reads as a
    /// second voice rather than the first.
    static let supporting = Color.primary.opacity(0.75)

    /// The colour of "the AI proposed this, a human has not confirmed it".
    ///
    /// Not `.orange`. iOS's own orange measures 2.2:1 against white — the
    /// *lowest* contrast anywhere in the app, on the one label that asks the
    /// family to check something.
    ///
    /// **#C2410C stood here until the ground stopped being white.** It
    /// measures 5.18:1 on white and **4.49:1 on `paper`** — under the 4.5:1
    /// minimum, on the one label whose whole job is to be noticed. It is the
    /// same trap the docs page fell into with the same hex, and it was caught
    /// here before the parchment shipped rather than after. #B23C0B measures
    /// **5.14:1 on paper**, 5.70:1 on card, 5.93:1 on white, and is still
    /// plainly orange next to the grey of a confirmed row.
    ///
    /// The shape of the icon carries the same meaning, and it always will:
    /// encoding a state in colour alone is an accessibility failure, and this
    /// app's user is precisely the one who suffers from it.
    static let proposal = Color("Proposal")

    /// "This went right": a memory saved, a person recognised, a name confirmed.
    ///
    /// Not `.green`. iOS's green measures about 1.8:1 against white — worse than
    /// the orange that started the whole contrast measurement (§15), and it was
    /// carrying *"Muisto tallennettu"*, the line that tells somebody their
    /// telling is safe.
    ///
    /// #1E7A3A stood here and, unlike `proposal`, it did not fail on paper —
    /// 4.67:1, above the minimum by a sixth of a step. Darkened to #B23C0B's
    /// neighbour #1B7136 anyway, which measures **5.26:1 on paper** and
    /// 5.83:1 on card, because a margin that thin is spent by the next change
    /// of ground rather than by anything anybody would notice, and this is the
    /// change of ground that spent `proposal`'s.
    ///
    /// As everywhere else here, the shape says it too: the checkmark is a
    /// checkmark whatever the colour does.
    static let affirmative = Color("Affirmative")

    /// Emptying the device, leaving the family — the actions that cannot be
    /// undone.
    ///
    /// Not `.red`. iOS's red measures 3.6:1 against white, and these are the
    /// labels a person most needs to read correctly before tapping. #B3261E
    /// measures **5.67:1 on `paper`** and 6.28:1 on card, and is unmistakably
    /// still a warning.
    ///
    /// It said 6.5:1 until 12 Sep 2026, which is the number on **white** —
    /// the exact trap the top of this section warns about, where #C2410C is
    /// 5.2:1 on white and 4.43:1 on the parchment this project actually uses.
    /// Nothing was wrong with the colour: it clears the minimum on both
    /// grounds the app has. What was wrong was the evidence for it, quoted
    /// against a background that does not exist here — and it was the only
    /// shipped colour in this file still measured that way.
    static let destructive = Color(red: 0.702, green: 0.149, blue: 0.118)

    // `recording` — iOS's own red — stood here and had all three of its call
    // sites taken, by `wax` for the disc and `.primary` for the waveform. It
    // was defended as a graphic judged at the 3:1 non-text minimum, which was
    // true and was not the best available: white on it measured ~3.55:1 where
    // cream on `wax` measures 5.59:1. Deleted rather than left unused, because
    // a token nothing draws goes on arguing its case to whoever reads it next.
    //
    // What it was right about is kept: red is the colour every recorder ever
    // made has taught this user, and `wax` is still unmistakably red.

    /// Headings, questions and names — the one line a screen is about.
    ///
    /// SF Rounded, bold. The whole app is rounded since 26 Sep 2026
    /// (`.fontDesign(.rounded)` at the root, KinloreApp.swift), so what sets
    /// this line apart is its weight rather than a second typeface. New York
    /// stood here until then: a serif for the heading and SF for everything
    /// else, which read as a printed page. Rounded reads as a voice, and this
    /// app is a place people talk.
    ///
    /// **A text style and not a point size, which is the whole safety of
    /// it.** `.custom(_:size:)` without `relativeTo:` stops answering the
    /// text-size setting, and so does a bare point size; both fail rule 1
    /// silently. Naming the style cannot be wrong that way.
    static func display(_ style: Font.TextStyle) -> Font {
        .system(style, design: .rounded, weight: .bold)
    }

    /// SF Rounded for the navigation bar's titles as well, which the root's
    /// `.fontDesign(.rounded)` cannot reach: the bar is UIKit's, and until
    /// this ran *Albumi* and a person's name stood in SF Pro over a rounded
    /// screen. Sized the way the bar sizes its own, measured from its
    /// screenshots on 26 Sep 2026: the large title follows the large-title
    /// style all the way up (34 pt, 60 pt at the largest size), and the
    /// inline one the headline style, stopping where the bar's own stops
    /// (17 pt, 21 pt). Both are scaled by `UIFontMetrics`, and both still
    /// answer the floor: 36 pt with it on, as the system's title did.
    ///
    /// **Called from the app delegate's launch and never earlier.** From
    /// `KinloreApp.init`, which runs before UIKit has an application, it
    /// turned every accent in the app back to the system blue.
    static func roundNavigationTitles() {
        func rounded(_ style: UIFont.TextStyle, _ weight: UIFont.Weight,
                     upTo cap: UIContentSizeCategory? = nil) -> UIFont {
            let size = { UIFont.preferredFont(forTextStyle: style,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: $0)).pointSize }
            let plain = UIFont.systemFont(ofSize: size(.large), weight: weight)
            let font = plain.fontDescriptor.withDesign(.rounded)
                .map { UIFont(descriptor: $0, size: size(.large)) } ?? plain
            let metrics = UIFontMetrics(forTextStyle: style)
            return cap.map { metrics.scaledFont(for: font, maximumPointSize: size($0)) }
                ?? metrics.scaledFont(for: font)
        }
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: rounded(.largeTitle, .bold)]
        bar.titleTextAttributes = [.font: rounded(.headline, .semibold, upTo: .extraExtraLarge)]
    }
}

/// The quieter button: ink on `honey`, for every action on a screen that is
/// not the one `elderPrimary(true)` claims.
///
/// **Not `.bordered`, which draws its label in the tint.** With the accent now
/// `wax`, every bordered button on every screen would have read in the same
/// red as the one that starts a telling — and 1.11:1 from `destructive`, so
/// "Siirrä toiselle kortille" and "Poista" would have been one colour apart
/// from nothing. A secondary action is ink, and red is kept for starting to
/// tell, the selected tab, and removal.
///
/// Opaque on purpose. iOS 26 draws `.bordered` as glass, and glass under text
/// is what made the audit's contrast check time out at the largest text size
/// (`AccessibilitySweepTests.swift`, the header). Honey is one colour, and the
/// text on it is one number: **13.74:1**.
///
/// The edge is the `rule` hairline and a shadow, because honey is 1.10:1
/// against `paper` and the fill alone is no boundary. The shadow is hung on
/// the shape and not on the label, so the text itself carries none.
///
/// Never below `Elder.minTapTarget`, which is the rule for secondary actions
/// as much as for the primary one, and the corner is `cardRadius` rather
/// than a capsule: a label that wraps at XXXL is three lines tall, and a
/// capsule that tall cuts into the first and last words.
struct ElderSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Elder.cardRadius, style: .continuous)
        return configuration.label
            .fontWeight(.semibold)
            // Disabled is `supporting` rather than a faded button, so the
            // words stay readable while it waits; fading the whole control
            // would fade the text under the minimum with it.
            .foregroundStyle(isEnabled ? Color.primary : Elder.supporting)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: Elder.minTapTarget)
            .background {
                shape
                    .fill(Elder.honey)
                    .shadow(color: Elder.rule, radius: 3, y: 2)
            }
            .overlay(shape.strokeBorder(Elder.rule, lineWidth: 1))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == ElderSecondaryButtonStyle {
    static var elderSecondary: ElderSecondaryButtonStyle { .init() }
}

extension View {
    /// The screen's one wax button — or the quieter honey one
    /// (`ElderSecondaryButtonStyle`), when something else on the screen has
    /// already claimed it.
    ///
    /// Exists so that "which of these is the primary action" is written as a
    /// condition in one place instead of being decided a second time by
    /// whoever adds the next button. Every screen in this app has exactly one
    /// prominent button; the reasoning, and the one framed exception, are in
    /// docs/ARCHITECTURE.md §22.
    @ViewBuilder
    func elderPrimary(_ isPrimary: Bool) -> some View {
        if isPrimary {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.elderSecondary)
        }
    }

    /// Parchment behind a screen.
    ///
    /// Two things and not one, because a `List` or a `Form` paints its own
    /// opaque grey and would simply cover anything put behind it —
    /// `.scrollContentBackground(.hidden)` is what makes the paper reachable.
    /// It is harmless on a screen that only stacks views, which is why every
    /// root can take the same call instead of each one deciding.
    ///
    /// **Put it INSIDE a `NavigationStack`, never around one.** A stack paints
    /// its own opaque ground over anything hung behind it, and the failure is
    /// silent in the worst way: the cards on the screen turn cream, the screen
    /// itself stays white, and it looks like a colour that was chosen. Both
    /// tabs that have a stack were shipped that way for an hour and only a
    /// screenshot said so.
    ///
    /// **This paints the ground and not the rows.** A grouped list's rows keep
    /// the system's white on the parchment, which is what every `List` and
    /// `Form` in this app looks like now; only the `.plain` list on Ihmiset
    /// needed more, and it says so at its own call site. `Elder.card` is a
    /// fifth of a per-cent lighter than white, and threading
    /// `.listRowBackground` through every `Section` of nine screens to buy
    /// that is a sweep this phase would not survive. It cannot be bought any
    /// other way either: `.listRowBackground` hung on a `List` — or anywhere
    /// above one — does **nothing at all**, silently, which is how nine of
    /// them sat here looking like they worked.
    func elderSurface() -> some View {
        scrollContentBackground(.hidden)
            .background(Elder.paper)
    }

    /// The one card in the app.
    ///
    /// `.background(.quaternary.opacity(0.3), in: RoundedRectangle(...))` was
    /// written fourteen times across seven files, at three different radii and
    /// two different opacities, because there was nowhere to put it once. It
    /// is one call now so that the next screen cannot invent a fifteenth, and
    /// so that a change of ground is a change to one line rather than a
    /// fourteen-file sweep — which is exactly what this modifier's first
    /// commit was.
    ///
    /// The border is not decoration and must not be dropped. `Elder.rule`
    /// measures **1.39:1**, far under anything WCAG would call a boundary, so
    /// what actually separates a card from the paper it lies on is the
    /// `card`/`paper` step itself; the hairline only makes the corner legible.
    /// A card whose only edge is a shadow has no edge at all for somebody
    /// looking at it through cataracts.
    ///
    /// The corner is `Elder.cardRadius` and no call site chooses its own. It
    /// took a `radius:` until 26 Sep 2026, and four radii were in use.
    func elderCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: Elder.cardRadius, style: .continuous)
        return background(Elder.card, in: shape)
            .overlay(shape.strokeBorder(Elder.rule, lineWidth: 1))
    }

    /// What somebody said, rather than a thing: a memory's words, a question
    /// put to the teller. `honey` is what tells it from a card, and `rule` is
    /// its edge for the reason `honey` gives — against the paper the fill
    /// measures 1.10:1, which is no edge at all. Ink on it, and nothing
    /// coloured smaller than a glyph.
    func elderBubble() -> some View {
        background(Elder.honey, in: Elder.bubble)
            .overlay(Elder.bubble.strokeBorder(Elder.rule, lineWidth: 1))
    }

    /// A card with a thickness: the same card, on a hard slab.
    ///
    /// The offset is 5 x 7 points with a blur of zero, which is what makes it
    /// read as a printed block rather than as a floating panel — a blurred
    /// shadow is a screen's idea of depth and a slab is a page's. The rows on
    /// the result screen are where it belongs, because those are the ones a
    /// person acts on; the memory they sit under stands on the same slab in
    /// its bubble's shape (`elderBubble`).
    ///
    /// It adds nothing to the *edge*: `elderCard` keeps its hairline
    /// underneath, and the rule that a shadow may never be the only boundary
    /// of a control is the reason this is a `background` and not a
    /// replacement.
    ///
    /// Give it room. The slab reaches 7 points past the card, so a container
    /// with less padding than that clips it — `Elder.screenPadding` is 24 and
    /// every screen this is used on has it.
    func elderBlock() -> some View {
        elderCard()
            .background {
                RoundedRectangle(cornerRadius: Elder.cardRadius, style: .continuous)
                    .fill(Elder.block)
                    .offset(x: 5, y: 7)
            }
    }

    /// Ensures a control is large enough regardless of the size of its content.
    func elderTapTarget() -> some View {
        frame(minWidth: Elder.minTapTarget, minHeight: Elder.minTapTarget)
            .contentShape(Rectangle())
    }

    /// Body text styling: generous leading, never a line limit. A truncated
    /// memory is a lost memory.
    func elderBody() -> some View {
        font(.body)
            .lineSpacing(Elder.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }
}
