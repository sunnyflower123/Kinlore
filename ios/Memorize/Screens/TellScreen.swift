import SwiftUI

/// Sovelluksen tärkein ruutu. Yksi nappi, ei valikkoja, ei asetuksia.
struct TellScreen: View {
    @Environment(MemoryStore.self) private var store

    /// Kun ruutu avataan kuvasta tai henkilöstä, muisto kiinnittyy siihen.
    /// Nil = vapaa sanelu, jolloin kohde päätellään puheesta.
    var target: Subject?
    /// Kun ruutu avataan avoimesta kysymyksestä, se kuitataan tallennuksessa.
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
            // AppServices valitsee stubin tai oikean palvelun sen mukaan onko
            // backendin osoite määritetty. Käyttöliittymä ei tiedä eroa, koska
            // se tuntee vain protokollat.
            let created = TellViewModel(
                store: store,
                transcription: AppServices.transcription(),
                extraction: AppServices.extraction(),
                target: target,
                question: question
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
            case .savedWithoutTranscript:
                AudioSavedView(model: model)
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
        case .idle, .done, .savedWithoutTranscript, .failed: false
        case .recording, .writing, .transcribing, .organizing: true
        }
    }
}

// MARK: - Lepotila

private struct IdleView: View {
    @Environment(MemoryStore.self) private var store
    let model: TellViewModel

    @State private var answering: FollowUpQuestion?

    /// Avoimet kysymykset näkyvät vain vapaassa sanelussa. Kuvasta tai
    /// henkilöstä kerrottaessa ruudulla on jo aihe, eikä siihen pidä tarjota
    /// kilpailevaa.
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

            // Avoin kysymys on syy palata sovellukseen. Se on myös helpompi
            // aloitus kuin tyhjä nappi: iäkkään on vaikea kertoa "jotain",
            // mutta helppo vastata kysymykseen.
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

                // Paywall juuri tässä: koettu arvo on huipussaan kun muisto on
                // valmis. Ei onboardingissa, ei asetuksissa — ja ei esteenä,
                // koska muisto on jo tallennettu.
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
            Text("Kuulinko nimet oikein?")
                .font(.headline)

            // Puheentunnistus erehtyy erisnimissä noin joka kolmannessa, ja
            // tämä on ainoa hetki jolloin kertoja vielä muistaa mitä sanoi.
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
                        // Kerrotaan että korjaus ulottuu myös muiston tekstiin
                        // — muuten käyttäjä luulee korjaavansa vain kortin.
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

/// Kertoo mitä on jäljellä, ei sitä mitä puuttuu.
///
/// Ei estä mitään: muisto on jo tallennettu, ja kertomista ei paywallata
/// koskaan. Tämä on kutsu, ei muuri.
private struct UpsellCard: View {
    let usage: EntitlementClient.Usage

    private var minutesLeft: Int? {
        usage.aiSeconds.remaining.map { $0 / 60 }
    }

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MemoryCard: View {
    let text: String
    /// Nil kun muisto kirjoitettiin — silloin ei ole ääntä kuunneltavaksi.
    let memory: Memory?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text)
                .elderBody()

            // Alkuperäinen ääni on soitettavissa heti muiston vierestä: se ei
            // ole välivaihe kohti tekstiä vaan osa lopputuotetta.
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
                // Kenttä eikä teksti: nimen korjaaminen on tämän ruudun
                // tarkoitus, joten sen pitää olla ilmeistä ilman että mitään
                // täytyy painaa ensin.
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

// MARK: - Ääni tallessa, purku odottaa

/// Kiintiö oli täynnä tai verkko poikki. Tämä ei ole virheruutu: käyttäjä ei
/// tehnyt mitään väärin eikä menettänyt mitään.
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
