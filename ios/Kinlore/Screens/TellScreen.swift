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

    @State private var model: TellViewModel?
    @State private var isConfirmingClose = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .toolbar {
            if onClose != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sulje") { requestClose() }
                }
            }
        }
        // A swipe must not do what "Sulje" is guarded against. Only the two
        // phases where an exit loses words are pinned: transcribing and
        // organizing finish on their own after a dismissal (the task holds the
        // model), and the interview between rounds has nothing unsaved.
        .interactiveDismissDisabled(
            onClose != nil && (model?.phase == .recording || model?.phase == .writing)
        )
        // The same words as the in-screen discard, and the same manners: the
        // recorder keeps running while the question is open, so saying no
        // costs nothing.
        .confirmationDialog(
            "Hylätäänkö tämä kertominen?",
            isPresented: $isConfirmingClose,
            titleVisibility: .visible
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
            #if DEBUG
            // `-screen starter` opens on a photo nobody has spoken about yet —
            // the state the starter questions exist for, and otherwise
            // reachable only by picking a photo from the library by hand.
            let opened = UserDefaults.standard.string(forKey: "screen") == "starter"
                ? Self.emptyPhoto(in: store)
                : target
            #else
            let opened = target
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
                question: question
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
            // cannot do this by tapping: "Riittää tältä erää" exists only
            // while a question is being spoken, and the next round's
            // recording replaces it within seconds, so tapping it races the
            // speech window and loses. What the result screen must then show
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
                IdleView(model: model)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    let model: TellViewModel

    @State private var answering: FollowUpQuestion?

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
    private func intro(withStarters: Bool) -> String {
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
            let open = store.openQuestions(limit: 2)
            return open.isEmpty ? (store.openingQuestions(), true) : (open, false)
        }
        let own = store.openQuestions(limit: 2, for: target.id)
        return own.isEmpty ? (store.starterQuestions(for: target), true) : (own, false)
    }

    private var title: String {
        guard let target = model.target else { return "Kerro mitä muistat" }
        return target.kind == .person
            ? "Kerro \(target.displayTitle):sta"
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

    private var content: some View {
        VStack(spacing: 28) {
            // Resolved once: what is offered at the bottom decides how long the
            // reassurance at the top can afford to be.
            let offered = offer

            Spacer(minLength: 0)

            Text(title)
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(intro(withStarters: offered.isStarter))
                .elderBody()
                .foregroundStyle(Elder.supporting)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            RecordButton(isRecording: false) {
                Task { await model.startRecording() }
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
            if !offered.questions.isEmpty {
                VStack(spacing: 10) {
                    Text(offered.isStarter ? "Jos et tiedä mistä aloittaa" : "Tai vastaa aiempaan kysymykseen")
                        .font(.subheadline)
                        .foregroundStyle(Elder.supporting)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(offered.questions) { question in
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
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }

            // Speaking is the primary way but not the only one: a grandchild
            // adding photos often prefers to type, and you cannot dictate on a
            // bus or in a hospital room.
            Button {
                model.beginWriting()
            } label: {
                Label("Kirjoita sen sijaan", systemImage: "keyboard")
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .elderTapTarget()
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

    private var heading: String {
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
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
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
        .confirmationDialog(
            "Hylätäänkö tämä kertominen?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
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
                    .font(.title3.weight(.semibold))
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
                .accessibilityLabel("Nauhoitettu \(Int(model.recorder.elapsed)) sekuntia")

            Spacer(minLength: 0)

            RecordButton(isRecording: true) {
                Task { await model.stopAndProcess() }
            }

            Text("Paina kun olet valmis")
                .font(.headline)
                .foregroundStyle(Elder.supporting)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

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
                        .fill(Elder.recording.gradient)
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

    private var title: String {
        phase == .transcribing ? "Kuuntelen mitä sanoit" : "Järjestelen muistoa"
    }

    private var detail: String {
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
    /// talking when the voice stops. Shortened at accessibility sizes for the
    /// same reason as IdleView's intro: the question and the button matter
    /// more than the full instruction.
    private var hint: String {
        if UIAccessibility.isVoiceOverRunning { return "Paina nauhoitusnappia ja vastaa." }
        return typeSize.isAccessibilitySize
            ? "Voit vastata puhumalla."
            : "Voit vastata puhumalla heti kun kysymys loppuu."
    }

    private var buttonCaption: String {
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

// MARK: - Result

private struct ResultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session
    let model: TellViewModel

    @State private var isConfirmingDiscard = false

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
                if model.showsUpsell {
                    switch UpsellRhythm.card(
                        membersInFamily: session.family?.members.count,
                        isPaid: session.isPaid
                    ) {
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
        .confirmationDialog(
            "Poistetaanko tämä muisto?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
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
                Text(
                    model.target == nil
                        ? "Sijoitin sen kohteeseen **\(placed.displayTitle)**"
                        : "Lisäsin sen kohteeseen **\(placed.displayTitle)**"
                )
                .elderBody()
                .foregroundStyle(Elder.supporting)
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
                .font(.headline)

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
        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
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
                .font(.headline)

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
        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
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
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct ProposalRow: View {
    let subject: Subject
    @Binding var text: String
    let onConfirm: () -> Void
    let onReject: () -> Void

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

                Text(isEdited ? "\(subject.kind.label) · korjattu" : subject.kind.label)
                    .font(.caption)
                    .foregroundStyle(isEdited ? Color.accentColor : Elder.supporting)
            }
            // The field takes the room, not a Spacer. With one beside it the
            // field sized itself to the name it happened to arrive with — 110
            // points, measured — and a longer one scrolled inside a box the
            // width of a short one. This is the field a wrong name is corrected
            // in; it should be the widest thing in the row.
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onReject) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Elder.supporting)
                    .elderTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Poista \(subject.title)")

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
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Audio saved, transcription pending

/// The quota was full or the network was down. This is not an error screen: the
/// user did nothing wrong and lost nothing.
private struct AudioSavedView: View {
    @Environment(\.dismiss) private var dismiss
    let model: TellViewModel

    @State private var isConfirmingDiscard = false

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
        .confirmationDialog(
            "Poistetaanko tämä muisto?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
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

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                // Decoration: the title beside it says the same thing in words.
                // Left visible, VoiceOver reads out the symbol's own name — the
                // defect the onboarding mark and the member rows had already.
                .accessibilityHidden(true)

            Text("Äänesi on tallessa")
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Emme ehtineet kirjoittaa sitä tekstiksi juuri nyt, mutta kertomasi ei katoa. Teksti valmistuu myöhemmin — voit myös kirjoittaa muiston itse.")
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

                Button {
                    if model.target == nil { model.reset() } else { dismiss() }
                } label: {
                    Text(model.target == nil ? "Selvä" : "Valmis")
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
                // afterwards.
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
                    .fill(Elder.recording.gradient)
                    .shadow(
                        color: Elder.recording.opacity(isRecording ? 0.5 : 0.25),
                        radius: isRecording ? 28 : 14
                    )

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: isRecording ? 60 : 72))
                    .foregroundStyle(.white)
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
