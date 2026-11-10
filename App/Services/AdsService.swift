import SwiftUI
import UIKit
import AppTrackingTransparency
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif
#if canImport(UserMessagingPlatform)
import UserMessagingPlatform
#endif

/// Banner ads for the free version — **only** on the Library and Settings screens, never over the running hourglass.
///
/// Consent flow (run once per launch, when the app is active):
/// 1. Google UMP — GDPR/CPRA consent form if required for the user's region;
/// 2. App Tracking Transparency prompt (only if UMP allows ads and status is undetermined);
/// 3. start the Mobile Ads SDK only when `canRequestAds`.
/// Supporters skip all of it.
@MainActor
final class AdsService: ObservableObject {
    @Published private(set) var canShowAds = false
    @Published private(set) var privacyOptionsRequired = false
    private var started = false

    var bannerUnitID: String {
        Bundle.main.object(forInfoDictionaryKey: "HGBannerAdUnitID") as? String ?? "ca-app-pub-3940256099942544/2435281174"
    }

    func prepare(isSupporter: Bool) async {
        guard !isSupporter else { canShowAds = false; return }
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        #if canImport(UserMessagingPlatform) && canImport(GoogleMobileAds)
        do {
            let params = RequestParameters()
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: params)
            try await ConsentForm.loadAndPresentIfRequired(from: Self.topViewController())
        } catch {
            AnalyticsService.shared.record(error: error, context: "ump")
        }
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        guard ConsentInformation.shared.canRequestAds else { return }

        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        if !started {
            started = true
            _ = await MobileAds.shared.start()
        }
        canShowAds = true
        #endif
    }

    /// Settings → "Privacy choices" (required by UMP when `privacyOptionsRequired`).
    func presentPrivacyOptions() async {
        #if canImport(UserMessagingPlatform)
        try? await ConsentForm.presentPrivacyOptionsForm(from: Self.topViewController())
        #endif
    }

    func disableForSupporter() { canShowAds = false }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}

/// Adaptive anchored banner. Renders nothing when ads are not allowed / SDK missing.
struct BannerAdView: View {
    @EnvironmentObject private var ads: AdsService
    @EnvironmentObject private var store: StoreService

    var body: some View {
        if ads.canShowAds && !store.isSupporter {
            GeometryReader { geo in
                BannerRepresentable(width: geo.size.width, unitID: ads.bannerUnitID)
            }
            .frame(height: 60)
            .accessibilityIdentifier("bannerAd")
        }
    }
}

#if canImport(GoogleMobileAds)
private struct BannerRepresentable: UIViewRepresentable {
    var width: CGFloat
    var unitID: String

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: currentOrientationAnchoredAdaptiveBanner(width: max(width, 320)))
        banner.adUnitID = unitID
        banner.rootViewController = AdsService.topViewController()
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}
#else
private struct BannerRepresentable: View {
    var width: CGFloat
    var unitID: String
    var body: some View { EmptyView() }
}
#endif
