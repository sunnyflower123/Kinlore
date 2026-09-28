// Checks what the app is willing to believe a model said about WHEN.
//
// The reply carries `start_year`, `end_year` and a `precision` that may say
// "day" or "month" — `extract.ts` has offered those two from the first, and
// nothing finer than a year ever travels beside them. So a model that heard
// "kesäkuussa 1957" answered month 1957, and the conversion built the first of
// January and stored it AS a month: the card then read *tammikuu 1957* as a
// fact nobody had said, and a day precision read *1.1.1957* the same way. Rule
// 5 is that uncertainty is stored rather than rounded, and that was its exact
// opposite — a coarse answer sharpened into a false one.
//
// The fix was reasoned rather than measured, which is what this closes. Every
// way of being wrong here is silent: a date is a short line on a card, it is
// right-looking whatever it says, no build fails and no screenshot shows the
// difference between a month the speaker gave and a month the arithmetic
// invented.
//
// The reply is decoded from the JSON the Worker actually sends rather than
// built by hand, so the field names are checked too — `start_year` and not
// `startYear` is the half that would otherwise go quietly nil and take every
// date with it.
//
// Costs nothing: no Worker, no key, no network, no model. Run it after
// touching `dateHint(from:)` in AppServices.swift, the date fields in
// extract.ts, or `DateHint` and `DatePrecision` in Models.swift.
//
//   swiftc -parse-as-library -enable-bare-slash-regex -o /tmp/date-hint-check \
//     scripts/date-hint-check.swift ios/Kinlore/Services/AppServices.swift \
//     ios/Kinlore/Model/Models.swift ios/Kinlore/Services/Extraction.swift \
//     ios/Kinlore/Services/ExtractionContext.swift \
//     ios/Kinlore/Services/PurchaseService.swift \
//     ios/Kinlore/Services/Transcription.swift \
//     ios/Kinlore/Services/Colourisation.swift \
//     ios/Kinlore/Services/RelationWords.swift
//
// Eight files for one function is the price of compiling the real one instead
// of a copy: AppServices.swift names every service protocol in the app, and
// `-enable-bare-slash-regex` is for the regex literals in Extraction.swift.
// The line is long and it is checked by the compiler, so it fails loudly and
// at once when it goes stale.

import Foundation

/// The one type on that list that cannot come from the repository.
///
/// `AppServices.purchases()` names `RevenueCatPurchases`, and the real one
/// imports the RevenueCat package — a SwiftPM dependency `swiftc` has no way
/// to resolve. Nothing below calls it; it exists so the file it is named in
/// will compile. If `PurchaseService` ever gains a requirement this stops
/// conforming, which is a compiler error in this file and a one-line repair.
struct RevenueCatPurchases: PurchaseService {
    static var configuredKey: String? { nil }
    var customerID: String? { get async { nil } }
    var hasActivePurchase: Bool { get async { false } }
}

@main
enum DateHintCheck {
    /// Reads the date object exactly as it arrives inside an extraction.
    static func reply(_ json: String) -> RemoteExtractionService.Reply.DateReply? {
        try? JSONDecoder().decode(
            RemoteExtractionService.Reply.DateReply.self,
            from: Data(json.utf8)
        )
    }

