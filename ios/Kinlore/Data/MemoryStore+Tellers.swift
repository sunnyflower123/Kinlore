import Foundation

extension MemoryStore {
    /// Who has told something about a subject, by the name each telling is
    /// signed with, first teller first and each name once.
    ///
    /// Albumi draws these as initials on a photograph's card, where a number
    /// used to stand: "Aino and Eero have told about this" is the reason to
    /// open a picture, and "2" was not. The name is `byline(for:)`'s, so a
    /// teller who asked not to be named is left out rather than shown as a
    /// blank — the card then says that somebody told, not who.
    ///
    /// Its own file because the store's main file is where the sync and
    /// persistence work happens, and this is a read for one screen.
    func tellers(of subjectID: String) -> [String] {
        var seen = Set<String>()
        return memories(for: subjectID).reversed().compactMap { memory in
            guard let name = byline(for: memory)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, seen.insert(name).inserted else { return nil }
            return name
        }
    }
}
