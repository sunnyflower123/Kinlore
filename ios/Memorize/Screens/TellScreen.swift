import SwiftUI

/// The app's most important screen. One button, no menus, no settings.
struct TellScreen: View {
    @Environment(MemoryStore.self) private var store

    /// When the screen is opened from a photo or a person, the memory attaches
    /// to it. Nil = free dictation, in which case the subject is inferred from
    /// the speech.
    var target: Subject?
    /// When the screen is opened from an open question, the question is marked
    /// answered on save.
    var question: FollowUpQuestion?

    @State private var model: TellViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .task {
            guard model == nil else { return }
            // AppServices picks the stub or the real service depending on
            // whether a backend address is configured. The UI cannot tell the
            // difference, because it only knows the protocols.
            let created = TellViewModel(
                store: store,
                transcription: AppServices.transcription(),
                extraction: AppServices.extraction(),
                target: target,
                question: question
            )
            #if DEBUG
            // Screenshot aid: `-screen write` opens the typing view directly.
            if UserDefaults.standard.string(forKey: "screen") == "write" {
                created.beginWriting()
            }
            #endif
            model = created
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
            case .done:
                ResultView(model: model)
            case .savedWithoutTranscript:
                AudioSavedView(model: model)
            case .failed(let message):
                FailureView(message: message) { model.reset() }
            }
        }
        // Mid-telling, the screen has one job. A tab bar would offer an exit
        // that loses the unfinished memory, and an 80-year-old user gains
        // nothing from alternatives at exactly the moment she is concentrating.
        .toolbar(hidesTabBar(model.phase) ? .hidden : .visible, for: .tabBar)
    }

    private func hidesTabBar(_ phase: TellViewModel.Phase) -> Bool {
        switch phase {
        case .idle, .done, .savedWithoutTranscript, .failed: false
        case .recording, .writing, .transcribing, .organizing: true
        }
    }
}

// MARK: - Idle

private struct IdleView: View {
    @Environment(MemoryStore.self) private var store
    let model: TellViewModel

    @State private var answering: FollowUpQuestion?

    /// Open questions appear only in free dictation. When telling about a photo
    /// or a person the screen already has a subject, and it should not be
    /// offered a competing one.
    private var openQuestions: [FollowUpQuestion] {
        model.target == nil ? store.openQuestions(limit: 2) : []
    }

    private var title: String {
        guard let target = model.target else { return "Kerro mitä muistat" }
        return target.kind == .person
            ? "Kerro \(target.displayTitle):sta"
            : "Kerro tästä kuvasta"
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text(title)
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("Puhu ihan rauhassa ja vapaasti. Ei tarvitse muistaa järjestystä eikä vuosilukuja — järjestämme ne puolestasi.")
                .elderBody()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            RecordButton(isRecording: false) {
                Task { await model.startRecording() }
            }

            Text("Paina ja ala puhua")
                .font(.headline)
                .foregroundStyle(.secondary)

            // An open question is a reason to come back to the app. It is also
            // an easier start than a blank button: telling "something" is hard
            // for an elderly person, answering a question is easy.
            if !openQuestions.isEmpty {
                VStack(spacing: 10) {
                    Text("Tai vastaa aiempaan kysymykseen")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(openQuestions) { question in
                        Button { answering = question } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "questionmark.circle.fill")
                                    .foregroundStyle(.tint)
                                Text(question.text)
                                    .elderBody()
                                    .multilineTextAlignment(.leading)
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
                    .elderTapTarget()
            }

            Spacer()
        }
        .padding(Elder.screenPadding)
        .sheet(item: $answering) { question in
            NavigationStack {
                TellScreen(
                    target: question.subjectID.flatMap { store.subject(id: $0) },
                    question: question
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Sulje") { answering = nil }
                    }
                }
            }
        }
    }
}

// MARK: - Typing

private struct WritingView: View {
    @Bindable var model: TellViewModel
    @FocusState private var isFocused: Bool

    private var isEmpty: Bool {
        model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.target == nil ? "Kirjoita muisto" : "Kirjoita tästä muisto")
                .font(.title.weight(.semibold))

