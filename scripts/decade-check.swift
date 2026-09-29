// Checks which decade the album files a photograph under, on a phone in any
// time zone, and how a span of years reads there.
//
// Every date in the archive is midnight in Helsinki (`DateHint.zone`): the
// date sheet's "1950s" is 1.1.1950 at 00:00 there, and so is the extraction's.
// Until 28 Sep 2026 the album read the year back on the phone's own calendar,
// and in Los Angeles that instant is the afternoon of 31.12.1949 — so on every
// phone west of Finland each photograph dated to a decade sat under the
// heading before it, the fifties among the forties. The seeds had the mirror
// image, dates built on the phone's calendar and read on Helsinki's, which on
// a phone in Tokyo puts the film's photograph from the thirties in the
// twenties. Nothing looks wrong either way: a heading reads as right whatever
// it says, and on this machine, in Helsinki, both were right.
//
// A span of years is the same clock read at its other end. The extraction
// stores "around 1955" as 1954 to 1956, and until 29 Sep 2026 the card read
// "1954": sharper than what was said, which is rule 5 broken on the screen
// while the archive keeps it.
//
// So the decade is taken here under zones on both sides of Helsinki, at both
// ends of a decade, the span with it, and then the app's sources are read for
// the phone's own calendar anywhere at all. Costs nothing: no simulator, no network, no key.
// Run it from the repository's root, as verify.sh does, after touching
// `DateHint` in Models.swift, the decade headings in GalleryScreen.swift or a
// seed's dates in MemoryStore.swift: the sources are found from the path it
// was compiled with, and a relative path is relative to where it runs.
//
//   swiftc -parse-as-library -o /tmp/decade-check \
//     scripts/decade-check.swift ios/Kinlore/Model/Models.swift

import Foundation

@main
enum DecadeCheck {
    static func main() {
        var failures = 0

        func check(_ label: String, _ passed: Bool, _ detail: String = "") {
            if passed {
                print("  ok   \(label)")
            } else {
                failures += 1
                print("  FAIL \(label)\(detail.isEmpty ? "" : ": \(detail)")")
            }
        }

        // The date sheet's calendar, built here rather than borrowed from
        // `DateHint`, so that a `DateHint` on the wrong clock cannot agree
        // with itself.
        var helsinki = Calendar(identifier: .gregorian)
        helsinki.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        func at(_ year: Int, _ month: Int = 1, _ day: Int = 1, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            helsinki.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }

        let dates: [(what: String, date: Date, decade: Int)] = [
            ("the date sheet's 1950s, midnight on 1.1.1950", at(1950), 1950),
            ("the last minute of 1959", at(1959, 12, 31, 23, 59), 1950),
            ("midnight on 1.1.1960", at(1960), 1960),
            // Before 1921 Helsinki kept its own mean time, 1 h 40 min ahead
            // of Greenwich, so this is the zone's history and not only its
            // offset.
            ("midnight on 1.1.1900", at(1900), 1900),
            ("the last minute of 1999", at(1999, 12, 31, 23, 59), 1990),
            ("midnight on 1.1.2000", at(2000), 2000),
        ]

        // A phone in each zone, as far as `Calendar.current` can tell: it
        // follows `NSTimeZone.default`, which is what a phone set to another
        // zone changes (measured 28 Sep 2026). West of Helsinki the first
        // midnight of a decade is still the decade before, and east of it the
        // last minute is already the next. Kiritimati is both: it kept
        // Hawaii's side of the date line until 1995.
        let home = NSTimeZone.default
        for zone in ["Pacific/Honolulu", "America/Los_Angeles", "UTC", "Europe/Helsinki",
                     "Asia/Tokyo", "Pacific/Kiritimati"] {
            NSTimeZone.default = TimeZone(identifier: zone)!
            print("— a phone in \(zone) —")
            // Without this every line below could pass on a phone that never
            // left Helsinki.
            check(
                "the phone's own calendar is on \(zone)",
                Calendar.current.timeZone.identifier == TimeZone(identifier: zone)!.identifier,
                "it is on \(Calendar.current.timeZone.identifier)"
            )
            for entry in dates {
                let decade = DateHint.decade(of: entry.date)
                check("\(entry.what) is in the \(entry.decade)s", decade == entry.decade, "filed in the \(decade)s")
            }
            // And the seeds' side: a 1.1.1930 built for the archive is
            // Helsinki's midnight wherever it was built.
            let built = DateHint.calendar.date(from: DateComponents(year: 1930, month: 1, day: 1))
            check(
                "a seed's 1.1.1930 is midnight in Helsinki",
                built == at(1930),
                built.map { "\(Int($0.timeIntervalSince(at(1930)) / 3600)) h from it" } ?? "nothing was built"
            )
            // West of Helsinki the span's end, 1.1.1956 there, is still 1955
            // on the phone's calendar.
            let span = DateHint(start: at(1954), end: at(1956), precision: .year).displayText
            check("\"around 1955\", stored as 1954 to 1956, reads 1954–1956", span == "1954–1956", span)
        }
        NSTimeZone.default = home

        print("— a year, and a span that is not one —")
        let alone = DateHint(start: at(1954), end: nil, precision: .year).displayText
        check("a year with no end reads 1954", alone == "1954", alone)
        let same = DateHint(start: at(1954), end: at(1954), precision: .year).displayText
        check("a span that ends in the year it starts reads 1954", same == "1954", same)
        let backwards = DateHint(start: at(1956), end: at(1954), precision: .year).displayText
        check("an end before the start is not drawn", backwards == "1956", backwards)

        print("— the phone's own calendar, anywhere in the app —")
        // The phone's calendar is right for one question, whether something
        // happened today. Everywhere else it is this defect waiting for a
        // phone somewhere else, and a calendar built without a zone takes the
        // phone's too.
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ios/Kinlore")
        var read: Set<String> = []
        var found: [String] = []
        let walk = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)
        while let url = walk?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            read.insert(url.lastPathComponent)
            let lines = text.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                let phones = code.contains("Calendar.current") || code.contains("Calendar.autoupdatingCurrent")
                let today = code.contains("isDateInToday") || code.contains("isDateInYesterday")
                let unzoned = code.contains("Calendar(identifier:")
                    && !lines.dropFirst(index + 1).prefix(2).contains { $0.contains(".timeZone =") }
                if phones && !today || unzoned {
                    found.append("\(url.lastPathComponent):\(index + 1)")
                }
            }
        }
        check(
            "the album, the seeds and the model were read",
            ["GalleryScreen.swift", "MemoryStore.swift", "Models.swift"].allSatisfy(read.contains),
            "\(read.count) files read from \(app.path)"
        )
        check("no date is built or read on the phone's calendar", found.isEmpty, found.joined(separator: ", "))

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
