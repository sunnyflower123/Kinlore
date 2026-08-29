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

                Button {
                    // The rows first, the mode second. They were told while
                    // there was nowhere to send them, so nothing ever queued
                    // them; without this the archive would sit on the phone
                    // while every screen said it was shared.
                    store.markAllPending()
                    session.enableFamilySharing()
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
    }
}

#Preview {
    NavigationStack {
        EnableSharingScreen()
            .environment(MemoryStore(filename: "preview-store.json"))
            .environment(Session())
    }
}
