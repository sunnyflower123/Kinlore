// Checks the rules of the full copy — the family's photographs and voices
// fetched to this phone after every sync, so the phone is a copy of the
// archive and not a window onto one (docs/RECOVERY.md).
//
// Every rule is silent when wrong. A copy that never starts looks exactly like
// one that is complete; a copy that fetches on cellular looks like a working
// app until the bill; a copy that fetches the same file on every round looks
// like a working app until the phone is full. None of it fails a build. Run
// this after touching FullCopy.swift — the command is in docs/DEVELOPMENT.md.
//
//   swiftc -parse-as-library -o /tmp/full-copy-check \
//     scripts/full-copy-check.swift ios/Kinlore/Services/FullCopy.swift

import Foundation

@main
enum FullCopyCheck {
    /// A phone: the rows, the files on disk, and what the network does.
    @MainActor
    final class Phone {
        var items: [FullCopy.Item]
        var files: Set<String> = []
        var fetched: [String] = []
        var recorded: [(String, String)] = []
        var flushes = 0
        /// Called after every fetch with the count so far; a check can change
        /// the phone under a running round.
        var afterFetch: ((Int) -> Void)?
        /// What each fetch answers, in order; past the end, everything succeeds.
        var answers: [Bool] = []
        var cheap = true
        var free: Int64? = 50_000_000_000
        var delay: Duration?

        init(_ items: [FullCopy.Item]) { self.items = items }

