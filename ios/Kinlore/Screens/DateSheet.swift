import SwiftUI

/// Putting a date on a photo or a moment by hand — or on a whole import of
/// them at once.
///
/// `date_start`, `date_end` and `date_precision` have been in the schema from the
/// first day, and rule 5 — uncertainty is stored, never rounded — is one of the
/// things this app is built on. Only the extraction could ever write them. So a
/// granddaughter who knows the summer was 1957, looking at a photograph the model
/// dated to nothing at all, had nowhere to put what she knew.
///
/// **One sheet, one or many subjects.** Thirty scanned photographs are almost
/// always one album and one era, and asking thirty times is asking nobody: the
/// import offers this once for everything it just brought in. The same rows, the
/// same three answers, and "en tiedä" is still there for the pile that really is
/// a jumble.
///
/// The precision is **chosen, not inferred**. That is the whole design: the
/// screen asks how sure you are before it asks what the answer is, so "joskus
/// viisikymmentäluvulla" is two taps rather than a compromise. A screen that
/// only offered a year would force everybody into a precision they do not have,
/// which is precisely what rule 5 exists to prevent.
struct DateSheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// What is being dated. One from a subject's own card, many straight after
    /// an import.
    let subjects: [Subject]

    init(subject: Subject) { self.subjects = [subject] }
    init(subjects: [Subject]) { self.subjects = subjects }

    private var single: Subject? { subjects.count == 1 ? subjects.first : nil }

    /// How sure the person is.
    ///
    /// Three choices, and the two that are missing are missing for different
    /// reasons. A **month** is the one nobody remembers without remembering the
    /// year anyway. An **exact day** was offered and then taken out: the only
    /// controls iOS has for it are a wheel and a graphical calendar, and neither
    /// one's text grows with Dynamic Type — measured, three findings on that
    /// state alone. A control this app's user cannot read is not a capability.
    ///
    /// The precision itself stays in the model: extraction still writes `.day`
    /// when somebody says a date out loud, and this screen shows it as the year
    /// it falls in rather than pretending it is not there.
    private enum Sureness: String, CaseIterable, Identifiable {
        case decade, year, unknown
        var id: String { rawValue }

        var label: String {
            switch self {
            case .decade: "Vuosikymmen"
            case .year: "Vuosi"
            case .unknown: "En tiedä"
            }
        }
    }

    @State private var sureness: Sureness = .year

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki") ?? .current
        return calendar
    }()

    /// This century back to the 1900s. An archive of a family's memories does
    /// not need the nineteenth, and a shorter column is a faster one.
    private static let decades: [Int] = Array(stride(from: 1900, through: 2020, by: 10))
    private static let years: [Int] = Array(1900 ... Self.calendar.component(.year, from: .now))

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kuinka tarkkaan tiedät?", selection: $sureness) {
                        ForEach(Sureness.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    // The way out lives here, above the answers, because the
                    // answers can be a hundred and twenty-six rows long. A
                    // toolbar button would be the usual place and its text
                    // barely grows with Dynamic Type; a row at the bottom would
                    // have to be scrolled to; a pinned bar was tried and it dims
                    // whatever scrolls under it, which the audit reads as a
                    // contrast failure and an eye reads as a covered row.
                    Button("Peruuta") { dismiss() }
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                } header: {
                    // A List styles its own headers below the contrast minimum.
                    Text("Kuinka tarkkaan tiedät?")
                        .foregroundStyle(Elder.supporting)
                } footer: {
                    Text(single == nil
                        ? "Vastaus koskee kaikkia \(subjects.count) kuvaa. Voit muuttaa yksittäisen kuvan ajankohtaa myöhemmin sen omalta kortilta."
                        : "Epävarma vastaus on oikea vastaus. Sovellus tallentaa sen sellaisenaan eikä arvaa tarkempaa.")
                        .foregroundStyle(Elder.supporting)
                }

                // **Choosing is answering.** There is no save button: tapping a
                // year stores it and closes the sheet, which is the pattern
                // `RelationPicker` already uses for the same shape of question.
                // One tap instead of two, and nothing that has to stay on screen
                // while a long list scrolls past it.
                //
                // Lists rather than wheels: a wheel's text does not grow with
                // Dynamic Type — measured on this very screen — and an inline
                // picker is a column of full-width rows that scale like
                // everything else.
                Section {
                    switch sureness {
                    case .decade:
                        ForEach(Self.decades, id: \.self) { start in
                            choice("\(String(start))-luku", isCurrent: isStored(.decade, start)) {
                                save(decade: start)
                            }
                        }
                    case .year:
                        // `String(year)` rather than the number: SwiftUI formats
                        // an Int with the locale's thousands separator, and
                        // "1 957" is not a year.
                        ForEach(Self.years, id: \.self) { value in
                            choice(String(value), isCurrent: isStored(.year, value)) {
                                save(year: value)
                            }
                        }
                    case .unknown:
                        choice("Poista ajankohta", isCurrent: false) { save(nothing: true) }
                    }
                } header: {
                    Text(sureness == .unknown ? "" : "Valitse")
                        .foregroundStyle(Elder.supporting)
                }
            }
            .navigationTitle(single == nil ? "Milloin nämä olivat?" : "Milloin tämä oli?")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { load() }
        }
    }

    /// One answer. The stored one is ticked — the shape says which it is, not a
    /// colour, and it is how somebody sees what the photo already claims.
    private func choice(_ label: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Elder.affirmative)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .elderTapTarget()
        }
        .buttonStyle(.plain)
    }

    /// Only when a single subject is being dated: with many, "the stored one"
    /// is a question with several answers, and a tick that means "some of them"
    /// says less than no tick at all.
    private func isStored(_ precision: DatePrecision, _ value: Int) -> Bool {
        guard let subject = single,
              let hint = subject.dateHint, hint.precision == precision, let start = hint.start
        else {
            return false
        }
        let storedYear = Self.calendar.component(.year, from: start)
        return precision == .decade ? storedYear / 10 * 10 == value : storedYear == value
    }

    /// Opens on what is already stored, so a small correction is a small
    /// gesture rather than a re-entry.
    private func load() {
        guard let subject = single, let hint = subject.dateHint, hint.start != nil else { return }
        switch hint.precision {
        case .decade:
            sureness = .decade
        case .year:
            sureness = .year
        case .day, .month:
            // A date the extraction heard in full. Shown as its year, because
            // that is the finest thing this screen can ask for — and saving
            // then coarsens it deliberately, which is the person's call and not
            // a silent one: the row behind the sheet says what is stored now.
            sureness = .year
        case .unknown:
            sureness = .unknown
        }
    }

    private func save(decade: Int? = nil, year: Int? = nil, nothing: Bool = false) {
        // "En tiedä" is an answer and is stored as one, rather than as an empty
        // field. The difference is invisible here — both show nothing — and it
        // decides what happens on another phone: sync keeps a date unless the
        // pushing device says something about it, so a cleared date sent as an
        // absence would come back on the next sync from somebody's older copy.
        // It is the same reason the sheet asks how sure you are before it asks
        // for a number.
        let answer = nothing
            ? DateHint(start: nil, end: nil, precision: .unknown)
            : hint(decade: decade, year: year)
        for subject in subjects {
            store.setDateHint(subjectID: subject.id, hint: answer)
        }
        dismiss()
    }

    /// The span the answer really covers. A decade is ten years wide and is
    /// stored that way — writing 1 January 1950 alone would turn "joskus
    /// viisikymmentäluvulla" into a day nobody claimed.
    private func hint(decade: Int?, year: Int?) -> DateHint? {
        if let decade {
            return DateHint(
                start: Self.calendar.date(from: DateComponents(year: decade, month: 1, day: 1)),
                end: Self.calendar.date(from: DateComponents(year: decade + 9, month: 12, day: 31)),
                precision: .decade
            )
        }
        if let year {
            return DateHint(
                start: Self.calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                end: Self.calendar.date(from: DateComponents(year: year, month: 12, day: 31)),
                precision: .year
            )
        }
        return nil
    }
}
