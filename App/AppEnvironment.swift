import Foundation
import HourglassCore

/// Composition root: builds every service once and wires them together (MVVM + services).
///
/// ```
///   Views ──▶ ViewModels ──▶ Services
///                │             ├─ MotionService      (CoreMotion: gravity, flip, shake)
///                │             ├─ TimerEngine        (HourglassCore, dates = source of truth)
///                │             ├─ SimulationDriver   (HourglassCore.SandSimulation on its own queue)
///                │             ├─ SandRenderer       (Metal)
///                │             ├─ AlarmService       (AlarmKit / time-sensitive notifications)
///                │             ├─ StoreService       (StoreKit 2)
///                │             ├─ AdsService         (UMP + ATT + Google Mobile Ads)
///                │             ├─ PersistenceService (Codable JSON, App Group)
///                │             ├─ LiveActivityService(ActivityKit)
///                │             └─ AnalyticsService   (Firebase, anonymous)
/// ```
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let settings: SettingsStore
    let motion: MotionService
    let alarms: AlarmService
    let feedback: FeedbackService
    let store: StoreService
    let ads: AdsService
    let persistence: PersistenceService
    let liveActivity: LiveActivityService
    let driver: SimulationDriver
    let hourglass: HourglassViewModel

    let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    private init() {
        if isUITesting { Self.resetForUITests() }
        settings = SettingsStore()
        motion = MotionService()
        alarms = AlarmService()
        feedback = FeedbackService()
        store = StoreService()
        ads = AdsService()
        persistence = PersistenceService()
        liveActivity = LiveActivityService()
        driver = SimulationDriver(density: settings.density)
        hourglass = HourglassViewModel(settings: settings, motion: motion, alarms: alarms, feedback: feedback,
                                       store: store, persistence: persistence, liveActivity: liveActivity, driver: driver)
        AnalyticsService.shared.configure(enabled: settings.analyticsEnabled && !isUITesting)
        TimerCommandRouter.handler = { [weak vm = hourglass] command in await vm?.handle(command) }
    }

    /// UI tests start from a clean slate.
    private static func resetForUITests() {
        let d = AppGroup.defaults
        for key in d.dictionaryRepresentation().keys { d.removeObject(forKey: key) }
        try? FileManager.default.removeItem(at: LibraryStore.fileURL)
        d.set(true, forKey: SettingsStore.Keys.onboarding)
    }
}
