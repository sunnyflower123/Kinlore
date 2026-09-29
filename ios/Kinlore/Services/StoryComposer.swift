import Foundation

/// Where a card's story comes from, and when it is asked for
/// (ARCHITECTURE §27).
///
/// The story is what a card reads as — one text composed from everything
/// told about it — and the tellings under it stay the product (rule 3). A
/// `StoryComposer` writes the text; `StoryPlan` decides whether to ask for
/// one at all, and it is the half that costs money: one telling is one
/// model call, and a card whose tellings have not changed is never
/// composed twice. Foundation only, so `scripts/story-check.swift` can
/// compile it beside the models and drive every rule without the app.
protocol StoryComposer {
    func compose(_ request: StoryRequest) async throws -> String
}

/// What the Worker is told (`POST /story`, `backend/src/story.ts`). The
/// tellings cross in the clear — the model has to read them — under the
/// same consent sentence as a colouring, and never a word more than the
/// card holds: no ids, no member ids, no other card.
struct StoryRequest: Encodable, Equatable {
    /// Which prompt runs: the language of the phone composing
    /// (`SpokenLanguage.current`), decided once, when the story is composed.
    /// The transcription's rule — the prompt follows who is speaking — has
    /// no one speaker to follow here: three tellers may have told in two
    /// languages, and a `Memory` does not record which. So the tellings
    /// cross verbatim in whatever language they were told, the prompt keeps
    /// each teller's words (its rule 5), and the frame — *kertoo, että* — is
    /// this phone's. A phone in another language that finds a story reading
    /// every telling asks for nothing (`StoryPlan`), so a story's language
    /// never flips on its own; a person's edit is in whatever they wrote.
    var lang: String
    var kind: String
    var title: String?
    var date: String?
    var mentions: [Mention]
    var memories: [Telling]
    /// A story a person corrected, when the request is for a continuation
    /// to be read after it rather than for a story. Nil asks for a story.
    var soFar: String?

    /// A name the family has confirmed, and only such a name: the prompt
    /// may use it as it is, and says any other name it meets in a telling
    /// through the teller. An unconfirmed name never leaves the phone — not
    /// as a mention, not as a flag on one — because a name the model is
    /// never handed is a name it cannot state as fact (rule 4). No
    /// relationship crosses either: the request has no field for one.
    struct Mention: Encodable, Equatable {
        var name: String
        var kind: String
    }

    struct Telling: Encodable, Equatable {
        /// Empty when the teller asked not to be named; the Worker says
        /// "Kertoja" or "Teller" for it.
        var teller: String
        var told: String
        var source: String
        var text: String
    }

