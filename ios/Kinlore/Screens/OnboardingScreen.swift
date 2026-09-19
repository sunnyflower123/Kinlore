import SwiftUI

/// Onboarding. Two options, nothing else.
///
/// No sign-in, no email, no password. Grandmother gets a link from a grandchild
/// and taps "Liity". This is precisely the point where this audience normally
/// drops out.
struct OnboardingScreen: View {
    @Environment(Session.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss

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

    /// Presented as a sheet over an archive kept to this phone, from
    /// EnableSharingScreen: the fork gets a way to cancel, and the create form
    /// stops offering "vain minulle", which is where the phone already is.
    var fromLocalArchive = false

    /// Presented over an archive whose device the server has stopped knowing
    /// (`SyncEngine.State.refused`): straight to the join form, which then
    /// calls `Session.rejoin` rather than `join`. See docs/UX.md §4.1.
    var rejoining = false

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
    private var intro: LocalizedStringKey? {
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
                    CreateFamilyForm(name: $name, canStayAlone: !fromLocalArchive)
                case .join:
                    JoinFamilyForm(name: $name, code: $code, rejoining: rejoining)
                }
            }
            .elderSurface()
        }
        .onAppear {
            if rejoining { route = .join }
            useInvite()
        }
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

            // Over a local archive the fork is a sheet, and a sheet needs a way
            // out an 80-year-old can find: the swipe is not one.
            if fromLocalArchive || rejoining {
                Button("Peruuta") { dismiss() }
                    .controlSize(.large)
                    .elderTapTarget()
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
    /// Whether the archive being set up is shared with a family.
    ///
    /// Both sentences change with the answer now, and both have to: *"muistot
    /// näkyvät perheen jäsenille"* is false on a phone that keeps them to
    /// itself, and since finding B4 the second clause splits too. The kept-here
    /// mode has no member the server knows, so nothing is sent and no text is
    /// ever written — this notice used to say *"lähetetään silti palveluumme"*,
    /// which was true while the mode still tried and met a 401, and became a
    /// false promise the day the attempt was removed. A consent notice that is
    /// wrong in either clause is worse than none.
    ///
    /// Since 19 Sep 2026 the shared branch also says what can be read off the
    /// voice — nothing is kept at the service, nothing is handed over as
    /// training data, nobody is identified from the voice, and the archived
    /// audio is sealed with the family key — matching the microphone
    /// permission text in `ios/project.yml` and the Help screen. The
    /// kept-here branch deliberately gained no such clause: nothing is sent,
    /// so there is nothing to describe, and `MemoryStore.save()` writes plain
    /// JSON, so a sentence about encryption would be the one kind of untruth
    /// a consent notice cannot afford.
    var isShared = true

    var body: some View {
        Section {
        } footer: {
            // Two `Text`s with one literal each. As a ternary of parts joined
            // with `+` this was a String, shown verbatim in every language —
            // the informed-consent sentence, Finnish on an English phone
            // (founder's-eye review, 3 Sep 2026, finding #38).
            Group {
                if isShared {
                    Text("Muistot näkyvät perheen jäsenille. Äänitys käy palvelussamme, jossa puheesta kirjoitetaan teksti — talteen sitä ei siellä jätetä, opetusaineistoksi sitä ei anneta eikä äänestä tunnisteta ketään. Alkuperäinen ääni säilytetään arkistossa salattuna, ja vain perheen omat puhelimet avaavat sen.")
                } else {
                    Text("Muistot jäävät tähän puhelimeen. Äänityksiä ei lähetetä mihinkään eikä puheesta kirjoiteta tekstiä — voit kirjoittaa muistot itse, ja alkuperäinen ääni säilyy puhelimessa.")
                }
            }
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
    /// Where the founder's own card is made once the family exists. See
    /// `Session.createFamily`.
    @Environment(MemoryStore.self) private var store
    @Binding var name: String
    /// False when reached from an archive already kept to this phone.
    var canStayAlone = true

    @AppStorage(Elder.largerTextKey) private var largerText = false

    /// Set by pressing the button with the form not filled in. See `missing`.
    @State private var wasPressedEmpty = false

    /// PLAN.md §10 lever 2, asked as a question rather than offered as a third
    /// button on the screen before.
    ///
    /// It belongs here because this is where the archive is created, which is
    /// the sentence lever 1 was written from — and because the first screen had
    /// no room. Two buttons at the largest text size already fill it; the intro
    /// paragraph was dropped entirely to keep the second one above the fold, and
    /// a third would have spent that fix on the least-used of the three.
    ///
    /// Not offered when joining. An invitation is somebody else's family, and
    /// "join, but keep it to myself" is not a thing that could be honoured.
    @State private var sharing: Sharing = .family

    private enum Sharing: Hashable { case family, alone }

    private var isShared: Bool { sharing == .family }

    /// The name is what a family sees beside a memory. Nothing shows it on a
    /// phone that has no family, so it is not asked for there — a field somebody
    /// fills in that changes nothing is a small dishonesty, and this is the
    /// first form in the app.
    private var isReady: Bool {
        !isShared || !name.trimmingCharacters(in: .whitespaces).isEmpty
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
    private var missing: LocalizedStringKey? {
        isReady ? nil : "Kirjoita ensin nimesi."
    }

    var body: some View {
        Form {
            // First, because it decides what the rest of the form is for. The
            // same inline shape as the question below it: both answers visible
            // without a tap, which is the difference between a question and a
            // control somebody has to discover.
            //
            // Above the name rather than below it so that choosing the single
            // phone takes a field away underneath the finger rather than out
            // from under it.
            if canStayAlone {
            Section {
                // A type of its own rather than a `Bool`, because the section
                // below is also an inline `Picker` over two cases and two `Bool`
                // pickers in one `Form` put `.tag(true)` and `.tag(false)` on
                // four rows — the same tag type and values twice, which SwiftUI
                // matches by type and value. It is the clearer code either way.
                //
                // It was **not** the cause of the audit finding this section
                // arrived with, and that is worth recording so nobody spends the
                // build on it twice: changing the tags from `Bool` to this enum
                // left "Dynamic Type font sizes are partially unsupported" on
                // the header below, byte for byte the same finding at the same
                // coordinates.
                Picker("Keiden kesken", selection: $sharing) {
                    Text("Perheen kesken").tag(Sharing.family)
                    Text("Vain minulle, tälle puhelimelle").tag(Sharing.alone)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Keiden kesken")
                    .foregroundStyle(Elder.supporting)
            } footer: {
                Text("Voit valita jommankumman. Perheen voi ottaa käyttöön myöhemmin Asetuksista — mutta perheelle kerrottua ei saa takaisin vain tähän puhelimeen.")
                    .foregroundStyle(Elder.supporting)
            }
            }

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

            // Above the button rather than below it, which is where it was
            // until this section was added. Measured, not preferred: with the
            // "keiden kesken" question in front of it the form grew past the
            // point where a `Form` builds rows nobody can see, and at
            // AccessibilityXXXL the notice did not exist at all by the time
            // "Luo arkisto" became pressable — `ConsentOrderTests` said so in
            // those words. Lever 1 is an order, so the order is what had to
            // move; the sentence itself is unchanged.
            WhereMemoriesGo(isShared: isShared)

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
        // The single-phone archive reaches no network, so it is not a `Task` and
        // cannot fail. That asymmetry is the feature: the option is taken by
        // somebody uneasy about the server, and making it wait on the server
        // answering would be a poor joke. See `Session.keepToThisPhone`.
        guard isShared else { return session.keepToThisPhone() }
        Task { await session.createFamily(named: "", displayName: name, archive: store) }
    }
}

// MARK: - Joining

private struct JoinFamilyForm: View {
    @Environment(Session.self) private var session
    @Environment(SyncEngine.self) private var sync: SyncEngine?
    @Binding var name: String
    @Binding var code: String
    /// Joining the same family again from a device the server has forgotten.
    var rejoining = false

    @AppStorage(Elder.largerTextKey) private var largerText = false

    @State private var wasPressedEmpty = false

    /// The same as `CreateFamilyForm.missing`, on the screen an 80-year-old
    /// reaches on her own, from a link, with nobody beside her.
    ///
    /// **The name is no longer part of it.** It used to be required, which made
    /// a keyboard the price of entry on exactly the path rule 1 most wanted
    /// clear — and for an answer the app can already have: whoever made the
    /// invitation was asked who it was for, and the server uses that name when
    /// this field is empty (`invite.display_name`). Demanding it here would be
    /// this app insisting she type something it has already been told.
    ///
    /// The code stays required, because nothing can supply it but her.
    private var missing: LocalizedStringKey? {
        code.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Liitä vielä saamasi kutsukoodi."
            : nil
    }

    /// The code, taken out of whatever was actually copied.
    ///
    /// The invitation is a four-line message carrying the link on one line and
    /// the pasteable code on another, and selecting one line out of a message
    /// is a finer gesture than selecting the whole message — so the whole
    /// message is what a paste button will usually deliver here. Failing on it
    /// would be answering the easy gesture with "invalid_invite", which is the
    /// least explicable error this app can produce.
    ///
    /// The link line is read by `KinloreApp.inviteCode(from:)` and not by a
    /// second parser written here: the family key rides the URL's fragment, and
    /// the last time that string had two readings the tapped link joined a
    /// family it could not decrypt.
    static func code(inPasted text: String) -> String {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("kinlore://"),
                  let url = URL(string: trimmed),
                  let code = KinloreApp.inviteCode(from: url)
            else { continue }
            return code
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            if rejoining {
                // Why this form is here at all, in the words of the note that
                // opened it — and what it does not cost.
                Section {
                    Text("Palvelin ei enää tunnista tätä puhelinta. Kun liityt uudella kutsulla, puhelimen muistot pysyvät ja perheen uudet muistot alkavat taas saapua.")
                        .elderBody()
                        .foregroundStyle(Elder.supporting)
                }
            }

            Section {
                TextField("Nimesi", text: $name)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Kuka sinä olet")
                    .foregroundStyle(Elder.supporting)
            } footer: {
                Text("Tämä näkyy muistojesi vieressä. Voit jättää tyhjäksi, jos kutsuja kirjoitti nimesi. Nimen voi vaihtaa myöhemmin.")
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

                // The one gesture in this app that this audience does not have.
                //
                // The code arrives inside a message and has to cross into a
                // text field, and the only way across was a long press and a
                // context menu: a fine, timed, two-step gesture on the screen
                // an 80-year-old reaches alone, from a link, with nobody
                // beside her. It is also the exact step the whole no-login
                // design exists to make possible, which makes it the worst
                // place in the app to leave a gesture nobody can do.
                //
                // The system's own control rather than one of ours: it carries
                // iOS's own Finnish label, and it is the one paste that asks
                // for no clipboard permission at all — the alert would be a
                // second English dialog on the same path as "Open in Kinlore?".
                PasteButton(payloadType: String.self) { items in
                    guard let pasted = items.first else { return }
                    code = Self.code(inPasted: pasted)
                }
                .labelStyle(.titleAndIcon)
                .elderTapTarget()
                .accessibilityIdentifier("invite-code-paste")
            } header: {
                Text("Kutsu")
                    .foregroundStyle(Elder.supporting)
            } footer: {
                Text("Sait linkin tai koodin perheenjäseneltä. Voit liittää sen tähän.")
                    .foregroundStyle(Elder.supporting)
            }

            // The same question the create form asks, for the same person: a
            // phone joined *for* a grandparent is set up by a grandchild in
            // the only minutes anybody is answering questions — and joining
            // was the one path where the text-size floor could never be set,
            // on precisely the phone that is handed over (docs/UX.md §5). The
            // long why lives on `CreateFamilyForm`; the wording is identical
            // on purpose — no new word for an old act (§21).
            Section {
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

            // Above the button, for the reason the create form measured: with
            // a section added in front, a `Form` at the largest text size has
            // not built the notice by the time the button is pressable.
            // `ConsentOrderTests` covers this form too, in both directions.
            WhereMemoriesGo()

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

            if let error = session.lastError {
                Section { ErrorNote(text: error) }
            }
        }
        .navigationTitle("Liity perheeseen")
        .onAppear {
            // The name this phone already had in the family, so that joining
            // again does not rename anybody. The joiner's own typing still
            // wins, as ever.
            if rejoining, name.isEmpty, let known = session.family?.you.displayName {
                name = known
            }
        }
    }

    private func join() {
        Task {
            if rejoining {
                // The sheet closes on success and the next round goes through
                // at once — the state it clears is the reason the sheet opened.
                if await session.rejoin(code: code, displayName: name) {
                    sync?.isRejoining = false
                    await sync?.sync()
                }
            } else {
                await session.join(code: code, displayName: name)
            }
        }
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
