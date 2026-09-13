import Foundation

/// Taking the archive out of the app.
///
/// The promise this keeps is the one the whole product rests on: what the family
/// told is theirs, and it survives this app, this phone and this Worker. So the
/// export is not a data dump but something a person can open — one zip holding a
/// readable page, the original photographs and the original audio.
///
/// See docs/ARCHITECTURE.md §14.
@MainActor
enum ArchiveExport {
    /// What the build produced — and what it could not.
    ///
    /// `missingMedia` counts the photographs and recordings that were skipped
    /// because they could not be fetched or copied. The skip itself is right
    /// (one failed download must not cost the family the other two hundred
    /// files); the count exists because the skip used to be silent, and an
    /// offline export looked complete while missing grandmother's voice — in
    /// the one artifact meant to outlive the app. The caller says the number
    /// out loud, and the page carries it too.
    struct Export {
        let zip: URL
        let missingMedia: Int
    }

    /// `Muistoarkisto-2026-09-05.zip`. The date, so that the copy a family
    /// makes every year does not write over the last one in the folder it
    /// keeps them in (founder's-eye review, finding #88). ISO order, because
    /// the folder sorts it and no locale is asked.
    static func zipName(for date: Date) -> String {
        "Muistoarkisto-\(date.formatted(.iso8601.year().month().day())).zip"
    }

    /// Builds the zip and returns its location in the temporary directory. The
    /// caller hands it to the share sheet; the system cleans it up afterwards.
    ///
    /// `progress` is called with a line of Finnish for the screen. Fetching a
    /// family's audio out of R2 takes long enough that silence would look like a
    /// hang.
    static func build(
        store: MemoryStore,
        session: Session,
        progress: (String) -> Void
    ) async throws -> Export {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Muistoarkisto", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let photos = root.appendingPathComponent("kuvat", isDirectory: true)
        let audio = root.appendingPathComponent("aani", isDirectory: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)

        // Media that only exists as an R2 key is fetched first. A phone that
        // joined last week holds keys, not files, and an export missing
        // grandmother's voice would be a lie about what the word means.
        var photoNames: [String: String] = [:]
        var audioNames: [String: String] = [:]
        var missing = 0

        let subjectsWithPhotos = store.subjects.filter {
            $0.deletedAt == nil && ($0.imageFilename != nil || $0.r2Key != nil)
        }
        for (index, subject) in subjectsWithPhotos.enumerated() {
            // "Peruuta" on the Settings row cancels the task; the half-built
            // folder is removed by the next build.
            try Task.checkCancellation()
            progress(String(localized: "Kootaan kuvia \(index + 1)/\(subjectsWithPhotos.count)"))
            guard let filename = await MediaLoader.imageFilename(
                for: subject, store: store, session: session
            ) else {
                missing += 1
                continue
            }
            if link(filename, into: photos) {
                photoNames[subject.id] = filename
            } else {
                missing += 1
            }
        }

        // `told`: the export is what the family opens in twenty years, not a
        // dump of the table. A recording the teller took back does not travel
        // into it.
        let memoriesWithAudio = store.told.filter {
            $0.audioFilename != nil || $0.audioR2Key != nil
        }
        for (index, memory) in memoriesWithAudio.enumerated() {
            try Task.checkCancellation()
            progress(String(localized: "Kootaan ääniä \(index + 1)/\(memoriesWithAudio.count)"))
            guard let filename = await MediaLoader.audioFilename(
                for: memory, store: store, session: session
            ) else {
                missing += 1
                continue
            }
            if link(filename, into: audio) {
                audioNames[memory.id] = filename
            } else {
                missing += 1
            }
        }

        // The colours the family confirmed, beside the photographs they colour.
        // Each carries its palette in its own pixels, and the page says whose
        // word the colours stand on.
        var colourNames: [String: String] = [:]
        let subjectsWithColours = store.subjects.filter {
            $0.deletedAt == nil && ($0.colourImageFilename != nil || $0.colourR2Key != nil)
        }
        for (index, subject) in subjectsWithColours.enumerated() {
            try Task.checkCancellation()
            progress(String(localized: "Kootaan värikuvia \(index + 1)/\(subjectsWithColours.count)"))
            guard let filename = await MediaLoader.colourFilename(
                for: subject, store: store, session: session
            ) else {
                missing += 1
                continue
            }
            if link(filename, into: photos) {
                colourNames[subject.id] = filename
            } else {
                missing += 1
            }
        }

        progress(String(localized: "Kirjoitetaan arkistoa"))
        let page = html(
            store: store,
            photoNames: photoNames,
            colourNames: colourNames,
            audioNames: audioNames,
            missingMedia: missing
        )
        try Data(page.utf8).write(to: root.appendingPathComponent("muistot.html"))
        try store.exportJSON().write(to: root.appendingPathComponent("arkisto.json"))

        progress(String(localized: "Pakataan"))
        try Task.checkCancellation()
        // Off the main actor: zipping a family's gigabyte takes as long as it
        // takes, and the screen showing "Pakataan" has to keep drawing it.
        let name = zipName(for: .now)
        let zip = try await Task.detached(priority: .userInitiated) {
            try Self.zip(root, named: name)
        }.value
        return Export(zip: zip, missingMedia: missing)
    }

