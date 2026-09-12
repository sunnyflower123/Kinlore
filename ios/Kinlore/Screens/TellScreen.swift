import SwiftUI
import UIKit

/// The app's most important screen. One button, no menus, no settings.
struct TellScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session

    /// When the screen is opened from a photo or a person, the memory attaches
    /// to it. Nil = free dictation, in which case the subject is inferred from
    /// the speech.
    var target: Subject?
    /// When the screen is opened from an open question, the question is marked
    /// answered on save.
    var question: FollowUpQuestion?
    /// Set when the screen is presented as a sheet. The "Sulje" in the corner
    /// is this screen's to draw rather than the presenter's, because only the
    /// screen knows which phases an exit would destroy: both sheet sites used
    /// to attach their own unguarded button, and one tap — or a swipe — in the
    /// middle of a recording threw the telling away with no question asked,
    /// past the exact guard the hidden tab bar and the confirmed discard
    /// already put on the other two exits.
    var onClose: (() -> Void)?
    /// Whether this screen may choose its own subject when it was given none.
    /// True on the tab and nowhere else: see `Deck`.
    var usesDeck = false

    @State private var model: TellViewModel?
    @State private var isConfirmingClose = false
    /// Resolved once, like the opened subject beside it, and held rather than
    /// recomputed.
    ///
    /// It was a computed property first and that was wrong in a way only the
    /// *correct* answer showed: confirming a person writes to the store, the
    /// store is `@Observable`, this view rebuilds, the query says there is no
    /// card any more — and the card vanished under the finger that had just
    /// answered it, before the one sentence it had to say could be read. A
    /// wrong answer writes nothing and so kept its card, which is the same bug
    /// wearing the opposite face.
    @State private var blind: BlindConfirmation.Card?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        // Here and not on `IdleView`, which is where it went first and looked
        // right: the idle screen is one of nine phases this `Group` switches
        // between, so the paper stopped the moment she pressed the button and
        // the whole telling — listening, transcribing, the result — played on
        // white. Four recorded takes said so; nothing on the idle screen did.
        .elderSurface()
        .toolbar {
            if onClose != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sulje") { requestClose() }
                }
            }
        }
        // The interview is the one phase that can outlive this view, and a
        // swipe is how it did.
        //
        // `ask` speaks the question from an unstructured `Task` — the button's
        // own, not this view's `.task`, so a dismissal does not cancel it —
        // and when the speaking ends it starts recording, checking only
        // `isInterviewing` and the phase. "Sulje" clears both through
        // `endInterview`; a swipe cleared neither. So the microphone opened on
        // a screen that was no longer there, and nothing stopped it again:
        // neither the recorder nor the model has a `deinit`, and `stop()` is
        // the only thing that re-enables the idle timer or invalidates the
        // 50 ms ticker. The screen stopped sleeping for the rest of the
        // launch — and the recording went on into `tmp`, where the next
        // launch's `RecordingRecovery.sweep` adopts anything over a second as
        // a memory. That sweep exists to rescue a telling the app was killed
        // under; here it would file whatever the room said after she put the
        // phone down into the family's shared archive. Found 12 Sep 2026.
        //
        // Ending the interview rather than blocking the swipe: `.asking` is
        // the app talking, and it is exactly the moment somebody may want
        // out. Rule 1 does not spend an 80-year-old's patience on a gesture
        // that can simply be made safe. `endInterview` is the same thing
        // "Sulje" already does — the voice stops, the unanswered question is
        // recorded as a skip, `isInterviewing` goes false so the pending
        // `ask` never reaches `startRecording`, and the question stays open.
        //
        // Guarded on the phase and not on `isInterviewing`, which is also
        // true mid-answer: `leaveInterview` narrows `showsUpsell`, and an
        // ordinary disappearance has no business touching that.
        .onDisappear {
            if model?.phase == .asking { model?.endInterview() }
        }
        // A swipe must not do what "Sulje" is guarded against. Only the two
        // phases where an exit loses words are pinned: transcribing and
        // organizing finish on their own after a dismissal (the task holds the
        // model), and the interview between rounds has nothing unsaved — now
        // that the disappearance above ends it.
        .interactiveDismissDisabled(
            onClose != nil && (model?.phase == .recording || model?.phase == .writing)
        )
        // The same words as the in-screen discard, and the same manners: the
        // recorder keeps running while the question is open, so saying no
        // costs nothing.
        .alert(
            "Hylätäänkö tämä kertominen?",
            isPresented: $isConfirmingClose
        ) {
            Button("Hylkää", role: .destructive) {
                model?.discardRecording()
                onClose?()
            }
            Button("Jatka kertomista", role: .cancel) {}
        } message: {
            Text("Nauhoitusta ei tallenneta. Voit aloittaa alusta heti.")
        }
        .task {
            guard model == nil else { return }
            blind = blindCard
            #if DEBUG
            // `-screen starter` opens on a photo nobody has spoken about yet —
            // the state the starter questions exist for, and otherwise
            // reachable only by picking a photo from the library by hand.
            let opened = UserDefaults.standard.string(forKey: "screen") == "starter"
                ? Self.emptyPhoto(in: store)
                : target ?? deckCard
            #else
            let opened = target ?? deckCard
            #endif
            // AppServices picks the stub or the real service depending on
            // whether a backend address is configured. The UI cannot tell the
            // difference, because it only knows the protocols.
            let transcriber = AppServices.transcription { session.identity.token }
            #if DEBUG
            // `-defer once` wraps it here rather than in AppServices, so the
            // catch-up keeps a transcriber that works: the argument exists to
            // show a memory being finished, not only being interrupted.
            let transcription: TranscriptionService = AppServices.defersNextTranscription
                ? DeferringTranscriptionService(wrapped: transcriber)
                : transcriber
            #else
            let transcription = transcriber
            #endif
            let created = TellViewModel(
                store: store,
                transcription: transcription,
                extraction: AppServices.extraction { session.identity.token },
                target: opened,
                question: question,
                // The chosen local mode of a build with a real backend has no
                // member the server knows, so transcription can never succeed
                // there — the model skips the attempt and the result screen
                // says so (finding B4).
                canTranscribe: !session.isLocalByChoice
            )
            #if DEBUG
            // Screenshot aid: `-screen write` opens the typing view directly.
            if UserDefaults.standard.string(forKey: "screen") == "write" {
                created.beginWriting()
            }
            // Demo and screenshot aid: `-screen interview` runs a canned
            // memory through the stub pipeline and enters the interview loop,
            // finishing the first spoken round by itself. One launch argument
            // shows the whole loop hands-free — it is also how the loop can be
            // verified and filmed without a second pair of hands.
            if UserDefaults.standard.string(forKey: "screen") == "interview" {
                Task {
                    created.beginWriting()
                    // The LAST sample, deliberately: the recorded answers
                    // rotate from the first, so the opening telling and the
                    // first round never share their names — which is what
                    // lets a test see whether the rounds accumulate.
                    created.draft = StubTranscriptionService.samples[2]
                    await created.submitTyped()
                    await created.beginInterview()
                    // beginInterview returns once the question has been spoken
                    // and the answer is recording. Give the waveform a moment,
                    // then finish the round so the loop visibly reaches its
                    // second question.
                    try? await Task.sleep(for: .seconds(3))
                    if created.phase == .recording {
                        await created.stopAndProcess()
                    }
                }
            }
            // `-screen interviewed`: the same canned loop, run to its END —
            // one spoken round finished, the loop left on the result. A test
            // could not do this by tapping until 4 Sep 2026: "Riittää tältä
            // erää" existed only while a question was being spoken, and the
            // next round's recording replaced it within seconds. It stands on
            // the listening screen too now (SilentFailureTests taps it); this
            // aid stays for the screenshot. What the result screen must then show
            // is every round's names — see the accumulation note in
            // `TellViewModel.save`.
            if UserDefaults.standard.string(forKey: "screen") == "interviewed" {
                Task {
                    created.beginWriting()
                    created.draft = StubTranscriptionService.samples[2]
                    await created.submitTyped()
                    await created.beginInterview()
                    try? await Task.sleep(for: .seconds(3))
                    if created.phase == .recording {
                        await created.stopAndProcess()
                    }
                    // The next question's recording has started by itself;
                    // ending here lands on the result with both rounds'
                    // names waiting.
                    if created.phase == .recording {
                        created.discardRecording()
                    } else if created.phase == .asking {
                        created.endInterview()
                    }
                }
            }
            // `-screen result` stops where the interview begins: a canned
            // memory through the stub pipeline, and then nothing.
            //
            // The result screen with its **name proposals** on it is the one
            // place a wrong name is caught before it becomes a person (rule 4),
            // and it was unreachable without hands: `-screen interview` starts
            // talking a second later, and `-defer structure` reaches the screen
            // with no proposals on it at all. So the rows that carry the accent
            // colour, the confirm tick and a text field each had never been
            // measured by anything.
            if UserDefaults.standard.string(forKey: "screen") == "result" {
                Task {
                    created.beginWriting()
                    created.draft = StubTranscriptionService.samples[0]
                    await created.submitTyped()
                }
            }
            // Demo and screenshot aid: `-defer once` records a few seconds and
            // has the transcription fail as though the month's minutes had just
            // run out, leaving the memory waiting for its text.
            //
            // The other half happens on its own: returning to the foreground
            // runs the catch-up, and the memory finishes. The two together are
            // one filmable sequence, and there is no other way to film it —
            // the real trigger is an outage nobody can schedule.
            if AppServices.defersNextTranscription {
                Task {
                    await created.startRecording()
                    // A recording under a second is read as an accident rather
                    // than a memory, and the point here is a memory.
                    try? await Task.sleep(for: .seconds(2))
                    if created.phase == .recording {
                        await created.stopAndProcess()
                    }
                }
            }
            #endif
            model = created
        }
    }

    /// What "Sulje" does depends on what would be lost. A running recording is
    /// asked about; a typed draft is let go the way the screen's own Peruuta
    /// already lets it go; an interview between rounds ends the way "Riittää
    /// tältä erää" ends it; everything else just closes.
    private func requestClose() {
        switch model?.phase {
        case .recording:
            isConfirmingClose = true
        case .writing:
            model?.cancelWriting()
            onClose?()
        case .asking:
            model?.endInterview()
            onClose?()
        default:
            onClose?()
        }
    }

    @ViewBuilder
    private func content(_ model: TellViewModel) -> some View {
        Group {
            switch model.phase {
            case .idle:
                IdleView(
                    model: model,
                    blind: blind,
                    onBlindDone: { blind = nil },
                    onSkip: usesDeck ? { skipCard(model) } : nil
                )
                .onAppear { advancePastTold(model) }
            case .recording:
                RecordingView(model: model)
            case .writing:
                WritingView(model: model)
            case .transcribing, .organizing:
                ProcessingView(phase: model.phase)
            case .asking:
                AskingView(model: model)
            case .done:
                ResultView(model: model)
            case .savedWithoutTranscript:
                AudioSavedView(model: model)
            case .needsMicrophone:
                MicrophoneDeniedView(model: model)
            case .failed(let message):
                FailureView(message: message) { model.reset() }
            }
        }
        // Mid-telling, the screen has one job. A tab bar would offer an exit
        // that loses the unfinished memory, and an 80-year-old user gains
        // nothing from alternatives at exactly the moment she is concentrating.
        .toolbar(hidesTabBar(model.phase) ? .hidden : .visible, for: .tabBar)
    }

    /// The deck's card, and the one thing that outranks it.
    ///
    /// **A question somebody in the family asked always comes first.** It is
    /// the strongest thing this app can put in front of anybody — *"Ville
    /// kysyy"* turns a prompt into a request from a person — and the deck must
    /// not step over it. Giving the screen a subject is exactly what would:
    /// with a target set, the idle screen offers *that subject's* questions and
    /// the family's question about something else disappears.
    ///
    /// It disappeared for one commit, and `VideoSceneTests` caught it — the
    /// demo video's fourth scene is that question being answered aloud, which
    /// is why the scene is pinned by a test at all.
    private var deckCard: Subject? {
        guard usesDeck,
              store.openQuestions(
                  limit: 1, excludingAuthor: session.identity.memberID
              ).isEmpty
        else { return nil }
        return Deck.next(in: store)
    }

    /// The strongest card this screen can offer, and the one thing it will not
    /// step over.
    ///
    /// **Ranked above the deck's own card and below a family question.** It
    /// asks for a tap rather than a telling, so it costs the least of anything
    /// here — and §13's account of the cut round says the same thing from the
    /// other end: it was the only part of the app that asked nothing of the
    /// 80-year-old. `BlindConfirmation` bounds it to one per session, which is
    /// what keeps a screen built for telling from becoming a quiz.
    ///
    /// It inherits the family-question guard rather than restating it: a
    /// question somebody actually asked outranks anything the app thought of
    /// by itself, and that is true of this card exactly as it is of the deck's.
    private var blindCard: BlindConfirmation.Card? {
        // Not on a grandparent's phone: there the Kerro tab is the button and
        // nothing else, and the card sits on Muistot, in the reading loop
        // (founder's-eye review, 3 Sep 2026, findings #75, #83).
        guard usesDeck, !UserDefaults.standard.bool(forKey: Elder.largerTextKey),
              store.openQuestions(
                  limit: 1, excludingAuthor: session.identity.memberID
              ).isEmpty
        else { return nil }
        return BlindConfirmation.next(in: store)
    }

    /// The card that has been answered gives way to the next one.
    ///
    /// Without this the loop stops after one telling: finishing returns to
    /// `.idle` with the same subject, now carrying a memory, still framed as a
    /// card and still offering a way past something already told. Telling more
    /// about one photograph is a real thing to want — it is just not what the
    /// deck is for, and the photograph is one tap away in Muistot.
    private func advancePastTold(_ model: TellViewModel) {
        guard usesDeck, let current = model.target, !store.isEmpty(current) else { return }
        model.moveTo(deckCard)
    }

    /// *"En muista tätä."* The card goes, the next one arrives, and the screen
    /// does not move — this is one act, not a navigation.
    ///
    /// `Deck.next` is asked again rather than a queue being held: the archive
    /// may have grown since the last card, and a list built once would go on
    /// offering a photograph somebody has meanwhile told about.
    private func skipCard(_ model: TellViewModel) {
        guard let current = model.target else { return }
        Deck.skip(current)
        model.moveTo(deckCard)
    }

    #if DEBUG
    /// A photo with no memories on it, created if the archive has none. Reuses
    /// an existing empty photo so repeated runs do not fill the gallery.
    private static func emptyPhoto(in store: MemoryStore) -> Subject {
        if let existing = store.subjects(of: .photo).first(where: { store.isEmpty($0) }) {
            return existing
        }
        let subject = Subject(kind: .photo, title: "")
        store.add(subject)
        return subject
    }
    #endif

    private func hidesTabBar(_ phase: TellViewModel.Phase) -> Bool {
        switch phase {
        // The refused microphone keeps the bar: it is a dead end for telling by
        // voice, and somebody who does not want to go to Settings has to be able
        // to walk away from it.
        case .idle, .done, .savedWithoutTranscript, .needsMicrophone, .failed: false
        case .recording, .writing, .transcribing, .organizing, .asking: true
        }
    }
}

