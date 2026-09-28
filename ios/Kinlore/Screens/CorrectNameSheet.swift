import SwiftUI

/// Correcting a name the speech recognition got wrong, after the moment of
/// telling has passed.
///
/// The Tell screen already offers this in the seconds after a memory is told,
/// and that is the best moment: the teller still remembers what they said. But
/// it was the *only* moment. Recognition is wrong about one proper noun in three
/// (65 % on Finnish proper nouns, `backend/wrangler.jsonc`), the correction
/// screen goes past quickly, and during an interview the proposals pile up
/// unhandled — so a name missed there was a wrong person in the family tree for
/// good.
///
/// That is the failure rule 4 exists to prevent, and the archive had no way out
/// of it. Sync has had a conflict rule for "a subject renamed on two devices"
/// from the beginning; until now the app could not produce that situation
/// outside those few seconds.
///
/// **And then the words (28 Sep 2026).** Until then the sheet corrected the
/// card and said that the memories' text stayed as it was, so a card corrected
/// to "Hilma" sat above stories that still said "Hildan kanssa". Once the card
/// is saved, the sheet counts the tellings whose words still carry the old
/// name and offers to correct them too, with the correction the Tell screen
/// already makes in the seconds after a telling
/// (`TellViewModel.applyCorrections`): the text goes back through extraction
/// with the name as a `NameCorrection`, because Finnish inflects a name and no
/// string replacement finds "Hildan". Nothing is rewritten without the tap,
/// and `updateBody` writes the body alone — the recording and the raw
/// transcript are rule 3's and stay as they were. Another member's tellings
/// are counted and never rewritten from here, and when they are the only
/// ones that say the name, the step says why their words stay instead of
/// offering anything.
///
/// See docs/ARCHITECTURE.md §17.
struct CorrectNameSheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let subject: Subject
    /// Called with whether the correction merged this subject into another
    /// one, once the sheet has gone — however it went.
    var onSave: (Bool) -> Void

    @State private var name: String = ""
    @FocusState private var isFocused: Bool
    @State private var isConfirmingMerge = false

    /// Where the sheet is. The name first; then, when tellings still say the
    /// old name, the offer, the correcting, and what came of it.
    @State private var step: Step = .name
    /// Whether the save merged the card into another one; nil until it saved.
    @State private var merged: Bool?
    /// The name as it was and as it is now, from the save.
    @State private var correction: NameCorrection?
    @State private var tellings = NamedTellings()
    /// Tellings whose text was rewritten, over every attempt.
    @State private var corrected = 0
    /// Tellings still carrying the old name after an attempt: failed, or not
    /// reached because the moment failed or the person stopped it.
    @State private var left: [String] = []
    @State private var stopRequested = false

    private enum Step: Equatable {
        case name
        case offer
        case correcting(Int, of: Int)
        case done
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isUnchanged: Bool {
        trimmed.isEmpty || trimmed == subject.title
    }

    /// Somebody the family already has under the corrected name. Saying so
    /// before the tap is the difference between a merge and a surprise: the two
    /// cards become one, and the memories on this one move across.
    private var existing: Subject? {
        guard !isUnchanged else { return nil }
        return store.subjects(of: subject.kind).first {
            $0.id != subject.id
                && $0.title.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }
    }

    private var isCorrecting: Bool {
        if case .correcting = step { return true }
        return false
    }

    /// The tellings saved on other members' phones: the server takes a
    /// memory's text only from the phone that saved it (`sync.ts`), so they
    /// are counted and said beside the offer, never rewritten from here. Two
    /// whole sentences rather than one with a number in it, as the card's
    /// headings are, so that "one" can be a word.
    ///
    /// Not under the name field, where they stood at first: three sentences
    /// there pushed "Peruuta" low enough on the sheet for the audit's
    /// default-size simulation to report it (the position signature,
    /// `AccessibilityAudit.swift`), and before the tap they answer a question
    /// nobody has asked yet.
    private static func othersSentence(_ count: Int) -> String? {
        switch count {
        case ..<1: nil
        case 1: String(localized: "Yksi muisto, jossa nimi lukee, on tallennettu toisen puhelimella. Sen tekstiä voi muuttaa vain se, joka sen tallensi.")
        default: String(localized: "\(count) muistoa, joissa nimi lukee, on tallennettu muiden puhelimilla. Niiden tekstiä voi muuttaa vain se, joka ne tallensi.")
        }
    }

    /// Whether this phone can ask for a text at all. The chosen local mode
    /// has no member the server knows, so every request would be the same
    /// 401 (`TranscriptionCatchUp.isEnabled` says the same).
    private var canRewrite: Bool {
        !session.isLocalByChoice
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .name:
                    Form { nameStep }
                        // The field is filled but not focused. Raising the
                        // keyboard on appear pushed both buttons under it at
                        // the largest text size — the audit caught "Peruuta"
                        // behind the keys, which is the way out of a mistake
                        // hidden at exactly the size where mistakes are most
                        // likely. It reads better too: the name to be
                        // corrected is the thing to look at first, and the
                        // keyboard arrives when it is wanted.
                        .onAppear { name = subject.title }
                case .offer:
                    page { offerStep }
                case .correcting(let index, let total):
                    page { correctingStep(index, of: total) }
                case .done:
                    page { doneStep }
                }
            }
            .navigationTitle("Korjaa nimi")
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                "Yhdistetäänkö kortit?",
                isPresented: $isConfirmingMerge
            ) {
                Button("Yhdistä", role: .destructive) { save() }
                Button("Peruuta", role: .cancel) {}
            } message: {
                Text("Perheessä on jo \(existing?.displayTitle ?? ""). Tämän kortin muistot siirtyvät hänelle, eikä yhdistämistä voi perua.")
            }
            // Not while a text is being rewritten: the sheet is where it says
            // how many were done, and a swipe would take that away mid-way.
            .interactiveDismissDisabled(isCorrecting)
            .elderSurface()
        }
        // The card is told once the sheet has gone, by whatever way it went —
        // "Valmis", "Jätä teksti ennalleen" or a swipe down on the offer. A
        // merged card is a tombstone, and the card screen leaves it then.
        .onDisappear {
            if let merged { onSave(merged) }
        }
    }

    // MARK: - The name

    @ViewBuilder
    private var nameStep: some View {
        Section {
            TextField("Nimi", text: $name)
                .font(.title3)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isFocused)
                .elderTapTarget()
        } footer: {
            // Said plainly rather than discovered afterwards. What becomes
            // of the memories' words is the next step's to say, with the
            // count in it, once there is something to count.
            Text(existing == nil
                ? String(localized: "Nimi korjataan tähän korttiin ja sukuun.")
                : String(localized: "Perheessä on jo \(existing?.displayTitle ?? ""). Kortit yhdistetään, ja tämän muistot siirtyvät sinne."))
                .foregroundStyle(Elder.supporting)
        }

        // Both actions are rows rather than a row and a toolbar button.
        // A toolbar button's text barely grows with Dynamic Type — the
        // audit calls it "partially unsupported" and it is right — and
        // on this screen that would put the way out of a mistake in the
        // smallest text on it. Rows grow, and they are 60 pt targets.
        Section {
            // Two different acts behind one button, so only the heavier
            // one asks. A rename can be undone by renaming back; a merge
            // moves another person's memories onto this card and leaves
            // a tombstone behind, and nothing in the app undoes that.
            // The footer says so beforehand, but a footer is read by
            // somebody who is already looking for it.
            Button("Tallenna") {
                if existing == nil { save() } else { isConfirmingMerge = true }
            }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .elderTapTarget()
                .disabled(isUnchanged)

            // Ink, for `NameSheet`'s reason.
            Button("Peruuta") { dismiss() }
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity)
                .elderTapTarget()
        }
    }

    // MARK: - The words

    /// The steps after the name: a page of words and buttons rather than
    /// `Form` rows, built as `MemoryChoiceSheet` is.
    ///
    /// As rows they failed the audit at the default size (28 Sep 2026): the
    /// offer's two buttons and its footer, at y 400, 490 and 580, and the
    /// outcome's "Valmis" at y 416, each "partially unsupported" — the
    /// position signature `AccessibilityAudit.swift` describes, where the
    /// simulation grows everything above a row until the list stops drawing
    /// it. A page draws every word whether or not it is on the screen, and
    /// the choice sheet's "Sulje" sits as low on a page and is not reported.
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Elder.screenPadding)
            // Ink for the plain buttons, for the tree menu's reason
            // (`TreeMenuSheet`): the accent is the red of removal.
            .tint(Color.primary)
        }
    }

    /// The card is corrected; this is what the memories still say, and the
    /// one tap that changes it.
    @ViewBuilder
    private var offerStep: some View {
        if let correction {
            Text("Nimi on nyt \(correction.to).")
                .font(Elder.display(.title2))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if tellings.own.count == 1 {
                Text("Yhdessä muistossa lukee yhä \(correction.from).")
                    .elderBody()
            } else if tellings.own.count > 1 {
                Text("\(tellings.own.count) muistossa lukee yhä \(correction.from).")
                    .elderBody()
            }
            // Here, where the question about the words is.
            if let others = Self.othersSentence(tellings.others) {
                Text(verbatim: others)
                    .elderBody()
                    .foregroundStyle(tellings.own.isEmpty ? Color.primary : Elder.supporting)
            }

            if tellings.own.isEmpty {
                // Only other members' words say it: nothing to offer, and
                // the sentence above is the whole of the step.
                finishButton
            } else if canRewrite {
                Button { start(tellings.own) } label: {
                    // An if rather than a ternary, so that
                    // `localisation-check.mjs` sees both keys.
                    Group {
                        if tellings.own.count == 1 {
                            Text("Korjaa nimi myös muistoon")
                        } else {
                            Text("Korjaa nimi myös muistoihin")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.elderSecondary)
                .padding(.top, 8)
                Text("Alkuperäinen äänitys ja sanatarkka puhe säilyvät ennallaan.")
                    .font(.subheadline)
                    .foregroundStyle(Elder.supporting)
                    .fixedSize(horizontal: false, vertical: true)
                // Ink: the way out, not a lesser yes.
                Button { dismiss() } label: {
                    Text("Jätä teksti ennalleen")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
            } else {
                // A phone kept to itself has no model to ask, and saying so
                // beats a button that fails every time.
                Text("Tekstin voit korjata itse muiston alta: ”Muokkaa tai poista”.")
                    .elderBody()
                finishButton
            }
        }
    }

    /// No `ProgressView` anywhere else in the sheet: a spinner never stops
    /// drawing, and the offer and the outcome are the two steps an audit can
    /// read (`hasStoppedDrawing`).
    @ViewBuilder
    private func correctingStep(_ index: Int, of total: Int) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Korjataan muistoa \(index), kaikkiaan \(total)…")
                .elderBody()
        }
        .elderTapTarget()
        // Stops after the telling on its way, which is already paid for.
        Button { stopRequested = true } label: {
            Text("Keskeytä")
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .elderTapTarget()
        }
        .disabled(stopRequested)
    }

    @ViewBuilder
    private var doneStep: some View {
        if corrected == 1 {
            Text("Nimi korjattiin yhteen muistoon.")
                .font(Elder.display(.title2))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        } else if corrected > 1 {
            Text("Nimi korjattiin \(corrected) muistoon.")
                .font(Elder.display(.title2))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        if left.count == 1 {
            Text("Yhden muiston teksti jäi korjaamatta.")
                .elderBody()
        } else if left.count > 1 {
            Text("\(left.count) muiston teksti jäi korjaamatta.")
                .elderBody()
        }
        if !left.isEmpty {
            Text("Voit yrittää uudelleen tai korjata tekstin itse muiston alta: ”Muokkaa tai poista”.")
                .elderBody()
                .foregroundStyle(Elder.supporting)
            Button { start(left) } label: {
                Text("Yritä uudelleen")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.elderSecondary)
            .padding(.top, 8)
        }
        finishButton
    }

    private var finishButton: some View {
        Button { dismiss() } label: {
            Text("Valmis")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .elderTapTarget()
        }
    }

    // MARK: - Acts

    private func save() {
        guard !isUnchanged else { return }
        // The name the card ends up with: the other card's own spelling when
        // this is a merge into it, which is what the words should then say.
        let final = existing?.title ?? trimmed
        let mergesInto = existing != nil
        // Counted before the rename: a merge moves every telling onto the
        // other card, and this one's would then be nobody's.
        let naming = NamedTellings(naming: subject, in: store, memberID: session.identity.memberID)
        // `rename` does the whole job: it renames, or it merges into the subject
        // that already has that name and leaves a tombstone with a forwarding
        // address so nothing anywhere points at nothing. See MemoryStore.rename
        // and docs/ARCHITECTURE.md §2.5.
        store.rename(subjectID: subject.id, to: trimmed)
        merged = mergesInto
        isFocused = false
        // No telling's words say the name: the sheet closes on the tap, as it
        // always has. When only other members' tellings say it, the next
        // step is not an offer but the reason the words stay — the usual
        // case, a grandchild correcting what a grandmother was heard to say,
        // and the one who would otherwise find the story unchanged and no
        // word about why.
        guard !naming.own.isEmpty || naming.others > 0 else {
            dismiss()
            return
        }
        correction = NameCorrection(from: subject.title, to: final)
        tellings = naming
        step = .offer
    }

    private func start(_ ids: [String]) {
        stopRequested = false
        Task { await rewrite(ids) }
    }

    /// The Tell screen's correction, one telling at a time: the text and the
    /// corrected name through extraction, and the text that comes back
    /// written with `updateBody`.
    ///
    /// The telling's *body* goes in, not its raw transcript as at the Tell
    /// screen. The body is what the family reads and what an earlier hand
    /// may have corrected — a word fixed with *Muokkaa tekstiä*, or a name
    /// fixed at the result — and the transcript still has every one of those
    /// wrong. What comes back is the same text with the name inflected into
    /// it. Its questions and names are not used.
    private func rewrite(_ ids: [String]) async {
        guard let correction else { return }
        let extraction = AppServices.extraction { [session] in session.identity.token }
        var notDone: [String] = []
        for (offset, id) in ids.enumerated() {
            if stopRequested {
                notDone += ids[offset...]
                break
            }
            step = .correcting(offset + 1, of: ids.count)
            guard let memory = store.told.first(where: { $0.id == id }), !memory.body.isEmpty else { continue }
            do {
                let result = try await extraction.extract(
                    transcript: memory.body,
                    corrections: [correction],
                    level: nil
                )
                let body = result.body.trimmingCharacters(in: .whitespacesAndNewlines)
                // An empty answer is not a text, and never written over one.
                guard !body.isEmpty else {
                    notDone.append(id)
                    continue
                }
                store.updateBody(memoryID: id, body: body)
                corrected += 1
            } catch {
                notDone.append(id)
                // The kind of failure and nothing of the telling (rule 9's
                // habit, on the phone's own log).
                print("[names] rewriting a telling failed: \(type(of: error))")
                // The network, the minutes or the day's limit: every telling
                // after this one would meet the same wall, so the rest wait
                // for "Yritä uudelleen" rather than each failing in turn.
                if TranscriptionCatchUp.isAboutTheMoment(error) {
                    notDone += ids[(offset + 1)...]
                    break
                }
            }
        }
        left = notDone
        step = .done
    }
}

/// The tellings whose words still carry a name that is being corrected,
/// split by whose they are.
///
/// Only tellings tied to the card — filed under it or naming it — and only
/// those whose text says the name (`NameInText`): a person placed in a
/// photograph by hand is named by the telling and not in its words, and
/// rewriting a text that does not say the name would only risk its wording
/// for nothing. Not a telling still waiting for its text either.
///
/// Own means what `MemoryRow` means by it: told on this phone, or by this
/// member. The server takes a memory's body only from its author (`sync.ts`),
/// so the others are counted and said, never rewritten from here.
struct NamedTellings: Equatable {
    var own: [String] = []
    var others = 0

    init() {}

    @MainActor
    init(naming subject: Subject, in store: MemoryStore, memberID: String) {
        let naming = store.told.filter { memory in
            (memory.subjectID == subject.id || memory.mentionedSubjectIDs.contains(subject.id))
                && !memory.isAwaitingTranscription
                && NameInText.carries(subject.title, in: memory.body)
        }
        own = naming
            .filter { $0.authorID == nil || $0.authorID == memberID }
            .map(\.id)
        others = naming.count - own.count
    }
}

/// Whether a text says a name, in any of its forms.
///
/// Finnish inflects a name and often changes its stem as it does — "Pekan"
/// for Pekka, "Toivosen" for Toivonen, "Turussa" for Turku — so the whole
/// name is too long a key, and `HeardSentence`'s match misses every one of
/// those. The key here is the name's first letters, all but the last three
/// and never fewer than three, found at the start of a word, which is where
/// every case ending leaves them; and not inside another word, so "Marin"
/// does not say Ari.
///
/// It can say yes to a word that only begins the same way ("hiljaa" for
/// Hilda). It is asked only about tellings already tied to the name, where a
/// yes costs one extraction that changes nothing and a no leaves a wrong name
/// in a story.
enum NameInText {
    static func carries(_ name: String, in text: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        let key = String(name.prefix(max(3, name.count - 3)))
        var from = text.startIndex
        while let hit = text.range(of: key, options: .caseInsensitive, range: from ..< text.endIndex) {
            if hit.lowerBound == text.startIndex || !text[text.index(before: hit.lowerBound)].isLetter {
                return true
            }
            from = hit.upperBound
        }
        return false
    }
}