    /// Puts a media file into the export without copying its bytes.
    ///
    /// A hard link costs nothing and takes no room — the export folder and the
    /// media store are on the same volume — and the zip reads the bytes
    /// through it. Until 5 Sep 2026 this was a copy: for a family's archive of
    /// a gigabyte, a second gigabyte on the phone before the zip took a third,
    /// on the old phone least able to spare it (founder's-eye review, finding
    /// #88). A volume that will not link still gets its copy. A missing file
    /// is skipped rather than fatal: one photo that failed to download must
    /// not cost the family the other two hundred.
    private static func link(_ filename: String, into directory: URL) -> Bool {
        let source = MediaStore.url(for: filename)
        let destination = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: source.path) else { return false }
        try? FileManager.default.removeItem(at: destination)
        if (try? FileManager.default.linkItem(at: source, to: destination)) != nil { return true }
        return (try? FileManager.default.copyItem(at: source, to: destination)) != nil
    }

    // MARK: - Zipping

    /// Zips a directory without adding a dependency.
    ///
    /// `NSFileCoordinator` with `.forUploading` hands back a zipped copy of the
    /// directory — the same mechanism the share sheet uses for a folder. The
    /// zip is only valid inside the block, so it is **moved** out before the
    /// block returns — moved and not copied, because for a gigabyte the copy
    /// was a second gigabyte of temporary space on the phone. A move that
    /// fails falls back to the copy.
    nonisolated private static func zip(_ folder: URL, named name: String) throws -> URL {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)

        var coordinatorError: NSError?
        var moveError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: folder,
            options: [.forUploading],
            error: &coordinatorError
        ) { zipped in
            do {
                try FileManager.default.moveItem(at: zipped, to: destination)
            } catch {
                do {
                    try FileManager.default.copyItem(at: zipped, to: destination)
                } catch {
                    moveError = error
                }
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let moveError { throw moveError }
        return destination
    }

    // MARK: - The readable page

    /// One HTML file, because a browser is the one program every family already
    /// has. The photographs are inline and the audio plays, without this app and
    /// without a network.
    private static func html(
        store: MemoryStore,
        photoNames: [String: String],
        colourNames: [String: String],
        audioNames: [String: String],
        missingMedia: Int
    ) -> String {
        // Ordered the way the app lists them, and only subjects somebody has
        // actually spoken about. The empty ones are named at the end rather than
        // dropped: a gap is shown, not hidden.
        // Neither a merged subject nor a rejected one. The rejected half is the
        // one worth naming: the archive is the copy that outlives the app, and
        // writing somebody the family threw out into it as though they were a
        // relative is the one place that mistake could never be taken back.
        let subjects = store.subjects
            .filter { $0.mergedInto == nil && $0.deletedAt == nil }
            .sorted { ($0.kind.sortOrder, $0.title) < ($1.kind.sortOrder, $1.title) }

        var out = """
        <!doctype html>
        <html lang="fi">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Muistoarkisto</title>
        <style>
        body { font-family: -apple-system, Georgia, serif; line-height: 1.6; max-width: 46rem;
               margin: 0 auto; padding: 2rem 1.25rem; color: #2b2723; background: #fbf8f3; }
        h1 { font-size: 2rem; }
        h2 { margin-top: 3rem; border-bottom: 1px solid #ded5c8; padding-bottom: .3rem; }
        .meta { color: #6f665c; font-size: .9rem; margin-top: -.6rem; }
        img { max-width: 100%; border-radius: .5rem; }
        article { background: #fff; border-radius: .75rem; padding: 1rem 1.25rem; margin: 1rem 0; }
        .byline { color: #6f665c; font-size: .9rem; }
        .pending { color: #6f665c; font-style: italic; }
        .open { color: #6f665c; }
        audio { width: 100%; margin-top: .5rem; }
        </style>
        </head>
        <body>
        <h1>\(String(localized: "Muistoarkisto"))</h1>

        """

        out += "<p class=\"meta\">"
        out += String(localized: "Viety \(dateText(.now)).")
        out += String(localized: " Äänitiedostot ovat kansiossa <code>aani</code> ja kuvat kansiossa <code>kuvat</code>. Tiedosto <code>arkisto.json</code> sisältää kaiken koneluettavassa muodossa.")
        out += "</p>\n"

        // The page says what it is missing. A zip built offline used to look
        // complete while the originals had been silently skipped — and this
        // page is the copy that outlives the app, so a gap it does not name
        // is a gap nobody will ever know to fill.
        // Two whole sentences rather than a shared tail: the tail's verb has
        // a number, and "Se on … ja tulevat" is not Finnish. Nor does the
        // sentence name the family's archive — on a single-phone archive
        // there is none, and a promise about where the files are must be
        // true in both modes.
        if missingMedia > 0 {
            out += "<p class=\"meta\"><strong>\(String(localized: "Huom:"))</strong> "
            out += missingMedia == 1
                ? String(localized: "Yksi kuva tai äänitys ei ollut saatavilla, kun tämä arkisto vietiin. Se on tallessa ja tulee mukaan seuraavaan vientiin.")
                : String(localized: "\(missingMedia) kuvaa tai äänitystä ei ollut saatavilla, kun tämä arkisto vietiin. Ne ovat tallessa ja tulevat mukaan seuraavaan vientiin.")
            out += "</p>\n"
        }

        var empty: [Subject] = []

        for subject in subjects {
            let memories = store.memories(for: subject.id)
            guard !memories.isEmpty else {
                empty.append(subject)
                continue
            }

            out += "<h2>\(escaped(subject.displayTitle))</h2>\n"

            var meta = [subject.kind.label]
            if let hint = subject.dateHint, hint.precision != .unknown {
                meta.append(hint.displayText)
            }
            out += "<p class=\"meta\">\(escaped(meta.joined(separator: " · ")))</p>\n"

            if let filename = photoNames[subject.id] {
                out += "<img src=\"kuvat/\(escaped(filename))\" alt=\"\(escaped(subject.displayTitle))\">\n"
            }
            // Under the photograph and never in its place, captioned with whose
            // word the colours stand on. The palette is in the image itself.
            if let filename = colourNames[subject.id] {
                let caption = subject.colourConfirmedByName.map {
                    String(localized: "Värit kerronnan mukaan, vahvisti \($0)")
                } ?? String(localized: "Värit kerronnan mukaan")
                let described = String(localized: "Väritetty kuva. Värit ovat tekoälyn arvaus kerrotun mukaan.")
                out += "<figure><img src=\"kuvat/\(escaped(filename))\" alt=\"\(escaped(described))\">"
                out += "<figcaption class=\"meta\">\(escaped(caption))</figcaption></figure>\n"
            }

            // Confirmed relationships only. An unconfirmed one is a proposal,
            // and a proposal written into an archive as fact is exactly the
            // error rule 4 exists to prevent.
            if subject.kind == .person {
                let lines = relationLines(for: subject, store: store)
                if !lines.isEmpty {
                    out += "<p class=\"meta\">\(escaped(lines.joined(separator: " · ")))</p>\n"
                }
            }

            for memory in memories {
                out += "<article>\n"
                if memory.isAwaitingTranscription {
                    // Only claim the recording is here when it is: a memory
                    // whose audio could not be fetched used to assert "Ääni
                    // tallessa" over an <audio> element that never came.
                    out += audioNames[memory.id] != nil
                        ? "<p class=\"pending\">\(String(localized: "Ääni tallessa, tekstiä ei ole vielä kirjoitettu."))</p>\n"
                        : "<p class=\"pending\">\(String(localized: "Ääni on tallessa, mutta ei ollut saatavilla tähän vientiin."))</p>\n"
                } else {
                    for paragraph in memory.body.components(separatedBy: "\n") where !paragraph.isEmpty {
                        out += "<p>\(escaped(paragraph))</p>\n"
                    }
                }
                if let filename = audioNames[memory.id] {
                    out += "<audio controls src=\"aani/\(escaped(filename))\"></audio>\n"
                }
                out += "<p class=\"byline\">\(escaped(memory.authorName)) · \(dateText(memory.createdAt))</p>\n"
                out += "</article>\n"
            }

            // A list rather than a run-on paragraph: a long interview leaves
            // dozens of these behind, and joined into one sentence they are a
            // wall of text nobody reads.
            let open = store.questions.filter { $0.subjectID == subject.id && !$0.answered }
            if !open.isEmpty {
                out += "<p class=\"open\"><strong>\(String(localized: "Vielä kysymättä"))</strong></p>\n<ul class=\"open\">\n"
                for question in open {
                    out += "<li>\(escaped(question.text))</li>\n"
                }
                out += "</ul>\n"
            }
        }

        if !empty.isEmpty {
            out += "<h2>\(String(localized: "Ilman muistoja"))</h2>\n"
            out += "<p class=\"open\">\(String(localized: "Näistä ei ole vielä kerrottu mitään:")) "
            out += escaped(empty.map(\.displayTitle).joined(separator: ", "))
            out += ".</p>\n"
        }

        out += "</body>\n</html>\n"
        return out
    }

    private static func relationLines(for subject: Subject, store: MemoryStore) -> [String] {
        func names(_ kind: RelationKind, asParent: Bool = false) -> String? {
            let people = store.relatives(of: subject.id, kind: kind, asParent: asParent)
                .filter { store.relation(between: $0.id, and: subject.id, kind: kind)?.confirmed ?? false
                    || store.relation(between: subject.id, and: $0.id, kind: kind)?.confirmed ?? false }
            return people.isEmpty ? nil : people.map(\.displayTitle).joined(separator: ", ")
        }

        var lines: [String] = []
        if let parents = names(.parentOf) { lines.append(String(localized: "Vanhemmat: \(parents)")) }
        if let children = names(.parentOf, asParent: true) { lines.append(String(localized: "Lapset: \(children)")) }
        if let spouse = names(.spouseOf) { lines.append(String(localized: "Puoliso: \(spouse)")) }
        if let siblings = names(.siblingOf) { lines.append(String(localized: "Sisarukset: \(siblings)")) }
        return lines
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fi_FI")
        formatter.dateFormat = "d.M.yyyy"
        return formatter.string(from: date)
    }

    /// A memory can contain anything a person said, including the characters
    /// that would otherwise end the document early.
    private static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private extension SubjectKind {
    /// Photos first, then people: the order the family thinks in, not the
    /// alphabet's.
    var sortOrder: Int {
        switch self {
        case .photo: 0
        case .person: 1
        case .place: 2
        case .event: 3
        }
    }
}
