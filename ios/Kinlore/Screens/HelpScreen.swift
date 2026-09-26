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

            // One literal per row, never parts joined with `+`: a String built
            // from parts is handed over as a String and never looked up, so
            // this sentence — the one that says the recording leaves the
            // phone — stayed Finnish on an English phone. See
            // scripts/localisation-check.mjs.
            //
            // Four rows rather than one because `section` is variadic and the
            // length had a measured cost: as a single row this answer stood
            // 2511 pt tall in English at AccessibilityXXXL on a 874 pt screen
            // — three and a half screens of one paragraph — against 309 pt at
            // the default size (measured 19 Sep 2026 with a GeometryReader
            // probe under `simctl launch --console-pty`, because a List builds
            // lazily and a row below the fold reports nothing). Splitting
            // costs no structure, changes no word, and gives both the eye and
            // VoiceOver somewhere to stop.
            section(
                "Mitä äänellesi tapahtuu",
                "Perheen arkistossa kertomasi ääni lähetetään OpenRouter-palvelun kautta tekoälylle, joka kirjoittaa puheen tekstiksi. Kun kerrot valokuvasta, kuva lähtee mukaan. Niillä ei opeteta tekoälyä.",
                "Arkistoon ääni tallentuu salattuna, ja vain perheesi omat puhelimet voivat avata sen.",
                "Jos arkisto on vain tällä puhelimella, ääni ei lähde perheen palvelimelle eikä tekoälylle. Tekstiä ei silloin kirjoiteta — muistot voi kirjoittaa itse.",
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

            // The reassurance that makes an old person willing to speak
            // freely: that a thing said can be unsaid. The app could do it
            // from the result screen since August and from the card since
            // 4 Sep 2026, and this page — the one place for whole-app answers
            // — had never said so.
            section(
                "Jos sanoit jotain, mitä et tarkoittanut",
                "Oman muistosi voit poistaa sen kortilta, ja sen tekstin voit korjata. Äänitys ja sanatarkka puhe eivät muutu korjatessa.",
                "Poisto näkyy koko perheelle, eikä sitä voi perua. Väärin arvatun nimen voit poistaa heti kertomisen jälkeen tai myöhemmin henkilön kortilta."
            )

            // Two words for two things, and this is the page that says so.
            // "Kertominen" is the act, and rule 2 says it is never limited;
            // the monthly meter is "litterointiaika", the time speech is
            // turned into text. Until 26 Sep 2026 the meter was called
            // "kertomisaika" here and "kertominen" elsewhere, so this section
            // said telling is never limited one line above a limit on telling
            // time — and in English, "the month's free telling is used up"
            // sat beside "Telling is always free". The middle line names the
            // meter once, because every other screen uses the name without
            // explaining it. "More" rather than "no limits": the paid tier's
            // fair-use ceiling is written down and not enforced (docs/PLAN.md
            // §9), and "more" stays true either way. See docs/ARCHITECTURE.md
            // §21. (Above the call rather than inside it: the localisation
            // check reads every literal inside a `section(` call as a key,
            // comments included.)
            section(
                "Mikä maksaa",
                "Kertominen on aina ilmaista. Sitä ei rajoiteta koskaan.",
                "Ilmaisessa arkistossa kuvia mahtuu rajattu määrä, ja puheesta kirjoitetaan tekstiä rajattu aika kuukaudessa: se on litterointiaika. Jos aika loppuu, ääni tallentuu silti, ja teksti kirjoitetaan, kun aikaa on taas.",
                "Maksullisessa arkistossa kumpaakin on enemmän. Yksi maksaja avaa sen koko perheelle."
            )

            // The one thing on this page that is addressed to the person
            // holding the phone rather than to the person using it. Setting up
            // takes a grandchild a few minutes; the reading is done for years by
            // somebody who has never opened iOS Settings — and the question is
            // asked once during setup, where it is easy to answer "minun" out of
            // habit and never think about it again. This is where they find it
            // afterwards.
            //
            // The last line is what else the switch does. Settings has room
            // for one line under it and names the tree and the colouring
            // there; this is where all four are said (26 Sep 2026).
            section(
                "Isompi teksti",
                "Jos puhelin on isovanhemman, laita isompi teksti päälle Asetuksista.",
                "Se koskee vain tätä sovellusta, ja puhelimen oma tekstikoko on sitä vahvempi: jos olet jo suurentanut tekstiä sieltä, koko säilyy.",
                "Samalla sovellus yksinkertaistuu: sukupuu näkyy listoina, albumissa ei ole hakua, eikä kuvien väritystä tai maksullista arkistoa tarjota."
            )

            section(
                "Omat muistot itsellesi",
                "Voit viedä koko arkiston yhtenä tiedostona Asetuksista.",
                "Siinä ovat muistot luettavana sivuna, alkuperäiset äänitykset ja kuvat. Sen voi avata millä tahansa koneella ilman tätä sovellusta."
            )

            // The truth about the key, said where somebody can act on it. The
            // server holds only ciphertext; the key is on the family's phones
            // and nowhere else, and the app cannot tell whether iCloud Keychain
            // — the one thing that carries it to a new phone on its own — is
            // on. So the two things that actually keep the archive are named:
            // a second member, and the export. Founder's-eye review, 3 Sep
            // 2026, findings #87 and #100.
            section(
                "Jos puhelin katoaa",
                "Perheen arkistossa muistot ovat myös perheen palvelimella, mutta salattuina avaimella, joka on vain perheen puhelimissa. Jos kaikki perheen puhelimet katoavat, avain katoaa niiden mukana, eikä palvelimen kopiota saa enää auki.",
                "Siksi kutsu toinen perheenjäsen — silloin avain on kahdessa puhelimessa — ja vie arkisto silloin tällöin omalle koneellesi. Applen iCloud-avainnippu siirtää avaimen uuteen puhelimeen, jos se on käytössä, mutta sen varaan ei kannata jättää.",
                "Kuvat ja äänet haetaan perheen jokaiseen puhelimeen wifi-yhteydellä, joten arkisto säilyy myös silloin, jos palvelin joskus sammuu. Perhe-näytön rivi ”Kopio tällä puhelimella” kertoo, onko kaikki jo tässä puhelimessa.",
                "Jos arkisto on vain tällä puhelimella, sen saa takaisin vain viedystä tiedostosta tai puhelimen iCloud-varmuuskopiosta, jos se on päällä."
            )
        }
        .navigationTitle("Näin tämä toimii")
        .elderSurface()
    }

    /// A heading and a few plain sentences. Nothing is folded away behind a
    /// tap: somebody who opened this page is already looking for the answer, and
    /// making them hunt for it twice is how a help page becomes decoration.
    ///
    /// `LocalizedStringKey`, not `String`: a literal handed to a String
    /// parameter is shown verbatim, and until 4 Sep 2026 this whole page was
    /// Finnish under an English title on an English phone.
    private func section(_ title: LocalizedStringKey, _ lines: LocalizedStringKey...) -> some View {
        Section {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
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