            ZStack(alignment: .topLeading) {
                // TextEditor has no placeholder of its own.
                if model.draft.isEmpty {
                    Text("Kirjoita ihan vapaasti. Ei tarvitse muistaa järjestystä eikä vuosilukuja — järjestämme ne puolestasi.")
                        .elderBody()
                        .foregroundStyle(.tertiary)
                        .padding(.top, 10)
                        .padding(.horizontal, 6)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $model.draft)
                    .font(.body)
                    .lineSpacing(Elder.lineSpacing)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
            }
            .frame(maxHeight: .infinity)
            .padding(10)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 12) {
                Button("Peruuta") {
                    isFocused = false
                    model.cancelWriting()
                }
                .controlSize(.large)
                .elderTapTarget()

                Spacer()

                Button("Tallenna") {
                    isFocused = false
                    Task { await model.submitTyped() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isEmpty)
                .elderTapTarget()
            }
        }
        .padding(Elder.screenPadding)
        .onAppear { isFocused = true }
    }
}

// MARK: - Recording

private struct RecordingView: View {
    let model: TellViewModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("Kuuntelen")
                .font(.largeTitle.weight(.semibold))

            // The waveform is the only feedback that the device can hear.
            // Somebody speaking quietly has no other way to know whether the
            // microphone works.
            Waveform(levels: model.recorder.levels)
                .frame(height: 96)
                .padding(.horizontal, 8)

            Text(Self.timeText(model.recorder.elapsed))
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityLabel("Nauhoitettu \(Int(model.recorder.elapsed)) sekuntia")

            Spacer()

            RecordButton(isRecording: true) {
                Task { await model.stopAndProcess() }
            }

            Text("Paina kun olet valmis")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(Elder.screenPadding)
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
                        .fill(.red.gradient)
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
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(Elder.screenPadding)
        .animation(.easeInOut, value: phase)
    }
}

// MARK: - Result

private struct ResultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session
    let model: TellViewModel

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

                // The paywall goes exactly here: perceived value peaks when the
                // memory is finished. Not in onboarding, not in settings — and
                // not as an obstacle, because the memory is already saved.
                if let usage = session.usage, !usage.isPaid {
                    UpsellCard(usage: usage)
                }

                VStack(spacing: 12) {
                    Button("Kerro toinen muisto") {
                        model.reset()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .elderTapTarget()

                    // When telling about a photo the screen is presented
                    // modally, so there has to be a way back to the photo.
                    if model.target != nil {
                        Button("Valmis") { dismiss() }
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                            .elderTapTarget()
                    }
                }
            }
            .padding(Elder.screenPadding)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Muisto tallennettu", systemImage: "checkmark.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.green)

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
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
                .buttonStyle(.borderedProminent)
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
                    .foregroundStyle(.secondary)
            }

            Text("Maksullisessa arkistossa rajoja ei ole, ja yksi maksaja avaa sen koko perheelle.")
                .elderBody()
                .foregroundStyle(.secondary)

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
                .foregroundStyle(.secondary)
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

                Text(isEdited ? "\(subject.kind.label) · korjattu" : subject.kind.label)
                    .font(.caption)
                    .foregroundStyle(isEdited ? Color.accentColor : Color.secondary)
            }

            Spacer()

            Button(action: onReject) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .elderTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Poista \(subject.title)")

            Button(action: onConfirm) {
                Image(systemName: "checkmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)
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

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Äänesi on tallessa")
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("Emme ehtineet kirjoittaa sitä tekstiksi juuri nyt, mutta kertomasi ei katoa. Teksti valmistuu myöhemmin — voit myös kirjoittaa muiston itse.")
                .elderBody()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: 12) {
                Button("Kirjoita se itse") { model.beginWriting() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .elderTapTarget()

                Button(model.target == nil ? "Selvä" : "Valmis") {
                    if model.target == nil { model.reset() } else { dismiss() }
                }
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .elderTapTarget()
            }

            Spacer()
        }
        .padding(Elder.screenPadding)
    }
}

// MARK: - Failure

private struct FailureView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text(message)
                .elderBody()
                .multilineTextAlignment(.center)
            Button("Yritä uudelleen", action: onRetry)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .elderTapTarget()
            Spacer()
        }
        .padding(Elder.screenPadding)
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
                    .fill(.red.gradient)
                    .shadow(color: .red.opacity(isRecording ? 0.5 : 0.25), radius: isRecording ? 28 : 14)

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
