import SwiftUI

/// Onboarding. Two options, nothing else.
///
/// No sign-in, no email, no password. Grandmother gets a link from a grandchild
/// and taps "Liity". This is precisely the point where this audience normally
/// drops out.
struct OnboardingScreen: View {
    @Environment(Session.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The code from an invite link, or nil.
    ///
    /// A binding rather than a value, and read on change rather than on appear.
    /// Both halves were wrong before, and the first one is the flow this whole
    /// no-login design exists for:
    ///
    /// **Tapping the link usually does not launch the app.** It is already
    /// running — a person opens a new app before they use the link, or reads the
    /// message with the app in the background — so iOS shows "Open in Memorize?"
    /// and returns to a screen that appeared minutes ago. `onAppear` fires once,
    /// so the code was dropped and grandmother was looking at the same two
    /// buttons as before, with nothing filled in and no clue why. On a cold
    /// launch it worked, which is exactly the kind of half that gets tested.
    ///
    /// Cleared once it has been used, so that a code from a family she has since
    /// left cannot fill itself in over a fresh invitation.
    @Binding var prefilledCode: String?

    @State private var route: Route?
    @State private var name = ""
    @State private var familyName = ""
    @State private var code = ""

    private enum Route: Hashable { case create, join }

    /// Shortened at accessibility sizes so the two buttons stay above the fold.
    /// In full it ran to eight lines and pushed both of them off the screen —
    /// and a first screen whose only two actions have to be found by scrolling
    /// is a first screen this user does not get past. The first sentence is the
    /// promise; the second is how it is kept, and the buttons say that anyway.
    private var intro: String {
        typeSize.isAccessibilitySize
            ? "Kerätkää talteen se mitä isovanhemmat muistavat."
            : "Kerätkää yhdessä talteen se mitä isovanhemmat muistavat. Kerro omalla äänelläsi — me järjestämme."
    }

    var body: some View {
        NavigationStack {
            // Scrolling, and every label allowed to wrap.
            //
            // At the largest text size this screen failed worse than any other,
            // and it is the first one a new user ever sees: the title truncated
            // to "Perheen m…", the primary button to "Aloita perh…", and "Liity
            // kutsulinkillä" was off the bottom of the screen entirely. A
            // grandmother holding an invite link could not find the way in —
            // which is the one flow the whole no-login design exists for.
            GeometryReader { proxy in
                ScrollView {
                    content
                        .padding(Elder.screenPadding)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationDestination(item: $route) { destination in
                switch destination {
                case .create:
                    CreateFamilyForm(name: $name, familyName: $familyName)
                case .join:
                    JoinFamilyForm(name: $name, code: $code)
                }
            }
        }
        .onAppear { useInvite() }
        // The link arriving while this screen is already open is the ordinary
        // case, not the exception.
        .onChange(of: prefilledCode) { _, _ in useInvite() }
    }

    /// Takes the code out of the link and puts the join form in front of her.
    ///
    /// A link is a deliberate act and the most recent one, so it wins over
    /// whatever is in the field — somebody who taps a fresh invitation while a
    /// stale code is half-typed meant the fresh one.
    private func useInvite() {
        guard let invite = prefilledCode, !invite.isEmpty else { return }
        code = invite
        route = .join
        prefilledCode = nil
    }

    private var content: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            // The mark is decoration. At accessibility sizes it competes with
            // the two buttons for the same screen, and the buttons win.
            if !typeSize.isAccessibilitySize {
                Image(systemName: "photo.stack")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                    // Decoration, and VoiceOver was reading it out as
                    // "photo.stack" — the symbol's own name, in English, on the
                    // first screen of a Finnish app.
                    .accessibilityHidden(true)
            }

            VStack(spacing: 14) {
                Text("Perheen muistot")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(intro)
                    .elderBody()
                    .foregroundStyle(Elder.supporting)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            VStack(spacing: 14) {
                Button {
                    route = .create
                } label: {
                    // fixedSize so the label wraps instead of truncating. A
                    // button whose text ends in an ellipsis does not say what
                    // it does, and this one is the whole point of the screen.
                    Text("Aloita perheen arkisto")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    route = .join
                } label: {
                    Text("Liity kutsulinkillä")
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
                .controlSize(.large)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Creating a family

private struct CreateFamilyForm: View {
    @Environment(Session.self) private var session
    @Binding var name: String
    @Binding var familyName: String

    private var isReady: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Esimerkiksi Virtaset", text: $familyName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Suvun nimi")
            } footer: {
                Text("Voit jättää tyhjäksi ja päättää myöhemmin.")
            }

            Section {
                TextField("Nimesi", text: $name)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Kuka sinä olet")
            } footer: {
                Text("Tämä näkyy muistojesi vieressä, jotta perhe tietää kuka kertoi.")
            }

            Section {
                Button {
                    Task {
                        await session.createFamily(named: familyName, displayName: name)
                    }
                } label: {
                    if session.isWorking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Luo arkisto")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!isReady || session.isWorking)
                .elderTapTarget()
            }

            if let error = session.lastError {
                Section { ErrorNote(text: error) }
            }
        }
        .navigationTitle("Uusi arkisto")
    }
}

// MARK: - Joining

private struct JoinFamilyForm: View {
    @Environment(Session.self) private var session
    @Binding var name: String
    @Binding var code: String

    private var isReady: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
            !code.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Nimesi", text: $name)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Kuka sinä olet")
            } footer: {
                Text("Tämä näkyy muistojesi vieressä.")
            }

            Section {
                // The invite code is not meant to be read, so autocorrection and
                // capitalisation would only break it.
                TextField("Liitä kutsukoodi", text: $code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("Kutsu")
            } footer: {
                Text("Sait linkin tai koodin perheenjäseneltä. Voit liittää sen tähän.")
            }

            Section {
                Button {
                    Task { await session.join(code: code, displayName: name) }
                } label: {
                    if session.isWorking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Liity perheeseen")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!isReady || session.isWorking)
                .elderTapTarget()
            }

            if let error = session.lastError {
                Section { ErrorNote(text: error) }
            }
        }
        .navigationTitle("Liity perheeseen")
    }
}

private struct ErrorNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(Elder.proposal)
            .elderBody()
    }
}

#Preview {
    OnboardingScreen(prefilledCode: .constant(nil))
        .environment(Session())
}
