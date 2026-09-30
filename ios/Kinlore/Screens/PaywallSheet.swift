import RevenueCat
import RevenueCatUI
import SwiftUI

/// The paywall.
///
/// RevenueCat's own paywall rather than a hand-built one. It is configured
/// remotely, so prices and wording can change without shipping a build — and on
/// a schedule this tight, a screen that does not have to be designed, localised
/// and re-tested is worth more than one that matches the app's typography
/// exactly.
///
/// **The purchase is not finished when this screen closes.** RevenueCat knows
/// about the buyer; the server knows about the family. `syncPurchase` is what
/// turns "this grandchild bought a subscription" into "this family's archive is
/// open", which is the whole monetisation model — see docs/ARCHITECTURE.md §6.
/// The server verifies the purchase against RevenueCat's REST API rather than
/// believing the app, so this call is a hint, not a claim.
struct PaywallSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// Set when the money went through and the archive did not — see
    /// `spreadToFamily`.
    @State private var isWaitingForTheFamily = false

    /// Set when a restore comes back with no active entitlement — see
    /// `onRestoreCompleted`.
    @State private var foundNothingToRestore = false

    /// Set by a completed purchase and spent by the request to close that
    /// RevenueCatUI sends straight after it — see `onRequestedDismissal`.
    @State private var declinesNextDismissal = false

    var body: some View {
        PaywallView(displayCloseButton: true)
            // Restore matters more here than in most apps: the person who pays
            // may reinstall, change phone, or be a different family member than
            // the one who benefits.
            //
            // But a restore that finds nothing completes too, with a
            // `CustomerInfo` that has nothing active in it — on the Test Store,
            // whose restore only returns the current one, that is anybody who
            // has not bought. Handed to `spreadToFamily`, it met the Worker's
            // "not paid" and thanked somebody who had paid nothing ("Kiitos —
            // maksu meni läpi"); in the seeded demo, with no server to ask, it
            // opened the archive. So a restore reaches the family only with an
            // active entitlement, the same test `hasActivePurchase` and the
            // Worker make, and the empty answer is said here, because
            // RevenueCatUI 5.83.2 only logs it.
            .onPurchaseCompleted { (info: CustomerInfo) in
                declinesNextDismissal = true
                Task { await spreadToFamily(info) }
            }
            .onRestoreCompleted { (info: CustomerInfo) in
                if info.entitlements.active.isEmpty {
                    foundNothingToRestore = true
                } else {
                    Task { await spreadToFamily(info) }
                }
            }
            // RevenueCatUI asks to close once a purchase completes, one
            // main-queue turn after `onPurchaseCompleted` — before the family
            // has the archive. Obeying it closed the sheet over the alert below
            // within half a second of the alert appearing (measured 21 Sep
            // 2026). Against a real Worker, where `syncPurchase` waits on the
            // network, it would close the sheet before the answer and leave
            // the alert no screen to appear on. So that one request is
            // declined and `spreadToFamily` closes the sheet. The close button
            // still works meanwhile, because a sync that fails can take tens
            // of seconds to say so. A restore sends no such request
            // (RevenueCatUI 5.83.2).
            .onRequestedDismissal {
                if declinesNextDismissal {
                    declinesNextDismissal = false
                } else {
                    dismiss()
                }
            }
            // The one moment in this app where somebody has parted with money,
            // and it used to end in a sheet closing over an unchanged screen.
            .alert("Kiitos — maksu meni läpi", isPresented: $isWaitingForTheFamily) {
                Button("Selvä") { dismiss() }
            } message: {
                Text("Perheen arkisto ei vielä ehtinyt avautua. Sovellus ilmoittaa asiasta uudelleen itsestään, eikä sinun tarvitse maksaa toista kertaa.")
            }
            // A title and nothing more, because it is all that is known. The
            // sheet stays open under it: somebody who found nothing may buy.
            .alert("Palautettavaa ostoa ei löytynyt", isPresented: $foundNothingToRestore) {
                Button("Selvä", role: .cancel) {}
            }
    }

    /// The purchase belongs to the buyer; the archive belongs to the family, and
    /// the second one is what they think they bought (§6). So the sheet closes
    /// on the family having it, and says so plainly when it does not — the
    /// alternative is a person who paid, saw nothing change, and pays again.
    private func spreadToFamily(_ info: CustomerInfo) async {
        if await session.syncPurchase(customerID: info.originalAppUserId) {
            dismiss()
        } else {
            isWaitingForTheFamily = true
        }
    }
}

/// Opens the paywall, but only when there is something to open.
///
/// Without a RevenueCat key the SDK is not configured, and `PaywallView` is
/// documented to require configuration before it is displayed. A dead button is
/// worse than no button, so the caller gets `nil` and shows nothing. The app
/// keeps working without purchases — that is deliberate, see `AppServices`.
extension View {
    @ViewBuilder
    func paywallSheet(isPresented: Binding<Bool>) -> some View {
        if RevenueCatPurchases.configuredKey == nil {
            self
        } else {
            sheet(isPresented: isPresented) { PaywallSheet() }
        }
    }
}
