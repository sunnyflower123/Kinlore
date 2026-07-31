import SwiftUI

/// Sovelluksen tärkein ruutu. Yksi nappi, ei valikkoja, ei asetuksia.
struct TellScreen: View {
    @Environment(MemoryStore.self) private var store

    /// Kun ruutu avataan kuvasta tai henkilöstä, muisto kiinnittyy siihen.
    /// Nil = vapaa sanelu, jolloin kohde päätellään puheesta.
    var target: Subject?

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
            // AppServices valitsee stubin tai oikean palvelun sen mukaan onko
            // backendin osoite määritetty. Käyttöliittymä ei tiedä eroa, koska
            // se tuntee vain protokollat.
            let created = TellViewModel(
                store: store,
                transcription: AppServices.transcription(),
                extraction: AppServices.extraction(),
                target: target
            )
            #if DEBUG
            // Kuvausapu: `-screen kirjoita` avaa suoraan kirjoitusnäkymän.
            if UserDefaults.standard.string(forKey: "screen") == "kirjoita" {
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
            case .failed(let message):
                FailureView(message: message) { model.reset() }
            }
        }
        // Kesken kertomisen ruudulla on yksi tehtävä. Välilehtipalkki tarjoaisi
        // poistumistien joka hukkaisi keskeneräisen muiston, eikä 80-vuotias
        // käyttäjä hyödy vaihtoehdoista juuri silloin kun hän keskittyy.
        .toolbar(hidesTabBar(model.phase) ? .hidden : .visible, for: .tabBar)
    }

    private func hidesTabBar(_ phase: TellViewModel.Phase) -> Bool {
        switch phase {
        case .idle, .done, .failed: false
        case .recording, .writing, .transcribing, .organizing: true
        }
    }
}

// MARK: - Lepotila

private struct IdleView: View {
    let model: TellViewModel

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

            // Puhuminen on ensisijainen tapa, mutta ei ainoa: kuvia lisäävä
            // lapsenlapsi kirjoittaa usein mieluummin, eikä bussissa tai
            // sairaalahuoneessa voi sanella.
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
    }
}

// MARK: - Kirjoittaminen

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
                // TextEditorissa ei ole omaa placeholderia.
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

// MARK: - Nauhoitus

private struct RecordingView: View {
    let model: TellViewModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("Kuuntelen")
                .font(.largeTitle.weight(.semibold))

            // Aaltokuvio on ainoa palaute siitä että laite kuulee. Hiljaa
            // puhuva ei muuten tiedä toimiiko mikrofoni.
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

/// Palkit uusin oikealla. Keskitetty pystysuunnassa, jotta hiljaisuus näyttää
/// ohuelta viivalta eikä tyhjältä ruudulta.
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

    /// Täytetään oikealta: uusin näyte on aina reunimmaisena.
    private func level(at index: Int, of count: Int) -> Float {
        let offset = count - levels.count
        guard index >= offset else { return 0 }
        return levels[index - offset]
    }
}

// MARK: - Käsittely

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

// MARK: - Tulos

private struct ResultView: View {
    @Environment(\.dismiss) private var dismiss
    let model: TellViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if let body = model.result?.body {
                    MemoryCard(text: body, duration: model.savedAudioDuration)
                }

                if !model.proposals.isEmpty {
                    proposalSection
                }

                if !model.newQuestions.isEmpty {
                    questionSection
                }

                VStack(spacing: 12) {
                    Button("Kerro toinen muisto") {
                        model.reset()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .elderTapTarget()

                    // Kuvasta kerrottaessa ruutu on esitetty modaalina, joten
                    // siitä pitää päästä myös takaisin kuvaan.
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
                // Tuloksen tärkein tieto: mihin tekoäly sijoitti muiston.
                // Juuri se järjestely jota käyttäjä ei itse jaksaisi tehdä.
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
            Text("Löysin nämä — ovatko oikein?")
                .font(.headline)

            Text("Tekoäly ehdottaa, sinä vahvistat. Emme lisää sukuun ketään jota et ole hyväksynyt.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(model.proposals) { subject in
                ProposalRow(
                    subject: subject,
                    onConfirm: { model.confirm(subject) },
                    onReject: { model.reject(subject) }
                )
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

private struct MemoryCard: View {
    let text: String
    /// Nil kun muisto kirjoitettiin — silloin ei ole ääntä kuunneltavaksi.
    let duration: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text)
                .elderBody()

            if let duration {
                // Alkuperäinen ääni on soitettavissa muiston vierestä: se ei ole
                // välivaihe kohti tekstiä vaan osa lopputuotetta.
                Label(
                    "Kuuntele omalla äänellä · \(Int(duration)) s",
                    systemImage: "play.circle.fill"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct ProposalRow: View {
    let subject: Subject
    let onConfirm: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: subject.kind.symbolName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(subject.title)
                    .font(.body.weight(.medium))
                Text(subject.kind.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

// MARK: - Virhe

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

// MARK: - Nauhoitusnappi

/// Sovelluksen tärkein kontrolli. Sen pitää löytyä ilman lukemista, joten se on
/// iso, pyöreä ja aina samassa paikassa.
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
