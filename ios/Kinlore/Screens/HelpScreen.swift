import SwiftUI

/// "Näin tämä toimii" — the page that was not there.
///
/// The app explains each step where the step happens, and that is the right
/// order. But three things are true of the whole app rather than of any screen,
/// and one of them the user cannot find out at all by using it: **the recording
/// leaves the phone.** It goes to our own server, which sends it on to be turned
/// into text. Nothing in the app said so, and the microphone prompt talked only
/// about keeping the voice for the family.
///
/// The other two are what a person asks when they are trusting something with
/// their family's memories: who can see this, and what happens to it if I stop
/// using the app.
///
/// It lives behind the gear rather than in the way. Nobody reads help before
/// they need it, and this audience least of all — but the day somebody wonders
/// whether the grandchildren can hear grandmother's voice, the answer has to be
/// somewhere.
struct HelpScreen: View {
    var body: some View {
        List {
            section(
                "Kertominen",
                "Paina isoa nappia ja puhu ihan vapaasti. Sinun ei tarvitse muistaa järjestystä eikä vuosilukuja — sovellus järjestää ne puolestasi.",
                "Jos puhuminen ei sovi juuri nyt, voit kirjoittaa muiston sen sijaan. Se päätyy arkistoon samanlaisena."
            )

            section(
                "Mitä äänellesi tapahtuu",
                "Äänitys lähetetään palveluumme, jossa puheesta kirjoitetaan teksti.",
                "Alkuperäinen äänitys säilyy aina. Teksti ei korvaa sitä — perhe voi kuunnella kertomasi omalla äänelläsi myös vuosien päästä."
            )

            section(
                "Kuka näkee muistot",
                "Vain ne, joille joku perheestä on lähettänyt kutsulinkin.",
                "Kuka tahansa linkin saanut näkee perheen kaikki muistot, joten jaa se vain omille. Perhe-näytöltä näet ketkä ovat liittyneet ja milloin."
            )

            section(
                "Sovellus ehdottaa, ihminen päättää",
                "Sovellus arvaa puheesta nimiä ja sukulaisuuksia, ja arvaa joskus väärin.",
                "Siksi ne näkyvät ehdotuksina, kunnes joku perheestä vahvistaa ne. Väärä sukulaisuus on pahempi kuin puuttuva."
            )

            section(
                "Mikä maksaa",
                "Kertominen on aina ilmaista. Sitä ei rajoiteta koskaan.",
                // "Kertomisaika", not "AI-minuutit". The same quota is called
                // "kertominen tässä kuussa" on the family screen and "kertomista
                // tässä kuussa jäljellä" on the card after a telling, and this
                // page was the last place still using the jargon name for it.
                // See docs/ARCHITECTURE.md §21.
                "Maksullinen arkisto poistaa kuvien määrän ja kuukausittaisen kertomisajan rajat. Yksi maksaja avaa sen koko perheelle."
            )

            // The one thing on this page that is addressed to the person
            // holding the phone rather than to the person using it. Setting up
            // takes a grandchild a few minutes; the reading is done for years by
            // somebody who has never opened iOS Settings — and the question is
            // asked once during setup, where it is easy to answer "minun" out of
            // habit and never think about it again. This is where they find it
            // afterwards.
            section(
                "Isompi teksti",
                "Jos puhelin on isovanhemman, laita isompi teksti päälle Asetuksista.",
                "Se koskee vain tätä sovellusta, ja puhelimen oma tekstikoko on sitä vahvempi: jos olet jo suurentanut tekstiä sieltä, koko säilyy."
            )

            section(
                "Omat muistot itsellesi",
                "Voit viedä koko arkiston yhtenä tiedostona Asetuksista.",
                "Siinä ovat muistot luettavana sivuna, alkuperäiset äänitykset ja kuvat. Sen voi avata millä tahansa koneella ilman tätä sovellusta."
            )
        }
        .navigationTitle("Näin tämä toimii")
    }

    /// A heading and one or two plain sentences. Nothing is folded away behind a
    /// tap: somebody who opened this page is already looking for the answer, and
    /// making them hunt for it twice is how a help page becomes decoration.
    private func section(_ title: String, _ lines: String...) -> some View {
        Section {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .elderBody()
            }
        } header: {
            // A List styles its own headers below the contrast minimum. Saying
            // the colour out loud is the only way to raise it.
            Text(title)
                .foregroundStyle(Elder.supporting)
        }
    }
}

#Preview {
    NavigationStack {
        HelpScreen()
    }
}
