import SwiftUI

/// Who told the memory that has just been saved.
///
/// The author is the phone and the teller is the voice, and they come apart
/// the moment one phone goes round a table — the case this app was born in
/// (docs/PLAN.md §8: a memorial, twenty-five people, photographs on the table
/// and nobody able to tell any of it). Until 19 Sep 2026 every telling made on
/// this phone was filed under the phone's owner, so a grandmother's story told
/// into a grandchild's phone read *"Ville kertoi"* for ever after.
///
/// **A question and not a quiet row.** It is asked outright after every
/// telling, above the memory's own text, because the one screen where the
/// answer is known is this one: the person who spoke is still in the room and
/// the phone is still in somebody's hand. A row that had to be noticed would
/// be noticed by whoever set the archive up and by nobody else.
///
/// Three answers, and the third is the reason there is a flag beside the id.
/// *"Minä"* is whoever holds the phone, which is what the archive already
/// assumed. A person is anybody the family has a card for, or a new name
/// typed into the sheet behind *"Joku muu"*. And a teller may decline to be
/// named at all — `Memory.tellerHidden`, which shows the day instead of a
/// name everywhere a name would otherwise stand.
///
/// No prominent button here (ARCHITECTURE §22): the blue one on this screen
/// belongs to *"Jatketaan jutellen"* or *"Kerro toinen muisto"*, and a
/// question that must be answered before either would be a fourth.
struct TellerCard: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    let model: TellViewModel

    @State private var isPicking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.tellerChoice == nil {
                question
            } else {
                answered
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elderCard(radius: 16)
        .sheet(isPresented: $isPicking) {
            TellerSheet(model: model)
        }
    }

    // MARK: - Asking

    private var question: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Kuka kertoi tämän muiston?")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Nimi tulee muiston viereen perheen arkistoon.")
                .font(.subheadline)
                .foregroundStyle(Elder.supporting)
                .fixedSize(horizontal: false, vertical: true)

            // Whoever holds the phone, first, because they are who answers
            // most of the time. Their own card in the tree when the member has
            // been linked to one; without a link the author's name already is
            // this person's and there is nothing to store.
            Button {
                model.chooseTeller(.me(session.family?.you.personSubjectID))
            } label: {
                Text("Minä").modifier(ChoiceLabel())
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            // Whoever spoke last time, and the time before. Built from what
            // has been chosen rather than from the person list: a family of
            // fifty-three has fifty-three people in it and two of them are in
            // the room.
            ForEach(model.recentTellers) { person in
                Button {
                    model.chooseTeller(.person(person.id))
                } label: {
                    // `verbatim`, because a name is not a key. `Text` shows a
                    // `String` variable as it stands in any case; saying so
                    // here keeps the next person from making it a literal and
                    // quietly looking up *"Aino"*.
                    Text(verbatim: person.displayTitle).modifier(ChoiceLabel())
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button {
                isPicking = true
            } label: {
                Text("Joku muu").modifier(ChoiceLabel())
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            // Quiet and last. A telling nobody wants their name on is still a
            // telling worth keeping — rule 2 read one step further — and the
            // alternative a person without this row has is not to speak.
            Button("En halua nimeäni näkyviin") {
                model.chooseTeller(.hidden)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Elder.supporting)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elderTapTarget()
        }
    }

    // MARK: - Answered

    private var answered: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.tellerIsHidden {
                Text("Nimeä ei näytetä tämän muiston vieressä.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Tämän muiston kertoi \(tellerName)")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Only after a name, and only under a photograph: the one answer
            // this card can give that the photograph does not already know.
            // Somebody who says *"that's me"* is not among its people until a
            // hand says so, because *"me"* is not a name the telling can hear.
            if let placed = model.placedTeller {
                Text("\(placed.displayTitle) on merkitty tämän kuvan ihmisiin.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                // The width inside the label and not on the button: outside
                // it the row is drawn 326 points wide and answers only on its
                // two words — measured 21 Sep 2026, a tap at the row's centre
                // did nothing and one on the words took it back.
                Button {
                    model.placeTellerInPhoto(false)
                } label: {
                    Text("Poista merkintä")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .elderTapTarget()
                }
                .foregroundStyle(Elder.supporting)
            } else if let teller = model.tellerToPlace {
                Button {
                    model.placeTellerInPhoto(true)
                } label: {
                    Group {
                        if case .me? = model.tellerChoice {
                            Text("Minä olen tässä kuvassa")
                        } else {
                            Text("\(teller.displayTitle) on tässä kuvassa")
                        }
                    }
                    .modifier(ChoiceLabel())
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button("Vaihda kertoja") { model.clearTellerChoice() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Elder.supporting)
                .frame(maxWidth: .infinity, alignment: .leading)
                .elderTapTarget()
        }
    }

    /// The chosen person's card title, or — for *"minä"* on a phone whose
    /// member has no card in the tree — the name this device already puts
    /// beside its tellings.
    private var tellerName: String {
        model.chosenTeller?.displayTitle ?? store.authorName
    }
}

/// One answer's label: full width, left aligned, and allowed to wrap.
///
/// A modifier rather than a helper that builds the whole button, because a
/// literal handed to a helper is invisible to `localisation-check.mjs` — the
/// defect the help page had for a week, where the check was green and the
/// whole page was Finnish on an English phone. Here every word the user reads
/// sits in a `Text` of its own where the check can see it.
///
/// A column of these and never a row: at the largest text size two names side
/// by side is two truncations, which is the lesson the heard-names rows above
/// already carry.
private struct ChoiceLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body.weight(.medium))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elderTapTarget()
    }
}