// MARK: - Idle

private struct IdleView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize
    let model: TellViewModel
    /// The blind confirmation, when the archive can make one. It replaces
    /// everything else on the screen while it is up — there is no record button
    /// on it, because the answer is a name and not a telling.
    var blind: BlindConfirmation.Card?
    /// Puts the card away once she has read what her answer did. The card is
    /// the screen while it is up, so this is the only way off it.
    var onBlindDone: () -> Void = {}
    /// Non-nil only when the subject on screen was chosen by the deck rather
    /// than navigated to. A photograph somebody opened on purpose is not a card
    /// to be pushed aside.
    var onSkip: (() -> Void)?

    @State private var answering: FollowUpQuestion?
    /// What to say once she has answered, and the only state this card keeps.
    /// Nil while the question is still on screen.

    /// The reassurance is what makes an elderly person willing to start talking,
    /// so it is not dropped at large text sizes — it is shortened. In full it ran
    /// to five lines at the largest size and pushed the record button, the one
    /// thing this screen exists for, below the fold where it has to be found by
    /// scrolling. The first sentence carries the permission; the rest is detail.
    ///
    /// It is shortened for starter questions too, and for the same reason from
    /// the other end: two starters below the button are three lines the screen
    /// does not have, and they pushed "Kirjoita sen sijaan" under the tab bar at
    /// the ordinary text size. A starter says what to do more concretely than
    /// the reassurance does — "Kuka tässä kuvassa on?" is the permission.
    ///
    /// Once per install it says something else entirely. The first press does
    /// not start a recording, it raises iOS's permission prompt — a dialog
    /// nobody chose to open, over a screen that has just been read, with a
    /// refusal one tap away. Answered wrongly it is not recoverable by this
    /// user: the way back is four taps into a settings tree, under a switch, in
    /// a list of apps, which is why the screen behind a refusal had to be built
    /// at all (ARCHITECTURE §8.9).
    ///
    /// So the app says it first, and the sentence **replaces** the reassurance
    /// rather than joining it. Nothing is lost by the swap: a starter question
    /// says what to do more concretely than the reassurance does, and the
    /// reassurance is there for every press after this one.
    ///
    /// It names no button. The affirmative label on that prompt is Apple's and
    /// has changed between iOS versions; sending an 80-year-old to look for a
    /// word that is not there would be worse than saying nothing.
    // `LocalizedStringKey`, here and on every other computed text of this
    // screen: as Strings they were shown verbatim, so the title, the
    // microphone hint, the starters' heading, the processing phases and the
    // blind card's answer were Finnish on an English phone — photographed
    // 5 Sep 2026, after the review's own list (#38, #93) had missed them.
    private func intro(withStarters: Bool) -> LocalizedStringKey {
        if AudioRecorder.isPermissionUnasked {
            // Shortened by the same rule as the reassurance below, and it was
            // measured the hard way: the two-line version at the *ordinary* text
            // size put "Kirjoita sen sijaan" underneath the floating tab bar —
            // the one way on from this screen that needs no permission at all,
            // hidden by the sentence about permission. On a first launch the
            // starters are always there, so the short one is what ships; the
            // long one is for somebody who joined a family that has already been
            // told about.
            return typeSize.isAccessibilitySize || withStarters
                ? "Puhelin kysyy ensin luvan mikrofoniin."
                : "Puhelin kysyy ensin luvan mikrofoniin. Anna lupa, niin voit puhua."
        }
        return typeSize.isAccessibilitySize || withStarters
            ? "Puhu ihan rauhassa ja vapaasti."
            : "Puhu ihan rauhassa ja vapaasti. Ei tarvitse muistaa järjestystä eikä vuosilukuja — järjestämme ne puolestasi."
    }

    /// What is offered beside the big button, chosen by the ladder: easy enough
    /// to be answerable, and never a competing subject.
    ///
    /// In free dictation these are the family's open questions. On a photo or a
    /// person the screen already has a subject, so only that subject's own
    /// questions appear — and when nobody has said anything about it yet, the
    /// starters that stand in for the questions extraction has had no chance to
    /// make. That case used to be a blank button, which is the hardest thing
    /// this app ever put in front of anyone. See docs/ARCHITECTURE.md §12.
    ///
    /// The same emptiness had been left standing on the screen where it costs
    /// most. Free dictation with a fresh archive has no open questions either —
    /// extraction has had nothing to make them from — so the first Tell screen an
    /// 80-year-old is ever handed offered nothing at all beside the button. The
    /// ladder had its bottom rung built for a photo and missing for the first
    /// launch; `openingQuestions()` is that rung.
    private var offer: (questions: [FollowUpQuestion], isStarter: Bool) {
        guard let target = model.target else {
            let open = store.openQuestions(limit: 2, excludingAuthor: session.identity.memberID)
            return open.isEmpty ? (store.openingQuestions(), true) : (open, false)
        }
        let own = store.openQuestions(
            limit: 2, for: target.id, excludingAuthor: session.identity.memberID
        )
        return own.isEmpty ? (store.starterQuestions(for: target), true) : (own, false)
    }

    /// Typing, which needs nobody's permission — and is not tinted.
    ///
    /// The card is what forced that question: with a photograph on this screen
    /// this row lands inside the tab bar's fade, where the audit measured the
    /// tint at 3.52:1 against a 4.5:1 minimum. It is the same call the
    /// gallery's "Kerro tästä" row already made — blue on this grey only
    /// nearly passes and fails outright in the fade. Weight invites; the
    /// keyboard says what it does.
    private var writingButton: some View {
        Button {
            model.beginWriting()
        } label: {
            Label("Kirjoita sen sijaan", systemImage: "keyboard")
                .font(.body.weight(.medium))
                .foregroundStyle(Elder.supporting)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .elderTapTarget()
        }
    }

    /// The way past a card she cannot answer, quiet for the same measured
    /// reason as the row beside it. A photograph she does not recognise with
    /// no way past it is a screen she leaves.
    private func skipButton(_ onSkip: @escaping () -> Void) -> some View {
        Button(action: onSkip) {
            Label("En muista tätä", systemImage: "arrow.forward")
                .font(.body.weight(.medium))
                .foregroundStyle(Elder.supporting)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .elderTapTarget()
        }
    }

    /// The card's one question — the smallest thing this app can ask, and on a
    /// card it is the whole screen's title.
    ///
    /// This is the shape the design was drawn in: picture, question, button,
    /// and two ways on. It arrived by measurement rather than by taste — with
    /// the ordinary title, the reassurance, the caption and the question in a
    /// box of its own, a 260 pt photograph and a 200 pt record button left the
    /// question itself under the tab bar. The card asked nothing on the one
    /// screen built to ask.
    ///
    /// The big button answers it rather than starting free dictation, which is
    /// what keeps the ladder learning: `answer(_:)` sets the question and then
    /// records, the same call the question cards make.
    private var cardQuestion: FollowUpQuestion? {
        guard deckPhoto != nil else { return nil }
        return offer.questions.first
    }

    /// The card's picture, when there is one. Only for a photograph nobody has
    /// spoken about: a person's card has a name and no face, and a photograph
    /// that already carries memories is not a card.
    private var deckPhoto: UIImage? {
        guard onSkip != nil,
              let target = model.target,
              target.kind == .photo,
              let filename = target.imageFilename
        else { return nil }
        return MediaStore.loadImage(named: filename)
    }

    private var title: LocalizedStringKey {
        guard let target = model.target else { return "Kerro mitä muistat" }
        // The name stays in the nominative. A colon before a case ending is
        // the spelling for abbreviations, never names — and a hardcoded -sta
        // breaks on vowel harmony ("Yrjö") and consonant stems ("Matias")
        // anyway. Same rule as the starters: Finnish inflection cannot be
        // done with string concatenation (QuestionLadder).
        return target.kind == .person
            ? "Kerro hänestä — \(target.displayTitle)"
            : "Kerro tästä kuvasta"
    }

    var body: some View {
        // Scrolling rather than a plain stack. At the largest text size this
        // screen is taller than the phone, and without a scroll view SwiftUI
        // compresses it: the title left the screen, "Paina ja ala puhua"
        // truncated to an ellipsis, and the open question disappeared under the
        // tab bar. The minimum height keeps everything centred at normal sizes,
        // which is where this screen spends most of its life.
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(Elder.screenPadding)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .sheet(item: $answering) { question in
            NavigationStack {
                TellScreen(
                    target: question.subjectID.flatMap { store.subject(id: $0) },
                    question: question,
                    onClose: { answering = nil }
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let blind {
            BlindCardView(card: blind, onDone: onBlindDone)
        } else {
            tellingContent
        }
    }

    // MARK: - The blind confirmation

    /// Picture, question, names. The deck's card with the record button taken
    /// out and the answers put where it stood, because the question is not
    /// *"tell me about this"* — it is *"who is this"*, and it is answered by
    /// pointing rather than by talking.
    ///
    /// **Nothing here carries the proposal's name until she has chosen one.**
    /// The rows are drawn from `card.names`, which the proposal sits inside
    /// unmarked, and `card.person` is never read by this view. That is the
    /// whole feature and it is the half that fails silently — a card that leaks
    /// its answer still looks like a working card — so
    /// `BlindConfirmationTests` asserts it instead of trusting this comment.
    private var tellingContent: some View {
        VStack(spacing: 28) {
            // Resolved once: what is offered at the bottom decides how long the
            // reassurance at the top can afford to be.
            let offered = offer

            Spacer(minLength: 0)

            // The card. A photograph asks its question without needing a word
            // in it, which is the whole reason this screen stopped being a
            // blank button — and it is the one thing here that gives way: at
            // accessibility sizes the words below it grow and the picture
            // yields, exactly as the camera's preview does.
            if let photo = deckPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    // 200, and the number is the screen's rather than the
                    // picture's: with the question, the button, its caption and
                    // the two ways on, 260 put the last row behind the floating
                    // tab bar. The picture is what this layout was built to let
                    // give way, so it gives way.
                    //
                    // Worth knowing before changing it: while the content still
                    // fitted, shrinking this moved nothing at all — it is
                    // centred between two spacers, so a smaller picture only
                    // fed the spacers. It only buys height once the screen has
                    // more on it than fits, which is exactly the case the card
                    // created.
                    .frame(maxHeight: typeSize.isAccessibilitySize ? 150 : 200)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    // A scanned photograph has no description and the app must
                    // not invent one — guessing at the content is precisely
                    // what rule 4 forbids. What is said is what is known.
                    .accessibilityLabel("Valokuva, josta ei ole vielä kerrottu")
            }

            // A question's text is the family's own words and is shown as it
            // is; the title is a key. Two `Text`s, one for each.
            Group {
                if let question = cardQuestion {
                    Text(question.text)
                } else {
                    Text(title)
                }
            }
            // The serif, and this is the one line on the screen that gets it:
            // the question is what the screen is about, and everything else
            // here — the reassurance, the starter, the counter — stays in SF
            // where an 80-year-old reads it at arm's length.
            .font(Elder.display(.largeTitle))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            // Dropped when there is a card. The reassurance exists to make a
            // blank button approachable — *"Puhu ihan rauhassa ja vapaasti"* is
            // the sentence that makes somebody willing to start — and a
            // photograph is not a blank button. It is also the cheapest 60 pt
            // on a screen that has just grown a picture: with it, the starter
            // question was below the fold, and the starter is what makes the
            // card answerable at all.
            if deckPhoto == nil {
                Text(intro(withStarters: offered.isStarter))
                    .elderBody()
                    .foregroundStyle(Elder.supporting)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            RecordButton(isRecording: false) {
                Task {
                    if let cardQuestion {
                        await model.answer(cardQuestion)
                    } else {
                        await model.startRecording()
                    }
                }
            }

            // fixedSize on every label below: under vertical pressure SwiftUI
            // truncates a Text before it shrinks anything else, and a truncated
            // instruction is worse than a longer screen.
            Text("Paina ja ala puhua")
                .font(.headline)
                .foregroundStyle(Elder.supporting)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // An open question is a reason to come back to the app. It is also
            // an easier start than a blank button: telling "something" is hard
            // for an elderly person, answering a question is easy.
            // Not on a card: the question is the title there, and repeating it
            // in a box below the button is the same ask twice on the screen
            // that can least afford the height.
            if !offered.questions.isEmpty, cardQuestion == nil {
                VStack(spacing: 10) {
                    Group {
                        if offered.isStarter {
                            Text("Jos et tiedä mistä aloittaa")
                        } else {
                            Text("Tai vastaa aiempaan kysymykseen")
                        }
                    }
                        .font(.subheadline)
                        .foregroundStyle(Elder.supporting)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    // One with a card, two without. The card is one question
                    // at a time by design; a second below a photograph is a
                    // choice to make before answering, and choosing is work.
                    ForEach(deckPhoto == nil ? offered.questions : Array(offered.questions.prefix(1))) { question in
                        Button {
                            // A question about some other subject opens that
                            // subject's own screen. When this screen is already
                            // the right subject the microphone just starts: no
                            // sheet on top of a sheet.
                            //
                            // Routed by the question rather than by the screen,
                            // because an opening starter has no subject at all —
                            // asking it to open "its own" screen would push an
                            // identical, emptier copy of this one in front of
                            // somebody who has not yet said a word.
                            if let subjectID = question.subjectID,
                               model.target?.id != subjectID {
                                answering = question
                            } else {
                                Task { await model.answer(question) }
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "questionmark.circle.fill")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    // "Ville kysyy" turns the prompt into a
                                    // request from a person — the strongest
                                    // reason there is to press the button.
                                    if let asker = question.authorName {
                                        Text("\(asker) kysyy")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.tint)
                                    }
                                    Text(question.text)
                                        .elderBody()
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .elderCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }

            // Side by side with the way past a card, and only there. A card
            // makes this screen taller than any state it has had, and stacked
            // these two put the second one under the tab bar — a way past a
            // photograph she cannot place, reachable only by scrolling, which
            // for this user is not reachable. At accessibility sizes they
            // stack again: two labels cannot share a line there, and the
            // screen is taller than the phone on purpose by then.
            if let onSkip, model.target != nil, !typeSize.isAccessibilitySize {
                HStack(spacing: 10) {
                    writingButton
                    skipButton(onSkip)
                }
            } else {
                writingButton
                if let onSkip, model.target != nil {
                    skipButton(onSkip)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Typing

private struct WritingView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Bindable var model: TellViewModel
    @FocusState private var isFocused: Bool

    private var isEmpty: Bool {
        model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var heading: LocalizedStringKey {
        model.target == nil ? "Kirjoita muisto" : "Kirjoita tästä muisto"
    }

    var body: some View {
        // The height is pinned to what the container actually offers rather than
        // left to `maxHeight: .infinity`.
        //
        // An editor that asks for infinite height reaches under the keyboard, and
        // iOS answers by shoving the whole view upwards — the heading went out
        // through the status bar and the first line of the placeholder went with
        // it. GeometryReader measures the space left *after* the keyboard has
        // taken its share, so nothing overflows and nothing is displaced.
        GeometryReader { proxy in
            editor
                .padding(Elder.screenPadding)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        // The actions live on the keyboard, not under the editor. Stacked below
        // they were pushed off the bottom at the largest text size: the memory
        // could be written but not saved. Attached to the keyboard they cannot be
        // displaced, because they travel with it.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Peruuta") {
                    isFocused = false
                    model.cancelWriting()
                }

                Spacer()

                Button("Tallenna") {
                    isFocused = false
                    Task { await model.submitTyped() }
                }
                .font(.body.weight(.semibold))
                .disabled(isEmpty)
            }
        }
        .onAppear { isFocused = true }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            // The heading is dropped at accessibility sizes: with the keyboard up
            // there is barely a screen left, and the placeholder already says what
            // to do. VoiceOver still hears it — it is on the editor below.
            if !typeSize.isAccessibilitySize {
                Text(heading)
                    .font(.title.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ZStack(alignment: .topLeading) {
                // TextEditor has no placeholder of its own.
                if model.draft.isEmpty {
                    Text("Kirjoita ihan vapaasti. Ei tarvitse muistaa järjestystä eikä vuosilukuja — järjestämme ne puolestasi.")
                        .elderBody()
                        // Not `.tertiary`. A placeholder is conventionally the
                        // faintest thing on screen, and this one is the sentence
                        // that tells her what to write.
                        .foregroundStyle(Elder.supporting)
                        .padding(.top, 10)
                        .padding(.horizontal, 6)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $model.draft)
                    .font(.body)
                    .lineSpacing(Elder.lineSpacing)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .accessibilityLabel(heading)
            }
            .frame(maxHeight: .infinity)
            .padding(10)
            .elderCard(radius: 16)
        }
    }
}

// MARK: - Recording

private struct RecordingView: View {
    let model: TellViewModel

    @State private var isConfirmingDiscard = false

    var body: some View {
        // The same scroll treatment as IdleView and AskingView: with a question
        // on screen this stack is taller than the phone at the largest text
        // size, and truncating the question somebody is answering right now
        // would be absurd.
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(Elder.screenPadding)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // The recorder keeps running while this is on screen, so saying no to it
        // costs nothing: the telling carries on where it left off. Stopping
        // first and asking afterwards would make the safe answer the expensive
        // one.
        .alert(
            "Hylätäänkö tämä kertominen?",
            isPresented: $isConfirmingDiscard
        ) {
            Button("Hylkää", role: .destructive) { model.discardRecording() }
            Button("Jatka kertomista", role: .cancel) {}
        } message: {
            Text("Nauhoitusta ei tallenneta. Voit aloittaa alusta heti.")
        }
    }

    private var content: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            Text("Kuuntelen")
                .font(.largeTitle.weight(.semibold))

            // The question stays visible while it is being answered. Vanishing
            // the moment the button is pressed is how somebody loses the thread
            // halfway through the first sentence — and it is the one question
            // they have not had time to memorise, because they only just chose
            // it.
            if let question = model.question {
                Text(question.text)
                    // The same serif it wore on the screen before this one:
                    // it is the same question, still being answered.
                    .font(Elder.display(.title3))
                    .foregroundStyle(Elder.supporting)
                    .multilineTextAlignment(.center)
                    .lineSpacing(Elder.lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The waveform is the only feedback that the device can hear.
            // Somebody speaking quietly has no other way to know whether the
            // microphone works.
            Waveform(levels: model.recorder.levels)
                .frame(height: 96)
                .padding(.horizontal, 8)

            Text(Self.timeText(model.recorder.elapsed))
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(Elder.supporting)
                .monospacedDigit()
                // The first audit ever run on this screen reported the timer
                // clipped at the default size; a single line of digits has no
                // honest reason to shrink.
                .fixedSize()
                .accessibilityLabel("Nauhoitettu \(Int(model.recorder.elapsed)) sekuntia")

            Spacer(minLength: 0)

            RecordButton(isRecording: true) {
                Task { await model.stopAndProcess() }
            }

            Text("Paina kun olet valmis")
                .font(.headline)
                // Full primary rather than Elder.supporting, which every
                // sibling caption wears: this one sits within the pulsing
                // record disc's reach, and the first audit of this screen
                // measured it under the minimum there. The instruction for
                // ending a telling is also the one caption that must never
                // be the faint one.
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // The loop's exit that keeps the answer. In the loop the big button
            // means "next question", and until 4 Sep 2026 the only other way
            // out while listening was the red one below — so ending a
            // conversation that had gone somewhere hard meant racing the
            // seconds "Riittää tältä erää" stood on the asking screen, or
            // throwing the answer away (finding #114). The same words as
            // there, for the same act: enough for now, and keep what I said.
            if model.isInterviewing {
                Button("Riittää tältä erää") { Task { await model.finishAfterThisAnswer() } }
                    .controlSize(.large)
                    .elderTapTarget()
            }

            // The way out. A false start, the wrong story, somebody coming into
            // the room — until this existed the only button here both stopped
            // and saved, so a telling begun by accident had to be finished and
            // then lived with. Quiet and below the big button: it is the rare
            // choice, and it must never be the easy one to hit by mistake.
            Button("Älä tallenna tätä") { isConfirmingDiscard = true }
                .font(.body.weight(.medium))
                .foregroundStyle(Elder.destructive)
                .controlSize(.large)
                .elderTapTarget()

            Spacer(minLength: 0)
        }
    }

    private static func timeText(_ interval: TimeInterval) -> String {
        String(format: "%d:%02d", Int(interval) / 60, Int(interval) % 60)
    }
}

/// Bars with the newest on the right. Centred vertically, so that silence looks
/// like a thin line rather than an empty screen.
private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        GeometryReader { geometry in
            let count = 48
            let spacing: CGFloat = 4
            let width = max(2, (geometry.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0 ..< count, id: \.self) { index in
                    let level = level(at: index, of: count)
                    Capsule()
                        // Ink, not the disc's colour. The line and the button
                        // were the same red, which spent the one loud colour
                        // on the screen twice; with the line in ink the disc
                        // is the only red thing and reads as the control. As
                        // a graphic it is judged at 3:1 and measures far
                        // above it — `.primary` is what the rest of this app
                        // calls its ink, and it is a shade darker than the
                        // token.
                        .fill(Color.primary.gradient)
                        .frame(
                            width: width,
                            height: max(3, CGFloat(level) * geometry.size.height)
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(.easeOut(duration: 0.08), value: levels.count)
        }
        .accessibilityHidden(true)
    }

    /// Filled from the right: the newest sample is always at the edge.
    private func level(at index: Int, of count: Int) -> Float {
        let offset = count - levels.count
        guard index >= offset else { return 0 }
        return levels[index - offset]
    }
}

// MARK: - Processing

private struct ProcessingView: View {
    let phase: TellViewModel.Phase

    private var title: LocalizedStringKey {
        phase == .transcribing ? "Kuuntelen mitä sanoit" : "Järjestelen muistoa"
    }

    private var detail: LocalizedStringKey {
        phase == .transcribing
            ? "Puran puheen tekstiksi."
            : "Etsin ihmiset, paikat ja ajankohdan."
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .controlSize(.extraLarge)

            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)

            Text(detail)
                .elderBody()
                .foregroundStyle(Elder.supporting)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(Elder.screenPadding)
        .animation(.easeInOut, value: phase)
    }
}

// MARK: - Asking (interview loop)

/// The app is reading a follow-up question aloud. Same geometry as
/// RecordingView — the big button stays in the same place, because
/// mid-conversation is the wrong moment to relearn a layout.
private struct AskingView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let model: TellViewModel

    @AccessibilityFocusState private var questionFocused: Bool

    /// VoiceOver users answer with the button; everyone else can just start
    /// talking when the voice stops — and the same sentence now says how the
    /// answer ends. It used to say only how it starts, on the one screen she
    /// is looking at: the microphone then armed itself, and the instruction
    /// to press when done stood on the listening screen she had been moved to
    /// without pressing anything. An app that speaks first is expected to
    /// take the turn back, and this one never did (finding #113). Shortened
    /// at accessibility sizes for the same reason as IdleView's intro.
    ///
    /// `LocalizedStringKey`, not `String`: as Strings these had never been
    /// looked up, on the flagship loop.
    private var hint: LocalizedStringKey {
        if UIAccessibility.isVoiceOverRunning { return "Paina nauhoitusnappia ja vastaa." }
        return typeSize.isAccessibilitySize
            ? "Vastaa puhumalla. Paina isoa nappia, kun olet valmis."
            : "Kun kysymys loppuu, nauhoitus alkaa itsestään. Kerro vastauksesi ja paina isoa nappia, kun olet valmis."
    }

    private var buttonCaption: LocalizedStringKey {
        UIAccessibility.isVoiceOverRunning
            ? "Paina ja vastaa"
            : "Paina jos haluat vastata heti"
    }

    var body: some View {
        // The same scroll treatment as IdleView: at the largest text size the
        // stack is taller than the phone, and truncating the question the
        // voice is reading aloud would be absurd.
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(Elder.screenPadding)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear { questionFocused = true }
    }

    private var content: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, isActive: model.voice.isSpeaking)
                .accessibilityHidden(true)

            Text(model.askedQuestion?.text ?? "")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineSpacing(Elder.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($questionFocused)

            Text(hint)
                .elderBody()
                .foregroundStyle(Elder.supporting)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            RecordButton(isRecording: false) {
                Task { await model.answerNow() }
            }

            Text(buttonCaption)
                .font(.headline)
                .foregroundStyle(Elder.supporting)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Riittää tältä erää") { model.endInterview() }
                .controlSize(.large)
                .elderTapTarget()

            Spacer(minLength: 0)
        }
    }
}

// MARK: - The blind card

/// The photograph the name was heard in, and four names with the proposal
/// unmarked among them (rule 4, ARCHITECTURE §23). One view, shown in two
/// places: on the Kerro tab of a reader's phone, where it was born, and on
/// Muistot of a grandparent's phone since 5 Sep 2026, so that her Kerro tab
/// is the button and nothing else. What it must keep is the same in both —
/// nothing on it names the proposal, and a wrong answer is never called
/// wrong. `BlindConfirmationTests` walks every element to see that it does.
struct BlindCardView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    let card: BlindConfirmation.Card
    var onDone: () -> Void = {}

    @State private var afterward: LocalizedStringKey?

    var body: some View {
        // 18 and not the 28 the telling screen uses. Four answers is three more
        // rows than that screen carries, and at 24 the last of them — the way
        // past a face she cannot place — was drawn underneath the floating tab
        // bar. Measured on the first build of this card.
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            if let filename = card.photo.imageFilename,
               let image = MediaStore.loadImage(named: filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: typeSize.isAccessibilitySize ? 150 : 200)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    // What is known and nothing more. A name in here would hand
                    // the answer to whoever is listening rather than looking —
                    // the audience this card is most for, and the same leak the
                    // cut round's mask existed to stop, arriving by the other
                    // door.
                    .accessibilityLabel("Valokuva, jossa on joku")
            }

            Text(afterward ?? "Kuka tässä on?")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if afterward == nil {
                // The answers, as one block: with the outer stack's spacing
                // between them they took the height the last row needed.
                VStack(spacing: 10) {
                    // **Untinted**, which the first build of this card got
                    // wrong. `.bordered` paints its label in the accent, so
                    // four names arrived in the system blue — the colour rule 1
                    // names outright — sitting in the tab bar's fade, where the
                    // audit has already measured that accent at 3.52:1 against
                    // a 4.5:1 minimum. The border says it is a control and the
                    // weight invites; the colour was doing neither job.
                    // **Filled, and the fill is the point.** These were
                    // `.bordered` over the old white ground, and the parchment
                    // took their edge away: a bordered capsule measures
                    // **1.53:1** against `Elder.paper`, where WCAG 1.4.11 asks
                    // 3:1 of anything that has to read as a control. The words
                    // inside were never the problem — black on that capsule is
                    // 11.9:1 — which is why it looked fine and why only a
                    // measurement found it. Ink against the paper is 15.17:1
                    // and cream on ink 16.56:1, so the button now has an edge
                    // for somebody who cannot pick a pale grey capsule out of
                    // a pale ground.
                    //
                    // Four filled buttons rather than one, which is the shape
                    // ARCHITECTURE §22 usually forbids. It holds here because
                    // they are not four actions competing to be the primary
                    // one: they are one question's four answers, and none of
                    // them may look more likely than the others — rule 4's
                    // whole point is that the proposal sits unmarked among
                    // them.
                    ForEach(card.names) { name in
                        Button {
                            answer(card, chose: name)
                        } label: {
                            Text(name.displayTitle)
                                .font(.body.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(Elder.cream)
                        }
                        // `.plain` with a capsule of our own, and not
                        // `.borderedProminent` with a tint. The prominent
                        // style picks its own label colour out of the tint
                        // after the label is built — the same overwrite that
                        // once turned these names blue under `.bordered` — so
                        // the one thing that must be certain here, cream on
                        // ink, would have been the system's decision rather
                        // than ours.
                        .buttonStyle(.plain)
                        .background(Color.primary, in: Capsule())
                        .elderTapTarget()
                    }
                }

                // An answer, not a refusal. It confirms nothing and un-confirms
                // nothing, and it is what stops the card coming back for ever —
                // which for this user matters more than the data does: a
                // question that returns every time she cannot answer it is the
                // app telling her so. §13 had to learn this the same way.
                Button {
                    answer(card, chose: nil)
                } label: {
                    Label("En muista", systemImage: "arrow.forward")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Elder.supporting)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .elderTapTarget()
                }
            } else {
                // The way on, and a button rather than a timer. The camera's
                // hint clears itself after two seconds because nothing depends
                // on its being read; this sentence is the whole answer to what
                // she just did, and a screen that moves on by itself while an
                // 80-year-old is still reading it has taken the answer away.
                // Filled like the four names above it, and for the same
                // measurement: a `.bordered` capsule has a 1.53:1 edge against
                // the parchment where 3:1 is asked of a control. It was the
                // only other button in the app wearing that shape.
                Button {
                    onDone()
                } label: {
                    Text("Jatka")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(Elder.cream)
                }
                .buttonStyle(.plain)
                .background(Color.primary, in: Capsule())
                .elderTapTarget()
            }

            Spacer(minLength: 0)
        }
    }

    /// Says the one true thing and stops.
    ///
    /// A name that matched is a person the archive now knows. Anything else
    /// leaves it open, and that is what the app says: it cannot call her wrong,
    /// because it does not know who is in the photograph either. Naming the
    /// proposal here would be the guess asserted as fact one screen after the
    /// entire point was not asserting it.
    private func answer(_ card: BlindConfirmation.Card, chose: Subject?) {
        let confirmed = BlindConfirmation.answer(card, chose: chose, in: store)
        afterward = confirmed
            ? "Kiitos. Nyt tiedämme, kuka hän on."
            : "Kiitos. Tämä jää toistaiseksi avoimeksi."
    }

    // MARK: - Telling

}

// MARK: - Result

private struct ResultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session
    let model: TellViewModel

    @State private var isConfirmingDiscard = false
    @State private var isMoving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if let body = model.result?.body {
                    MemoryCard(text: body, memory: model.savedMemory)
                }

                if !model.proposals.isEmpty {
                    proposalSection
                }

                if !model.known.isEmpty {
                    knownSection
                }

                if !model.newQuestions.isEmpty {
                    questionSection
                }

                // The offer slot: one card, on the rhythm, and never on a
                // screen that is also asking whether the names were heard
                // right (`UpsellRhythm`). The moment stays the one §8.6 argued
                // for — value peaks when a memory has just finished — but what
                // the slot holds depends on who is there to hear it: while the
                // family is one person the offer is the family itself, and the
                // paid archive follows once there is somebody to share it
                // with. See docs/UX.md §3.2.
                let card = UpsellRhythm.card(
                    membersInFamily: session.family?.members.count,
                    isPaid: session.isPaid
                )
                if UpsellRhythm.slotShows(
                    card: card, rhythm: model.showsUpsell,
                    proposalsRemaining: !model.proposals.isEmpty
                ) {
                    switch card {
                    case .invite:
                        InviteCard()
                    case .archive:
                        if let usage = session.usage, !usage.isPaid {
                            UpsellCard(usage: usage)
                        }
                    case nil:
                        EmptyView()
                    }
                }

                VStack(spacing: 12) {
                    // Prominent only when nothing above it already is.
                    //
                    // With follow-up questions on the screen the blue button is
                    // "Jatketaan jutellen" — carrying on about the memory she
                    // has just told is worth more than starting a second one,
                    // and it is the loop this app was built around (§10). With
                    // no questions there is nothing above to defer to, and
                    // telling another is the whole of what is left to do.
                    //
                    // Chosen rather than accumulated: see docs/ARCHITECTURE.md
                    // §22.
                    Button("Kerro toinen muisto") {
                        model.reset()
                    }
                    .elderPrimary(model.newQuestions.isEmpty)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .elderTapTarget()

                    // When telling about a photo the screen is presented
                    // modally, so there has to be a way back to the photo.
                    // `initialTarget`, not `target`: an interview moves the
                    // latter even in free dictation, and the tab screen must
                    // not grow a close button that closes nothing.
                    if model.initialTarget != nil {
                        Button("Valmis") { dismiss() }
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                            .elderTapTarget()
                    }

                    // Last and quietest on the screen. It is the rarest thing
                    // anybody does here, and the one that must never be hit by
                    // mistake — but before this there was no way at all to take
                    // back a telling, and "I did not mean to say that" is not a
                    // rare thought about one's own family.
                    Button("Poista tämä muisto") { isConfirmingDiscard = true }
                        .font(.body.weight(.medium))
                        .foregroundStyle(Elder.destructive)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
            }
            .padding(Elder.screenPadding)
        }
        .alert(
            "Poistetaanko tämä muisto?",
            isPresented: $isConfirmingDiscard
        ) {
            Button("Poista", role: .destructive) {
                model.discardSavedMemory()
                // Told about a photo or a person, this screen is a sheet on top
                // of that card, and there is nothing left here to return to.
                if model.initialTarget != nil { dismiss() }
            }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("Muisto poistuu perheen arkistosta äänityksineen, eikä sitä voi palauttaa.")
        }
        .sheet(isPresented: $isMoving) {
            if let placed = model.placedSubject {
                MoveMemorySheet(current: placed.id) { model.move(to: $0) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Muisto tallennettu", systemImage: "checkmark.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Elder.affirmative)

            if let placed = model.placedSubject {
                // The most important piece of the result: where the AI filed
                // the memory. Precisely the organising the user would never do
                // themselves.
                // Two branches rather than a ternary inside Text: a ternary of
                // two interpolated literals resolves to String, and Text(String)
                // is shown verbatim instead of being looked up. The sentence
                // stayed Finnish in the English build until this was split.
                Group {
                    if model.movedByHand {
                        Text("Muisto on nyt kohteessa **\(placed.displayTitle)**")
                    } else if model.target == nil {
                        Text("Sijoitin sen kohteeseen **\(placed.displayTitle)**")
                    } else {
                        Text("Lisäsin sen kohteeseen **\(placed.displayTitle)**")
                    }
                }
                .elderBody()
                .foregroundStyle(Elder.supporting)

                // The correction for the sentence above. The AI's placement
                // was the one thing on this screen nobody could correct
                // until 5 Sep 2026 (finding #27): grandfather's war years
                // filed under "Kesä Puumalassa" stayed there for good. Also
                // for a telling started from a card: the deck offered Aino
                // and grandmother talked about the cottage, and the card is
                // wrong the same way.
                if model.savedMemoryID != nil {
                    Button("Siirrä toiselle kortille") { isMoving = true }
                        .buttonStyle(.bordered)
                        .elderTapTarget()
                }
            }

            // Said out loud rather than left to be inferred. Without it a
            // memory that could not be organised looks exactly like one the AI
            // read and found nobody in: no names to check, no questions, no
            // reason given. The telling itself is safe, and that is the first
            // thing the sentence says.
            if !model.wasOrganised {
                Label(
                    "En saanut järjesteltyä sitä juuri nyt. Kertomasi on tallessa omilla sanoillasi.",
                    systemImage: "text.quote"
                )
                .elderBody()
                .foregroundStyle(Elder.supporting)
            }

            // The words arrived and the recording did not. Rule 3 broken, and
            // said — the row used to look like every other voice memory.
            if model.audioLost {
                Label(
                    "Äänitystä ei saatu talteen tälle puhelimelle. Kertomasi on tallessa tekstinä.",
                    systemImage: "waveform.slash"
                )
                .elderBody()
                .foregroundStyle(Elder.supporting)
            }
        }
    }

    /// Names the family already has, resolved by title alone — which is also
    /// how two Mattis become one card (finding #14). Shown so the teller can
    /// say "not that one" while she still knows which one she meant; the
    /// split name becomes a proposal above, where it can be told apart and
    /// confirmed. Quiet, below the names that need checking: the common case
    /// is that the familiar name is right.
    private var knownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tutut nimet")
                .font(.headline)

            Text("Perhe tuntee nämä jo. Jos joku niistä on eri henkilö kuin luulin, sano se nyt.")
                .font(.subheadline)
                .foregroundStyle(Elder.supporting)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(model.known) { subject in
                // A column, not a row: at the largest text size a name and a
                // button side by side is two truncations.
                VStack(alignment: .leading, spacing: 6) {
                    Text(subject.displayTitle)
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    // Two buttons rather than a ternary label: a ternary of
                    // literals is a String and is never looked up.
                    if subject.kind == .place {
                        Button("Eri paikka") { model.splitMention(subject) }
                            .buttonStyle(.bordered)
                            .elderTapTarget()
                            .accessibilityLabel("Eri paikka kuin \(subject.title)")
                    } else {
                        Button("Eri henkilö") { model.splitMention(subject) }
                            .buttonStyle(.bordered)
                            .elderTapTarget()
                            .accessibilityLabel("Eri henkilö kuin \(subject.title)")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .elderCard(radius: 16)
            }
        }
    }

    private var proposalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kuulinko nimet oikein?")
                .font(.headline)

            // Speech recognition gets roughly one proper noun in three wrong,
            // and this is the only moment when the teller still remembers what
            // they said.
            Text("Kirjoita nimi uudelleen jos kuulin väärin. Emme lisää sukuun ketään jota et ole hyväksynyt.")
                .font(.subheadline)
                .foregroundStyle(Elder.supporting)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(model.proposals) { subject in
                ProposalRow(
                    subject: subject,
                    text: Binding(
                        get: { model.editedNames[subject.id] ?? subject.title },
                        set: { model.editedNames[subject.id] = $0 }
                    ),
                    onConfirm: { model.confirm(subject) },
                    onReject: { model.reject(subject) }
                )
            }

            if !model.pendingCorrections.isEmpty {
                Button {
                    Task { await model.applyCorrections() }
                } label: {
                    if model.isCorrecting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        // Say that the correction reaches the memory text too —
                        // otherwise the user thinks they are only fixing the card.
                        Label("Korjaa nimet myös muistoon", systemImage: "checkmark.circle")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                // Bordered, not prominent. It confirms something already typed
                // into the row above it, which is not what this screen is for —
                // and it used to be one of four blue buttons down one scroll.
                // See docs/ARCHITECTURE.md §22.
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.isCorrecting)
                .elderTapTarget()
            }
        }
    }

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kysyisin vielä")
                .font(.headline)

            ForEach(model.newQuestions) { question in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.tint)
                        .font(.title3)
                    Text(question.text)
                        .elderBody()
                }
                .padding(.vertical, 4)
            }

            // One tap turns the questions into a spoken conversation: the app
            // asks aloud, listens, and asks again. See the interview loop in
            // TellViewModel.
            Button {
                Task { await model.beginInterview() }
            } label: {
                Label("Jatketaan jutellen", systemImage: "waveform.and.mic")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .elderTapTarget()
            .padding(.top, 4)

            Text("Kysyn nämä ääneen, ja voit vastata puhumalla.")
                .font(.subheadline)
                .foregroundStyle(Elder.supporting)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Says what is left, not what is missing.
///
/// Blocks nothing: the memory is already saved, and telling is never paywalled.
/// This is an invitation, not a wall.
private struct UpsellCard: View {
    let usage: EntitlementClient.Usage

    @State private var isShowingPaywall = false

    private var minutesLeft: Int? {
        usage.aiSeconds.remaining.map { $0 / 60 }
    }

    /// Without a RevenueCat key there is nothing to buy, so the card stays
    /// informational rather than growing a button that does nothing.
    private var canPurchase: Bool { RevenueCatPurchases.configuredKey != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ilmainen arkisto", systemImage: "sparkles")
                // The serif, like every other card title that names what the
                // card is about.
                .font(Elder.display(.title3))

            if let minutes = minutesLeft, let photos = usage.photos.remaining {
                Text("Kertomista tässä kuussa jäljellä noin \(minutes) minuuttia, ja kuville tilaa \(photos).")
                    .elderBody()
                    .foregroundStyle(Elder.supporting)
            }

            Text("Maksullisessa arkistossa rajoja ei ole, ja yksi maksaja avaa sen koko perheelle.")
                .elderBody()
                .foregroundStyle(Elder.supporting)

            if canPurchase {
                Button {
                    isShowingPaywall = true
                } label: {
                    Text("Avaa koko arkisto")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        // The same cream as every other card. It was a tinted panel, which
        // put a blue ground under a blue button and made the one offer on the
        // screen the loudest thing on a warm page. What marks it as an offer
        // is the prominent button inside it — ARCHITECTURE §22 gives a screen
        // exactly one — and not a second colour saying the same thing.
        .elderCard(radius: 18)
        .paywallSheet(isPresented: $isShowingPaywall)
    }
}

/// The other card the offer slot can hold: the family, while it is one person.
///
/// The invitation used to live only behind People → Asetukset → Perhe —
/// four levels from any tab — while this very screen told a family of one
/// that a single payer opens the archive *"koko perheelle"*. The moment a
/// memory finishes is when there is finally something worth inviting somebody
/// into, so the offer of the family sits exactly where the offer of the paid
/// archive otherwise does, on the same rhythm and under the same rules.
private struct InviteCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Perheen arkisto", systemImage: "person.2")
                // The serif, like every other card title that names what the
                // card is about.
                .font(Elder.display(.title3))

            Text("Tämä arkisto on vielä vain sinun. Kutsuttu perheenjäsen näkee muistot ja voi kertoa omansa.")
                .elderBody()
                .foregroundStyle(Elder.supporting)

            InviteShareButton()
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        // The same cream as every other card. It was a tinted panel, which
        // put a blue ground under a blue button and made the one offer on the
        // screen the loudest thing on a warm page. What marks it as an offer
        // is the prominent button inside it — ARCHITECTURE §22 gives a screen
        // exactly one — and not a second colour saying the same thing.
        .elderCard(radius: 18)
    }
}

private struct MemoryCard: View {
    let text: String
    /// Nil when the memory was typed — then there is no audio to listen to.
    let memory: Memory?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text)
                .elderBody()

            // The original audio is playable right next to the memory: it is not
            // a step on the way to text but part of the product.
            if let memory, memory.audioFilename != nil || memory.audioR2Key != nil {
                MemoryPlaybackButton(memory: memory)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        // A block and not a card: this is what the telling became, and the one
        // card on the screen worth a thickness.
        .elderBlock(radius: 20)
    }
}

