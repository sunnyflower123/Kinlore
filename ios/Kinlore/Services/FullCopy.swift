import Foundation
import Observation

/// The family's photographs and voices, all of them, on this phone.
///
/// The views fetch on demand (`MediaLoader`): the grid asks for the tiles it
/// draws, the card for the recording somebody presses play on. That is right
/// for the views and wrong for the archive, and until 5 Sep 2026 the two were
/// the same thing: everything nobody had happened to open existed in R2 alone,
/// and R2 exists for as long as one hobbyist's Cloudflare account does
/// (docs/RECOVERY.md; founder's-eye review, finding #86). The text has always
/// been on every phone. This puts the bytes beside it.
///
/// The rules, every one of them silent when wrong — a copy that never starts
/// looks exactly like one that is complete, so `scripts/full-copy-check.swift`
/// holds them:
///
///   - After every successful sync, in the background: what is missing and
///     nothing else. A file that is already here is never fetched again.
///   - Voices before photographs. The recording is the thing that cannot be
///     made a second time; a paper photograph can be scanned twice.
///   - A cheap network only — never cellular, never a hotspot. A grandmother's
///     phone that never meets Wi-Fi never copies, and the family screen says
///     so, which is the true sentence rather than a quietly empty one.
///   - Never the last gigabyte of the phone.
///   - Three failures in a row end the round. The next sync starts another,
///     from wherever this one stopped.
///   - One round at a time.
///   - The store is written once per ten files and once at the end of a
///     round, not once per file. Recording a filename used to save the whole
///     archive: 150 files wrote a 5.4 MB JSON 150 times, measured 6 Sep 2026
///     (ARCHITECTURE §5), and a family's real archive would have written
///     tens of gigabytes of JSON to copy a few of media. A phone killed
///     mid-round fetches at most nine files again.
///
/// Compiled on its own by the check, which is why the network, the disk, the
/// fetch and the store arrive as closures rather than as frameworks.
@MainActor
@Observable
final class FullCopy {
    struct Item: Equatable {
        enum Kind: Equatable {
            case audio, photo
        }

        let id: String
        let kind: Kind
        /// The R2 key.
        let key: String
        /// Where the bytes already are on this phone, if anywhere.
        let filename: String?

        var fileExtension: String { kind == .audio ? "m4a" : "jpg" }
    }

    /// Why the last round stopped short, if it did.
    enum Halt: Equatable {
        case none
        case expensiveNetwork
        case lowDisk
        case failures
    }

    struct Progress: Equatable {
        var have: Int
        var total: Int
        var isComplete: Bool { have >= total }
    }

    /// Everything the copy touches, handed in.
    struct Ports {
        /// Every photograph and recording the family has, whether or not its
        /// bytes are here yet.
        var items: () -> [Item]
        var exists: (String) -> Bool
        /// Opened bytes, or nil on any failure — the network, the server, a
        /// seal that will not open. The copy does not need to know which.
        var fetch: (String) async -> Data?
        /// Bytes and an extension in, a filename out.
        var save: (Data, String) -> String?
        /// The filename, written back to the row it belongs to — in memory.
        /// Nothing reaches the disk until `flush`.
        var record: (Item, String) -> Void
        /// Writes the rows to disk. Called every `filesPerFlush` recorded
        /// files and once more at the end of a round that recorded any.
        var flush: () -> Void
        var networkIsCheap: () -> Bool
        /// Bytes free on the phone, or nil when the phone will not say.
        var freeBytes: () -> Int64?
    }

    /// One gigabyte. The copy is a copy, not the thing the phone is for.
    static let diskFloor: Int64 = 1_000_000_000
    static let failuresThatEndARound = 3
    static let filesPerFlush = 10

    private(set) var progress = Progress(have: 0, total: 0)
    private(set) var halt: Halt = .none
    private(set) var isRunning = false
    /// Set by `hold`, for the audit. A held copy measures and fetches nothing.
    private var isHeld = false

    private let ports: Ports

    init(ports: Ports) {
        self.ports = ports
        measure()
    }

    /// Counts without fetching, so the family screen is right before the first
    /// round and after every one.
    func measure() {
        guard !isHeld else { return }
        let items = ports.items()
        progress = Progress(have: items.filter(isHere).count, total: items.count)
    }

    /// One round. Safe to call often — a round already running is left alone.
    func run() async {
        guard !isRunning, !isHeld else { return }
        isRunning = true
        defer { isRunning = false }

        measure()
        halt = .none
        var failuresInARow = 0
        var unflushed = 0
        // Every way out of the loop below — done, expensive, full, failed —
        // writes what the round recorded since its last flush.
        defer { if unflushed > 0 { ports.flush() } }

        for item in ports.items().sorted(by: Self.order) where !isHere(item) {
            guard ports.networkIsCheap() else {
                halt = .expensiveNetwork
                return
            }
            if let free = ports.freeBytes(), free < Self.diskFloor {
                halt = .lowDisk
                return
            }
            guard let data = await ports.fetch(item.key),
                  let filename = ports.save(data, item.fileExtension)
            else {
                failuresInARow += 1
                if failuresInARow >= Self.failuresThatEndARound {
                    halt = .failures
                    return
                }
                continue
            }
            failuresInARow = 0
            ports.record(item, filename)
            progress.have += 1
            unflushed += 1
            if unflushed >= Self.filesPerFlush {
                ports.flush()
                unflushed = 0
            }
        }
    }

    private func isHere(_ item: Item) -> Bool {
        guard let filename = item.filename else { return false }
        return ports.exists(filename)
    }

    /// Voices first; within a kind, the order the rows came in.
    private static func order(_ a: Item, _ b: Item) -> Bool {
        if a.kind != b.kind { return a.kind == .audio }
        return false
    }

    #if DEBUG
    /// Holds one state still so the family screen's row can be measured at
    /// both text sizes. Nothing is fetched while held.
    func hold(progress: Progress, halt: Halt) {
        isHeld = true
        self.progress = progress
        self.halt = halt
    }
    #endif
}
