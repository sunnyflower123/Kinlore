import SwiftUI
import UIKit

/// The app's most important screen. One button, no menus, and no settings
/// but the gear (`SettingsGear`), on a reader's phone only (`showsSettings`).
struct TellScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session

    /// When the screen is opened from a photo or a person, the memory attaches
    /// to it. Nil = free dictation, in which case the subject is inferred from
    /// the speech.
    var target: Subject?
    /// When the screen is opened from an open question, the question is the
    /// screen's title and is marked answered on save.
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
    /// Set by the colour sheet (`ColourSheet`), and called once a telling has
    /// been saved with its words, in place of the result screen: the sheet
    /// swaps this screen for the colouring, which reads that telling first.
    var onTold: (() -> Void)?
    /// The colour sheet's second way: colour from what was told before,
    /// without telling more. Nil when nothing has been told yet.
    var onColourFromTold: (() -> Void)?

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

    @AppStorage(Elder.largerTextKey) private var largerText = false

    /// The gear (`SettingsGear`, since 30 Sep 2026), on the tab's idle
    /// screen, which is its root, and on a reader's phone. Not on a
    /// grandparent's, where this tab is the button and nothing else
    /// (`blindCard`): she reaches Settings from Ihmiset. Not in the
    /// other phases either, which are a telling under way or what came of it.
    /// The navigation bar comes and goes with the gear, so no other phase of
    /// the tab is drawn under an empty one.
    ///
    /// True before the model exists, so that the bar is already in place when
    /// the idle screen first lays out: `IdleView` measures its room once.
    private var showsSettings: Bool {
        guard usesDeck, !largerText else { return false }
        return model.map { $0.phase == .idle } ?? true
    }

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
            if showsSettings {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsGear()
                }
            }
        }
        .toolbar(usesDeck && !showsSettings ? .hidden : .automatic, for: .navigationBar)
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
                canTranscribe: !session.isLocalByChoice,
                endsWithTheTelling: onTold != nil
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
                    // The film's English under `-sample film`, otherwise the
                    // phone's language; see `StubTranscriptionService.filmMemory`.
                    created.draft = UserDefaults.standard.string(forKey: "sample") == "film"
                        ? StubTranscriptionService.filmMemory
                        : StubTranscriptionService.inPhoneLanguage[2]
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
                    // The film's English under `-sample film`, otherwise the
                    // phone's language; see `StubTranscriptionService.filmMemory`.
                    created.draft = UserDefaults.standard.string(forKey: "sample") == "film"
                        ? StubTranscriptionService.filmMemory
                        : StubTranscriptionService.inPhoneLanguage[2]
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
                    // Under `-sample film`, for the README's pictures, the
                    // film's own telling rather than the interview's opening,
                    // because the film's extraction names Puumala, Helmi and
                    // Toivo whatever it is given, and this is the one telling
                    // that says them. Otherwise the phone's language.
                    created.draft = UserDefaults.standard.string(forKey: "sample") == "film"
                        ? StubTranscriptionService.film
                        : StubTranscriptionService.inPhoneLanguage[0]
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
                    onSkip: usesDeck ? { skipCard(model) } : nil,
                    onColourFromTold: onColourFromTold
                )
                .onAppear { advancePastTold(model) }
            case .recording:
                RecordingView(model: model)
            case .writing:
                WritingView(model: model)
            case .transcribing, .organizing:
                ProcessingView(phase: model.phase, voiceIsKept: model.recordingIsKept)
            case .asking:
                AskingView(model: model)
            case .done:
                if onTold == nil {
                    ResultView(model: model, onClose: onClose)
                } else {
                    // The frame before the colour sheet takes over.
                    ProgressView()
                }
            case .savedWithoutTranscript:
                AudioSavedView(model: model, onClose: onClose)
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
        .modifier(NoPaperWithoutTheTabBar(barHidden: hidesTabBar(model.phase)))
        // A telling saved with its words, on the colour sheet. A recording
        // kept without them lands on its own screen instead, and colours
        // nothing: what was just said is not there to be read first.
        .onChange(of: model.phase) { _, phase in
            if phase == .done { onTold?() }
        }
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
    ///
    /// **The telling's own follow-up questions do not outrank it.** Until
    /// 12 Sep 2026 the guard counted every open question, and the extraction
    /// makes two or three from each telling — so the first card told about
    /// took the deck off the screen until its follow-ups were answered, and a
    /// pack meant to go from photograph to photograph stopped at one. Nothing
    /// failed: the blank button with questions under it is a screen this app
    /// has. The follow-ups lose this one screen and nothing else — the
    /// interview loop asks them the moment a spoken telling ends (since
    /// 26 Sep 2026; a written one lists them on its result, one tap from the
    /// same loop), the Tell screen opened from that photograph offers them
    /// again, and the idle screen returns to them once the deck has nothing
    /// left to offer.
    private var deckCard: Subject? {
        guard usesDeck,
              store.openQuestions(
                  limit: 1, excludingAuthor: session.identity.memberID,
                  onlyAuthored: true, viewer: session.identity.memberID
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
                  limit: 1, excludingAuthor: session.identity.memberID,
                  onlyAuthored: true, viewer: session.identity.memberID
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

/// RootView's paper under the tab bar (`PaperUnderTheTabBar`) is there for
/// the bar, and it does not leave with it: in the phases that hide the bar the
/// hard edge still laid its band over the bottom of the page. Measured
/// 27 Sep 2026 at the largest size: on an SE the last line of "Paina kun olet
/// valmis" went under it while the recording ran, and on a 17 Pro it covered
/// "Älä tallenna tätä" to 1.09:1, which failed the audit. Those phases get
/// the edge iOS draws by itself, and every other phase keeps whatever the tab
/// above chose, because `nil` sets nothing.
private struct NoPaperWithoutTheTabBar: ViewModifier {
    let barHidden: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectStyle(barHidden ? .automatic : nil, for: .bottom)
        } else {
            content
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
    /// The colour sheet's second way (`TellScreen.onColourFromTold`). Never on
    /// the same screen as `onSkip`: the deck has no colour sheet.
    var onColourFromTold: (() -> Void)?

    @State private var answering: FollowUpQuestion?
    /// What to say once she has answered, and the only state this card keeps.
    /// Nil while the question is still on screen.

    /// The steps this screen has taken to fit above the tab bar at each text
    /// size, and what it measured to decide them. See `Squeeze`, which is
    /// where all of it lives.
    @State private var steps: [DynamicTypeSize: Set<Squeeze>] = [:]
    @State private var ceilings: [DynamicTypeSize: CGFloat] = [:]
    @State private var room: CGFloat?
    @State private var lastWayOn: Edge?
    @State private var recordButton: Edge?
    @State private var photoDrawn: CGFloat?

    private var squeeze: Set<Squeeze> { steps[typeSize] ?? [] }
    private var photoCeiling: CGFloat? { ceilings[typeSize] }

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
    /// the reassurance does — "Kuka tässä kuvassa on?" is the permission. And
    /// on a phone too small for the long one, which is `Squeeze.shortReassurance`.
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
    private func intro(short: Bool) -> LocalizedStringKey {
        if AudioRecorder.isPermissionUnasked {
            // Shortened by the same rule as the reassurance below, and it was
            // measured the hard way: the two-line version at the *ordinary* text
            // size put "Kirjoita sen sijaan" underneath the floating tab bar —
            // the one way on from this screen that needs no permission at all,
            // hidden by the sentence about permission. On a first launch the
            // starters are always there, so the short one is what ships; the
            // long one is for somebody who joined a family that has already been
            // told about.
            return typeSize.isAccessibilitySize || short
                ? "Puhelin kysyy ensin luvan mikrofoniin."
                : "Puhelin kysyy ensin luvan mikrofoniin. Anna lupa, niin voit puhua."
        }
        return typeSize.isAccessibilitySize || short
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
    ///
    /// **Only questions a person asked, since 12 Sep 2026.** The extraction's
    /// follow-ups stood here too, under *"Tai vastaa aiempaan kysymykseen"*,
    /// and after one telling that was three questions the app had thought of
    /// by itself on the screen somebody opens cold. They keep every other
    /// place they are offered — the interview loop asks them the moment a
    /// spoken telling ends (since 26 Sep 2026; a written one lists them on its
    /// result, one tap from the same loop), and the Tell screen opened from
    /// their subject lists them below — and this screen carries a family
    /// member's question alone.
    ///
    /// On an install somebody is trying the app out on, the example stands
    /// where the opening starters would, and the list is empty
    /// (`offersExample`). A family member's question still comes first.
    private var offer: (questions: [FollowUpQuestion], isStarter: Bool) {
        guard let target = model.target else {
            let open = store.openQuestions(
                limit: 2, excludingAuthor: session.identity.memberID, onlyAuthored: true,
                viewer: session.identity.memberID
            )
            guard open.isEmpty else { return (open, false) }
            return (offersExample ? [] : store.openingQuestions(), true)
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

    /// Colouring from what the family has already told, for somebody who has
    /// nothing to add. Quiet like the rows beside it: the question above is
    /// what the screen asks.
    private func colourButton(_ onColour: @escaping () -> Void) -> some View {
        Button(action: onColour) {
            Label("Väritä jo kerrotun mukaan", systemImage: "paintpalette")
                .font(.body.weight(.medium))
                .foregroundStyle(Elder.supporting)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .elderTapTarget()
        }
    }

    /// Whether the example sentence (`TryIt`) is offered: on an install
    /// somebody is trying the app out on, in free dictation, before anything
    /// has been told — the moment the opening starters are for, which it
    /// replaces (`offer`). Drawn only where no family member's question is
    /// offered either, which the stack checks.
    private var offersExample: Bool {
        TryIt.isOn && model.target == nil && model.openedQuestion == nil && store.told.isEmpty
    }

    /// The example: what it is and what to do with it, the sentence in the
    /// bubble that holds what somebody said, and a way to have it typed.
    ///
    /// Read aloud, it goes through the same press as any telling, and the
    /// sentence stays on the listening screen while it is read, because the
    /// press takes this screen away (`RecordingView`). Typed, it only fills
    /// the field: *"Tallenna"* is still pressed by whoever is trying it, as
    /// for anything they write, so nothing is sent that they did not send.
    ///
    /// Compact is the squeeze's `card` step: the bubble's padding and the
    /// gaps, never the words or the button's 60 points.
    private func exampleCard(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 10) {
            Text("Esimerkki: paina mikrofonia ja lue tämä ääneen.")
                .font(.subheadline)
                .foregroundStyle(Elder.supporting)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Ink on honey and nothing else on it, as `elderBubble` asks: the
            // instruction above stays on the paper, where `supporting` was
            // measured.
            Text(TryIt.sentence)
                .elderBody()
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, compact ? 8 : 14)
                .elderBubble()

            Button {
                model.beginWriting()
                model.draft = TryIt.sentence
            } label: {
                Label("Kirjoita se puolestani", systemImage: "text.cursor")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.elderSecondary)
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
        // Opened from a question — its row on a subject's card, or an offer
        // on the Kerro tab about another subject — the screen is that
        // question's, card or not: its title, and what the big button answers
        // (26 Sep 2026). Until then the title asked for any telling at all,
        // and the question stood in the list below the button, beside others.
        if let opened = model.openedQuestion { return opened }
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
        //
        // Scrolling is also how a small phone hid the ways on under the tab
        // bar without anything saying so, which is what `Squeeze` answers.
        // The room it measures is the page's, from here.
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(.horizontal, Elder.screenPadding)
                    .padding(.bottom, Elder.screenPadding)
                    .padding(.top, squeeze.contains(.air) ? 12 : Elder.screenPadding)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    .coordinateSpace(.named(Self.page))
                    .onGeometryChange(for: CGRect?.self) { $0.bounds(of: .scrollView) } action: { visible in
                        guard room == nil, let visible, visible.height > 0 else { return }
                        room = visible.maxY
                        giveWayIfNeeded()
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .sheet(item: $answering) { question in
            CardOpeningStack {
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
        // 14, and the number is English's rather than Finnish's. This screen is
        // taller than the phone in every language — 778 pt of content against a
        // 729 pt viewport in Finnish, measured 19 Sep 2026 — and what saved it
        // there was the band the floating tab bar sits in: "Kirjoita sen sijaan"
        // ended at 788 pt, just above the bar's top edge at 793. English says
        // the same things in two more lines, because the title wraps and so does
        // the sentence about the microphone, and those 67 pt put the row at
        // 795 pt: drawn, tappable by nobody, entirely behind the tab bar on the
        // very first launch — the one launch where the way past the microphone
        // matters most, and the one place a screenshot of the Finnish build
        // could never show it.
        //
        // Air is what this stack has to give. Eight gaps at 28 were 224 pt; at
        // 14 the row sits at 697 pt in English and 672 in Finnish, both clear of
        // the bar with a line of text to spare. A screen with room loses nothing
        // by the squeeze — the three Spacers below take back exactly what the
        // gaps give up, which is why the Finnish screen still reads as open.
        //
        // On a phone smaller than that, 8 and two Spacers fewer: `Squeeze.air`.
        VStack(spacing: gap) {
            // Resolved once: what is offered at the bottom decides how long the
            // reassurance at the top can afford to be.
            let offered = offer
            let showsExample = offersExample && offered.questions.isEmpty
            // The steps each edge below is measured under, and the text size,
            // so that a measurement taken before a step, or at another size,
            // is never read as one taken now.
            let squeezed = squeeze
            let size = typeSize

            if !squeezed.contains(.air) {
                Spacer(minLength: 0)
            }

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
                    // created. On a small phone it gives way further, to what
                    // the rows below leave it: `Squeeze.card`.
                    .frame(maxHeight: photoCeiling ?? (typeSize.isAccessibilitySize ? 150 : 200))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    // A tap opens it to the whole screen: 200 points is
                    // enough to know the picture by and not the faces in it,
                    // and the question under it is often who they are.
                    //
                    // A scanned photograph has no description and the app must
                    // not invent one — guessing at the content is precisely
                    // what rule 4 forbids. What is said is what is known.
                    .opensToTheWholeScreen(photo, label: String(localized: "Valokuva, josta ei ole vielä kerrottu"))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        photoDrawn = height
                    }
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
            // The display weight, and this is the one line on the screen that
            // gets it: the question is what the screen is about, and
            // everything else here — the reassurance, the starter, the
            // counter — stays at the weight an 80-year-old reads at arm's
            // length.
            .font(Elder.display(.largeTitle))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            // For the tests that ask what the title says: a question's words
            // are also on the card this screen is a sheet over.
            .accessibilityIdentifier("tell.title")

            // Dropped when there is a card. The reassurance exists to make a
            // blank button approachable — *"Puhu ihan rauhassa ja vapaasti"* is
            // the sentence that makes somebody willing to start — and a
            // photograph is not a blank button. It is also the cheapest 60 pt
            // on a screen that has just grown a picture: with it, the starter
            // question was below the fold, and the starter is what makes the
            // card answerable at all.
            if deckPhoto == nil, !squeezed.contains(.reassuranceBelow) {
                reassurance(offered)
            }

            if !squeezed.contains(.air) {
                Spacer(minLength: 0)
            }

            // No glow and no rings once the air is taken. The spacer over the
            // button kept the glow 28 from the text above it without being
            // asked — two gaps of 14 even at no height — and `Squeeze.air`
            // takes that to 8, which on the SE put "Puhu ihan rauhassa ja
            // vapaasti." inside it: the text measures 9.54:1 from the pixels,
            // and the audit failed it anyway, on a first launch and under a
            // family member's question at the default size, alone on a quiet
            // machine (27 Sep 2026). Giving the 28 back instead cost 20 pt
            // the SE does not have: under a family member's question on a
            // grandparent's phone in English, "Write instead" would have
            // ended at 594, under the bar.
            RecordButton(isRecording: false, glows: !squeezed.contains(.air)) {
                Task {
                    if let cardQuestion {
                        await model.answer(cardQuestion)
                    } else {
                        await model.startRecording(reading: showsExample ? TryIt.sentence : nil)
                    }
                }
            }
            .onGeometryChange(for: Edge.self) { proxy in
                Edge(maxY: proxy.frame(in: .named(Self.page)).maxY, squeeze: squeezed, size: size)
            } action: { edge in
                recordButton = edge
                giveWayIfNeeded()
            }

            // fixedSize on every label below: under vertical pressure SwiftUI
            // truncates a Text before it shrinks anything else, and a truncated
            // instruction is worse than a longer screen.
            Text("Paina ja ala puhua")
                .font(.headline)
                .foregroundStyle(Elder.supporting)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                // The one gap the squeeze above is not allowed to take, and the
                // audit is what said so: the button's glow is a red shadow at
                // radius 14, it reaches some 28 pt past the disc, and this line
                // is measured against whatever is behind it. At the stack's new
                // 14 pt all five Kerro sweeps went red at the default text size
                // with "Contrast failed — Paina ja ala puhua" (19 Sep 2026).
                // 14 here puts the caption back where 28 had it — and so does
                // 20 when a small phone takes the stack to 8.
                .padding(.top, 28 - gap)

            // Where the reassurance goes when an accessibility size leaves the
            // record button no room under it: read after the instruction, as
            // its second half, rather than dropped (`Squeeze.reassuranceBelow`).
            if deckPhoto == nil, squeezed.contains(.reassuranceBelow) {
                reassurance(offered)
            }

            // An open question is a reason to come back to the app. It is also
            // an easier start than a blank button: telling "something" is hard
            // for an elderly person, answering a question is easy.
            // Not on a card: the question is the title there, and repeating it
            // in a box below the button is the same ask twice on the screen
            // that can least afford the height.
            if !offered.questions.isEmpty, cardQuestion == nil {
                VStack(spacing: 10) {
                    // The one line here a small phone gives up, with the cards'
                    // padding. It is an instruction about the cards rather
                    // than one of them: *"Mummo kysyy"* already says whose
                    // question a family's card is, and a starter reads as a
                    // question to answer without being introduced as one.
                    if !squeezed.contains(.card) {
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
                    }

                    // One with a card, two without. The card is one question
                    // at a time by design; a second below a photograph is a
                    // choice to make before answering, and choosing is work.
                    // One starter, too, on a phone too small for two
                    // (`Squeeze.oneStarter`) — never one of the family's.
                    let one = deckPhoto != nil || (offered.isStarter && squeezed.contains(.oneStarter))
                    ForEach(one ? Array(offered.questions.prefix(1)) : offered.questions) { question in
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
                                        // Asked of this phone's member by
                                        // name, which is a stronger pull still.
                                        Group {
                                            if question.targetMemberID == session.identity.memberID {
                                                Text("\(asker) kysyy sinulta")
                                            } else {
                                                Text("\(asker) kysyy")
                                            }
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tint)
                                    }
                                    Text(question.text)
                                        .elderBody()
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, squeezed.contains(.card) ? 8 : 14)
                            // A one-line starter is 48 points at 14 and would
                            // be 36 at 8, so the squeeze stops at 44: the
                            // floor it keeps for anything tapped.
                            .frame(minHeight: squeezed.contains(.card) ? 44 : nil)
                            .elderCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, squeezed.contains(.air) ? 0 : 4)
            }

            // Where the starters would be, and on the same terms: under the
            // button it is read with, above the quiet rows.
            if showsExample {
                exampleCard(compact: squeezed.contains(.card))
                    .padding(.top, squeezed.contains(.air) ? 0 : 4)
            }

            waysOn
                .onGeometryChange(for: Edge.self) { proxy in
                    Edge(maxY: proxy.frame(in: .named(Self.page)).maxY, squeeze: squeezed, size: size)
                } action: { edge in
                    lastWayOn = edge
                    giveWayIfNeeded()
                }

            Spacer(minLength: 0)
        }
    }

    /// The reassurance, in whichever of its two places the screen has room for.
    private func reassurance(_ offered: (questions: [FollowUpQuestion], isStarter: Bool)) -> some View {
        Text(intro(short: offered.isStarter || squeeze.contains(.shortReassurance)))
            .elderBody()
            .foregroundStyle(Elder.supporting)
            .multilineTextAlignment(.center)
    }

    /// The two quiet rows, as one block so that the last of them can be
    /// measured — three on the colour sheet, whose second way is the last.
    ///
    /// Side by side with the way past a card, and only there. A card makes
    /// this screen taller than any state it has had, and stacked these two put
    /// the second one under the tab bar — a way past a photograph she cannot
    /// place, reachable only by scrolling, which for this user is not
    /// reachable. At accessibility sizes they stack again: two labels cannot
    /// share a line there, and the screen is taller than the phone on purpose
    /// by then.
    @ViewBuilder
    private var waysOn: some View {
        if let onSkip, model.target != nil, !typeSize.isAccessibilitySize {
            HStack(spacing: 10) {
                writingButton
                skipButton(onSkip)
            }
        } else {
            VStack(spacing: gap) {
                writingButton
                if let onSkip, model.target != nil {
                    skipButton(onSkip)
                }
                if let onColourFromTold {
                    colourButton(onColourFromTold)
                }
            }
        }
    }

    // MARK: - Giving way on a small phone

    /// The steps this screen takes to fit above the tab bar, and the order it
    /// takes them in — the part of this screen worth keeping through any
    /// redesign of it.
    ///
    /// The screen scrolls when its content is taller than the phone, and at
    /// rest nothing on it says so. Measured in Finnish on 26 and 27 Sep 2026
    /// on an iPhone SE, whose tab bar begins at 584: under a photograph's
    /// card the two quiet rows ended at 704 on a reader's phone and 711 on a
    /// grandparent's, where the disc itself reached 586; with a family
    /// member's question, "Kirjoita sen sijaan" ended at 677 and 727 and the
    /// question card at 603 and 653; and on a first launch it ended at 663
    /// and 680, and in English at 704 and 723. On a 13 mini, whose bar begins
    /// at 729, the rows under a card reached 5 and 12 points into it, the
    /// question's 28 and the first launch's in English 4 and 24, and at the
    /// largest size in English the disc 12. The accessibility audit saw none
    /// of it, because the tree keeps an element's whole frame when the bar is
    /// drawn over it — and none of it is one swipe away for the person this
    /// screen is built for: she does not scroll a screen with one big button
    /// on it, so a way on under the bar is a way on she does not have.
    /// `DeckTests.testEveryWayOnClearsTheTabBarAtRest` is what holds this.
    ///
    /// So the screen measures, at rest, where its last way on ends against
    /// where the bar begins, and when it ends under the bar it takes the next
    /// step below, and the next, until 8 points of daylight are left: one step
    /// per layout, each measured before the next is taken, and never back, so
    /// that nothing rearranges under her thumb once she can see it. At
    /// accessibility sizes the page is taller than any phone on purpose and
    /// scrolls, as it always has; there the record button is what has to
    /// clear the bar, and the rest is below. A phone with room never takes the
    /// first step, and looks as it did.
    ///
    /// The order is the decision. Air first, because nobody reads it. Then the
    /// reassurance's detail, whose short form keeps the permission it gives.
    /// Then the card, which is what this layout was built to let give way.
    /// Then, on a first launch, the second of the two starters: one is still
    /// the rung the ladder needs, and of every screen measured on the SE, the
    /// 13 mini and the 17 Pro, only the SE's first launch in English — where
    /// the title takes two lines — gets this far. Never the record button, the
    /// family's question or either quiet row: they are the ways on, and the
    /// whole point is that they stay. Text keeps its Dynamic Type size
    /// throughout, the quiet rows their 60 points, and a question card never
    /// goes under 44.
    ///
    /// Measured, and not proposed, for the reason `BlindCardView.photoMax`
    /// records: a height handed to `ViewThatFits` turned the audit red in
    /// places where no height was being proposed at all.
    ///
    /// The screen keeps the steps it took as a set rather than a level. A step
    /// that would change nothing here is passed over, and as a level it would
    /// have come back with the next one taken: at the largest text size the
    /// question cards' heading, which is under the record button and was never
    /// the problem, went with the reassurance's move.
    ///
    /// And one set per text size, because the size can change under a running
    /// screen: the accessibility audit's Dynamic Type check scales the text up
    /// and back while it audits. One set for every size kept what an
    /// accessibility size had taken, and the SE's default-size screen came
    /// back from the audit with its reassurance under "Paina ja ala puhua"; a
    /// set emptied at every change stepped again from nothing while the audit
    /// was still reading the screen. Both turned the Kerro sweeps on the SE red
    /// with contrast findings `main` does not have (27 Sep 2026). A size
    /// already measured comes back as it was, in the same frame as the size.
    private enum Squeeze: Int, CaseIterable, Comparable {
        /// The two empty spacers, the stack's gaps 14 → 8 with the caption
        /// kept 28 from the disc, the questions' extra 4, the top margin
        /// 24 → 12, and the disc's resting glow and rings, which the 8 over
        /// it would otherwise put behind the text there.
        case air
        /// The reassurance's short form, which accessibility sizes and starter
        /// questions already get.
        case shortReassurance
        /// The photograph down to what the rows leave it, never under 100 —
        /// the floor `BlindCardView` chose, below which a face stops being
        /// something to recognise — or the question cards' padding 14 → 8,
        /// never under 44, without the heading above them. On an install
        /// somebody is trying out, the example's bubble 14 → 8 and its gaps
        /// 10 → 6, with every word of it and its button kept.
        case card
        /// One starter question instead of two. Starters only: a family
        /// member's question is a way on, and stays.
        case oneStarter
        /// Accessibility sizes only: the reassurance moves under "Paina ja ala
        /// puhua", which it reads as the second half of, rather than leaving
        /// the screen.
        case reassuranceBelow

        static func < (a: Squeeze, b: Squeeze) -> Bool { a.rawValue < b.rawValue }
    }

    /// Where a measured row ends, in the page's coordinates, and the steps and
    /// the text size it was laid out under.
    private struct Edge: Equatable {
        var maxY: CGFloat
        var squeeze: Set<Squeeze>
        var size: DynamicTypeSize
    }

    private static let page = "IdleView.page"

    private var gap: CGFloat { squeeze.contains(.air) ? 8 : 14 }

    /// The next step, when the row that has to clear the bar does not — and
    /// only when it was measured as the screen is now: under the steps taken,
    /// at this text size.
    ///
    /// What starts it is a way on under the bar; what it gives way to, once
    /// started, is 8 points of daylight above it. A screen that fits is left
    /// as it is drawn even with less: on the 17 Pro, in English, under a
    /// family member's question on a grandparent's phone, "Write instead" ends
    /// 7 points above the bar, and with the daylight as the trigger that
    /// screen took a step and moved the row 68 points up, for a row nobody
    /// had lost.
    private func giveWayIfNeeded() {
        guard blind == nil, let room,
              let edge = typeSize.isAccessibilitySize ? recordButton : lastWayOn,
              edge.size == typeSize, edge.squeeze == squeeze
        else { return }
        let under = edge.maxY - room
        let deficit = under + 8
        guard squeeze.isEmpty ? under > 0 : deficit > 0,
              let next = Squeeze.allCases.first(where: { step in
                  squeeze.allSatisfy { $0 < step } && takes(step)
              })
        else { return }
        if next == .card, let photoDrawn {
            ceilings[typeSize] = max(100, photoDrawn - deficit)
        }
        steps[typeSize, default: []].insert(next)
    }

    /// Whether a step changes anything on this screen as it stands. One that
    /// does not is passed over, because a layout it does not change is never
    /// measured again and the screen would wait on it for ever.
    private func takes(_ step: Squeeze) -> Bool {
        let accessibility = typeSize.isAccessibilitySize
        let reassured = deckPhoto == nil
        switch step {
        case .air: return true
        case .shortReassurance: return reassured && !accessibility && !offer.isStarter
        case .card:
            if deckPhoto != nil { return (photoDrawn ?? 0) > 100 }
            // The cards are under the button, which is all an accessibility
            // size asks to clear. And they are drawn only where the stack
            // draws them, which is the condition repeated here — the example
            // where the questions would be.
            let offered = offer
            if offersExample && offered.questions.isEmpty { return !accessibility }
            return !offered.questions.isEmpty && cardQuestion == nil && !accessibility
        case .oneStarter:
            let offered = offer
            return reassured && offered.isStarter && offered.questions.count > 1
                && cardQuestion == nil && !accessibility
        case .reassuranceBelow: return reassured && accessibility
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
            .elderCard()
        }
    }
}

// MARK: - Recording

private struct RecordingView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let model: TellViewModel

    @State private var isConfirmingDiscard = false
    /// The steps this screen has taken at each text size to keep "Paina kun
    /// olet valmis" in sight, and what it measured to decide them. See
    /// `Squeeze`.
    @State private var steps: [DynamicTypeSize: Set<Squeeze>] = [:]
    @State private var room: CGFloat?
    @State private var caption: Edge?
    /// Every step taken and the caption still below the room: a question at
    /// the largest size, on any phone. The page then opens at the disc.
    @State private var atTheDisc = false

    private var squeeze: Set<Squeeze> { steps[typeSize] ?? [] }

    var body: some View {
        // The same scroll treatment as IdleView and AskingView: with a question
        // on screen this stack is taller than the phone at the largest text
        // size, and truncating the question somebody is answering right now
        // would be absurd. The room `Squeeze` measures is the page's, from here.
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView {
                    content
                        .padding(.horizontal, Elder.screenPadding)
                        .padding(.bottom, Elder.screenPadding)
                        .padding(.top, squeeze.contains(.air) ? 12 : Elder.screenPadding)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                        .coordinateSpace(.named(Self.page))
                        .id(Self.page)
                        .onGeometryChange(for: CGFloat.self) { $0.bounds(of: .scrollView)?.height ?? 0 } action: { height in
                            guard height > 0, height != room else { return }
                            // Measured again whenever it changes, unlike IdleView's:
                            // this screen's first layout still has the tab bar's
                            // room taken off, 83 points on an SE and 49 on a
                            // 17 Pro, and a step taken against that is one the
                            // screen never needed. A new room starts the steps over.
                            if room != nil {
                                steps = [:]
                                atTheDisc = false
                            }
                            room = height
                            giveWayIfNeeded()
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
                // When no step is left and the way to stop is still out of
                // sight, the page opens at the disc, with "Kuuntelen" and the
                // question above it a scroll away. She read the question on
                // the screen before this one, and in the loop heard it spoken;
                // while the phone listens, the disc is the thing she needs.
                // Decided 27 Sep 2026: the other order is the one where a
                // grandparent has to scroll to stop.
                //
                // And back to the top when a new room makes the page fit. The
                // first layout's room is short by the tab bar, and on an SE
                // at the largest size it asks for the disc on a page the real
                // room then shows whole; this way the last decision is the
                // one that holds, whatever became of the first scroll.
                .onChange(of: atTheDisc) { _, _ in land(reader) }
                // And again when the scroll view's insets move, which they do
                // after the room has: since the Kerro tab has a navigation
                // stack of its own (`SettingsGear`), UIKit takes the bars that
                // leave with the recording out of the insets in a pass of its
                // own. On a 17 Pro at the largest size the bottom inset went
                // from 83 to 34 some 13 ms after the room had grown to 778,
                // and the scroll to the disc asked for between the two was
                // lost: the page stayed at its top, with the caption wholly
                // below the window and the disc's last 37 points too
                // (29 Sep 2026). What the page lands on is still decided
                // against the room; this only makes the landing hold.
                .modifier(WhenTheInsetsMove { land(reader) })
            }
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
        // Read once, here, so that the caption's edge says which layout it
        // was measured under.
        let squeezed = squeeze
        let size = typeSize
        let air = squeezed.contains(.air)
        return VStack(spacing: air ? 14 : 28) {
            if !air {
                Spacer(minLength: 0)
            }

            Text("Kuuntelen")
                .font(.largeTitle.weight(.semibold))

            // The question stays visible while it is being answered. Vanishing
            // the moment the button is pressed is how somebody loses the thread
            // halfway through the first sentence — and it is the one question
            // they have not had time to memorise, because they only just chose
            // it. Where it and the disc cannot both fit, it is a scroll above
            // the disc rather than gone (`atTheDisc`).
            //
            // With no question, the example sentence stands here on an install
            // somebody is trying out (`TryIt`), for the same reason: the press
            // that started this took away the screen it was to be read from.
            // Only when that screen showed it, which the press says
            // (`readingAloud`) rather than this screen guessing.
            if let prompt = model.question?.text ?? model.readingAloud {
                Text(prompt)
                    // The same display face it wore on the screen before this
                    // one: it is the same question, still being answered.
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
                .frame(height: squeezed.contains(.waveform) ? 56 : 96)
                .padding(.horizontal, 8)

            Text(Self.timeText(model.recorder.elapsed))
                // The app's own rounded face, with figures of one width so
                // that the count does not jitter as it runs. It was set in
                // the monospaced face, the one line on the screen that read
                // as a machine's.
                .font(.title2.weight(.semibold))
                .foregroundStyle(Elder.supporting)
                .monospacedDigit()
                // The first audit ever run on this screen reported the timer
                // clipped at the default size; a single line of digits has no
                // honest reason to shrink.
                .fixedSize()
                .accessibilityLabel("Nauhoitettu \(Int(model.recorder.elapsed)) sekuntia")

            if !air {
                Spacer(minLength: 0)
            }

            RecordButton(isRecording: true) {
                Task { await model.stopAndProcess() }
            }
            // 28 clear above and below the disc in both layouts: the rings
            // reach 26 past it at the top of a breath, and the caption under
            // it is measured against whatever is behind it.
            .padding(.vertical, air ? 14 : 0)

            Text("Paina kun olet valmis")
                .font(.headline)
                // Full primary rather than Elder.supporting, which every
                // sibling caption wears: this one sits within the record
                // disc's reach — its glow, and its rings at the top of a
                // breath — and the first audit of this screen measured it
                // under the minimum there. The instruction for
                // ending a telling is also the one caption that must never
                // be the faint one.
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: Edge.self) { proxy in
                    Edge(maxY: proxy.frame(in: .named(Self.page)).maxY, squeeze: squeezed, size: size)
                } action: { edge in
                    caption = edge
                    giveWayIfNeeded()
                }
                // Where the page stops when it opens at the disc: the
                // squeeze's 8 points of daylight under the caption. On an SE
                // that puts the ways out below it wholly out of sight; a
                // 17 Pro still draws 34 points under its room, behind the
                // home indicator, and the top of the next one shows there,
                // as it does at rest without a question.
                .background {
                    Color.clear
                        .id(Self.stop)
                        .padding(.bottom, -8)
                }

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
                    // Ink: wax is the disc above it (`Elder.wax`).
                    .foregroundStyle(Color.primary)
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

    /// What this screen gives, in this order, when "Paina kun olet valmis"
    /// ends below what the phone shows of the page — which is
    /// `IdleView.Squeeze`'s measure on a screen with less to give. The disc,
    /// the caption, the question and every text size stay as they are.
    ///
    /// A small phone gets here, and a question. On an iPhone SE at the
    /// largest size, with no question, the caption stood at 647–772.5 on a
    /// screen 667 tall, so the one instruction for ending a telling had to be
    /// found by scrolling while the phone listened, and the audit read the 20
    /// points left in sight as a contrast failure (27 Sep 2026). With a
    /// question the SE lost the caption at the default size as well. Without
    /// one, a 17 Pro takes a step only in English at the largest size, where
    /// the caption is three lines rather than two.
    ///
    /// A question at the largest size is taller than either phone with every
    /// step taken, and so is the SE's English screen without one; there the
    /// page opens at the disc instead (`atTheDisc`).
    ///
    /// Kept per text size and as a set for the reasons `IdleView.Squeeze`
    /// records: the audit's Dynamic Type check changes the size under a
    /// running screen, and a step is never given back — only a new room,
    /// which `body` explains, starts them over.
    private enum Squeeze: Int, CaseIterable, Comparable {
        /// The empty spacers above the disc, the stack's gaps 28 → 14 with
        /// the disc kept 28 clear of its neighbours, and the top margin
        /// 24 → 12.
        case air
        /// The waveform 96 → 56: still a line that moves when she speaks,
        /// which is all it has to say.
        case waveform

        static func < (a: Squeeze, b: Squeeze) -> Bool { a.rawValue < b.rawValue }
    }

    /// Where the caption ends, in the page's coordinates, and the steps and
    /// the text size it was laid out under.
    private struct Edge: Equatable {
        var maxY: CGFloat
        var squeeze: Set<Squeeze>
        var size: DynamicTypeSize
    }

    private static let page = "RecordingView.page"
    private static let stop = "RecordingView.stop"

    /// Puts the page where `atTheDisc` says: the caption and the daylight
    /// under it at the bottom of the room, or the page's top.
    private func land(_ reader: ScrollViewProxy) {
        if atTheDisc {
            reader.scrollTo(Self.stop, anchor: .bottom)
        } else {
            reader.scrollTo(Self.page, anchor: .top)
        }
    }

    /// The next step, when the caption ends below the page's room — and only
    /// when it was measured as the screen is now. As in `IdleView`, what
    /// starts it is the caption out of sight and what it stops at is 8
    /// points of daylight under it.
    private func giveWayIfNeeded() {
        guard let room, let caption, caption.size == typeSize, caption.squeeze == squeeze else { return }
        let under = caption.maxY - room
        guard squeeze.isEmpty ? under > 0 : under + 8 > 0 else {
            atTheDisc = false
            return
        }
        guard let next = Squeeze.allCases.first(where: { step in squeeze.allSatisfy { $0 < step } }) else {
            atTheDisc = true
            return
        }
        steps[typeSize, default: []].insert(next)
    }
}

/// Calls `action` when the insets of the scroll view it is on change, as
/// they do when a bar comes or goes, and never for a scroll. Before iOS 18
/// nothing reports a scroll view's insets, and the page keeps the landing it
/// was given (`RecordingView.land`).
private struct WhenTheInsetsMove: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: EdgeInsets.self) { $0.contentInsets } action: { _, _ in
                action()
            }
        } else {
            content
        }
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
    /// Said while the words are awaited, and only when the recording is
    /// already out of tmp (`TellViewModel.recordingIsKept`). The first
    /// grandparent to use the app asked this screen *"Mistä tiedän että se on
    /// tallessa?"*, and it had no answer (PLAN.md §8).
    let voiceIsKept: Bool

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

            // First, above the spinner: it answers what the teller is asking
            // the moment the button is let go, before anything is waited for.
            // "Tässä puhelimessa" because that is all that is true yet — and
            // not the audio-saved screen's title, which the UI tests wait on.
            if voiceIsKept {
                Label("Äänesi on tallessa tässä puhelimessa", systemImage: "checkmark.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Elder.affirmative)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
        // The width, which every other phase takes from its scroll view's
        // frame and this one had nothing to take it from. The paper is hung
        // on the screen's `Group`, so it stopped at the longest line and the
        // window's white showed down both sides while a telling was being
        // put in order. The README's GIF showed it on 28 Sep 2026.
        .frame(maxWidth: .infinity)
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

            // Said only while it is true. The voice never speaks under
            // VoiceOver (`ask`), so a screen-reader user does not meet this;
            // a UI test does, and it is how the spoken question is checked
            // without anybody listening (`InterviewLoopTests`, `-voice stub`).
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 44))
                // Ink: wax is for what starts a telling, and on this screen
                // that is the disc below (`Elder.wax`).
                .foregroundStyle(Color.primary)
                .symbolEffect(.variableColor.iterative, isActive: model.voice.isSpeaking)
                .accessibilityLabel("Luen kysymyksen ääneen")
                .accessibilityHidden(!model.voice.isSpeaking)

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
                .foregroundStyle(Color.primary)
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
    /// The tallest the photograph may be. 200 on the Kerro tab, where the
    /// card has the screen to itself; Albumi passes 150, because there the
    /// card sits under a large title. Measured 19 Sep 2026 at the text floor
    /// on her album: with 200 the fourth name was drawn under the tab bar and
    /// "En muista" below the screen, so she was shown three of the four names
    /// the instrument depends on, and the way past a face she cannot place
    /// was not on the screen at all. Accessibility sizes cap it at 150 either
    /// way.
    ///
    /// A ceiling and, on a small phone, not the height: since 26 Sep 2026 the
    /// photograph takes what the answers leave of the room above the tab bar,
    /// because 150 was itself too tall on an iPhone 13 mini, and on an SE the
    /// column fits under neither ceiling — see `photoMax` and
    /// `answers(inPairs:)`.
    var photoHeight: CGFloat = 200
    var onDone: () -> Void = {}

    @State private var afterward: LocalizedStringKey?
    /// From the top of this card to the top of the tab bar, measured once at
    /// rest. Nil until then, and for a card outside any scroll view.
    @State private var room: CGFloat?
    /// Everything under the photograph — the question, the answers and the
    /// way past them — as last laid out. None of it depends on the
    /// photograph, which is what lets the photograph be sized from it.
    @State private var below: CGFloat?
    /// Two rows of two instead of the column, decided once: the first time
    /// the room and the column have both been measured. Nil until then, which
    /// is the column.
    @State private var inPairs: Bool?

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
                    .frame(maxHeight: photoMax)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    // What is known and nothing more. A name in here would hand
                    // the answer to whoever is listening rather than looking —
                    // the audience this card is most for, and the same leak the
                    // cut round's mask existed to stop, arriving by the other
                    // door. The whole screen a tap opens it to says the same
                    // words and nothing else, which `BlindConfirmationTests`
                    // walks as it walks this card: the face the question is
                    // about is a few points wide here, and a closer look is
                    // what answers it.
                    .opensToTheWholeScreen(image, label: String(localized: "Valokuva, jossa on joku"))
            }

            VStack(spacing: 18) {
                Text(afterward ?? "Kuka tässä on?")
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if afterward == nil {
                    answers(inPairs: (inPairs ?? false) && !typeSize.isAccessibilitySize)

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
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                below = height
                decide()
            }

            Spacer(minLength: 0)
        }
        // The room, once and at rest. In this card's own coordinates the
        // enclosing scroll view's bounds are the part of it that no bar
        // covers, so their maxY is the distance from the top of the card to
        // the top of the tab bar — on a 13 mini, 541 on her album at the text
        // floor and 655 on a reader's Kerro tab, which is 729 − 188 and
        // 729 − 74 against the tab bar's own frame (26 Sep 2026). Once,
        // because the number moves as the page scrolls, and a card measured
        // again under her thumb would grow its photograph while she read it.
        // The first pass reports a scroll view not laid out yet, zero high; a
        // card outside any scroll view gets nil and keeps the column.
        .onGeometryChange(for: CGRect?.self) { $0.bounds(of: .scrollView) } action: { visible in
            guard room == nil, let visible, visible.height > 0 else { return }
            room = visible.maxY
            decide()
        }
    }

    /// What is left for the photograph: the room less 18 points above it, 18
    /// under it, 8 of daylight between "En muista" and the bar, and everything
    /// under it. Never taller than the ceiling, and never under 100 points — a
    /// floor chosen rather than measured: below it a face in a family
    /// photograph stops being something to recognise, and the page had better
    /// scroll than ask. Accessibility sizes keep the ceiling, as they always
    /// have: nothing fits a phone at those sizes, and the page scrolls.
    ///
    /// Arithmetic and not a proposed height, and that is measured too. The
    /// first version of this handed the card a height to fit and let
    /// `ViewThatFits` choose; the accessibility audit then reported the
    /// question and "En muista" partially unsupported on a reader's Kerro
    /// tab, and "Sanni", "Aino" and the question clipped on her album at the
    /// largest size — where no height was being proposed at all. `main`
    /// audited clean on the same simulator minutes apart (26 Sep 2026). A
    /// photograph given a smaller ceiling changes nothing else in the card.
    private var photoMax: CGFloat {
        let ceiling = min(photoHeight, typeSize.isAccessibilitySize ? 150 : 200)
        guard let room, let below, !typeSize.isAccessibilitySize else { return ceiling }
        return min(ceiling, max(100, room - 18 - 18 - 8 - below))
    }

    /// The column where it fits with the photograph at its ceiling — and on a
    /// phone where it does, nothing about this card has changed. Decided once,
    /// with the column on the screen, so that the card does not rearrange
    /// itself under her thumb.
    private func decide() {
        guard inPairs == nil, let room, let below, !typeSize.isAccessibilitySize else { return }
        inPairs = below > room - 18 - 18 - 8 - min(photoHeight, 200)
    }

    /// The answers, as one block: with the outer stack's spacing between them
    /// they took the height the last row needed.
    ///
    /// **Two rows of two where the column does not fit.** Every name keeps its
    /// full 60 points of height and gives up width instead, which a first name
    /// has to spare and a face does not. Measured 26 Sep 2026 in English with
    /// `-seed blind`: on a 13 mini at the text floor the column put
    /// "En muista" 54 points under her album's tab bar, and a column made to
    /// fit would have left the photograph 88 points tall. On an SE it fits
    /// nowhere: her album has 426 points from the top of the card to the bar,
    /// and the column needs 445 of them before the photograph has any height.
    private func answers(inPairs: Bool) -> some View {
        VStack(spacing: 10) {
            if inPairs {
                ForEach(0..<(card.names.count + 1) / 2, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(card.names[(row * 2)..<min(row * 2 + 2, card.names.count)]) { name in
                            nameButton(name)
                        }
                        // A card of three keeps its last name as wide as the
                        // others: alone at full width it would be the one name
                        // that looked different, and none of them may.
                        if row * 2 + 1 == card.names.count {
                            Spacer(minLength: 0)
                        }
                    }
                }
            } else {
                ForEach(card.names) { name in
                    nameButton(name)
                }
            }
        }
    }

    private func nameButton(_ name: Subject) -> some View {
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
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    /// Whose phone this is, for the offer slot (`UpsellRhythm.card`).
    @AppStorage(Elder.largerTextKey) private var largerText = false
    let model: TellViewModel
    /// The presenter's way out, when there is a presenter: the same closure
    /// "Sulje" calls, and nil on the tab. Whether this screen offers *Valmis*
    /// is read off this and nothing else — see the button.
    let onClose: (() -> Void)?

    @State private var isConfirmingDiscard = false
    @State private var isMoving = false
    @State private var isDating = false

    /// Where the memory was filed, as the store has it **now** rather than as
    /// the view model captured it. A date given on this screen has to be on
    /// this screen the moment the sheet closes, and `placedSubject` is a value
    /// taken when the telling was saved.
    private var placedNow: Subject? {
        guard let placed = model.placedSubject else { return nil }
        return store.subject(id: placed.id) ?? placed
    }

    /// Whether "when did this happen" is a question this subject can answer —
    /// the same rule the card keeps (`datable` in `RootView.swift`), and kept
    /// twice on purpose rather than shared: a person's date would have to mean
    /// birth or death, which `date_start` does not say and the app must not
    /// guess.
    private var datable: Bool {
        guard let kind = placedNow?.kind else { return false }
        return kind == .photo || kind == .event
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                // Above the memory's own text, because it is the one thing on
                // this screen that has to be answered while the room is still
                // the room: who spoke is known now and guessable never
                // (`TellerCard`). Not on the saved-audio screen, which is the
                // other way a telling ends — that screen is already a title, a
                // paragraph and four buttons on the day the network failed,
                // and a question added to it would be measured at the largest
                // text size before it was read.
                TellerCard(model: model)

                if let body = model.result?.body {
                    MemoryCard(text: body, memory: model.savedMemory)
                }

                // One section for everything the telling named — people and
                // places, the ones to check and the ones the family already
                // has — each with the sentence it was heard in. *"Kuulin nämä"*
                // rather than a question: the rows are the question, and
                // nothing on them is asserted (12 Sep 2026). A name confirmed
                // here keeps the section open for its note (30 Sep 2026).
                if !model.proposals.isEmpty || !model.known.isEmpty || !confirmedHere.isEmpty {
                    heardSection
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
                // with. See docs/UX.md §3.2. On a grandparent's phone it never
                // follows: she is not the one who pays. Nor where there is no
                // store to buy from, since an offer nobody can take is only a
                // sentence about money.
                let card = UpsellRhythm.card(
                    membersInFamily: session.family?.members.count,
                    isPaid: session.isPaid,
                    onGrandparentsPhone: largerText,
                    canPurchase: RevenueCatPurchases.configuredKey != nil
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
                    // With follow-up questions on the screen the prominent
                    // button is "Jatketaan jutellen" — carrying on about
                    // the memory she has just told is worth more than
                    // starting a second one, and it is the loop this app
                    // was built around (§10). With no questions there is
                    // nothing above to defer to, and telling another is the
                    // whole of what is left to do.
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
                    // modally, so there has to be a way back to the photo —
                    // and the tab screen must not grow a close button that
                    // closes nothing.
                    //
                    // Read off the presenter, not the subject. Until 12 Sep
                    // 2026 this asked `initialTarget != nil`, which was the
                    // same question while only a sheet ever had a subject; the
                    // deck gave the tab one on 29 Aug, and from then on a
                    // telling about its card ended on a *Valmis* that called
                    // `dismiss()` on a view nobody had presented. Nothing
                    // reports that: a button that does nothing raises no
                    // error, and it was found by a thumb.
                    if let onClose {
                        Button("Valmis") { onClose() }
                            .controlSize(.large)
                            // Ink: in the accent it was the red of the
                            // removal below it (`Elder.wax`).
                            .foregroundStyle(Color.primary)
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
                // On the tab the discard has already reset the screen, and the
                // card comes back by itself.
                onClose?()
            }
            Button("Peruuta", role: .cancel) {}
        } message: {
            // The same two truths as the card's dialog (`MemoryRow`), from
            // the result screen: the telling is offered back for thirty days
            // on the card it was filed under (§19) — unless that card was
            // made here for this telling alone and goes with it, which is
            // what `discardSavedMemory` does when `initialTarget` is nil.
            // Named as *the card it was filed under* rather than *this card*,
            // because on the tab no card is in view.
            if model.initialTarget == nil, let saved = model.savedMemoryID, store.cardGoesWith(memoryID: saved) {
                Text("Muisto poistuu perheen näkyvistä kaikilta puhelimilta ja tämä kortti sen mukana, eikä sitä voi palauttaa.")
            } else {
                Text("Muisto poistuu perheen näkyvistä kaikilta puhelimilta. Voit palauttaa sen 30 päivän ajan siltä kortilta, jolle se on tallennettu.")
            }
        }
        .sheet(isPresented: $isMoving) {
            if let placed = model.placedSubject {
                MoveMemorySheet(current: placed.id) { model.move(to: $0) }
            }
        }
        // `placedNow` and not the captured subject, for the reason the card's
        // own date sheet reads the store: the sheet opens on the archive as it
        // is now, so a date another phone gave while this screen was open is
        // the date it starts from.
        .sheet(isPresented: $isDating) {
            if let dated = placedNow {
                DateSheet(subject: dated)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Muisto tallennettu", systemImage: "checkmark.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Elder.affirmative)

            if let placed = model.placedSubject {
                // Only a placement a person made is announced. The screen used
                // to open with where the AI had filed the memory — *"Sijoitin
                // sen kohteeseen Kesä Puumalassa"*, a moment it had also named
                // — which is one telling asserted as an arrangement (12 Sep
                // 2026). A telling about a photograph sits under that
                // photograph and needs no sentence to say so; a free dictation
                // is its own moment, shown under its day.
                if model.movedByHand {
                    Text("Muisto on nyt kohteessa **\(placed.displayTitle)**")
                        .elderBody()
                        .foregroundStyle(Elder.supporting)
                }

                // The way to file it somewhere else. The placement was the one
                // thing on this screen nobody could correct until 5 Sep 2026
                // (finding #27): grandfather's war years filed under "Kesä
                // Puumalassa" stayed there for good. Also for a telling started
                // from a card: the deck offered a photograph and grandmother
                // talked about the cottage, and the card is wrong the same way.
                if model.savedMemoryID != nil {
                    Button("Siirrä toiselle kortille") { isMoving = true }
                        .buttonStyle(.elderSecondary)
                        .elderTapTarget()
                }

                // And when it happened, asked where it is known.
                //
                // The date could be given only on the subject's own card until
                // 19 Sep 2026, which is two screens away from the one moment
                // somebody has just said *"se oli kesäkuussa 1957"* out loud.
                // Rule 5 stores uncertainty rather than rounding it, and a date
                // nobody walks two screens to record is not stored at all —
                // the rule was kept by the schema and lost by the geometry.
                //
                // A `Text` and an `Image` rather than a `Label`, which is not a
                // style preference: the same row on the card was reported as
                // clipped by the audit in every shape it was tried in as a
                // `Label`, and split into two views it passes at both sizes
                // (`RootView.swift`, four runs to learn one fact).
                if datable, let dated = placedNow {
                    Button {
                        isDating = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar")
                            Text(dated.dateHint?.displayText ?? String(localized: "Lisää ajankohta"))
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .buttonStyle(.elderSecondary)
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
    /// Everything the telling named, under one heading. The rows to check come
    /// first; the familiar names follow, quieter.
    private var heardSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Kuulin nämä")
                .font(.headline)

            if !model.proposals.isEmpty || !confirmedHere.isEmpty {
                proposalSection
            }
            if !model.known.isEmpty {
                knownSection
            }
        }
    }

    /// The sentence a name was heard in, from the text on this screen. A name
    /// alone on a row asks her to remember where it came up; the sentence lets
    /// her recognise it. Matched on the name as a prefix, which is what Finnish
    /// inflection leaves intact most of the time — "Puumalassa" carries
    /// "Puumala", "Ainon" carries "Aino" — and a name whose stem changes
    /// ("Matin" for Matti) gets no sentence rather than a wrong one.
    private func heard(_ subject: Subject) -> String? {
        guard let text = model.result?.body ?? model.transcript else { return nil }
        return HeardSentence.find(subject.title, in: text)
    }

    private var knownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tutut nimet")
                .font(.subheadline.weight(.semibold))

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
                    if let heard = heard(subject) {
                        Text(verbatim: heard)
                            .font(.subheadline)
                            .foregroundStyle(Elder.supporting)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if subject.kind == .place {
                        Button("Eri paikka") { model.splitMention(subject) }
                            .buttonStyle(.elderSecondary)
                            .elderTapTarget()
                            .accessibilityLabel("Eri paikka kuin \(subject.title)")
                    } else {
                        Button("Eri henkilö") { model.splitMention(subject) }
                            .buttonStyle(.elderSecondary)
                            .elderTapTarget()
                            .accessibilityLabel("Eri henkilö kuin \(subject.title)")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .elderCard()
            }
        }
    }

    /// The people confirmed on this screen, as the store has them now: a
    /// correction may have renamed one since, and a card removed since has no
    /// note left to give.
    private var confirmedHere: [Subject] {
        model.confirmedPeople.compactMap { id in
            store.subject(id: id).flatMap { $0.kind == .person && $0.confirmed ? $0 : nil }
        }
    }

    private var proposalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Speech recognition gets roughly one proper noun in three wrong,
            // and this is the only moment when the teller still remembers what
            // they said. While there is still a name to check.
            if !model.proposals.isEmpty {
                Text("Kirjoita nimi uudelleen jos kuulin väärin. Emme lisää sukuun ketään jota et ole hyväksynyt.")
                    .font(.subheadline)
                    .foregroundStyle(Elder.supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Where each confirmed name went, above the names still waiting,
            // so the one just answered takes the place of its row when the
            // rows are answered from the top (`ConfirmedNameNote`).
            ForEach(confirmedHere) { person in
                ConfirmedNameNote(person: person)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .elderCard()
            }

            ForEach(model.proposals) { subject in
                ProposalRow(
                    subject: subject,
                    heard: heard(subject),
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
                // Secondary, not prominent. It confirms something already typed
                // into the row above it, which is not what this screen is for —
                // and it used to be one of four blue buttons down one scroll.
                // See docs/ARCHITECTURE.md §22. The control size is for the
                // spinner while the correction runs; the style has its own.
                .buttonStyle(.elderSecondary)
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

            // Two of the three. Three under the names was a wall; the third is
            // still stored, and the interview loop and the subject's own Tell
            // screen offer it (12 Sep 2026).
            // Bubbles, as the memory above them is: these are things said to
            // the teller, and nothing here is pressed. So the mark is
            // `supporting` and not wax — the button under them is what starts
            // talking.
            ForEach(model.newQuestions.prefix(2)) { question in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(Elder.supporting)
                        .font(.title3)
                    Text(question.text)
                        .elderBody()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .elderBubble()
            }

            // One tap turns the questions into a spoken conversation: the app
            // asks aloud, listens, and asks again. See the interview loop in
            // TellViewModel. A spoken telling has already been through it by
            // the time this screen is drawn (26 Sep 2026), so the button is
            // where a written telling starts it, and where a conversation
            // ended with "Riittää tältä erää" can be taken up again.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ilmainen arkisto", systemImage: "sparkles")
                // The display face, like every other card title that names
                // what the card is about.
                .font(Elder.display(.title3))

            // The meter by its own name. "Kertomista jäljellä" said on this
            // card that telling runs out, a sentence away from rule 2's
            // "Kertominen on aina ilmaista" on the help page — and in English
            // the two read as "telling left" and "telling is never limited".
            if let minutes = minutesLeft, let photos = usage.photos.remaining {
                Text("Litterointiaikaa tässä kuussa jäljellä noin \(minutes) minuuttia, ja kuville tilaa \(photos).")
                    .elderBody()
                    .foregroundStyle(Elder.supporting)
            }

            // "More", not "no limits". The paid archive's fair-use ceiling is
            // written down and not enforced (docs/PLAN.md §9), so a promise of
            // none would be a promise nobody has decided to keep, and "more"
            // stays true whichever way that goes.
            Text("Maksullisessa arkistossa on enemmän tilaa kuville ja enemmän litterointiaikaa, ja yksi maksaja avaa sen koko perheelle.")
                .elderBody()
                .foregroundStyle(Elder.supporting)

            // Always a button. The card rises only where there is a store to
            // buy from (`UpsellRhythm.card`); until 26 Sep 2026 it
            // rose without one too and drew no button, which on any phone
            // opened from its home screen was every third telling.
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        // The same cream as every other card. It was a tinted panel, which
        // put a blue ground under a blue button and made the one offer on the
        // screen the loudest thing on a warm page. What marks it as an offer
        // is the prominent button inside it — ARCHITECTURE §22 gives a screen
        // exactly one — and not a second colour saying the same thing.
        .elderCard()
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
                // The display face, like every other card title that names
                // what the card is about.
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
        .elderCard()
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
            // a step on the way to text but part of the product. Its shape
            // first, then the button that plays it.
            if let memory, memory.audioFilename != nil || memory.audioR2Key != nil {
                VStack(alignment: .leading, spacing: 6) {
                    VoiceShape(memory: memory)
                    MemoryPlaybackButton(memory: memory)
                        // Ink on honey. The button's words are a caption's
                        // size, and wax on honey is a glyph's colour and never
                        // a sentence's (`Elder.honey`).
                        .tint(Color.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        // Somebody's words, so a bubble. And on the slab `elderBlock` gives a
        // card, in the bubble's own shape: this is what the telling became,
        // and the one thing on the screen worth a thickness.
        .elderBubble()
        .background {
            Elder.bubble
                .fill(Elder.block)
                .offset(x: 5, y: 7)
        }
    }
}

/// The recording's own shape, under the words it became (`AudioEnvelope`).
///
/// Only from a file on this phone. A telling just made always has one, and a
/// recording that is still only in R2 is not downloaded for a picture of
/// itself. Nothing stands in for it when there is no file or it cannot be
/// read: a made-up shape would be a picture of a voice that is not the
/// teller's.
///
/// Drawn in `supporting` on honey — a graphic, judged at 3:1 and measured at
/// 6.73:1 as text — so that it stays quieter than the words above it.
private struct VoiceShape: View {
    let memory: Memory

    /// Empty until the file has been read, which on a five-minute telling is
    /// a moment after the screen appears. The strip keeps its height
    /// meanwhile, so the button under it does not move.
    @State private var bars: [Float] = []

    private static let count = 48

    private var fileURL: URL? {
        guard let filename = memory.audioFilename, MediaStore.exists(filename) else { return nil }
        return MediaStore.url(for: filename)
    }

    var body: some View {
        if let url = fileURL {
            GeometryReader { geometry in
                let spacing: CGFloat = 3
                let count = CGFloat(Self.count)
                let width = max(2, (geometry.size.width - spacing * (count - 1)) / count)
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(bars.indices, id: \.self) { index in
                        Capsule()
                            .fill(Elder.supporting)
                            // Silence as a thin line rather than a gap, as on
                            // the listening screen.
                            .frame(width: width, height: max(3, CGFloat(bars[index]) * geometry.size.height))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            }
            .frame(height: 24)
            .accessibilityHidden(true)
            .task(id: url) {
                let count = Self.count
                bars = await Task.detached(priority: .utility) {
                    AudioEnvelope.bars(of: url, count: count) ?? []
                }.value
            }
        }
    }
}

private struct ProposalRow: View {
    let subject: Subject
    /// The sentence the name was heard in, when one was found.
    let heard: String?
    @Binding var text: String
    let onConfirm: () -> Void
    let onReject: () -> Void

    @State private var isConfirmingReject = false

    private var isEdited: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(subject.title, options: .caseInsensitive) != .orderedSame
    }

    /// The name the tick confirms: the typed one once there is one
    /// (`TellViewModel.confirm`), so VoiceOver says what the tap does.
    private var tickName: String {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? subject.title : typed
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

                // Where it was heard: recognition rather than recall, on the
                // row where a wrong name is caught.
                if let heard {
                    Text(verbatim: heard)
                        .font(.subheadline)
                        .foregroundStyle(Elder.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            .accessibilityLabel("Vahvista \(tickName)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        // The rows a person acts on. The slab makes them read as separate
        // things to press rather than as bands of one list — the film's
        // "blocks", which is what the user asked for by that name.
        .elderBlock()
    }
}

// MARK: - Audio saved, transcription pending

/// The quota was full or the network was down. This is not an error screen: the
/// user did nothing wrong and lost nothing.
private struct AudioSavedView: View {
    @Environment(Session.self) private var session
    /// Whose phone this is, for the handle below
    /// (`UpsellRhythm.offersPurchaseAtCeiling`).
    @AppStorage(Elder.largerTextKey) private var largerText = false
    let model: TellViewModel
    /// As on the result screen: the presenter's closure, nil on the tab. It
    /// decides which of two words the last button carries (ARCHITECTURE §21).
    let onClose: (() -> Void)?

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
                onClose?()
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
            // Until 4 Sep 2026 two of these were one ternary's branches, and
            // neither had a key: `localisation-check.mjs` does not look
            // inside a ternary.
            Group {
                if model.audioLost {
                    Text("Puhelin ei saanut äänitystä talteen. Vapauta tilaa puhelimesta ja kerro uudelleen, tai kirjoita muisto itse nyt, kun se on vielä mielessä.")
                } else if !model.canTranscribe {
                    Text("Kun arkisto on vain tällä puhelimella, puhetta ei muuteta tekstiksi. Äänesi säilyy — voit kirjoittaa muiston itse.")
                } else if model.savedBecauseOfQuota {
                    let date = Session.nextFreeMinutes().formatted(.dateTime.day().month(.wide))
                    Text("Kuukauden ilmainen litterointiaika on käytetty, joten tekstiä ei kirjoitettu nyt. Se kirjoitetaan, kun aikaa on taas \(date) — tai heti, jos perhe avaa koko arkiston. Voit myös kirjoittaa muiston itse.")
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
                // On a grandparent's phone too: the sentence above says the
                // family can lift the wall, and this is how.
                if model.savedBecauseOfQuota, !session.isPaid,
                   UpsellRhythm.offersPurchaseAtCeiling(
                       onGrandparentsPhone: largerText,
                       canPurchase: RevenueCatPurchases.configuredKey != nil
                   ) {
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
                    .foregroundStyle(Color.primary)
                }

                // *Valmis* closes the sheet this screen is on; *Selvä*, on the
                // tab where there is nothing to close, returns to telling. By
                // the presenter and not by `target`: the deck gives the tab a
                // subject too, and read off that this was a *Valmis* whose
                // `dismiss()` had nothing to dismiss — on the screen that
                // tells somebody their voice is safe, with no other way off it.
                Button {
                    if let onClose { onClose() } else { model.reset() }
                } label: {
                    Group {
                        if onClose == nil {
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
                // Ink, for the result screen's *Valmis*: the removal is below.
                .foregroundStyle(Color.primary)

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isRecording: Bool
    /// The resting glow and the rings round the disc at rest. Off only on
    /// the Tell tab of a phone too small for the air round the disc
    /// (`Squeeze.air`); a recording always has both.
    var glows = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Elder.wax.gradient)
                    // One glow for both states. It was twice as wide and
                    // twice as strong while recording, and the rings say that
                    // now — a haze 28 points deep round a breathing ring was
                    // the same news twice, on the caption's side of the disc.
                    .shadow(color: Elder.wax.opacity(isRecording || glows ? 0.25 : 0), radius: 14)

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
            // The rings are drawn outside the disc's frame and take no room in
            // the layout, so the room has to be there already: they reach 24
            // points past the disc, 26 at the top of a breath, and every
            // screen this button is on keeps 28 clear above and below it —
            // except the Tell tab squeezed for air, which leaves them out
            // with the glow (`glows`).
            .background {
                if isRecording && !reduceMotion {
                    // In and out once every 2.6 seconds while it listens:
                    // slower than breath at rest, so that it reads as the
                    // phone waiting rather than hurrying anybody.
                    Color.clear.phaseAnimator([false, true]) { _, drawn in
                        RecordRings(inner: drawn ? 16 : 10, outer: drawn ? 26 : 18)
                    } animation: { _ in
                        .easeInOut(duration: 1.3)
                    }
                } else if isRecording {
                    // Reduce Motion: where a breath starts, and still.
                    RecordRings(inner: 10, outer: 18)
                } else if glows {
                    RecordRings(inner: 12, outer: 24)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? String(localized: "Lopeta kertominen") : String(localized: "Aloita kertominen"))
        .accessibilityHint(isRecording ? String(localized: "Tallentaa muiston") : String(localized: "Nauhoittaa puheesi ja tallentaa sen muistoksi"))
    }
}

/// Two rings of wax round the disc, the inner one stronger: the room the one
/// loud control on the screen stands in. `inner` and `outer` are how far past
/// the disc each reaches.
///
/// Wax at 13 % and 7 % on the paper, so they are a tint round the disc and
/// never an edge of anything — the disc's own 5.12:1 against the paper is
/// what makes it an object. Nothing reads them: they are hidden from
/// VoiceOver and let every tap through to whatever they lie over.
private struct RecordRings: View {
    let inner: CGFloat
    let outer: CGFloat

    var body: some View {
        let size = Elder.recordButtonSize
        ZStack {
            Circle()
                .fill(Elder.wax.opacity(0.07))
                .frame(width: size + 2 * outer, height: size + 2 * outer)
            Circle()
                .fill(Elder.wax.opacity(0.13))
                .frame(width: size + 2 * inner, height: size + 2 * inner)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    TellScreen()
        .environment(MemoryStore(filename: "preview-store.json"))
}