// MARK: - The whole family

/// Everybody the family has a card for, when the two names on the card were
/// not the right ones.
///
/// The same shape as `RelationPicker` and for the same reasons: *"Joku uusi"*
/// first, because a person who has never been spoken of has no card yet and
/// the teller at the table is exactly that person; confirmed people only,
/// because a heard name nobody has checked is not somebody to file a telling
/// under (rule 4); and the way out is a row rather than a toolbar button,
/// whose text barely grows with Dynamic Type.
struct TellerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: TellViewModel

    @State private var isAddingSomeoneNew = false
    @State private var addedSomeoneNew = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    isAddingSomeoneNew = true
                } label: {
                    // An `Image` and a `Text` rather than the `Label` this
                    // row is copied from, for the reason `HeardNamesDoorLabel`
                    // and the date row in `RootView` are written the same way:
                    // as a `Label` the audit reported *"Text clipped"* at the
                    // DEFAULT text size on this sweep's first run, while the
                    // screenshot taken by the same run showed *"Joku uusi"*
                    // drawn in full with two hundred points of room to spare.
                    // `fixedSize` alone did not move it; splitting the two
                    // views did, which is the third time in this repo that a
                    // `Label`'s title has measured clipped and its own words
                    // have not been the reason.
                    //
                    // `RelationPicker`'s identical row still uses a `Label`,
                    // and no sweep has ever opened that sheet — so this is one
                    // finding surfaced and one still unmeasured, not a defect
                    // fixed in both places.
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.plus")
                        Text("Joku uusi")
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .elderTapTarget()
                }

                ForEach(model.tellerCandidates) { person in
                    Button {
                        model.chooseTeller(.person(person.id))
                        dismiss()
                    } label: {
                        Text(verbatim: person.displayTitle)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .elderTapTarget()
                    }
                }
            }
            .navigationTitle("Muiston kertoja")
            .navigationBarTitleDisplayMode(.inline)
            // The picker closes only once the name sheet has gone, so two
            // sheets are not dismissed on the same frame.
            .sheet(isPresented: $isAddingSomeoneNew, onDismiss: {
                if addedSomeoneNew { dismiss() }
            }) {
                NameSheet(title: "Lisää henkilö", initial: "") { name in
                    guard model.addTeller(named: name) != nil else { return false }
                    addedSomeoneNew = true
                    return true
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Peruuta") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .elderTapTarget()
                    .padding(Elder.screenPadding)
                    .background(.bar)
            }
            .elderSurface()
        }
    }
}
