import SwiftUI

/// Export, leaving the family, and emptying this device.
///
/// Everything here is rare and some of it cannot be undone, which is why it sits
/// behind a gear rather than in the way. See docs/ARCHITECTURE.md §14.
struct SettingsScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session

    @State private var exportURL: URL?
    @State private var exportStatus: String?
    @State private var isExporting = false
    @State private var isSharing = false
    /// How many photographs or recordings the export could not include, and
    /// whether that is waiting to be said before the share sheet opens. The
    /// zip used to go out looking complete while the originals had been
    /// silently skipped — an offline export without grandmother's voice, in
    /// the one file meant to outlive the app.
    @State private var missingFromExport = 0
    @State private var isReportingMissing = false
    /// What went wrong, and which thing it was.
    ///
    /// A title of its own because there are two failures on this screen now, and
    /// the export's title on a family that could not be left is a wrong sentence
    /// in a confident voice.
    private struct Failure: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @State private var failure: Failure?

    @State private var isConfirmingLeave = false
    @State private var isConfirmingWipe = false

    @AppStorage(Elder.largerTextKey) private var largerText = false

    /// Leaving is only offered when there is somebody to leave it to. The last
    /// member leaving would not delete the archive, it would strand it.
    private var canLeave: Bool {
        if case .inFamily = session.mode {} else { return false }
        return (session.family?.members.count ?? 0) > 1
    }

    /// What emptying this device actually costs, which depends entirely on
    /// whether anyone else has a copy — and, for the last copy of a shared
    /// family, on the invites: the invitation text carries the family key, so
    /// a live code is join-and-read access to the archive this sentence just
    /// called gone. The wipe revokes them, and the sentence says so.
    private var wipeWarning: String {
        if canLeave {
            return "Poistut perheestä ja tämän laitteen muistot poistetaan. Perheen muistot säilyvät muilla."
        }
        if case .inFamily = session.mode {
            return "Muistot poistetaan lopullisesti ja avoimet kutsut perutaan. Vie arkisto ensin, jos haluat säilyttää ne."
        }
        return "Muistot poistetaan lopullisesti. Vie arkisto ensin, jos haluat säilyttää ne."
    }

    var body: some View {
        List {
            // First, and the only thing here that is neither rare nor
            // irreversible. It is the answer to the setup question in
            // `CreateFamilyForm`, kept where it can be changed: the phone may be
            // handed over later than it was set up, or handed back.
            Section {
                Toggle(isOn: $largerText) {
                    Text("Isompi teksti")
                        .font(.body.weight(.medium))
                }
                .elderTapTarget()
            } footer: {
                Text("Puhelimen oma tekstikoko on tätä vahvempi.")
                    .foregroundStyle(Elder.supporting)
            }

            Section {
                Button {
                    Task { await export() }
                } label: {
                    if isExporting {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(exportStatus ?? "Kootaan arkistoa")
                                .foregroundStyle(Elder.supporting)
                        }
                    } else {
                        Label("Vie arkisto", systemImage: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .elderTapTarget()
                    }
                }
                .disabled(isExporting)
            } header: {
                // A List styles its own headers and footers below the contrast
                // minimum. Saying the colour out loud is the only way to raise
                // it.
                Text("Arkisto")
                    .foregroundStyle(Elder.supporting)
            } footer: {
                // Say what comes out, in the words of somebody who will open it
                // on a computer years from now.
                Text("Saat yhden tiedoston, jossa ovat muistot luettavana sivuna, alkuperäiset äänitteet ja kuvat. Sen voi avata millä tahansa koneella ilman tätä sovellusta.")
                    .foregroundStyle(Elder.supporting)
            }

            // First, and without a header. It is the only row here that answers
            // a question rather than doing something, and the questions it
            // answers — where does my voice go, who can hear it — are the ones
            // somebody has before they are willing to use the rest.
            Section {
                NavigationLink(value: HelpRoute()) {
                    Label("Näin tämä toimii", systemImage: "questionmark.circle")
                        .elderTapTarget()
                }
            }

            if case .inFamily = session.mode {
                // A bare `Section("Perhe")` header is the framework's own grey —
                // the finding the first audit of the family screen's top
                // reported on "Käyttö" and "Jäsenet". This one has never been
                // measured at all: the sweep's Settings run has no family, so
                // the section is not on its screen. Fixed by the same move as
                // every measured header rather than left for the audit to find.
                Section {
                    NavigationLink(value: FamilyRoute()) {
                        Label("Perheen jäsenet ja kutsut", systemImage: "person.2")
                            .elderTapTarget()
                    }
                } header: {
                    Text("Perhe")
                        .foregroundStyle(Elder.supporting)
                }
            }

            Section {
                // The symbol is tinted with the text: a destructive row whose
                // icon stays the ordinary blue reads as a mistake rather than a
                // warning, and this is the one row that cannot be undone.
                if canLeave {
                    Button(role: .destructive) {
                        isConfirmingLeave = true
                    } label: {
                        Label("Poistu perheestä", systemImage: "person.badge.minus")
                            .foregroundStyle(Elder.destructive)
                            .elderTapTarget()
                    }
                }

                Button(role: .destructive) {
                    isConfirmingWipe = true
                } label: {
                    Label("Tyhjennä tämä laite", systemImage: "trash")
                        .foregroundStyle(Elder.destructive)
                        .elderTapTarget()
                }
            } footer: {
                // The distinction between the two is the whole design of this
                // screen, so it is spelled out rather than implied by the names.
                Text(canLeave
                    ? "Perheestä poistuminen ei poista kertomiasi muistoja. Ne jäävät perheen arkistoon, koska kerrottu on tarkoitettu säilymään kertojaansa pidempään."
                    : "Kertomasi muistot ovat vain tässä laitteessa.")
                    .foregroundStyle(Elder.supporting)
            }
        }
        .navigationTitle("Asetukset")
        .task {
            await session.refresh()
            #if DEBUG
            // `-screen export` runs it at once. The export is the one thing here
            // whose output leaves the app for good, so being able to open the
            // actual file without a pair of hands is worth a launch argument.
            if UserDefaults.standard.string(forKey: "screen") == "export" {
                await export()
            }
            #endif
        }
        .confirmationDialog(
            "Poistutaanko perheestä?",
            isPresented: $isConfirmingLeave,
            titleVisibility: .visible
        ) {
            Button("Poistu perheestä", role: .destructive) {
                Task {
                    guard await session.leaveFamily() else {
                        // It used to return here and say nothing at all: the
                        // dialog closed, the family stayed, and the reason sat
                        // in `session.lastError` where no screen read it. A
                        // refusal that looks like nothing happening is the
                        // worst possible answer to a deliberate act.
                        failure = Failure(
                            title: "Perheestä ei voitu poistua",
                            message: session.lastError
                                ?? "Yritä uudelleen, kun verkkoyhteys toimii."
                        )
                        return
                    }
                    // The memories stay on this device — leaving the family is
                    // not losing your own copy. Only the sync cursor goes, so
                    // that the next family is not read through this one's
                    // numbering.
                    store.resetSyncCursor()
                }
            }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("Et enää näe perheen uusia muistoja etkä voi kertoa niitä. Kertomasi muistot jäävät perheelle.")
        }
        .confirmationDialog(
            "Tyhjennetäänkö tämä laite?",
            isPresented: $isConfirmingWipe,
            titleVisibility: .visible
        ) {
            // The way out, above the way through. The warning has always told
            // somebody with no other copy to export first, and then offered
            // them one button that empties the device — an instruction to go
            // and do something else, in a dialog whose only action is the
            // irreversible one. Prevention beats a well-worded warning, and on
            // a single-device archive this is the tap that ends the archive.
            if !canLeave {
                Button("Vie arkisto ensin") {
                    Task { await export() }
                }
            }

            Button("Tyhjennä", role: .destructive) {
                Task { await wipe() }
            }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text(wipeWarning)
        }
        .sheet(isPresented: $isSharing) {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Tallenna tai lähetä arkisto", systemImage: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .elderTapTarget()
                }
                .presentationDetents([.medium])
                .padding(Elder.screenPadding)
            }
        }
        .alert(item: $failure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.message),
                dismissButton: .default(Text("Selvä"))
            )
        }
        // Before the share sheet, not after: once the zip has left, nobody is
        // going to open it against a checklist. "Jaa silti" is the ordinary
        // answer — the files are safe in the family's archive either way, and
        // the page inside the zip says the same thing this does.
        .alert("Viennistä puuttuu tiedostoja", isPresented: $isReportingMissing) {
            Button("Jaa silti") { isSharing = true }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text(
                missingFromExport == 1
                    ? "Yksi kuva tai äänitys ei ollut saatavilla — todennäköisesti verkkoyhteyttä ei juuri nyt ole. Se on tallessa perheen arkistossa."
                    : "\(missingFromExport) kuvaa tai äänitystä ei ollut saatavilla — todennäköisesti verkkoyhteyttä ei juuri nyt ole. Ne ovat tallessa perheen arkistossa."
            )
        }
    }

    private func export() async {
        isExporting = true
        exportStatus = nil
        defer { isExporting = false }
        do {
            let export = try await ArchiveExport.build(store: store, session: session) { status in
                exportStatus = status
            }
            exportURL = export.zip
            missingFromExport = export.missingMedia
            if export.missingMedia > 0 {
                isReportingMissing = true
            } else {
                isSharing = true
            }
            #if DEBUG
            let size = (try? FileManager.default.attributesOfItem(atPath: export.zip.path)[.size]) ?? 0
            print("[export] wrote \(export.zip.path) (\(size) bytes, \(export.missingMedia) missing)")
            #endif
        } catch {
            failure = Failure(
                title: "Arkiston vienti ei onnistunut",
                message: "Yritä uudelleen. Jos vika toistuu, laitteessa voi olla tila lopussa."
            )
        }
    }

    private func wipe() async {
        // Leaving happens first and on the server: a wipe that left the
        // membership behind would keep this device's name in the family list
        // for good, and the invite links it made would stay alive.
        //
        // First AND decisive. The result used to be discarded, and a failed
        // leave — offline, or the server refusing — then wiped the store and
        // renewed the Keychain identity anyway: the member row stayed in the
        // family forever with nobody left who could authenticate as it, its
        // ghost counted against the last-member check, and the invites it
        // made stayed alive. The comment above described the exact invariant
        // the discard was violating.
        if canLeave {
            guard await session.leaveFamily() else {
                failure = Failure(
                    title: "Perheestä ei voitu poistua",
                    message: session.lastError
                        ?? "Yritä uudelleen, kun verkkoyhteys toimii. Laitetta ei tyhjennetty."
                )
                return
            }
        } else if case .inFamily = session.mode {
            // The last copy cannot leave — the server refuses the last member
            // — but the invites must not outlive it: the invitation text
            // carries the family key, so a live code is join-and-read access
            // to an archive whose dialog just said it is gone. Best effort,
            // never blocking: this wipe is a device-local right, and an
            // offline phone must still be emptiable.
            for invite in session.family?.invites ?? [] {
                _ = await session.revokeInvite(code: invite.code)
            }
        }
        store.wipe()
        // The ladder describes whoever holds the phone, so it goes too — and so
        // does the tally of recordings this device gave up on transcribing.
        // Both are counts about the person and the phone, not about the family,
        // and both would otherwise outlive the archive they refer to.
        QuestionLadder.reset()
        UpsellRhythm.reset()
        TranscriptionAttempts.reset()
        // What this phone has seen of the family's tellings goes the same way:
        // a record about the person holding the phone, not about the family.
        NewFromFamily.reset()
        // Last, because it is what makes the wipe stick: with the old identity
        // the next sync would pull the whole archive straight back.
        session.renewIdentity()
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
            .environment(MemoryStore(filename: "preview-store.json"))
            .environment(Session())
    }
}
