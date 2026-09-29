import SwiftUI

/// The language the app is shown in: the phone's own, English or Suomi
/// (`AppLanguage`), one step below Settings.
///
/// A screen of its own rather than three rows in Settings. It was made one
/// while the row stood beside the text size, above the wipe row, where that
/// List is at its height limit (`SettingsScreen`). The row is last there now,
/// where three rows and a footer would move nothing, and it stays one row: the
/// answers belong with the sentence about when they take effect, and the end
/// of Settings grows by one cell rather than three and a footer.
struct LanguageScreen: View {
    @State private var language = AppLanguage.chosen

    var body: some View {
        List {
            Section {
                // Inline, as the setup forms ask the text size: all three
                // answers visible without a tap. The check mark in ink, as
                // `DateSheet`'s, and not the accent, which is the red of
                // removal (`Elder.wax`).
                Picker("Kieli", selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(verbatim: option.name).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                // When, and nothing about how: the app keeps the language it
                // opened in until it is opened again (`AppLanguage`).
                Text("Kinlore vaihtaa kielen, kun se avataan seuraavan kerran.")
                    .foregroundStyle(Elder.supporting)
            }
        }
        .tint(Color.primary)
        .navigationTitle("Kieli")
        .onChange(of: language) { _, chosen in
            AppLanguage.chosen = chosen
        }
        .elderSurface()
    }
}

#Preview {
    NavigationStack {
        LanguageScreen()
    }
}