        var ports: FullCopy.Ports {
            FullCopy.Ports(
                items: { self.items },
                exists: { self.files.contains($0) },
                fetch: { key in
                    self.fetched.append(key)
                    self.afterFetch?(self.fetched.count)
                    if let delay = self.delay { try? await Task.sleep(for: delay) }
                    let ok = self.fetched.count <= self.answers.count
                        ? self.answers[self.fetched.count - 1]
                        : true
                    return ok ? Data([1, 2, 3]) : nil
                },
                save: { _, ext in
                    let name = "media-\(self.files.count + 1).\(ext)"
                    self.files.insert(name)
                    return name
                },
                record: { item, filename in
                    self.recorded.append((item.id, filename))
                    if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                        let old = self.items[index]
                        self.items[index] = FullCopy.Item(
                            id: old.id, kind: old.kind, key: old.key, filename: filename
                        )
                    }
                },
                flush: { self.flushes += 1 },
                networkIsCheap: { self.cheap },
                freeBytes: { self.free }
            )
        }
    }

    static func photo(_ id: String, here: String? = nil) -> FullCopy.Item {
        FullCopy.Item(id: id, kind: .photo, key: "k-\(id)", filename: here)
    }

    static func audio(_ id: String, here: String? = nil) -> FullCopy.Item {
        FullCopy.Item(id: id, kind: .audio, key: "k-\(id)", filename: here)
    }

    @MainActor
    static func main() async {
        var failures = 0

        func check(_ label: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("  ok   \(label)")
            } else {
                failures += 1
                print("  FAIL \(label)\(detail.isEmpty ? "" : " — \(detail)")")
            }
        }

        print("— what is fetched, and in what order —")
        do {
            let phone = Phone([photo("a"), audio("b"), photo("c", here: "media-c.jpg"), audio("d")])
            phone.files.insert("media-c.jpg")
            let copy = FullCopy(ports: phone.ports)
            check("the count is right before anything is fetched",
                  copy.progress == .init(have: 1, total: 4), "\(copy.progress)")
            await copy.run()
            check("only what is missing is fetched, voices first",
                  phone.fetched == ["k-b", "k-d", "k-a"], "\(phone.fetched)")
            check("every fetched file is written back to its row",
                  phone.recorded.map(\.0) == ["b", "d", "a"], "\(phone.recorded)")
            check("and the round ends complete",
                  copy.progress == .init(have: 4, total: 4) && copy.halt == .none, "\(copy.progress) \(copy.halt)")
            await copy.run()
            check("a second round fetches nothing", phone.fetched.count == 3, "\(phone.fetched)")
        }

        do {
            let phone = Phone([photo("a", here: "media-gone.jpg")])
            let copy = FullCopy(ports: phone.ports)
            await copy.run()
            check("a file that has gone from the disk is fetched again",
                  phone.fetched == ["k-a"] && copy.progress.isComplete, "\(phone.fetched)")
        }

        print("— what stops a round —")
        do {
            let phone = Phone([audio("b"), photo("a")])
            phone.cheap = false
            let copy = FullCopy(ports: phone.ports)
            await copy.run()
            check("an expensive network fetches nothing, and says so",
                  phone.fetched.isEmpty && copy.halt == .expensiveNetwork, "\(phone.fetched) \(copy.halt)")
            check("the count still says what is missing",
                  copy.progress == .init(have: 0, total: 2), "\(copy.progress)")
            phone.cheap = true
            await copy.run()
            check("Wi-Fi back, the round completes", copy.progress.isComplete && copy.halt == .none)
        }

        do {
            let phone = Phone([audio("b"), photo("a")])
            phone.free = FullCopy.diskFloor - 1
            let copy = FullCopy(ports: phone.ports)
            await copy.run()
            check("the last gigabyte is left alone",
                  phone.fetched.isEmpty && copy.halt == .lowDisk, "\(phone.fetched) \(copy.halt)")
            phone.free = nil
            await copy.run()
            check("a phone that will not say how much is free is not refused",
                  copy.progress.isComplete, "\(copy.progress)")
        }

        do {
            let phone = Phone([audio("b"), audio("c"), photo("a"), photo("d")])
            phone.answers = [false, false, false]
            let copy = FullCopy(ports: phone.ports)
            await copy.run()
            check("three failures in a row end the round",
                  phone.fetched.count == 3 && copy.halt == .failures && copy.progress.have == 0,
                  "\(phone.fetched.count) \(copy.halt) \(copy.progress)")
            await copy.run()
            check("and the next round carries on from where it stopped",
                  copy.progress.isComplete && copy.halt == .none && phone.recorded.count == 4,
                  "\(copy.progress) \(copy.halt) \(phone.recorded.count)")
        }

        do {
            let phone = Phone([audio("b"), audio("c"), photo("a"), photo("d")])
            phone.answers = [false, true, false, true]
            let copy = FullCopy(ports: phone.ports)
            await copy.run()
            check("failures with successes between them do not end the round",
                  copy.halt == .none && copy.progress.have == 2 && phone.fetched.count == 4,
                  "\(copy.halt) \(copy.progress) \(phone.fetched.count)")
        }

        print("— the store is written in batches, not once per file —")
        do {
            let phone = Phone((0 ..< 25).map { photo("p\($0)") })
            let copy = FullCopy(ports: phone.ports)
            await copy.run()
            check("twenty-five files are recorded twenty-five times",
                  phone.recorded.count == 25, "\(phone.recorded.count)")
            check("and written three times: at ten, at twenty, and at the end",
                  phone.flushes == 3, "\(phone.flushes)")
        }
        do {
            let phone = Phone((0 ..< 10).map { photo("p\($0)") })
            let copy = FullCopy(ports: phone.ports)
            await copy.run()
            check("exactly ten files are written once, not once more at the end",
                  phone.flushes == 1, "\(phone.flushes)")
        }
        do {
            let phone = Phone([photo("a", here: "media-a.jpg")])
            phone.files.insert("media-a.jpg")
            let copy = FullCopy(ports: phone.ports)
            await copy.run()
            check("a round with nothing to fetch writes nothing", phone.flushes == 0, "\(phone.flushes)")
        }
        do {
            let phone = Phone((0 ..< 7).map { audio("v\($0)") })
            phone.answers = [true, true, true, true, false, false, false]
            let copy = FullCopy(ports: phone.ports)
            await copy.run()
            check("a round ended by failures still writes the four it kept",
                  copy.halt == .failures && phone.recorded.count == 4 && phone.flushes == 1,
                  "\(copy.halt) \(phone.recorded.count) \(phone.flushes)")
        }
        do {
            let phone = Phone((0 ..< 7).map { audio("v\($0)") })
            phone.afterFetch = { count in if count == 3 { phone.cheap = false } }
            let copy = FullCopy(ports: phone.ports)
            await copy.run()
            check("a round the network ended still writes the three it kept",
                  copy.halt == .expensiveNetwork && phone.recorded.count == 3 && phone.flushes == 1,
                  "\(copy.halt) \(phone.recorded.count) \(phone.flushes)")
        }

        print("— one round at a time —")
        do {
            let phone = Phone([audio("b"), photo("a")])
            phone.delay = .milliseconds(30)
            let copy = FullCopy(ports: phone.ports)
            let first = Task { await copy.run() }
            try? await Task.sleep(for: .milliseconds(5))
            await copy.run()
            await first.value
            check("a round already running is left alone",
                  phone.fetched.count == 2, "\(phone.fetched)")
        }

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