private struct ProposalRow: View {
    let subject: Subject
    @Binding var text: String
    let onConfirm: () -> Void
    let onReject: () -> Void

    @State private var isConfirmingReject = false

    private var isEdited: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(subject.title, options: .caseInsensitive) != .orderedSame
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: subject.kind.symbolName)
                .font(.title2)
                .foregroundStyle(Elder.supporting)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                // A field rather than a label: correcting the name is the point
                // of this screen, so it has to be obvious without anything
                // needing to be tapped first.
                TextField("Nimi", text: $text)
                    .font(.body.weight(.medium))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    // The placeholder is not a name for this field: it is only
                    // drawn while the field is empty, and this one arrives with
                    // the heard name already in it — so VoiceOver had a text
                    // field with no label at all on the screen where a wrong
                    // name is caught.
                    .accessibilityLabel("Nimi")

                // kind.label is a runtime String — the Finnish IS the key, so
                // it has to be handed over as one to be looked up at all.
                Text(isEdited
                     ? LocalizedStringKey("\(subject.kind.label) · korjattu")
                     : LocalizedStringKey(subject.kind.label))
                    .font(.caption)
                    .foregroundStyle(isEdited ? Color.accentColor : Elder.supporting)
            }
            // The field takes the room, not a Spacer. With one beside it the
            // field sized itself to the name it happened to arrive with — 110
            // points, measured — and a longer one scrolled inside a box the
            // width of a short one. This is the field a wrong name is corrected
            // in; it should be the widest thing in the row.
            .frame(maxWidth: .infinity, alignment: .leading)

            // Asks first. The cross sits beside the tick, and the hand that
            // holds this phone shakes: a miss here tombstoned the real person
            // just named, on the spot, with no dialog and no way back — the
            // one destructive act in the app that did not ask, until 4 Sep
            // 2026. The text under it is not touched: the name stays in what
            // was told, and only the card goes.
            Button {
                isConfirmingReject = true
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Elder.supporting)
                    .elderTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Poista \(subject.title)")
            .alert(
                "Poistetaanko \(subject.title)?",
                isPresented: $isConfirmingReject
            ) {
                Button("Poista", role: .destructive, action: onReject)
                Button("Peruuta", role: .cancel) {}
            } message: {
                Text("Nimi poistuu perheen listalta. Kertomasi teksti ei muutu.")
            }

            Button(action: onConfirm) {
                Image(systemName: "checkmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Elder.affirmative)
                    .elderTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Vahvista \(subject.title)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        // The rows a person acts on. The slab makes them read as separate
        // things to press rather than as bands of one list — the film's
        // "blocks", which is what the user asked for by that name.
        .elderBlock(radius: 16)
    }
}

