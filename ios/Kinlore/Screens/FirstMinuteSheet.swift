import SwiftUI

/// The first minute after an archive is created, on the phone of whoever set
/// it up: whose memories it is for, and how that person will tell them.
///
/// Since 13 Sep 2026. Until then "Luo arkisto" led straight to the Kerro tab,
/// which asks the person holding the phone to tell *their own* memories — and
/// the person who sets up a family archive has, as a rule, bought it for
/// somebody else's. The name they type becomes a confirmed card
/// (`MemoryStore.addPerson`), so the family has somebody in it before anybody
/// has spoken.
///
/// The second step asks how she will tell, and both answers are real ones: her
/// own phone, which sends an invitation made out to her name, or this phone,
/// which is the only answer for a grandmother with no smartphone. The founder
/// asked for that second answer on first sight of the sheet, when it offered
/// the invitation and a "Valmis" that did not say it meant "no invitation".
///
/// One blue button (§22), and a way out of the first step that creates nobody.
/// Scrolls, because at the largest text size a title, a sentence, a field and
/// two buttons do not fit on a screen — the lesson `InviteShareButton`'s sheet
/// records.
struct FirstMinuteSheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    /// The card made in the first step, which is what the second is about.
    @State private var person: Subject?

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let person {
                        howTheyTell(person)
                    } else {
                        naming
                    }
                }
                .padding(Elder.screenPadding)
            }
            .elderSurface()
        }
    }

    private var naming: some View {
        Group {
            Text("Kenen muistot haluat tallentaa?")
                .font(Elder.display(.title2))
                .fixedSize(horizontal: false, vertical: true)

            Text("Kirjoita hänen nimensä, niin hän saa oman kortin. Hän voi kertoa omalla puhelimellaan tai tällä.")
                .font(.subheadline)
                .foregroundStyle(Elder.supporting)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Nimi", text: $name)
                .textInputAutocapitalization(.words)
                .font(.body)
                .padding(12)
                .elderCard(radius: 16)

            Button {
                person = store.addPerson(named: trimmed)
            } label: {
                Text("Jatka")
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .elderTapTarget()
            .disabled(trimmed.isEmpty)

            Button("Sulje") { dismiss() }
                .frame(maxWidth: .infinity)
                .elderTapTarget()
        }
    }

    /// Two short answers to one question, rather than a long label on each:
    /// the question carries the meaning, and a short label does not get cut
    /// at the largest text size.
    private func howTheyTell(_ person: Subject) -> some View {
        Group {
            Text("\(person.displayTitle) on nyt arkistossa")
                .font(Elder.display(.title2))
                .fixedSize(horizontal: false, vertical: true)

            Text("Miten hän kertoo muistonsa?")
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            // With her card, so that joining through this invitation makes her
            // that card rather than a second person under her name.
            InviteShareButton(
                title: "Omalla puhelimellaan",
                suggestedName: person.displayTitle,
                personSubjectID: person.id
            )
                .buttonStyle(.borderedProminent)

            // The card already exists, so this is the way out as well as an
            // answer: nothing is sent, and she tells on the Kerro tab here.
            Button {
                dismiss()
            } label: {
                Text("Tällä puhelimella")
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .elderTapTarget()

            Text("Jos hänellä ei ole älypuhelinta, hän voi kertoa tällä. Kutsun voi lähettää myöhemmin Asetuksista.")
                .font(.subheadline)
                .foregroundStyle(Elder.supporting)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
