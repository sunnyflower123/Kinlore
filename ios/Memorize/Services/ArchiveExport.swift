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
    ) async throws -> URL {
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

        let subjectsWithPhotos = store.subjects.filter {
            $0.deletedAt == nil && ($0.imageFilename != nil || $0.r2Key != nil)
        }
        for (index, subject) in subjectsWithPhotos.enumerated() {
            progress("Kootaan kuvia \(index + 1)/\(subjectsWithPhotos.count)")
            guard let filename = await MediaLoader.imageFilename(
                for: subject, store: store, session: session
            ) else { continue }
            if copy(filename, into: photos) { photoNames[subject.id] = filename }
        }

        let memoriesWithAudio = store.memories.filter {
            $0.audioFilename != nil || $0.audioR2Key != nil
        }
        for (index, memory) in memoriesWithAudio.enumerated() {
            progress("Kootaan ääniä \(index + 1)/\(memoriesWithAudio.count)")
            guard let filename = await MediaLoader.audioFilename(
                for: memory, store: store, session: session
            ) else { continue }
            if copy(filename, into: audio) { audioNames[memory.id] = filename }
        }

        progress("Kirjoitetaan arkistoa")
        let page = html(store: store, photoNames: photoNames, audioNames: audioNames)
        try Data(page.utf8).write(to: root.appendingPathComponent("muistot.html"))
        try store.exportJSON().write(to: root.appendingPathComponent("arkisto.json"))

        progress("Pakataan")
        return try zip(root)
    }

    /// Copies a media file into the export. A missing file is skipped rather
    /// than fatal: one photo that failed to download must not cost the family
    /// the other two hundred.
    private static func copy(_ filename: String, into directory: URL) -> Bool {
        let source = MediaStore.url(for: filename)
        let destination = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: source.path) else { return false }
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Zipping

    /// Zips a directory without adding a dependency.
    ///
    /// `NSFileCoordinator` with `.forUploading` hands back a zipped copy of the
    /// directory — the same mechanism the share sheet uses for a folder. The
    /// copy is only valid inside the block, so it is copied out before the
    /// block returns.
    private static func zip(_ folder: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(folder.lastPathComponent).zip")
        try? FileManager.default.removeItem(at: destination)

        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: folder,
            options: [.forUploading],
            error: &coordinatorError
        ) { zipped in
            do {
                try FileManager.default.copyItem(at: zipped, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        return destination
    }

    // MARK: - The readable page

    /// One HTML file, because a browser is the one program every family already
    /// has. The photographs are inline and the audio plays, without this app and
    /// without a network.
    private static func html(
        store: MemoryStore,
        photoNames: [String: String],
        audioNames: [String: String]
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
        <h1>Muistoarkisto</h1>

        """

        out += "<p class=\"meta\">Viety \(dateText(.now)). Äänitiedostot ovat kansiossa "
        out += "<code>aani</code> ja kuvat kansiossa <code>kuvat</code>. "
        out += "Tiedosto <code>arkisto.json</code> sisältää kaiken koneluettavassa muodossa.</p>\n"

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
                    out += "<p class=\"pending\">Ääni tallessa, tekstiä ei ehditty kirjoittaa.</p>\n"
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
                out += "<p class=\"open\"><strong>Vielä kysymättä</strong></p>\n<ul class=\"open\">\n"
                for question in open {
                    out += "<li>\(escaped(question.text))</li>\n"
                }
                out += "</ul>\n"
            }
        }

        if !empty.isEmpty {
            out += "<h2>Ilman muistoja</h2>\n"
            out += "<p class=\"open\">Näistä ei ole vielä kerrottu mitään: "
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
        if let parents = names(.parentOf) { lines.append("Vanhemmat: \(parents)") }
        if let children = names(.parentOf, asParent: true) { lines.append("Lapset: \(children)") }
        if let spouse = names(.spouseOf) { lines.append("Puoliso: \(spouse)") }
        if let siblings = names(.siblingOf) { lines.append("Sisarukset: \(siblings)") }
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