// MARK: - Audio saved, transcription pending

/// The quota was full or the network was down. This is not an error screen: the
/// user did nothing wrong and lost nothing.
private struct AudioSavedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session
    let model: TellViewModel

    @State private var isConfirmingDiscard = false
    @State private var isShowingPaywall = false

    var body: some View {
        // The same scroll treatment as IdleView and the refused microphone. As a
        // plain stack this screen was the one that had never been measured, and
        // at the largest text size it failed worst of anything seen: the title
        // clipped off the top, "Kirjoita se itse" truncated to one line, and
        // "Selvä" and "Poista tämä muisto" were below the bottom edge with no
        // way to reach them — on the screen that tells somebody their telling is
        // safe, in the state a dead cottage connection produces.
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(Elder.screenPadding)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .paywallSheet(isPresented: $isShowingPaywall)
        // The meter has just moved; every note that reads it should know.
        .task { if model.savedBecauseOfQuota { await session.refresh() } }
        .alert(
            "Poistetaanko tämä muisto?",
            isPresented: $isConfirmingDiscard
        ) {
            Button("Poista", role: .destructive) {
                model.discardSavedMemory()
                if model.initialTarget != nil { dismiss() }
            }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("Äänitys poistuu eikä sitä voi palauttaa.")
        }
    }

    private var content: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            // The one case this screen must not open on its usual sentence:
            // the recording could not be kept (`TellViewModel.audioLost`).
            // Two titles rather than a ternary — a ternary of literals is a
            // String and is never looked up.
            Image(systemName: model.audioLost ? "exclamationmark.triangle" : "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(model.audioLost ? Elder.proposal : Color.accentColor)
                // Decoration: the title beside it says the same thing in words.
                // Left visible, VoiceOver reads out the symbol's own name — the
                // defect the onboarding mark and the member rows had already.
                .accessibilityHidden(true)

            Group {
                if model.audioLost {
                    Text("Nauhoitusta ei saatu talteen")
                } else {
                    Text("Äänesi on tallessa")
                }
            }
            .font(.title.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            // Three truths for one screen: a mode where no text is ever
            // coming, the month's minutes, and a deferral the catch-up will
            // finish. Promising "valmistuu myöhemmin" in the first would be
            // the §16 lie all over again; in the second it was a delay's
            // words on a wall that lifts on a date, or when somebody pays —
            // so the date is said, and the way to lift it is beside it.
            // Three `Text`s and not a ternary: a ternary of literals is a
            // String, and neither of the two here had ever been looked up.
            Group {
                if model.audioLost {
                    Text("Puhelin ei saanut äänitystä talteen. Vapauta tilaa puhelimesta ja kerro uudelleen, tai kirjoita muisto itse nyt, kun se on vielä mielessä.")
                } else if !model.canTranscribe {
                    Text("Kun arkisto on vain tällä puhelimella, puhetta ei muuteta tekstiksi. Äänesi säilyy — voit kirjoittaa muiston itse.")
                } else if model.savedBecauseOfQuota {
                    let date = Session.nextFreeMinutes().formatted(.dateTime.day().month(.wide))
                    Text("Kuukauden ilmainen kertominen on täynnä, joten tekstiä ei kirjoitettu nyt. Se kirjoitetaan, kun kertomista on taas \(date) — tai heti, jos perhe avaa koko arkiston. Voit myös kirjoittaa muiston itse.")
                } else {
                    Text("Emme ehtineet kirjoittaa sitä tekstiksi juuri nyt, mutta kertomasi ei katoa. Teksti valmistuu myöhemmin — voit myös kirjoittaa muiston itse.")
                }
            }
            .elderBody()
            .foregroundStyle(Elder.supporting)
            .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                // The text lands in the memory whose audio is already saved,
                // rather than beside it. What she just told is one telling, and
                // the archive must not hold it as a silent recording next to a
                // voice-less text.
                Button {
                    model.beginWriting(completing: model.savedMemoryID)
                } label: {
                    // fixedSize on every label here, as on the idle screen:
                    // under vertical pressure SwiftUI truncates a Text before it
                    // shrinks anything else, and this one was measured doing it.
                    Text("Kirjoita se itse")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                // The handle on the wall, when there is one: the same
                // purchase the family screen and the finished-memory card
                // offer, here beside the one moment it is the answer to.
                // Quiet, below the prominent one — §22 allows one of those.
                if model.savedBecauseOfQuota, !session.isPaid,
                   RevenueCatPurchases.configuredKey != nil {
                    Button {
                        isShowingPaywall = true
                    } label: {
                        Text("Avaa koko arkisto")
                            .font(.body.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .elderTapTarget()
                    }
                    .controlSize(.large)
                }

                Button {
                    if model.target == nil { model.reset() } else { dismiss() }
                } label: {
                    // Two labels rather than a ternary: a ternary of literals
                    // is a String, and "Selvä" was never looked up here.
                    Group {
                        if model.target == nil {
                            Text("Selvä")
                        } else {
                            Text("Valmis")
                        }
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .elderTapTarget()
                }
                .controlSize(.large)

                // The same way out as on the result screen. A telling somebody
                // did not mean to keep is not any more meant once the quota
                // happened to interrupt it — and here the memory is a recording
                // with no text, which is the hardest kind to find and remove
                // afterwards. Not when nothing was saved: there is no memory
                // to remove, and the button would promise one.
                if !model.audioLost {
                Button {
                    isConfirmingDiscard = true
                } label: {
                    Text("Poista tämä muisto")
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
                .foregroundStyle(Elder.destructive)
                .controlSize(.large)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - The microphone was refused

/// The one failure the app cannot fix, and it used to be handed a retry button.
///
/// "Salli mikrofoni asetuksista" is an instruction, and the person it is written
/// for is the least likely of anybody to be able to follow it: four taps into an
/// iOS settings tree, in a list of apps, under a switch. So the screen opens the
/// place itself — and offers the keyboard, which needs no permission from
/// anybody. Telling is never blocked (rule 2); a refused microphone must not
/// become the thing that blocks it.
private struct MicrophoneDeniedView: View {
    @Environment(\.openURL) private var openURL
    let model: TellViewModel

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(Elder.screenPadding)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var content: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            Image(systemName: "mic.slash")
                .font(.system(size: 56))
                .foregroundStyle(Elder.supporting)
                .accessibilityHidden(true)

            Text("Mikrofoni ei ole käytössä")
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Puhuminen tarvitsee luvan mikrofoniin. Voit antaa sen puhelimen asetuksista — tai kirjoittaa muiston nyt.")
                .elderBody()
                .foregroundStyle(Elder.supporting)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                } label: {
                    Text("Avaa asetukset")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                // Not a consolation prize: a written memory goes through the
                // same extraction and ends up the same kind of memory.
                Button {
                    model.beginWriting()
                } label: {
                    Label("Kirjoita sen sijaan", systemImage: "keyboard")
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

// MARK: - Failure

private struct FailureView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        // The same scroll treatment as the audio-saved screen, and for the same
        // reason: a plain stack clips from both ends at the largest text size,
        // and this one holds a message whose length nobody controls here.
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(Elder.screenPadding)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var content: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundStyle(Elder.proposal)
                // Decoration: the message is the content.
                .accessibilityHidden(true)
            Text(message)
                .elderBody()
                .multilineTextAlignment(.center)
            Button("Yritä uudelleen", action: onRetry)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .elderTapTarget()
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Record button

/// The app's most important control. It has to be findable without reading, so
/// it is large, round and always in the same place.
private struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Elder.wax.gradient)
                    .shadow(
                        color: Elder.wax.opacity(isRecording ? 0.5 : 0.25),
                        radius: isRecording ? 28 : 14
                    )

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: isRecording ? 60 : 72))
                    // Cream on wax measures 5.59:1, where white on the system
                    // red measured ~3.55:1. The glyph clears the *text*
                    // minimum now and not merely the 3:1 a graphic is judged
                    // by — and it is still a mic and still a stop, which is
                    // what actually carries the state.
                    .foregroundStyle(Elder.cream)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: Elder.recordButtonSize, height: Elder.recordButtonSize)
            .scaleEffect(pulse ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Lopeta kertominen" : "Aloita kertominen")
        .accessibilityHint(isRecording ? "Tallentaa muiston" : "Nauhoittaa puheesi ja tallentaa sen muistoksi")
        .onAppear { pulse = isRecording }
        .onChange(of: isRecording) { _, recording in
            guard recording else {
                pulse = false
                return
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

#Preview {
    TellScreen()
        .environment(MemoryStore(filename: "preview-store.json"))
}
