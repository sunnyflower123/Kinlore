import Foundation

/// Asking who is in a photograph without saying who the app thinks it is.
///
/// Rule 4 says the AI proposes and a human confirms, and until this existed the
/// only instrument for the second half was a card with the name already written
/// on it — *"Ehdotus — vahvista henkilö"*, on the people list and at the end of
/// a telling. That card gets tapped "yes" without being read, and a wrong
/// relationship is worse than a missing one precisely because later nobody
/// remembers it was a guess.
///
/// Somebody who was never shown the name and arrived at it anyway has genuinely
/// recognised the person. That is the strongest confirmation this app can
/// collect, it was what the cut guessing round was really for
/// (ARCHITECTURE §13), and CLAUDE.md rule 4 has been carrying a sentence saying
/// so was no longer true.
///
/// **The photograph does the asking, so nothing has to be masked.** The round
/// hid a name inside a sentence, and hiding it properly was most of its cost —
/// an em dash run reads to VoiceOver as punctuation, so the card asked nothing
/// at all to the person most likely to be listening rather than looking. A
/// picture has no name in it to leak. That is why this shape is cheaper than
/// the one that was cut, and it is the whole reason it could be built at all.
@MainActor
enum BlindConfirmation {
    /// A photograph, a proposal nobody has seen, and the names to choose from.
    ///
    /// `person` is never drawn. It is the answer, and this type exists so that
    /// the screen can be handed the question without being handed it.
    struct Card: Equatable {
        let person: Subject
        let photo: Subject
        /// The proposal and its decoys, in an order that does not move.
        let names: [Subject]
    }

    /// Proposals this device has already answered, right or wrong.
    ///
    /// Device-local, like the ladder's comfort and the deck's skips — and for
    /// the same reason with a sharper edge: a recognition is a fact about the
    /// person holding the phone. Her sister should still be asked, and her
    /// sister's answer is worth as much as hers.
    static let answeredKey = "blind.answered"

    /// How many names the card puts up, and the fewest it will settle for.
    ///
    /// Four is what the round used. Three is the floor because a choice of two
    /// is a coin, and one is not a question at all — an archive with too few
    /// people simply gets no card, which is correct: there is nothing to
    /// recognise her *against*.
    static let choices = 4
    static let fewestChoices = 3

    /// At most one per session.
    ///
    /// This card asks nothing — one tap, no telling — which is exactly why it
    /// must not become what the app is. The product is memories, and a person
    /// who opens Kerro and taps through four confirmations has told nothing.
    /// One is a warm-up; the deck's own card is the point.
    ///
    /// Set by answering and never by asking. `next(in:)` is a computed property
    /// on a SwiftUI view in practice — it runs on every render — so a flag
    /// raised by the *question* would take the card off the screen one frame
    /// after it arrived, which looks exactly like a card that was never there.
    private static var answeredThisSession = false

    /// The strongest card, or nil when the archive cannot make one.
    ///
    /// Everything it needs already existed in the model. `Memory.subjectID` is
    /// what a telling is about and `mentionedSubjectIDs` is who it named, so
    /// "the photograph this name was heard in" is a join and not a new column —
    /// which is the same reason the deck needed no schema either.
    static func next(in store: MemoryStore) -> Card? {
        guard !answeredThisSession else { return nil }
        let answered = Set(UserDefaults.standard.stringArray(forKey: answeredKey) ?? [])
        let people = store.subjects(of: .person)

        for person in people where !person.confirmed && !answered.contains(person.id) {
            // The telling that named her, and the photograph it was told about.
            // A proposal heard while talking about a person rather than a
            // picture has nothing to show, and a card with no face on it is the
            // proposal row again with extra steps.
            guard let heardIn = store.memories(mentioning: person.id).first(where: {
                guard let subject = store.subject(id: $0.subjectID) else { return false }
                return subject.kind == .photo && subject.imageFilename != nil
            }),
                let photo = store.subject(id: heardIn.subjectID)
            else { continue }

            // Decoys, and never anybody the same telling also named: they may
            // be in the photograph too, and a question with two right answers
            // teaches the archive nothing about either.
            let decoys = people.filter {
                $0.confirmed
                    && $0.id != person.id
                    && !heardIn.mentionedSubjectIDs.contains($0.id)
            }
            guard decoys.count >= fewestChoices - 1 else { continue }

            let names = ([person] + decoys.prefix(choices - 1))
                .sorted { seat(person.id, $0.id) < seat(person.id, $1.id) }
            return Card(person: person, photo: photo, names: names)
        }
        return nil
    }

    /// Where a name sits on the card.
    ///
    /// Its own hash and not Swift's: `hashValue` is seeded per process, so the
    /// same card would deal its names in a different order on the next launch —
    /// and, worse, this is recomputed on every render, so anything unstable
    /// would move the buttons under a finger that is already reaching for one.
    /// Seeded by the proposal, so the answer is not in the same seat every time.
    private static func seat(_ seed: String, _ id: String) -> Int {
        var hash = 5381
        for byte in (seed + "/" + id).utf8 {
            hash = (hash &* 33 &+ Int(byte)) & 0xFF_FFFF
        }
        return hash
    }

    /// The answer, which is the whole point and is deliberately quiet.
    ///
    /// A name that matches the proposal confirms it. Anything else — a
    /// different name, or *"En muista"* — **confirms nothing and un-confirms
    /// nothing**, and the app says so by saying nothing: it does not know who
    /// is in the photograph either. Telling her she was wrong would be
    /// asserting the AI's guess as fact, which is rule 4 read backwards.
    ///
    /// Either way the proposal is marked answered. One guess per person: the
    /// second attempt is answering a question whose answer you have just been
    /// shown, and for this user a card that keeps coming back is the app
    /// insisting she failed.
    ///
    /// - Returns: whether the proposal was confirmed, so the screen can say the
    ///   one true thing it has to say.
    @discardableResult
    static func answer(_ card: Card, chose: Subject?, in store: MemoryStore) -> Bool {
        answeredThisSession = true
        var answered = UserDefaults.standard.stringArray(forKey: answeredKey) ?? []
        if !answered.contains(card.person.id) {
            answered.append(card.person.id)
            UserDefaults.standard.set(answered, forKey: answeredKey)
        }
        // Through the merge chain on both sides. A correct answer given before
        // two people were merged into one has to keep counting, or the archive
        // punishes a family for tidying itself up (ARCHITECTURE §13).
        guard let chose,
              let chosen = store.subject(id: chose.id),
              let proposed = store.subject(id: card.person.id),
              chosen.id == proposed.id
        else { return false }
        store.confirm(subjectID: proposed.id)
        return true
    }

    /// Part of emptying the device, beside the ladder's and the deck's — all of
    /// them records about the person holding the phone.
    static func reset() {
        answeredThisSession = false
        UserDefaults.standard.removeObject(forKey: answeredKey)
    }
}
