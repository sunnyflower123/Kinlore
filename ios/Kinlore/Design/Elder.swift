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
    /// family to check something. #C2410C measures 5.2:1 and is still plainly
    /// orange next to the grey of a confirmed row.
    ///
    /// The shape of the icon carries the same meaning, and it always will:
    /// encoding a state in colour alone is an accessibility failure, and this
    /// app's user is precisely the one who suffers from it.
    static let proposal = Color(red: 0.761, green: 0.255, blue: 0.047)

    /// "This went right": a memory saved, a person recognised, a name confirmed.
    ///
    /// Not `.green`. iOS's green measures about 1.8:1 against white — worse than
    /// the orange that started the whole contrast measurement (§15), and it was
    /// carrying *"Muisto tallennettu"*, the line that tells somebody their
    /// telling is safe. #1E7A3A measures 5.4:1 and is unmistakably still green.
    ///
    /// As everywhere else here, the shape says it too: the checkmark is a
    /// checkmark whatever the colour does.
    static let affirmative = Color(red: 0.118, green: 0.478, blue: 0.227)

    /// Emptying the device, leaving the family — the actions that cannot be
    /// undone.
    ///
    /// Not `.red`. iOS's red measures 3.6:1 against white, and these are the
    /// labels a person most needs to read correctly before tapping. #B3261E
    /// measures 6.5:1 and is unmistakably still a warning.
    static let destructive = Color(red: 0.702, green: 0.149, blue: 0.118)

    /// The record button's fill, and the waveform's. The one place iOS's own
    /// red is allowed, and the reason is the shape it is on: a 200 pt disc with
    /// a white glyph is a graphic, judged by the 3:1 non-text minimum rather
    /// than text's 4.5:1, and white on this red measures about 3.5:1. The same
    /// red under a *label* fails — that case is `destructive` above. Red is
    /// also the one colour every recorder ever made has taught this user, and
    /// the glyph — mic or stop — carries the meaning whatever the colour does.
    static let recording = Color.red
}

extension View {
    /// The screen's one blue button — or the quieter version of the same
    /// control, when something else on the screen has already claimed it.
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
            buttonStyle(.bordered)
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
