import SwiftUI

/// Onboarding. Two options, nothing else.
///
/// No sign-in, no email, no password. Grandmother gets a link from a grandchild
/// and taps "Liity". This is precisely the point where this audience normally
/// drops out.
struct OnboardingScreen: View {
    @Environment(Session.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The code from an invite link, or nil.
    ///
    /// A binding rather than a value, and read on change rather than on appear.
    /// Both halves were wrong before, and the first one is the flow this whole
    /// no-login design exists for:
    ///
    /// **Tapping the link usually does not launch the app.** It is already
    /// running — a person opens a new app before they use the link, or reads the
    /// message with the app in the background — so iOS shows "Open in Kinlore?"
    /// and returns to a screen that appeared minutes ago. `onAppear` fires once,
    /// so the code was dropped and grandmother was looking at the same two
    /// buttons as before, with nothing filled in and no clue why. On a cold
    /// launch it worked, which is exactly the kind of half that gets tested.
    ///
    /// Cleared once it has been used, so that a code from a family she has since
    /// left cannot fill itself in over a fresh invitation.
    @Binding var prefilledCode: String?

    @State private var route: Route?
    @State private var name = ""
    @State private var code = ""

    private enum Route: Hashable { case create, join }

    /// Shortened at accessibility sizes so the two buttons stay above the fold.
    /// In full it ran to eight lines and pushed both of them off the screen —
    /// and a first screen whose only two actions have to be found by scrolling
    /// is a first screen this user does not get past. The first sentence is the
    /// promise; the second is how it is kept, and the buttons say that anyway.
    /// Nil at accessibility sizes, where it is dropped rather than shortened.
    ///
    /// Shortening was tried and was not enough: one sentence is still four lines
    /// at XXXL, and *"Liity kutsulinkillä"* was below the fold again — the exact
    /// failure the paragraph above describes as fixed. Measured on screen rather
    /// than reasoned about, because that is the only way this particular
    /// promise can be kept honest.
    ///
    /// The title says what the app is and the two buttons say what can be done.
    /// A promise nobody can reach the buttons past is not a promise.
    private var intro: String? {
        typeSize.isAccessibilitySize
            ? nil
            : "Kerätkää yhdessä talteen se mitä isovanhemmat muistavat. Kerro omalla äänelläsi — me järjestämme."
    }

    var body: some View {
        NavigationStack {
            // Scrolling, and every label allowed to wrap.
            //
            // At the largest text size this screen failed worse than any other,
            // and it is the first one a new user ever sees: the title truncated
            // to "Perheen m…", the primary button to "Aloita perh…", and "Liity
            // kutsulinkillä" was off the bottom of the screen entirely. A
            // grandmother holding an invite link could not find the way in —
            // which is the one flow the whole no-login design exists for.
            GeometryReader { proxy in
                ScrollView {
                    content
                        .padding(Elder.screenPadding)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationDestination(item: $route) { destination in
                switch destination {
                case .create:
                    CreateFamilyForm(name: $name)
                case .join:
                    JoinFamilyForm(name: $name, code: $code)
                }
            }
        }
        .onAppear { useInvite() }
        // The link arriving while this screen is already open is the ordinary
        // case, not the exception.
        .onChange(of: prefilledCode) { _, _ in useInvite() }
    }

    /// Takes the code out of the link and puts the join form in front of her.
    ///
    /// A link is a deliberate act and the most recent one, so it wins over
    /// whatever is in the field — somebody who taps a fresh invitation while a
    /// stale code is half-typed meant the fresh one.
    private func useInvite() {
        guard let invite = prefilledCode, !invite.isEmpty else { return }
        code = invite
        route = .join
        prefilledCode = nil
    }

    private var content: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            // The mark is decoration. At accessibility sizes it competes with
            // the two buttons for the same screen, and the buttons win.
            if !typeSize.isAccessibilitySize {
                Image(systemName: "photo.stack")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                    // Decoration, and VoiceOver was reading it out as
                    // "photo.stack" — the symbol's own name, in English, on the
                    // first screen of a Finnish app.
                    .accessibilityHidden(true)
            }

            VStack(spacing: 14) {
                Text("Perheen muistot")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let intro {
                    Text(intro)
                        .elderBody()
                        .foregroundStyle(Elder.supporting)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 14) {
                Button {
                    route = .create
                } label: {
                    // fixedSize so the label wraps instead of truncating. A
                    // button whose text ends in an ellipsis does not say what
                    // it does, and this one is the whole point of the screen.
                    Text("Aloita perheen arkisto")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    route = .join
                } label: {
                    Text("Liity kutsulinkillä")
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
                .controlSize(.large)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - What happens to a recording

/// Said where the archive is chosen, rather than after it exists.
///
/// The app already tells this once, in `NSMicrophoneUsageDescription` — but that
/// prompt arrives only when the first recording starts, which is after the
/// family has been created. The choice was being asked before the consequence
/// was explained, and that order is the whole of the trust problem: not that the
/// audio leaves the phone, but that nobody was told before deciding. See
/// PLAN.md §10.
///
/// The wording deliberately repeats the permission prompt's own sentence rather
/// than paraphrasing it. Hearing the same words twice reads as one consistent
/// statement; a second phrasing reads as a second, slightly different claim.
///
/// It says what happens, never what does not. "We do not use it for anything
/// else" would be a promise this screen cannot keep on its own, and fixing a
/// trust barrier with an unkept promise is worse than the barrier.
/// A section of its own, whose only content is its footer.
///
/// It was first written into the button's existing footer, wrapped in a `VStack`
/// beside the missing-name hint. That failed the audit on both screens as
/// **"Dynamic Type font sizes are partially unsupported"**, and the length was
/// not the reason: `SettingsScreen`'s export footer is longer, carries nothing
/// but `foregroundStyle`, and passes. The `VStack` was the reason — a footer
/// holding a stack rather than a `Text` stops scaling with the type size.
///
/// So this matches the shape that already passes everywhere else in the app: a
/// plain `Text` alone in a `footer:`, styled and nothing more. The lesson is
/// worth more than the fix — a wrapper in a footer is invisible on screen and
/// visible only to the audit.
private struct WhereMemoriesGo: View {
    var body: some View {
        Section {
        } footer: {
            Text("Muistot näkyvät perheen jäsenille. Äänitys lähetetään palveluumme, "
                + "jossa puheesta kirjoitetaan teksti, ja alkuperäinen ääni säilytetään.")
                .foregroundStyle(Elder.supporting)
        }
    }
}

// MARK: - Creating a family

/// The one screen in this app that a 30-year-old fills in.
///
/// Which is the reason it asks who the phone is for. Setting up takes a few
/// minutes and is done by a grandchild; the using is done for years by somebody
/// who has never opened iOS Settings and will not be told to. The question is
/// therefore asked in the only moment where the person who *can* answer it is
/// already answering questions — and it is asked plainly, because a "make text
/// larger" switch reads as an admission and "kenen puhelin tämä on" does not.
private struct CreateFamilyForm: View {
    @Environment(Session.self) private var session
    @Binding var name: String

    @AppStorage(Elder.largerTextKey) private var largerText = false

    /// Set by pressing the button with the form not filled in. See `missing`.
    @State private var wasPressedEmpty = false

    private var isReady: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// What is still missing, said in words, instead of a button gone grey.
    ///
    /// The button used to be `.disabled` until the field had something in it,
    /// and a disabled prominent button is drawn grey on grey — the one contrast
    /// failure left on this screen once the headers were fixed, and measured as
    /// such. That is the wrong half of the problem to solve, though: the colour
    /// is only how it fails. A control that goes quiet gives no reason, and the
    /// reason is the whole content of "you have not typed your name yet".
    ///
    /// The same trade as the refused microphone in ARCHITECTURE §8.9: the dead
    /// end is replaced by the way out of it, rather than being made prettier.
    private var missing: String? {
        isReady ? nil : "Kirjoita ensin nimesi."
    }

    var body: some View {
        Form {
            Section {
                TextField("Nimesi", text: $name)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Kuka sinä olet")
                    .foregroundStyle(Elder.supporting)
            } footer: {
                Text("Tämä näkyy muistojesi vieressä, jotta perhe tietää kuka kertoi.")
                    .foregroundStyle(Elder.supporting)
            }

            Section {
                // Inline rather than a menu: both answers are visible without a
                // tap, which is the difference between a question and a control
                // somebody has to discover.
                Picker("Kenen puhelin tämä on", selection: $largerText) {
                    Text("Isovanhemman").tag(true)
                    Text("Minun").tag(false)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Kenen puhelin tämä on")
                    .foregroundStyle(Elder.supporting)
            } footer: {
                Text("Isovanhemman puhelimessa teksti on isompaa. Voit vaihtaa tämän myöhemmin asetuksista.")
                    .foregroundStyle(Elder.supporting)
            }

            Section {
                Button {
                    guard missing != nil else {
                        wasPressedEmpty = false
                        return start()
                    }
                    wasPressedEmpty = true
                } label: {
                    if session.isWorking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Luo arkisto")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                // Only while the request is in flight, when the label is a
                // spinner and there is nothing to read anyway.
                .disabled(session.isWorking)
                .elderTapTarget()
            } footer: {
                if wasPressedEmpty, let missing {
                    Label(missing, systemImage: "arrow.up")
                        .foregroundStyle(Elder.proposal)
                        .elderBody()
                }
            }

            WhereMemoriesGo()

            if let error = session.lastError {
                Section { ErrorNote(text: error) }
            }
        }
        .navigationTitle("Uusi arkisto")
    }

    /// No family name is asked for any more, and the server's own default fills
    /// it in. It was one text field on the first form in the app, in exchange
    /// for a row reading "Nimi — Perhe" on a screen most families open once:
    /// nothing renames a family later, so the field's own footer — *"voit
    /// päättää myöhemmin"* — was a promise nothing in the app kept.
    private func start() {
        Task { await session.createFamily(named: "", displayName: name) }
    }
}

// MARK: - Joining

private struct JoinFamilyForm: View {
    @Environment(Session.self) private var session
    @Binding var name: String
    @Binding var code: String

    @State private var wasPressedEmpty = false

    /// The same as `CreateFamilyForm.missing`, and it has more to say here:
    /// this form has two fields, and "grey" cannot tell somebody which of them
    /// it is waiting for. This is also the screen an 80-year-old reaches on her
    /// own, from a link, with nobody beside her.
    private var missing: String? {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let hasCode = !code.trimmingCharacters(in: .whitespaces).isEmpty
        switch (hasName, hasCode) {
        case (true, true): return nil
        case (false, true): return "Kirjoita ensin nimesi."
        case (true, false): return "Liitä vielä saamasi kutsukoodi."
        case (false, false): return "Kirjoita nimesi ja liitä saamasi kutsukoodi."
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Nimesi", text: $name)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Kuka sinä olet")
                    .foregroundStyle(Elder.supporting)
            } footer: {
                Text("Tämä näkyy muistojesi vieressä.")
                    .foregroundStyle(Elder.supporting)
            }

            Section {
                // The invite code is not meant to be read, so autocorrection and
                // capitalisation would only break it.
                //
                // One word, because a placeholder is not allowed to wrap: it was
                // "Liitä kutsukoodi", which fits at the ordinary size and is cut
                // off at the largest one — the field is 338 pt wide whatever the
                // text does. The audit caught it the first time this screen was
                // ever measured. The instruction it used to carry is in the
                // footer below, where it can wrap.
                TextField("Kutsukoodi", text: $code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("Kutsu")
                    .foregroundStyle(Elder.supporting)
            } footer: {
                Text("Sait linkin tai koodin perheenjäseneltä. Voit liittää sen tähän.")
                    .foregroundStyle(Elder.supporting)
            }

            Section {
                Button {
                    guard missing != nil else {
                        wasPressedEmpty = false
                        return join()
                    }
                    wasPressedEmpty = true
                } label: {
                    if session.isWorking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Liity perheeseen")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(session.isWorking)
                .elderTapTarget()
            } footer: {
                if wasPressedEmpty, let missing {
                    Label(missing, systemImage: "arrow.up")
                        .foregroundStyle(Elder.proposal)
                        .elderBody()
                }
            }

            WhereMemoriesGo()

            if let error = session.lastError {
                Section { ErrorNote(text: error) }
            }
        }
        .navigationTitle("Liity perheeseen")
    }

    private func join() {
        Task { await session.join(code: code, displayName: name) }
    }
}

private struct ErrorNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(Elder.proposal)
            .elderBody()
    }
}

#Preview {
    OnboardingScreen(prefilledCode: .constant(nil))
        .environment(Session())
}
