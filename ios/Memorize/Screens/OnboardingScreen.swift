import SwiftUI

/// Aloitus. Kaksi vaihtoehtoa, ei muuta.
///
/// Ei kirjautumista, ei sähköpostia, ei salasanaa. Isoäiti saa linkin
/// lapsenlapselta ja painaa "Liity". Juuri tässä kohdassa tämä käyttäjäryhmä
/// tavallisesti putoaa pois.
struct OnboardingScreen: View {
    @Environment(Session.self) private var session

    /// Kutsulinkistä avattaessa koodi tulee valmiiksi täytettynä.
    var prefilledCode: String?

    @State private var route: Route?
    @State private var name = ""
    @State private var familyName = ""
    @State private var code = ""

    private enum Route: Hashable { case create, join }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "photo.stack")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)

                VStack(spacing: 14) {
                    Text("Perheen muistot")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text("Kerätkää yhdessä talteen se mitä isovanhemmat muistavat. Kerro omalla äänelläsi — me järjestämme.")
                        .elderBody()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 14) {
                    Button {
                        route = .create
                    } label: {
                        Text("Aloita perheen arkisto")
                            .font(.body.weight(.semibold))
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
                            .frame(maxWidth: .infinity)
                            .elderTapTarget()
                    }
                    .controlSize(.large)
                }

                Spacer()
            }
            .padding(Elder.screenPadding)
            .navigationDestination(item: $route) { destination in
                switch destination {
                case .create:
                    CreateFamilyForm(name: $name, familyName: $familyName)
                case .join:
                    JoinFamilyForm(name: $name, code: $code)
                }
            }
        }
        .onAppear {
            guard let prefilledCode, code.isEmpty else { return }
            code = prefilledCode
            route = .join
        }
    }
}

// MARK: - Perheen luonti

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

// MARK: - Liittyminen

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
                // Kutsukoodi ei ole luettavaksi tarkoitettu, joten
                // automaattikorjaus ja isot alkukirjaimet vain rikkoisivat sen.
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
            .foregroundStyle(.orange)
            .elderBody()
    }
}

#Preview {
    OnboardingScreen()
        .environment(Session())
}