    static func main() {
        var failures = 0

        func check(_ label: String, _ actual: String, _ expected: String) {
            if actual == expected {
                print("  ok   \(label)")
            } else {
                failures += 1
                print("  FAIL \(label): got \(actual), expected \(expected)")
            }
        }

        /// The Helsinki calendar the archive is written in, which is the one
        /// the stored instant has to be read back through.
        var helsinki = Calendar(identifier: .gregorian)
        helsinki.timeZone = DateHint.zone

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt

        /// A date written out in a calendar, or the word for having none.
        func day(_ date: Date?, in calendar: Calendar) -> String {
            guard let date else { return "none" }
            let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return "\(parts.day!).\(parts.month!).\(parts.year!) \(parts.hour!):00"
        }

        /// What a reply becomes, in one readable line.
        func shaped(_ json: String) -> String {
            guard let decoded = reply(json) else { return "undecodable" }
            guard let hint = RemoteExtractionService.dateHint(from: decoded) else { return "nothing" }
            return "\(hint.precision.rawValue) \(day(hint.start, in: helsinki)) – \(day(hint.end, in: helsinki))"
        }

        print("— a precision finer than the data behind it —")
        // The defect itself. Only the year arrived, so only the year is stored,
        // however confidently the model named a month or a day.
        check(
            "a month with a year behind it is stored as a year",
            shaped(#"{"start_year":1957,"end_year":1957,"precision":"month"}"#),
            "year 1.1.1957 0:00 – 1.1.1957 0:00"
        )
        check(
            "a day is stored as a year too",
            shaped(#"{"start_year":1957,"end_year":1957,"precision":"day"}"#),
            "year 1.1.1957 0:00 – 1.1.1957 0:00"
        )

        print("— and a precision the data does support —")
        check(
            "a year is a year",
            shaped(#"{"start_year":1957,"end_year":1957,"precision":"year"}"#),
            "year 1.1.1957 0:00 – 1.1.1957 0:00"
        )
        // Rule 5's own example, all the way through: "joskus 50-luvulla" keeps
        // its ten years instead of being pinned to one of them.
        check(
            "a decade keeps both ends",
            shaped(#"{"start_year":1950,"end_year":1959,"precision":"decade"}"#),
            "decade 1.1.1950 0:00 – 1.1.1959 0:00"
        )
        check(
            "an open end stays open",
            shaped(#"{"start_year":1950,"end_year":null,"precision":"decade"}"#),
            "decade 1.1.1950 0:00 – none"
        )

        print("— what is not a date at all —")
        check(
            "nothing was said",
            shaped(#"{"start_year":null,"end_year":null,"precision":"unknown"}"#),
            "nothing"
        )
        // A precision outside the five is a Worker this app does not know. It
        // is not an invitation to guess.
        check(
            "a precision this app has never heard of",
            shaped(#"{"start_year":1957,"end_year":1957,"precision":"vuosikymmen"}"#),
            "nothing"
        )
        // The one that would be tempting to keep: a confident precision with no
        // year under it. Storing it is worse than storing nothing, because
        // `date_precision` is the signal sync reads as "this device has
        // something to say about the date" — so an empty hint pushed from here
        // clears a date another phone in the family already had.
        check(
            "a precision with no year behind it",
            shaped(#"{"start_year":null,"end_year":null,"precision":"year"}"#),
            "nothing"
        )
        check(
            "and not even with an end year to lean on",
            shaped(#"{"start_year":null,"end_year":1959,"precision":"decade"}"#),
            "nothing"
        )

        print("— the wire —")
        // The names are the backend's, and they are the whole contract: a
        // decoder reading `startYear` would find nothing, answer nil, and drop
        // every date in the archive without one line of the app looking wrong.
        check(
            "the years are read under the names extract.ts sends",
            shaped(#"{"startYear":1957,"endYear":1957,"precision":"year"}"#),
            "nothing"
        )
        // `precision` is required on the wire and required here: a date object
        // without it is not half a date, it is a reply this app cannot read.
        check(
            "a reply with no precision does not decode",
            shaped(#"{"start_year":1957,"end_year":1957}"#),
            "undecodable"
        )

        print("— the clock —")
        // Every date in the archive is midnight in Helsinki, because `DateSheet`
        // and the fixtures build them that way and `displayText` reads them
        // back that way. Built in UTC instead, the same stored instant would be
        // read here as the last day of the year before — a photograph from 1957
        // filed under 1956. Finland was two hours ahead of UTC in 1957, so the
        // instant behind 1.1.1957 is 31.12.1956 at 22:00 UTC, and that is what
        // says the zone was applied rather than assumed away.
        let newYear = reply(#"{"start_year":1957,"end_year":null,"precision":"year"}"#)
            .flatMap(RemoteExtractionService.dateHint(from:))
        check("midnight in Helsinki", day(newYear?.start, in: helsinki), "1.1.1957 0:00")
        check("which is the evening before in UTC", day(newYear?.start, in: utc), "31.12.1956 22:00")

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
