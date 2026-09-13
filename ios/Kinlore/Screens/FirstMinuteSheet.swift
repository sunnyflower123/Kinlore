import SwiftUI

/// The first minute after an archive is created, on the phone of whoever set
/// it up: whose memories it is for, then an invitation made out to them.
///
/// Since 13 Sep 2026. Until then "Luo arkisto" led straight to the Kerro tab,
/// which asks the person holding the phone to tell *their own* memories — and
/// the person who sets up a family archive has, as a rule, bought it for
/// somebody else's. The name they type becomes a confirmed card
/// (`MemoryStore.addPerson`), so the family has somebody in it before anybody
/// has spoken, and the invitation carries the same name, so the grandparent
/// who taps it does not have to type one.
///
/// Two steps, one blue button each (§22), and a way out of both that leaves
/// nothing half done: closing the first creates nobody, and the second is
/// "Valmis" because the card already exists. Scrolls, because at the largest
/// text size a title, a sentence, a field and two buttons do not fit on a
/// screen — the lesson `InviteShareButton`'s sheet records.
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
                        invitation(for: person)
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

            Text("Kirjoita hänen nimensä, niin hän saa oman kortin. Sitten voit kutsua hänet kertomaan omalla puhelimellaan.")
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

    private func invitation(for person: Subject) -> some View {
        Group {
            Text("\(person.displayTitle) on nyt arkistossa")
                .font(Elder.display(.title2))
                .fixedSize(horizontal: false, vertical: true)

            Text("Kutsu hänet omalle puhelimelleen, niin hän voi kertoa muistonsa itse.")
                .font(.subheadline)
                .foregroundStyle(Elder.supporting)
                .fixedSize(horizontal: false, vertical: true)

            InviteShareButton(suggestedName: person.displayTitle)
                .buttonStyle(.borderedProminent)

            Button("Valmis") { dismiss() }
                .frame(maxWidth: .infinity)
                .elderTapTarget()
        }
    }
}
