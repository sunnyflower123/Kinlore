import Foundation
import RevenueCat

/// RevenueCat-toteutus.
///
/// Avain luetaan asetuksista eikä koodista: **RevenueCat Test Store** on
/// kehityksessä ja demossa, ja alustakohtainen avain vasta jos joskus
/// julkaistaan storeen. Ilman avainta sovellus käyttää stubia ja toimii
/// normaalisti — ostot vain eivät ole tarjolla.
struct RevenueCatPurchases: PurchaseService {
    /// Asetetaan käynnistysargumentilla `-rcKey <avain>` tai UserDefaultsiin
    /// avaimella `rcKey`. Julkinen SDK-avain on suunniteltu asiakaspuolelle,
    /// joten sen upottaminen olisi turvallista — se luetaan silti asetuksista,
    /// jotta Test Store ja tuotanto voidaan vaihtaa kääntämättä uudelleen.
    static var configuredKey: String? {
        guard let key = UserDefaults.standard.string(forKey: "rcKey"), !key.isEmpty else {
            return nil
        }
        return key
    }

    /// Kutsutaan kerran käynnistyksessä.
    ///
    /// `appUserID` sidotaan perheen jäsentunnisteeseen, jotta webhook löytää
    /// perheen ilman että sovellus on auki. Ilman tätä uusiutunut tilaus
    /// näkyisi vasta kun maksaja seuraavan kerran avaa sovelluksen — ja hän ei
    /// ole se joka sitä eniten käyttää.
    static func configure(memberID: String) {
        guard let key = configuredKey else { return }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: key, appUserID: memberID)
    }

    var customerID: String? {
        get async {
            guard Self.configuredKey != nil else { return nil }
            return try? await Purchases.shared.customerInfo().originalAppUserId
        }
    }

    var hasActivePurchase: Bool {
        get async {
            guard Self.configuredKey != nil,
                  let info = try? await Purchases.shared.customerInfo()
            else { return false }
            return !info.entitlements.active.isEmpty
        }
    }
}