    /// One card's request. `tellerNames` is what each telling's byline says
    /// (`MemoryStore.byline(for:)`), keyed by memory id; a telling with no
    /// entry is a teller who asked not to be named.
    init(
        subject: Subject,
        memories: [Memory],
        tellerNames: [String: String],
        mentions: [Subject],
        lang: String,
        soFar: String? = nil,
        zone: TimeZone = DateHint.zone
    ) {
        self.lang = lang
        kind = subject.kind.rawValue
        title = subject.title.isEmpty ? nil : subject.title
        date = subject.dateHint.flatMap { $0.precision == .unknown ? nil : $0.displayText }
        self.mentions = mentions.filter(\.confirmed).map {
            Mention(name: $0.displayTitle, kind: $0.kind.rawValue)
        }
        let told = DateFormatter()
        told.locale = Locale(identifier: "en_US_POSIX")
        told.timeZone = zone
        // The date the way the measured prompt saw it: 14.6.2025 in Finnish,
        // 2026-09-15 in English (`scripts/story-bench.mjs`).
        told.dateFormat = lang == "en" ? "yyyy-MM-dd" : "d.M.yyyy"
        self.memories = memories.map { memory in
            Telling(
                teller: tellerNames[memory.id] ?? "",
                told: told.string(from: memory.createdAt),
                source: memory.source.rawValue,
                text: memory.body.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        self.soFar = soFar
    }
}

enum StoryComposeFailure: Error {
    case unavailable
    /// The family's server has no `/story`: a Worker deployed before the
    /// story card. Not a failure to say on the card — nothing went wrong, and
    /// nothing will go right by trying again until the server is updated.
    case notOffered
}

/// `-story stub`, for the UI tests: each telling as its teller's word, in
/// the language asked for, after a short wait so that a screen shows its
/// composing state. No model, no network.
struct StubStoryComposer: StoryComposer {
    func compose(_ request: StoryRequest) async throws -> String {
        try await Task.sleep(for: .milliseconds(400))
        let paragraphs = request.memories.map { telling -> String in
            let teller = telling.teller.isEmpty ? (request.lang == "en" ? "Teller" : "Kertoja") : telling.teller
            let text = Self.lowercasingFirst(telling.text)
            return request.lang == "en" ? "\(teller) says that \(text)" : "\(teller) kertoo, että \(text)"
        }
        return paragraphs.joined(separator: "\n\n")
    }

    static func lowercasingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}

/// `-story fail`: every composition fails the way a Worker that is down
/// fails, so the card's failure note can be reached and audited.
struct FailingStoryComposer: StoryComposer {
    func compose(_ request: StoryRequest) async throws -> String {
        try await Task.sleep(for: .milliseconds(200))
        throw StoryComposeFailure.unavailable
    }
}

/// `-story missing`: the answer of a Worker deployed before the story card,
/// which knows no `/story` and says 404 (`RemoteStoryComposer`), so the card
/// a phone shows against such a server can be reached and audited.
struct MissingStoryComposer: StoryComposer {
    func compose(_ request: StoryRequest) async throws -> String {
        try await Task.sleep(for: .milliseconds(200))
        throw StoryComposeFailure.notOffered
    }
}

// MARK: - When to compose

/// What a card should do about its story now, from what it holds.
///
/// Read on every appearance of the card and after every change to its
/// tellings or its story, and cheap enough to be: it is set arithmetic over
/// ids. Only `compose` and `propose` cost a model call, and each is asked
/// for once per change in the set of live tellings — the ids the story was
/// composed from are kept on it for exactly this comparison.
enum StoryPlan: Equatable {
    /// The story is what the tellings say, or there is nothing to say.
    case nothing
    /// Every telling the story was composed from is gone: the story goes.
    case clear
    /// A proposal whose tellings are gone, or that has been answered by a
    /// change to the story: dropped, without a model call.
    case dropProposal
    /// Compose the story from these tellings, oldest first.
    case compose([Memory])
    /// The story was corrected by hand and these tellings came after: ask
    /// for a continuation to be read after it, and show it as a proposal.
    case propose([Memory], toStory: String)

    /// The tellings a story can be made of: not taken back, transcribed,
    /// with words in them; oldest first, which is the order the prompt
    /// reads them in.
    static func live(_ memories: [Memory]) -> [Memory] {
        memories
            .filter { $0.deletedAt == nil && !$0.isAwaitingTranscription }
            .filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func plan(story: Story?, memories: [Memory]) -> StoryPlan {
        let live = Self.live(memories)
        let liveIDs = Set(live.map(\.id))
        guard let story, !story.text.isEmpty else {
            return live.isEmpty ? .nothing : .compose(live)
        }
        if story.isEdited {
            // A telling taken back from under a person's story is not the
            // plan's to answer: the card reports it (`Story.takenBack`) and
            // a person decides. Only what came after the edit is looked at.
            let new = live.filter { !story.composedFrom.contains($0.id) }
            if new.isEmpty { return story.proposal == nil ? .nothing : .dropProposal }
            if let proposal = story.proposal, Set(proposal.from) == Set(new.map(\.id)) { return .nothing }
            return .propose(new, toStory: story.text)
        }
        if live.isEmpty { return .clear }
        return Set(story.composedFrom) == liveIDs ? .nothing : .compose(live)
    }
}

// MARK: - The story's transitions

extension Story {
    /// Composed by the model from these tellings: a new story, unedited.
    static func composed(_ text: String, from memories: [Memory], at now: Date = .now) -> Story {
        Story(text: text, composedFrom: memories.map(\.id), composedAt: now)
    }

    /// A person's reading of the story. From here on the model proposes and
    /// never writes. Everything live that is not waiting in a proposal
    /// counts as read — a story written over a cleared one would otherwise
    /// be followed by a proposal repeating what the writer had just read.
    func edited(to text: String, live: [Memory], now: Date = .now) -> Story {
        var next = self
        next.text = text
        next.editedAt = Story.moment(now)
        let pending = Set(proposal?.from ?? [])
        let read = live.map(\.id).filter { !pending.contains($0) && !composedFrom.contains($0) }
        next.composedFrom += read
        return next
    }

    /// The model's continuation, held under the story until somebody says.
    func proposing(_ text: String, from memories: [Memory], at now: Date = .now) -> Story {
        var next = self
        next.proposal = StoryProposal(text: text, from: memories.map(\.id), at: now)
        return next
    }

    /// Appended after the story as its own paragraph, by a person: the
    /// story stays theirs, so `editedAt` moves.
    func accepting(now: Date = .now) -> Story {
        guard let proposal else { return self }
        var next = self
        next.text = text + "\n\n" + proposal.text
        next.composedFrom += proposal.from
        next.editedAt = Story.moment(now)
        next.proposal = nil
        return next
    }

    /// Left out, and not asked about again: the tellings count as read.
    func dismissing() -> Story {
        guard let proposal else { return self }
        var next = self
        next.composedFrom += proposal.from
        next.proposal = nil
        return next
    }

    /// The tellings the story reads that are no longer on the card — taken
    /// back after it was composed or edited. Under a composed story
    /// `StoryPlan` composes again from what is left; under a person's story
    /// nothing happens by itself, and the card says so and asks: keep the
    /// story as it is, or have it composed again from what is left, which
    /// loses the person's words. Rule 4's shape once more — the app does
    /// not decide what a person's text is worth without a telling under it.
    func takenBack(live: [Memory]) -> [String] {
        let liveIDs = Set(live.map(\.id))
        return composedFrom.filter { !liveIDs.contains($0) }
    }

    /// Kept as it is: the words stay, the story stays the person's, and the
    /// tellings that are gone are no longer counted, so the card stops
    /// asking.
    func keeping(live: [Memory]) -> Story {
        let liveIDs = Set(live.map(\.id))
        var next = self
        next.composedFrom = composedFrom.filter { liveIDs.contains($0) }
        return next
    }
}
