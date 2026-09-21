import Foundation

/// Where a reference to a merged card lands.
///
/// A merge is a forwarding address (`MemoryStore.rename`, ARCHITECTURE §2.5):
/// the corrected card keeps its row with `mergedInto` set, and every telling
/// that pointed at it is pointed at the survivor instead. On the phone that
/// merged, both halves happen. On every other phone, until 21 Sep 2026, only
/// the first one did.
///
/// **The server keeps the address and refuses the re-pointing.** Measured
/// that day against the shipping `sync.ts` over SQLite: one member corrects
/// "Aina" onto "Aino" and pushes the tombstone together with two tellings
/// another member told — one filed under Aina, one naming her. The reply
/// counts six rows accepted. The tombstone was kept, and both tellings still
/// pointed at Aina. A telling is written only by its author (the upsert's
/// `WHERE memory.author_id = ?` — rule 3, which `memory-rules-check.mjs`
/// holds on purpose), and a question's subject is written once and never
/// again.
///
/// So on every phone but the merging one, the telling stayed filed under a
/// card no list shows — `subjects(of:)` leaves a merged card out, and
/// `memories(for:)` compares the id as it is stored. It was on no card and in
/// no count, and the export's readable page left it out. The merging phone
/// joined them at its first pull from zero, which brought the server's copy.
///
/// **The answer is on the phone, once, rather than in every query.** The
/// forwarding address did travel, so every phone can draw the merge's
/// conclusion for itself, and it does wherever a stale id can arrive: after
/// the file is loaded, after every pull, and after a merge made here. Moving
/// the reference is what makes every comparison by id right at once — the
/// survivor's card, the gallery's counts, `isOrphaned`, the export — where
/// following the chain inside each of them would mean finding every one.
///
/// Nothing is queued. Most of it the server would refuse, and none of it
/// needs the server's agreement: every phone reads the same address and draws
/// the same conclusion from it.
enum MergeChain {
    /// How many forwarding addresses are followed. A cycle is broken data, and
    /// broken data must not hang the UI.
    static let hops = 8

    /// The card an id stands for: itself, or the survivor at the end of its
    /// forwarding addresses. A rejected card stands for nothing — that is the
    /// point of rejecting it — and so does an address whose card this phone
    /// has not been sent yet.
    ///
    /// `MemoryStore.subject(id:)` is this over the store's own cards, so what
    /// a reference is moved to below and what a screen resolves it to cannot
    /// come apart.
    static func resolve(_ id: String, in lookup: (String) -> Subject?) -> Subject? {
        var current = lookup(id).flatMap { $0.deletedAt == nil ? $0 : nil }
        for _ in 0 ..< hops {
            guard let target = current?.mergedInto else { return current }
            current = lookup(target)
        }
        return current
    }

    /// Every reference a telling or a question holds, moved to the card it
    /// already resolves to. Returns how many rows changed.
    ///
    /// Only ever to where `resolve` lands, and only when the card there
    /// resolves to itself. So nothing a screen finds through `subject(id:)`
    /// moves, and whatever cannot be settled is left exactly as it was: a
    /// cycle, a chain longer than `hops`, a survivor the pull has not brought
    /// yet, a survivor the family has since rejected.
    ///
    /// The teller moves with the rest. `byline(for:)` already follows the
    /// chain, but `recentTellers` tells people apart by this id.
    @discardableResult
    static func follow(
        memories: inout [Memory],
        questions: inout [FollowUpQuestion],
        subjects: [Subject]
    ) -> Int {
        // An archive that has never merged anything pays nothing.
        guard subjects.contains(where: { $0.mergedInto != nil }) else { return 0 }
        let byID = Dictionary(subjects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func settled(_ id: String) -> String {
            guard let survivor = resolve(id, in: { byID[$0] }), survivor.id != id,
                  resolve(survivor.id, in: { byID[$0] })?.id == survivor.id
            else { return id }
            return survivor.id
        }

        var changed = 0
        for index in memories.indices {
            var row = memories[index]
            row.subjectID = settled(row.subjectID)
            let named = row.mentionedSubjectIDs.map(settled)
            if named != row.mentionedSubjectIDs {
                // Two names heard in one telling are one person once the
                // family says so, and the server's mention table holds that
                // pair once. Only a list this pass moved is folded; one it
                // did not touch is none of its business.
                var seen = Set<String>()
                row.mentionedSubjectIDs = named.filter { seen.insert($0).inserted }
            }
            row.tellerSubjectID = row.tellerSubjectID.map(settled)
            if row != memories[index] {
                memories[index] = row
                changed += 1
            }
        }
        for index in questions.indices {
            guard let id = questions[index].subjectID else { continue }
            let landed = settled(id)
            guard landed != id else { continue }
            questions[index].subjectID = landed
            changed += 1
        }
        return changed
    }
}
