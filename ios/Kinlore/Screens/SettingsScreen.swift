import SwiftUI

/// Export, leaving the family, and emptying this device.
///
/// Everything here is rare and some of it cannot be undone, which is why it sits
/// behind a gear rather than in the way. See docs/ARCHITECTURE.md §14.
struct SettingsScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(SyncEngine.self) private var sync: SyncEngine?

    @State private var exportURL: URL?
    @State private var exportStatus: String?
    @State private var isExporting = false
    /// The running export, so that "Peruuta" beside the progress can end it.
    @State private var exportTask: Task<Void, Never>?
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

    /// Photographs and recordings the family has that are not on this phone —
    /// they exist only on the server, and after a wipe nothing can open them:
    /// the identity and the key go with the store. `FullCopy` counts them.
    private var missingLocally: Int {
        guard let progress = sync?.fullCopy.progress else { return 0 }
        return max(0, progress.total - progress.have)
    }

    /// What emptying this device actually costs, which depends entirely on
    /// whether anyone else has a copy — and, for the last copy of a shared
    /// family, on the invites: the invitation text carries the family key, so
    /// a live code is join-and-read access to the archive this sentence just
    /// called gone. The wipe revokes them, and the sentence says so.
    ///
    /// And on what the phone actually holds. The last copy's warning said "vie
    /// arkisto ensin" while the export at a cottage had just fetched nothing
    /// and reassured that the files would come along next time — and there is
    /// no next time after the wipe forgets the key (founder's-eye review,
    /// finding #43). Now the sentence carries the number of files that are
    /// only on the server, and the button says "silti".
    private var wipeWarning: String {
        // Every branch ends on the same sentence, and it is the one nothing
        // said before: the app does not come back to an emptied version of this
        // screen, it comes back to its first. That is what makes this the way
        // to walk the whole thing again, and it was invisible.
        let afterwards = String(localized: " Sovellus avautuu ensimmäiselle näytölle.")
        // A device the server has stopped knowing cannot leave — the same
        // server refuses it — and until 5 Sep 2026 that meant it could not be
        // emptied either: the wipe stops on a failed leave. There is nothing
        // to leave; the wipe says so and goes ahead.
        if canLeave, sync?.state == .refused {
            return String(localized: "Palvelin ei enää tunnista tätä puhelinta, joten perheestä ei voi poistua: muistot poistetaan vain tästä laitteesta. Perheen muistot säilyvät muilla.")
                + afterwards
        }
        if canLeave {
            return String(localized: "Poistut perheestä ja tämän laitteen muistot poistetaan. Perheen muistot säilyvät muilla.")
                + afterwards
        }
        if case .inFamily = session.mode {
            if missingLocally > 0 {
                return String(localized: "Tällä puhelimella ei ole kaikkia perheen kuvia ja ääniä: \(missingLocally) on vain palvelimella, eikä tyhjennyksen jälkeen niitä saa enää auki. Odota, että Perhe-näytön kopio on valmis, tai vie arkisto verkossa ensin.")
                    + afterwards
            }
            // Not "poistetaan lopullisesti". The server deletes nothing — the
            // last member cannot leave, so the sealed rows and media stay for
            // good — and what actually ends here is the ability to open them:
            // the only key goes with the wipe (`renewIdentity`). Say that. The
            // weaker "poistetaan tästä puhelimesta" would be wrong the other
            // way, hiding the no-way-back that finding #43 was about.
            return String(localized: "Tämä on perheen ainoa kopio. Tyhjennyksen jälkeen muistoja ei saa enää auki mistään, ja avoimet kutsut perutaan. Vie arkisto ensin, jos haluat säilyttää ne.")
                + afterwards
        }
        return String(localized: "Muistot poistetaan lopullisesti. Vie arkisto ensin, jos haluat säilyttää ne.")
            + afterwards
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

            // The way out of the archive chosen on the first form in the app,
            // and the only row on this screen that opens something up rather
            // than taking something away. Offered only where the choice was
            // actually made: `isLocalByChoice` is false on a build with no
            // backend address, where `.needsFamily` would be a fork with
            // nothing behind either button.
            //
            // **A `Text` and not a `Label`, which is measured rather than
            // preferred.** With an icon this row failed the audit as "Text
            // clipped" and "Dynamic Type font sizes are partially
            // unsupported", in every shape it was written in: as a `Button`
            // and as a `NavigationLink`, in a section of its own and inside
            // the help row's, with a header, with a footer, high on the screen
            // and low, with the label long and short, and with the same symbol
            // the help row carries. A `Label` in this `List` exposes its title
            // as a static text element of its own, 60 pt tall inside the tap
            // target, and that is the element the audit objects to; a plain
            // `Text` composes into the link's own element and passes at both
            // sizes.
            //
            // Not the row's defect, and worth saying so: swapping this row
            // with the help row above moved the identical finding onto
            // "Näin tämä toimii", which has passed every audit it has ever
            // been in. The older rows are left alone — they are green where
            // they stand, and this is a new row's problem to solve, not an
            // excuse to rewrite four that work.
            //
            // The icon is the price. The row reads plainly without one, and
            // what it leads to says the rest.
            if session.isLocalByChoice {
                Section {
                    NavigationLink(value: SharingRoute()) {
                        Text("Ota perhe käyttöön")
                            .elderTapTarget()
                    }
                }
            }

            Section {
                Button {
                    exportTask = Task { await export() }
                } label: {
                    if isExporting {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(exportStatus
                                ?? String(localized: "Kootaan arkistoa"))
                                .foregroundStyle(Elder.supporting)
                        }
                    } else {
                        Label("Vie arkisto", systemImage: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .elderTapTarget()
                    }
                }
                .disabled(isExporting)
                // A way out of a long export. A family's archive takes as long
                // to gather as it takes, and until 5 Sep 2026 the only way to
                // stop one was to leave the screen and hope.
                if isExporting {
                    Button("Peruuta", role: .cancel) {
                        exportTask?.cancel()
                    }
                    .elderTapTarget()
                }
            } header: {
                // A List styles its own headers and footers below the contrast
                // minimum. Saying the colour out loud is the only way to raise
                // it.
                Text("Arkisto")
                    .foregroundStyle(Elder.supporting)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    // First, whose copy this is. The server holds ciphertext
                    // and the key is only on the family's phones, so for one
                    // phone the export is the only copy that opens anywhere
                    // else — and the app cannot tell whether iCloud Keychain
                    // would carry the key on. Said here, beside the one act
                    // that changes it. Two `Text`s rather than a ternary: a
                    // ternary of two literals is a String, and is never looked
                    // up.
                    if case .local = session.mode {
                        Text("Arkisto on vain tällä puhelimella: viety tiedosto on sen ainoa muu kopio.")
                    } else if case .inFamily = session.mode, (session.family?.members.count ?? 0) <= 1 {
                        Text("Arkisto on vielä sinun yksin. Kunnes kutsut jonkun, viety tiedosto on ainoa kopio, jonka saa auki ilman tätä puhelinta.")
                    }
                    // Say what comes out, in the words of somebody who will
                    // open it on a computer years from now.
                    Text("Saat yhden tiedoston, jossa ovat muistot luettavana sivuna, alkuperäiset äänitteet ja kuvat. Sen voi avata millä tahansa koneella ilman tätä sovellusta.")
                    // Not here: "Viety viimeksi 5.9.2026." One more line in
                    // this footer pushed the leave section's footer to y 729
                    // and the wipe row below the fold at the default size —
                    // three audit findings and one failing test, 5 Sep 2026,
                    // the same wall §14 records for the row that was reverted
                    // on 29 Aug. This List is at its height limit.
                }
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
                    // Renamed 29 Aug 2026 from "Tyhjennä tämä laite". That
                    // name was true and half the story: what follows the
                    // emptying is a first launch — the identity is renewed with
                    // everything else, so the app has no family to return to
                    // and lands on the onboarding fork. Somebody wanting to
                    // walk the whole arc again could not tell from the old
                    // label that this was the way, and asked for a second
                    // button that would have done the identical thing.
                    //
                    // Comments elsewhere in the app still name this act by its
                    // old label; they are describing the same act. See
                    // ARCHITECTURE §14.
                    Label("Tyhjennä ja aloita alusta", systemImage: "trash")
                        .foregroundStyle(Elder.destructive)
                        .elderTapTarget()
                }
            } footer: {
                // The distinction between the two is the whole design of this
                // screen, so it is spelled out rather than implied by the names.
                Text(canLeave
                    ? String(localized: "Perheestä poistuminen ei poista kertomiasi muistoja. Ne jäävät perheen arkistoon, koska kerrottu on tarkoitettu säilymään kertojaansa pidempään.")
                    : String(localized: "Kertomasi muistot ovat vain tässä laitteessa."))
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
        // Alerts, not confirmation dialogs — here and at every other
        // confirmation in the app, since 5 Sep 2026. Measured before it was
        // changed: on iOS 26 a `confirmationDialog` attached to a list comes up
        // as a popover anchored to the list's top edge, 240 pt wide under the
        // navigation bar, and a popover adaptation draws no cancel action at
        // all. This dialog was screenshotted with "Poistu perheestä" as its
        // only button; the way out was a tap in the dimmed area beside it,
        // which nothing on screen said. The sweep's tap on "Peruuta" in
        // FamilyScreen found it; no test had ever tapped a cancel button. An
        // alert draws both buttons, and the way out is one an 80-year-old can
        // see and VoiceOver can name.
        .alert(
            "Poistutaanko perheestä?",
            isPresented: $isConfirmingLeave
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
                            title: String(localized: "Perheestä ei voitu poistua"),
                            message: session.lastError
                                ?? String(localized: "Yritä uudelleen, kun verkkoyhteys toimii.")
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
        .alert(
            "Tyhjennetäänkö tämä laite?",
            isPresented: $isConfirmingWipe
        ) {
            // The way out, above the way through. The warning has always told
            // somebody with no other copy to export first, and then offered
            // them one button that empties the device — an instruction to go
            // and do something else, in a dialog whose only action is the
            // irreversible one. Prevention beats a well-worded warning, and on
            // a single-device archive this is the tap that ends the archive.
            if !canLeave {
                Button("Vie arkisto ensin") {
                    exportTask = Task { await export() }
                }
            }

            // "Silti" when the sentence above has just said what is lost:
            // the same act, named for what it is on this phone. Two buttons
            // rather than a ternary — a ternary of literals is a String.
            if case .inFamily = session.mode, !canLeave, missingLocally > 0 {
                Button("Tyhjennä silti", role: .destructive) {
                    Task { await wipe() }
                }
            } else {
                Button("Tyhjennä", role: .destructive) {
                    Task { await wipe() }
                }
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
            // Three truths, by whose copy this is. "Tulee mukaan seuraavaan
            // vientiin" is true while somebody else holds the archive; on the
            // last copy it was the reassurance before the wipe that made it
            // false (finding #43), and on a local archive a file that is not
            // here is not anywhere. Texts, not a ternary: a ternary of
            // literals is a String and neither sentence had been looked up.
            Group {
                if canLeave {
                    if missingFromExport == 1 {
                        Text("Yksi kuva tai äänitys ei ollut saatavilla — todennäköisesti verkkoyhteyttä ei juuri nyt ole. Se on yhä tallessa perheellä ja tulee mukaan seuraavaan vientiin.")
                    } else {
                        Text("\(missingFromExport) kuvaa tai äänitystä ei ollut saatavilla — todennäköisesti verkkoyhteyttä ei juuri nyt ole. Ne ovat yhä tallessa perheellä ja tulevat mukaan seuraavaan vientiin.")
                    }
                } else if case .inFamily = session.mode {
                    if missingFromExport == 1 {
                        Text("Yksi kuva tai äänitys ei ollut saatavilla. Se on vain perheen palvelimella, joten tämä vienti ei ole täydellinen kopio. Yritä uudelleen verkossa, äläkä tyhjennä laitetta ennen sitä.")
                    } else {
                        Text("\(missingFromExport) kuvaa tai äänitystä ei ollut saatavilla. Ne ovat vain perheen palvelimella, joten tämä vienti ei ole täydellinen kopio. Yritä uudelleen verkossa, äläkä tyhjennä laitetta ennen sitä.")
                    }
                } else {
                    if missingFromExport == 1 {
                        Text("Yhtä kuvaa tai äänitystä ei löytynyt tältä puhelimelta, eikä siitä ole muuta kopiota.")
                    } else {
                        Text("\(missingFromExport) kuvaa tai äänitystä ei löytynyt tältä puhelimelta, eikä niistä ole muuta kopiota.")
                    }
                }
            }
        }
        .elderSurface()
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
        } catch is CancellationError {
            // Asked for. Nothing to report; the next build starts clean.
        } catch {
            failure = Failure(
                title: String(localized: "Arkiston vienti ei onnistunut"),
                message: String(localized: "Yritä uudelleen. Jos vika toistuu, laitteessa voi olla tila lopussa.")
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
        if canLeave, sync?.state != .refused {
            guard await session.leaveFamily() else {
                failure = Failure(
                    title: String(localized: "Perheestä ei voitu poistua"),
                    message: session.lastError
                        ?? String(localized: "Yritä uudelleen, kun verkkoyhteys toimii. Laitetta ei tyhjennetty.")
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
        // And which cards she pushed aside, for the same reason.
        Deck.reset()
        // And which faces she was asked to put a name to. A recognition is a
        // fact about the person holding the phone, so it goes with the rest of
        // what this phone knew about her.
        BlindConfirmation.reset()
        // And whose phone this is, which is asked in onboarding and was the
        // one answer that used to outlive the archive it was given for.
        Elder.forgetLargerText()
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
