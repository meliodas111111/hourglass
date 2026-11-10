import Foundation
import StoreKit

/// StoreKit 2: a single non-consumable "Supporter" purchase (removes ads, unlocks premium themes).
///
/// * entitlements are verified from `Transaction.currentEntitlements` at launch and on every update;
/// * the last known state is cached (App Group) so the UI is correct offline and widgets can read it;
/// * "Restore purchases" → `AppStore.sync()`.
@MainActor
final class StoreService: ObservableObject {

    @Published private(set) var product: Product?
    @Published private(set) var isSupporter: Bool
    @Published private(set) var isBusy = false
    /// User-facing error (already localised). The view shows it in an alert and clears it.
    @Published var errorMessage: String?

    let productID: String
    private var updatesTask: Task<Void, Never>?

    init(productID: String = Bundle.main.object(forInfoDictionaryKey: "HGSupporterProductID") as? String
                             ?? "com.meliodas.hourglass.supporter") {
        self.productID = productID
        self.isSupporter = AppGroup.defaults.bool(forKey: SharedKeys.isSupporter)
        updatesTask = Task { [weak self] in
            // Purchases made on other devices, Ask-to-Buy approvals, refunds.
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let t) = update {
                    await t.finish()
                }
                await self.refreshEntitlements()
            }
        }
    }

    deinit { updatesTask?.cancel() }

    /// Launch: load product metadata and verify entitlements.
    func start() async {
        await refreshEntitlements()
        await loadProduct()
    }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [productID]).first
        } catch {
            product = nil   // shown as "Store unavailable" in the paywall
        }
    }

    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == productID, t.revocationDate == nil {
                owned = true
            }
        }
        setSupporter(owned)
    }

    func purchase() async {
        guard let product else {
            errorMessage = String(localized: "The App Store is not available right now. Please check your connection and try again.")
            await loadProduct()
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let t)):
                await t.finish()
                setSupporter(true)
                AnalyticsService.shared.log(.purchaseCompleted)
            case .success(.unverified):
                errorMessage = String(localized: "The purchase could not be verified.")
            case .pending:
                errorMessage = String(localized: "The purchase is pending approval.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func restore() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isSupporter { errorMessage = String(localized: "No previous purchases were found for this Apple ID.") }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func setSupporter(_ value: Bool) {
        isSupporter = value
        AppGroup.defaults.set(value, forKey: SharedKeys.isSupporter)
    }

    static func message(for error: Error) -> String {
        if let e = error as? StoreKitError {
            switch e {
            case .networkError, .systemError:
                return String(localized: "The App Store is not available right now. Please check your connection and try again.")
            case .userCancelled:
                return ""
            case .notAvailableInStorefront:
                return String(localized: "This purchase is not available in your country or region.")
            case .notEntitled:
                return String(localized: "The purchase could not be verified.")
            default: break
            }
        }
        if case .purchaseNotAllowed? = error as? Product.PurchaseError {
            return String(localized: "Purchases are disabled on this device (Screen Time restrictions).")
        }
        return String(localized: "Something went wrong. Please try again later.")
    }
}
