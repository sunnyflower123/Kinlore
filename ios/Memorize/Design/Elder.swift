import SwiftUI

/// Suunnitteluvakiot, jotka pitävät sovelluksen käytettävänä 80-vuotiaalle.
///
/// Nämä eivät ole tyylimieltymyksiä vaan tuotteen ydin: jos ruutu ei toimi
/// suurimmalla tekstikoolla, se ei ole valmis. Applen minimikosketuskohde on
/// 44 pt, mutta se on suunniteltu vakaalle kädelle — käytämme 60 pt.
enum Elder {
    /// Pienin kosketuskohde. Ei koskaan alle tämän, ei edes sekundäärisille
    /// toiminnoille.
    static let minTapTarget: CGFloat = 60

    /// Nauhoitusnapin halkaisija. Se on sovelluksen tärkein kontrolli, ja sen
    /// pitää löytyä ilman lukemista.
    static let recordButtonSize: CGFloat = 200

    /// Leipätekstin väli. Väljä riviväli auttaa heikkonäköistä pitämään rivin.
    static let lineSpacing: CGFloat = 6

    static let screenPadding: CGFloat = 24
}

extension View {
    /// Varmistaa että kontrolli on riittävän suuri riippumatta sisällön koosta.
    func elderTapTarget() -> some View {
        frame(minWidth: Elder.minTapTarget, minHeight: Elder.minTapTarget)
            .contentShape(Rectangle())
    }

    /// Leipätekstin muotoilu: väljä riviväli, ei koskaan rivimäärärajoitusta.
    /// Katkaistu muisto on menetetty muisto.
    func elderBody() -> some View {
        font(.body)
            .lineSpacing(Elder.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }
}
