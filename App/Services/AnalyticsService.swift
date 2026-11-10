import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

/// Minimal, anonymous interaction + crash analytics.
///
/// * no user id, no IDFA / IDFV (disabled in Info.plist), no free text — only coarse enums / buckets;
/// * user can opt out in Settings (`analyticsEnabled`);
/// * Firebase is configured only if `GoogleService-Info.plist` is present, so the project runs without it.
final class AnalyticsService {
    static let shared = AnalyticsService()

    enum Event {
        case timerStarted(durationBucket: String, isSequence: Bool, viaFlip: Bool)
        case timerFinished(isSequence: Bool)
        case themeSelected(String)
        case zenToggled(Bool)
        case paywallShown
        case purchaseCompleted

        var name: String {
            switch self {
            case .timerStarted: return "timer_started"
            case .timerFinished: return "timer_finished"
            case .themeSelected: return "theme_selected"
            case .zenToggled: return "zen_toggled"
            case .paywallShown: return "paywall_shown"
            case .purchaseCompleted: return "purchase_completed"
            }
        }

        var parameters: [String: Any] {
            switch self {
            case let .timerStarted(bucket, seq, flip): return ["duration": bucket, "sequence": seq, "flip": flip]
            case let .timerFinished(seq): return ["sequence": seq]
            case let .themeSelected(id): return ["theme": id]
            case let .zenToggled(on): return ["on": on]
            case .paywallShown, .purchaseCompleted: return [:]
            }
        }
    }

    private(set) var isConfigured = false
    private var enabled = true

    func configure(enabled: Bool) {
        self.enabled = enabled
        #if canImport(FirebaseCore)
        if !isConfigured, Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            isConfigured = true
        }
        #endif
        setCollection(enabled)
    }

    func setCollection(_ enabled: Bool) {
        self.enabled = enabled
        guard isConfigured else { return }
        #if canImport(FirebaseAnalytics)
        Analytics.setAnalyticsCollectionEnabled(enabled)
        #endif
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled)
        #endif
    }

    func log(_ event: Event) {
        guard enabled, isConfigured else { return }
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent(event.name, parameters: event.parameters)
        #endif
    }

    func record(error: Error, context: String) {
        guard enabled, isConfigured else { return }
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().log("context=\(context)")
        Crashlytics.crashlytics().record(error: error)
        #endif
    }

    /// Coarse bucket so exact durations are never sent.
    static func bucket(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return "<1m"
        case ..<300: return "1-5m"
        case ..<1800: return "5-30m"
        case ..<7200: return "30m-2h"
        default: return ">2h"
        }
    }
}
