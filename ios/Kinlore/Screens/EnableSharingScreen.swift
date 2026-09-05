import SwiftUI

/// The way out of a single-device archive that does not cost the archive.
///
/// *"Keiden kesken"* is answered on the first form in the app, before anybody
/// knows what the app does, and until this existed the only thing that unmade
/// it was *"Tyhjennä tämä laite"* — an exit priced at every memory on the
/// phone. The wrong answer was expensive too: the kept-here mode attempts no
/// transcription at all, so one picker answered out of habit turned the product
/// off for good on that device.
///
/// **A screen and not a `confirmationDialog`.** The dialog was written first
/// and its row would not pass the audit at all — a `Label` inside a `Button`
/// inside this `List` is measured as a text element pinned to the tap target's
/// height, and reports as clipped and as not scaling with Dynamic Type, six
/// runs' worth of it. A `NavigationLink` carrying the identical label passes,
/// and it does so twice already on the screen this row sits on. That is the
/// shape with evidence behind it.
///
/// It is the better answer anyway. A system dialog's message is the smallest
/// text in the exchange and grows worst of anything on screen, and what has to
/// be read here is three sentences about a change that cannot be undone.
struct EnableSharingScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var isOpening = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Nyt muistot ovat vain tässä puhelimessa, eikä puheesta kirjoiteta tekstiä.")
                    .elderBody()

                Text("Perheen kesken kutsumasi jäsenet näkevät muistot, ja kertomasi kirjoitetaan tekstiksi.")
                    .elderBody()

                // The one consequence somebody could reasonably not expect,
                // said before it happens rather than discovered after: what is
                // already on this phone is not left behind, it travels.
                Text("Tämän puhelimen muistot lähtevät sille perheelle, jonka perustat tai johon liityt.")
                    .elderBody()

                // And the direction. This is a one-way door — what has reached
                // the family is on other people's phones, and an app that
                // offered to take it back would be lying about somebody else's
                // device.
                Text("Takaisin vain tähän puhelimeen ei pääse.")
                    .elderBody()
                    .foregroundStyle(Elder.supporting)

                // And the one thing that is not yet one-way: until a family
                // exists, nothing has happened. The fork opens as a sheet over
                // this archive, and the answer to "keiden kesken" is unmade
                // only when the create or the join succeeds
                // (`Session.store(familyID:)`). Before 5 Sep 2026 the button
                // itself flipped the mode and the root view became the fork —
                // and at a cottage with no signal, every relaunch landed there
                // again, with the month's memories out of sight and this
                // screen's last sentence saying there was no way back.
                Text("Voit vielä perua, kunnes perhe on perustettu tai siihen on liitytty.")
                    .elderBody()
                    .foregroundStyle(Elder.supporting)

                Button {
                    // The rows first. They were told while there was nowhere
                    // to send them, so nothing ever queued them; without this
                    // the archive would sit on the phone while every screen
                    // said it was shared. Harmless if the sheet is cancelled:
                    // the queue only runs in a family.
                    store.markAllPending()
                    isOpening = true
                } label: {
                    // Allowed to wrap, and the 60 pt minimum on the control
                    // rather than on the label: on the label it fights the
                    // button style over the box the text goes in, and the audit
                    // reports the words as clipped. See `AskQuestionSheet`.
                    Text("Ota perhe käyttöön")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .elderTapTarget()
            }
            .padding(Elder.screenPadding)
        }
        .navigationTitle("Perhe")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isOpening) {
            OnboardingScreen(prefilledCode: .constant(nil), fromLocalArchive: true)
        }
        // The family exists: the sheet has done its work, and so has this
        // screen — the row that leads here is gone from Settings.
        .onChange(of: session.isLocalByChoice) { _, isLocal in
            if !isLocal {
                isOpening = false
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        EnableSharingScreen()
            .environment(MemoryStore(filename: "preview-store.json"))
            .environment(Session())
    }
}
