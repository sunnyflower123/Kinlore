import SwiftUI

/// The family's members and the invite link.
///
/// The invite link is the entire security boundary: anyone who receives it sees
/// all of the family's memories. That is why this screen shows who has joined
/// and how many people have used the link — it is the only visibility into that
/// boundary.
struct FamilyScreen: View {
    @Environment(Session.self) private var session

    @State private var freshCode: String?
    @State private var isSharing = false

    var body: some View {
        List {
            if let family = session.family {
                Section("Perhe") {
                    LabeledContent("Nimi", value: family.name)
                    LabeledContent(
                        "Tila",
                        value: family.entitlement == "archive" ? "Maksullinen" : "Ilmainen"
                    )
                }

                if let usage = session.usage {
                    Section("Käyttö") {
                        LabeledContent(
                            "AI-minuutit",
                            value: usage.aiSeconds.limit == nil
                                ? "rajaton"
                                : "\(usage.aiSeconds.used / 60) / \(usage.aiSeconds.limit! / 60) min"
                        )
                        LabeledContent(
                            "Kuvat",
                            value: usage.photos.limit == nil
                                ? "rajaton"
                                : "\(usage.photos.used) / \(usage.photos.limit!)"
                        )
                    }
                }

                Section("Jäsenet") {
                    ForEach(family.members) { member in
                        MemberRow(member: member, isYou: member.id == family.you.id)
                    }
                }

                Section {
                    Button {
                        Task {
                            freshCode = await session.createInvite()
                            if freshCode != nil { isSharing = true }
                        }
                    } label: {
                        if session.isWorking {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label("Kutsu perheenjäsen", systemImage: "person.badge.plus")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .elderTapTarget()
                        }
                    }
                    .disabled(session.isWorking)

                    ForEach(family.invites) { invite in
                        InviteRow(invite: invite) {
                            Task { await session.revokeInvite(code: invite.code) }
                        }
                    }
                } header: {
                    Text("Kutsut")
                } footer: {
                    Text("Kutsu on voimassa viikon. Kuka tahansa linkin saanut näkee perheen kaikki muistot, joten jaa se vain niille joille se kuuluu.")
                }
            } else {
                Section {
                    // The family details are not a precondition for use:
                    // membership is local state and the app works offline.
                    Label("Perheen tietoja ei saatu haettua", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                    Text("Voit silti kertoa muistoja. Ne synkronoituvat kun yhteys palaa.")
                        .elderBody()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Perhe")
        .task { await session.refresh() }
        .refreshable { await session.refresh() }
        .sheet(isPresented: $isSharing) {
            if let code = freshCode {
                ShareLink(item: Self.inviteText(code: code)) {
                    Label("Jaa kutsu", systemImage: "square.and.arrow.up")
                }
                .presentationDetents([.medium])
                .padding(Elder.screenPadding)
            }
        }
    }

    /// The shared text contains both the link and the code. The link is quick,
    /// but the code works even when the messaging app does not make the link
    /// tappable — and grandmother cannot be asked to work out why a link will
    /// not open.
    private static func inviteText(code: String) -> String {
        """
        Liity perheen muistoarkistoon:
        memorize://join?code=\(code)

        Tai avaa sovellus ja liitä tämä koodi:
        \(code)
        """
    }
}

private struct MemberRow: View {
    let member: Session.Member
    let isYou: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: member.role == "owner" ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(isYou ? "\(member.displayName) (sinä)" : member.displayName)
                    .font(.body.weight(.medium))
                Text(member.role == "owner" ? "Perustaja" : "Jäsen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct InviteRow: View {
    let invite: Session.Invite
    let onRevoke: () -> Void

    private var expiryText: String {
        let days = Int((invite.expiresAt - Date().timeIntervalSince1970) / 86_400)
        if days <= 0 { return "vanhenee tänään" }
        return days == 1 ? "vanhenee huomenna" : "vanhenee \(days) päivän päästä"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(invite.usedCount == 0
                    ? "Avoin kutsu"
                    : "Käytetty \(invite.usedCount) kertaa")
                    .font(.body)
                Text(expiryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Mitätöi", role: .destructive, action: onRevoke)
                .font(.subheadline.weight(.medium))
                .elderTapTarget()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        FamilyScreen().environment(Session())
    }
}
