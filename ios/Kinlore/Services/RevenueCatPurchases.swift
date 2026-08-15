import Foundation
import RevenueCat

/// The RevenueCat implementation.
///
/// The key is read from settings rather than code: the **RevenueCat Test Store**
/// is used in development and in the demo, and a platform key only if this is
/// ever released to a store. Without a key the app uses the stub and works
/// normally — purchases just are not offered.
struct RevenueCatPurchases: PurchaseService {
    /// Set with the launch argument `-rcKey <key>`, or in UserDefaults under the
    /// key `rcKey`. A public SDK key is designed for the client side, so
    /// embedding it would be safe — it is still read from settings so that Test
    /// Store and production can be swapped without recompiling.
    static var configuredKey: String? {
        guard let key = UserDefaults.standard.string(forKey: "rcKey"), !key.isEmpty else {
            return nil
        }
        return key
    }

    /// Called once at launch.
    ///
    /// `appUserID` is bound to the family member id so that the webhook can find
    /// the family without the app being open. Without this, a renewed
    /// subscription would only show up when the payer next opens the app — and
    /// they are not the one who uses it most.
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
