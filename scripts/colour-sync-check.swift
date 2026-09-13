// A confirmed colouring through sync, on the phone's side of it.
//
// The server keeps the newest yes, and `subject-rules-check.mjs` holds it to
// that. What comes back is then laid over the phone's own copy by
// `Subject.withColours`, and every way of getting that wrong is silent:
//
//   1. **A row that says nothing takes nothing away.** A Worker that has not
//      been redeployed sends no colour fields at all, and a merge that believed
//      it would wipe every colouring the family had confirmed on the first pull
//      after the app updated.
//   2. **A yes not yet uploaded is kept** over whatever arrives: it is newer than
//      anything the server can hold, and it travels on the next push.
//   3. **Another phone's newer yes replaces this one** — and this phone's old
//      picture is handed back to be deleted rather than shown under it.
//
// And one rule on the way out: a yes travels with its file, or not at all.
//
// Costs nothing: no simulator, no Worker, no network.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -o /tmp/colour-sync-check scripts/colour-sync-check.swift \
//     ios/Kinlore/Services/FamilyCrypto.swift ios/Kinlore/Data/MemoryStore+Sync.swift \
//     ios/Kinlore/Model/Models.swift && /tmp/colour-sync-check

import Foundation

@main
struct ColourSyncCheck {
    nonisolated(unsafe) static var failures = 0

    static func check(_ what: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("  ok   \(what)")
        } else {
            failures += 1
            print("  FAIL \(what)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    static func main() {
        let at = Date(timeIntervalSince1970: 1_780_000_000)
        var local = Subject(id: "kuva", kind: .photo, title: "")
        local.colourImageFilename = "media-here.jpg"
        local.colourR2Key = "perhe/one.jpg"
        local.colourConfirmedByID = "mummo"
        local.colourConfirmedByName = "Mummo"
        local.colourConfirmedAt = at

        print("— a yes travels with its file, or not at all —")
        do {
            var pending = local
            pending.colourR2Key = nil
            let unsent = pending.dto
            check(
                "before the upload, nothing of it is sent",
                unsent.colour_r2_key == nil && unsent.colour_confirmed_by == nil && unsent.colour_confirmed_at == nil,
                "\(unsent.colour_r2_key ?? "nil") \(unsent.colour_confirmed_by ?? "nil")"
            )
            let sent = local.dto
            check(
                "with its key, all of it is",
                sent.colour_r2_key == "perhe/one.jpg" && sent.colour_confirmed_by == "mummo"
                    && sent.colour_confirmed_at == at.timeIntervalSince1970
            )
            check("and never the name, which is the server's to say", sent.colour_confirmed_by_name == nil)
        }

        print("— and comes back as it was sent —")
        do {
            var dto = local.dto
            dto.colour_confirmed_by_name = "Mummo"
            let back = Subject(dto: dto)
            check(
                "the key, the confirmer, the name and the moment",
                back?.colourR2Key == "perhe/one.jpg" && back?.colourConfirmedByID == "mummo"
                    && back?.colourConfirmedByName == "Mummo" && back?.colourConfirmedAt == at
            )
            check("with no file, which is this phone's own business", back?.colourImageFilename == nil)
        }

        print("— a pull laid over this phone's copy —")
        do {
            let silent = Subject(id: "kuva", kind: .photo, title: "Mökin ranta")
            let (row, stale) = silent.withColours(from: local)
            check(
                "a row that says nothing about colours takes nothing away",
                row.colourR2Key == local.colourR2Key && row.colourImageFilename == local.colourImageFilename
                    && row.colourConfirmedByID == "mummo" && row.colourConfirmedAt == at && stale == nil
            )
            check("while the rest of the row still lands", row.title == "Mökin ranta", row.title)
        }
        do {
            var pending = local
            pending.colourR2Key = nil
            pending.colourImageFilename = "media-new.jpg"
            var older = Subject(id: "kuva", kind: .photo, title: "")
            older.colourR2Key = "perhe/older.jpg"
            older.colourConfirmedAt = at.addingTimeInterval(-600)
            let (row, stale) = older.withColours(from: pending)
            check(
                "a yes not uploaded yet is kept over whatever arrives",
                row.colourImageFilename == "media-new.jpg" && row.colourR2Key == nil && stale == nil,
                "\(row.colourImageFilename ?? "nil") \(row.colourR2Key ?? "nil")"
            )
        }
        do {
            var echo = Subject(id: "kuva", kind: .photo, title: "")
            echo.colourR2Key = local.colourR2Key
            echo.colourConfirmedByID = "mummo"
            echo.colourConfirmedByName = "Aino-mummo"
            echo.colourConfirmedAt = at
            let (row, stale) = echo.withColours(from: local)
            check("the same yes keeps its file here", row.colourImageFilename == "media-here.jpg" && stale == nil)
            check("and takes what the server now says about it", row.colourConfirmedByName == "Aino-mummo")
        }
        do {
            var newer = Subject(id: "kuva", kind: .photo, title: "")
            newer.colourR2Key = "perhe/two.jpg"
            newer.colourConfirmedByID = "ville"
            newer.colourConfirmedAt = at.addingTimeInterval(600)
            let (row, stale) = newer.withColours(from: local)
            check(
                "another phone's newer yes replaces this one",
                row.colourR2Key == "perhe/two.jpg" && row.colourConfirmedByID == "ville"
            )
            check(
                "and this phone's old picture is not shown under it",
                row.colourImageFilename == nil && stale == "media-here.jpg",
                "\(row.colourImageFilename ?? "nil") \(stale ?? "nil")"
            )
        }

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
