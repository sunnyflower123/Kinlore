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
/// which is precisely what rule 5 exists to prevent — and it cuts the other way
/// too, which is why the month and the day are here as well.
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
    /// Four choices since 19 Sep 2026, where there were three. A **month** was
    /// held to be the thing nobody remembers without remembering the year
    /// anyway — which is true of a bare month and false of "kesäkuussa 1957",
    /// the shape a wedding, a funeral and a first day at school are remembered
    /// in. An **exact day** was offered and then taken out: the only controls
    /// iOS has for it are a wheel and a graphical calendar, and neither one's
    /// text grows with Dynamic Type — measured, three findings on that state
    /// alone.
    ///
    /// That second finding was about the CONTROL and not about the capability,
    /// and the rest of this screen had already answered it: a column of
    /// full-width rows scales like everything else. So the fine answer is a
    /// list too, asked one step at a time — the year, then the month, then the
    /// day — and no wheel appears anywhere.
    ///
    /// **It is one row and not two, and that is measured.** A row apiece for
    /// the month and the day made this section a screenful: the accessibility
    /// sweep then reported whatever stood last in it as "Dynamic Type font
    /// sizes are partially unsupported", the footer at five rows and the
    /// *Peruuta* button when the footer was moved. Measured 19 Sep 2026 on one
    /// simulator, minutes apart, the same file throughout: three rows pass,
    /// four pass, five fail at the default text size. So the whole of
    /// "päivämäärä" is one answer, and the month is offered inside it — where
    /// somebody looking at the days of June 1957 can say the day is the one
    /// thing they do not remember.
    private enum Sureness: String, CaseIterable, Identifiable {
        case decade, year, date, unknown
        var id: String { rawValue }

        var label: String {
            switch self {
            case .decade: "Vuosikymmen"
            case .year: "Vuosi"
            case .date: "Päivämäärä"
            case .unknown: "En tiedä"
            }
        }
    }

    @State private var sureness: Sureness = .year

    /// The steps already answered on the way to a month or a day. A month is
    /// not a date without its year, and a year is not one without its century:
    /// asking in that order keeps every list short enough to read, twelve rows
    /// after the hundred and twenty-six rather than eighteen hundred at once.
    @State private var pickedYear: Int?
    @State private var pickedMonth: Int?

    /// Which list is on screen. The sureness says how deep the questions go;
    /// the answers so far say how deep we are.
    private enum Step { case decade, year, month, day, nothing }

    private var step: Step {
        switch sureness {
        case .decade: .decade
        case .year: .year
        case .date:
            if pickedYear == nil { .year } else { pickedMonth == nil ? .month : .day }
        case .unknown: .nothing
        }
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki") ?? .current
        return calendar
    }()

    /// This century back to the 1900s. An archive of a family's memories does
    /// not need the nineteenth, and a shorter column is a faster one.
    private static let decades: [Int] = Array(stride(from: 1900, through: 2020, by: 10))
    private static let thisYear = calendar.component(.year, from: .now)
    private static let thisMonth = calendar.component(.month, from: .now)
    private static let thisDay = calendar.component(.day, from: .now)
    private static let years: [Int] = Array(1900 ... Self.thisYear)

    /// The row the finer lists scroll back to: the step already answered, which
    /// sits above them.
    private static let topRow = "chosen"

    /// The months there have been. The year list already stops at this year for
    /// the same reason — a memory of next June is not a memory — and a list
    /// that stops halfway through the current year says so without a word.
    private func months(of year: Int) -> [Int] {
        Array(1 ... (year == Self.thisYear ? Self.thisMonth : 12))
    }

    /// The days that month really had. February 1956 had twenty-nine of them,
    /// and a list of thirty-one would offer two days nobody lived through.
    private func days(of year: Int, _ month: Int) -> [Int] {
        guard let first = Self.calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = Self.calendar.range(of: .day, in: .month, for: first)
        else {
            return Array(1 ... 28)
        }
        let last = year == Self.thisYear && month == Self.thisMonth
            ? min(Self.thisDay, range.count)
            : range.count
        return Array(1 ... max(1, last))
    }

    /// The month's name in the phone's own language, and in the archive's own
    /// clock. The date was built as midnight in Helsinki, so read anywhere west
    /// of it the same instant is the month before.
    private func monthName(_ year: Int, _ month: Int) -> String {
        format(year: year, month: month, style: .dateTime.month(.wide))
    }

    private func monthAndYear(_ year: Int, _ month: Int) -> String {
        format(year: year, month: month, style: .dateTime.month(.wide).year())
    }

    private func format(year: Int, month: Int, style: Date.FormatStyle) -> String {
        guard let date = Self.calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return String(month)
        }
        var style = style
        style.timeZone = Self.calendar.timeZone
        return date.formatted(style)
    }

    /// Changing how sure somebody is starts the questions again. A year chosen
    /// on the way to a day means nothing once the answer is "vuosikymmen", and
    /// leaving it there would tick a row nobody had chosen.
    private var chosenSureness: Binding<Sureness> {
        Binding(
            get: { sureness },
            set: { choice in
                sureness = choice
                pickedYear = nil
                pickedMonth = nil
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                form(proxy)
            }
            .elderSurface()
        }
    }

    private func form(_ proxy: ScrollViewProxy) -> some View {
            Form {
                Section {
                    Picker("Kuinka tarkkaan tiedät?", selection: chosenSureness) {
                        ForEach(Sureness.allCases) { choice in
                            Text(LocalizedStringKey(choice.label)).tag(choice)
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
                    // contrast failure and an eye reads as a covered row. It is
                    // also what every other sheet in this app does — see
                    // `NameSheet` and `AskQuestionSheet`.
                    Button("Peruuta") { dismiss() }
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                } header: {
                    // A List styles its own headers below the contrast minimum.
                    Text("Kuinka tarkkaan tiedät?")
                        .foregroundStyle(Elder.supporting)
                } footer: {
                    Text(single == nil
                        ? String(localized: "Vastaus koskee kaikkia \(subjects.count) kuvaa. Voit muuttaa yksittäisen kuvan ajankohtaa myöhemmin sen omalta kortilta.")
                        : String(localized: "Epävarma vastaus on oikea vastaus. Sovellus tallentaa sen sellaisenaan eikä arvaa tarkempaa."))
                        .foregroundStyle(Elder.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // **Choosing is answering.** There is no save button: tapping a
                // year stores it and closes the sheet, which is the pattern
                // `RelationPicker` already uses for the same shape of question.
                // One tap instead of two, and nothing that has to stay on screen
                // while a long list scrolls past it.
                //
                // On the way to a month or a day the same tap answers one step
                // and asks the next, which is the one thing that had to give:
                // the rule is that the LAST tap saves and closes, and nothing in
                // between is stored. A day half chosen is not a date.
                //
                // Lists rather than wheels: a wheel's text does not grow with
                // Dynamic Type — measured on this very screen — and an inline
                // picker is a column of full-width rows that scale like
                // everything else.
                Section {
                    switch step {
                    case .decade:
                        ForEach(Self.decades, id: \.self) { start in
                            choice(String(localized: "\(String(start))-luku"), isCurrent: isStored(decade: start)) {
                                save(hint(decade: start))
                            }
                            .id("decade-\(start)")
                        }
                    case .year:
                        // `String(year)` rather than the number: SwiftUI formats
                        // an Int with the locale's thousands separator, and
                        // "1 957" is not a year.
                        ForEach(Self.years, id: \.self) { value in
                            choice(String(value), isCurrent: isStored(year: value)) {
                                if sureness == .year { save(hint(year: value)) } else { pickedYear = value }
                            }
                            .id("year-\(value)")
                        }
                    case .month:
                        if let year = pickedYear {
                            chosen(String(year), change: String(localized: "Vaihda vuosi")) {
                                pickedYear = nil
                            }
                            ForEach(months(of: year), id: \.self) { value in
                                choice(monthName(year, value), isCurrent: isStored(year: year, month: value)) {
                                    pickedMonth = value
                                }
                                .id("month-\(value)")
                            }
                        }
                    case .day:
                        if let year = pickedYear, let month = pickedMonth {
                            chosen(monthAndYear(year, month), change: String(localized: "Vaihda kuukausi")) {
                                pickedMonth = nil
                            }
                            // The month as an answer in its own right, offered
                            // where it is actually needed: somebody who has
                            // just said "kesäkuu 1957" and is looking at the
                            // days of it is exactly the person who knows
                            // whether the day is remembered. It is first
                            // because it is the coarser answer and the screen
                            // never makes the finer one the default.
                            choice(
                                String(localized: "Koko kuukausi"),
                                isCurrent: isStored(year: year, month: month, whole: true)
                            ) {
                                save(hint(year: year, month: month))
                            }
                            ForEach(days(of: year, month), id: \.self) { value in
                                choice(
                                    String(value),
                                    isCurrent: isStored(year: year, month: month, day: value)
                                ) {
                                    save(hint(year: year, month: month, day: value))
                                }
                                .id("day-\(value)")
                            }
                        }
                    case .nothing:
                        choice(String(localized: "Poista ajankohta"), isCurrent: false) {
                            save(DateHint(start: nil, end: nil, precision: .unknown))
                        }
                    }
                } header: {
                    // Which of the three questions this list is. "Valitse" alone
                    // was enough while there was only ever one of them, and it
                    // was also one of two strings on this screen that reached an
                    // English phone in Finnish: a ternary's literal is not an
                    // argument, and the check cannot see one (19 Sep 2026).
                    Text(heading)
                        .foregroundStyle(Elder.supporting)
                }
            }
            .navigationTitle(single == nil ? String(localized: "Milloin nämä olivat?") : String(localized: "Milloin tämä oli?"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                load()
                // To the ticked row, once the list exists. Verifying what a
                // photo already claims meant scrolling most of a century: the
                // years run 1900 upwards, and a family archive's common
                // decades sit mid-list with the tick ~60 rows off-screen.
                Task { scrollToStored(proxy) }
            }
            // A new question is a new list, and it arrives scrolled to wherever
            // the last one was left. The months of 1957 read from the top; the
            // years read from the year the photograph already claims.
            .onChange(of: sureness) { _, _ in Task { scrollToStored(proxy) } }
            .onChange(of: pickedYear) { _, value in
                Task { value == nil ? scrollToStored(proxy) : proxy.scrollTo(Self.topRow, anchor: .top) }
            }
            .onChange(of: pickedMonth) { _, _ in
                Task { proxy.scrollTo(Self.topRow, anchor: .top) }
            }
    }

    private var heading: String {
        switch step {
        case .decade: String(localized: "Valitse vuosikymmen")
        case .year: String(localized: "Valitse vuosi")
        case .month: String(localized: "Valitse kuukausi")
        case .day: String(localized: "Valitse päivä")
        case .nothing: ""
        }
    }

    /// Brings the stored answer's row into view. Only when there is one:
    /// a fresh photo and the many-photos import start at the top as before.
    private func scrollToStored(_ proxy: ScrollViewProxy) {
        guard let stored else { return }
        switch step {
        case .decade: proxy.scrollTo("decade-\(stored.year / 10 * 10)", anchor: .center)
        case .year: proxy.scrollTo("year-\(stored.year)", anchor: .center)
        case .month, .day, .nothing: break
        }
    }

    /// One answer. The stored one is ticked — the shape says which it is, not a
    /// colour, and it is how somebody sees what the photo already claims.
    private func choice(_ label: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    // Every row here was one word or one number until "Koko
                    // kuukausi", and a phrase in an HStack beside a Spacer is
                    // squeezed rather than wrapped: the sweep read it as
                    // "Dynamic Type font sizes are partially unsupported" at
                    // the default size, on the row at the very top of the
                    // screen, so this one is not about the fold. Vertical
                    // fixedSize lets it take the lines it needs.
                    .fixedSize(horizontal: false, vertical: true)
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

    /// The step already answered, and the way back up it. Standing above the
    /// days it is also the only place on the screen that says which month they
    /// belong to — so it says it in words, "kesäkuu 1957", rather than leaving
    /// a column of numbers to stand for a date on its own.
    ///
    /// Two lines and not one row of two texts: at the largest text size a year
    /// beside a sentence is the clipping the audit reports on this very screen.
    private func chosen(_ value: String, change: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "chevron.left")
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.body.weight(.semibold))
                    Text(change)
                        .font(.body)
                        .foregroundStyle(Elder.supporting)
                }
                // No Spacer beside these two lines. One was here, and at the
                // largest text size the sweep read "Vaihda kuukausi" as clipped
                // inside a 200-point frame: a Spacer takes the room it is given
                // before the text it stands beside asks for any.
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .elderTapTarget()
        }
        .buttonStyle(.plain)
        .id(Self.topRow)
    }

    /// What the archive holds for this photograph, in pieces this screen can
    /// compare a row against. Only when a single subject is being dated: with
    /// many, "the stored one" is a question with several answers, and a tick
    /// that means "some of them" says less than no tick at all.
    private var stored: (precision: DatePrecision, year: Int, month: Int, day: Int)? {
        guard let subject = single, let hint = subject.dateHint, let start = hint.start else { return nil }
        let parts = Self.calendar.dateComponents([.year, .month, .day], from: start)
        return (hint.precision, parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func isStored(decade: Int) -> Bool {
        guard let stored, stored.precision == .decade else { return false }
        return stored.year / 10 * 10 == decade
    }

    /// A stored day is a stored year as well, so the year it falls in is ticked
    /// on the way past it. A decade is not: "joskus viisikymmentäluvulla" makes
    /// no claim about 1957, and a tick there would be the rounding rule 5
    /// forbids, drawn by the screen that exists to prevent it.
    private func isStored(year: Int) -> Bool {
        guard let stored, stored.precision == .year || stored.precision == .month || stored.precision == .day
        else {
            return false
        }
        return stored.year == year
    }

    private func isStored(year: Int, month: Int) -> Bool {
        guard let stored, stored.precision == .month || stored.precision == .day else { return false }
        return stored.year == year && stored.month == month
    }

    /// The whole month, which is a different answer from any day in it.
    private func isStored(year: Int, month: Int, whole: Bool) -> Bool {
        guard let stored, stored.precision == .month else { return false }
        return stored.year == year && stored.month == month
    }

    private func isStored(year: Int, month: Int, day: Int) -> Bool {
        guard let stored, stored.precision == .day else { return false }
        return stored.year == year && stored.month == month && stored.day == day
    }

    /// Opens on what is already stored, so a small correction is a small
    /// gesture rather than a re-entry. A stored day opens on its own day, with
    /// the month and the year above it and one tap back to either.
    private func load() {
        guard let stored else { return }
        switch stored.precision {
        case .decade:
            sureness = .decade
        case .year:
            sureness = .year
        case .month, .day:
            sureness = .date
            pickedYear = stored.year
            pickedMonth = stored.month
        case .unknown:
            sureness = .unknown
        }
    }

    private func save(_ answer: DateHint) {
        // "En tiedä" is an answer and is stored as one, rather than as an empty
        // field. The difference is invisible here — both show nothing — and it
        // decides what happens on another phone: sync keeps a date unless the
        // pushing device says something about it, so a cleared date sent as an
        // absence would come back on the next sync from somebody's older copy.
        // It is the same reason the sheet asks how sure you are before it asks
        // for a number.
        for subject in subjects {
            store.setDateHint(subjectID: subject.id, hint: answer)
        }
        dismiss()
    }

    /// The span the answer really covers. A decade is ten years wide and is
    /// stored that way — writing 1 January 1950 alone would turn "joskus
    /// viisikymmentäluvulla" into a day nobody claimed. A day is the one answer
    /// whose two ends are the same date, which is what makes it a day.
    private func hint(decade: Int) -> DateHint {
        DateHint(
            start: Self.calendar.date(from: DateComponents(year: decade, month: 1, day: 1)),
            end: Self.calendar.date(from: DateComponents(year: decade + 9, month: 12, day: 31)),
            precision: .decade
        )
    }

    private func hint(year: Int) -> DateHint {
        DateHint(
            start: Self.calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
            end: Self.calendar.date(from: DateComponents(year: year, month: 12, day: 31)),
            precision: .year
        )
    }

    private func hint(year: Int, month: Int) -> DateHint {
        let start = Self.calendar.date(from: DateComponents(year: year, month: month, day: 1))
        return DateHint(
            start: start,
            end: start.flatMap {
                Self.calendar.date(byAdding: DateComponents(month: 1, day: -1), to: $0)
            },
            precision: .month
        )
    }

    private func hint(year: Int, month: Int, day: Int) -> DateHint {
        let date = Self.calendar.date(from: DateComponents(year: year, month: month, day: day))
        return DateHint(start: date, end: date, precision: .day)
    }
}
