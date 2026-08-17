import SwiftUI

/// The invitation, from tap to share sheet, in one implementation.
///
/// Two screens offer it — the family view, and the finished-memory screen's
/// offer slot while the family is one person (docs/UX.md §3.2) — and they must
/// produce the same invitation: the same code, the same key, the same words
/// around them. The button creates the invite on the server, then opens a
/// small sheet whose one row hands the text to the system share sheet.
///
/// Unstyled on purpose: the family view shows it as an ordinary row and the
/// offer card makes it prominent, and `buttonStyle` reaches it from either
/// call site. §22's one-blue-button rule is decided where the button is
/// placed, not here.
struct InviteShareButton: View {
    @Environment(Session.self) private var session

    @State private var code: String?
    @State private var isSharing = false

    var body: some View {
        Button {
            Task {
                code = await session.createInvite()
                if code != nil { isSharing = true }
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
        .sheet(isPresented: $isSharing) {
            if let code {
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
    ///
    /// **Both halves carry the family key since PLAN.md §10 lever 3**, joined
    /// to the invite code by `#`. They have to be the same string: the paste
    /// field exists so that somebody who cannot open a link can still get in,
    /// and a fallback that produced a member who could not read anything would
    /// be worse than no fallback.
    ///
    /// This is also where the honesty about lever 3 has to be stated, because
    /// it is the one thing about it a user could be misled by. The server
    /// never sees this key — that is the whole design — but **whatever carried
    /// this message did.** Sending it over a chat app puts the key wherever
    /// that app keeps it. It is still a large improvement on the archive
    /// itself being readable in a dump, and it is not the same claim as
    /// end-to-end.
    static func inviteText(code: String) -> String {
        let shared = FamilyKey.shareable().map { "\(code)#\($0)" } ?? code
        return """
        Liity perheen muistoarkistoon:
        kinlore://join?code=\(shared)

        Tai avaa sovellus ja liitä tämä koodi:
        \(shared)
        """
    }
}
