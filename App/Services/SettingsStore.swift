import Foundation
import Combine
import HourglassCore

/// User preferences (Settings screen). Stored in the App Group defaults so extensions can read the alert sound.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    @Published var alertSound: AlertSound { didSet { defaults.set(alertSound.rawValue, forKey: SharedKeys.alertSound) } }
    @Published var volume: Double { didSet { defaults.set(volume, forKey: Keys.volume) } }
    @Published var vibrationEnabled: Bool { didSet { defaults.set(vibrationEnabled, forKey: Keys.vibration) } }
    @Published var flipGestureEnabled: Bool { didSet { defaults.set(flipGestureEnabled, forKey: Keys.flipGesture) } }
    @Published var keepScreenOn: Bool { didSet { defaults.set(keepScreenOn, forKey: Keys.keepScreenOn) } }
    @Published var zenByDefault: Bool { didSet { defaults.set(zenByDefault, forKey: Keys.zenDefault) } }
    @Published var density: SandDensity { didSet { defaults.set(density.rawValue, forKey: Keys.density) } }
    @Published var themeID: SandTheme.ID { didSet { defaults.set(themeID.rawValue, forKey: Keys.theme) } }
    @Published var lastDuration: TimeInterval { didSet { defaults.set(lastDuration, forKey: Keys.lastDuration) } }
    @Published var analyticsEnabled: Bool { didSet { defaults.set(analyticsEnabled, forKey: Keys.analytics) } }
    /// Lower the sand density automatically when the phone can't keep up or overheats.
    @Published var autoQuality: Bool { didSet { defaults.set(autoQuality, forKey: Keys.autoQuality) } }
    @Published var hasSeenOnboarding: Bool { didSet { defaults.set(hasSeenOnboarding, forKey: Keys.onboarding) } }

    enum Keys {
        static let volume = "settings.volume"
        static let vibration = "settings.vibration"
        static let flipGesture = "settings.flipGesture"
        static let keepScreenOn = "settings.keepScreenOn"
        static let zenDefault = "settings.zenDefault"
        static let density = "settings.density"
        static let theme = "settings.theme"
        static let lastDuration = "settings.lastDuration"
        static let analytics = "settings.analytics"
        static let onboarding = "settings.onboarding"
        static let autoQuality = "settings.autoQuality"
    }

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.volume: 0.8,
            Keys.vibration: true,
            Keys.flipGesture: true,
            Keys.keepScreenOn: true,
            Keys.zenDefault: false,
            Keys.lastDuration: 5 * 60.0,
            Keys.analytics: true,
            Keys.autoQuality: true,
        ])
        alertSound = AlertSound.current
        volume = defaults.double(forKey: Keys.volume)
        vibrationEnabled = defaults.bool(forKey: Keys.vibration)
        flipGestureEnabled = defaults.bool(forKey: Keys.flipGesture)
        keepScreenOn = defaults.bool(forKey: Keys.keepScreenOn)
        zenByDefault = defaults.bool(forKey: Keys.zenDefault)
        density = defaults.string(forKey: Keys.density).flatMap(SandDensity.init(rawValue:)) ?? Self.defaultDensity
        themeID = defaults.string(forKey: Keys.theme).flatMap(SandTheme.ID.init(rawValue:)) ?? .goldenSand
        lastDuration = DurationLimits.clamp(defaults.double(forKey: Keys.lastDuration))
        analyticsEnabled = defaults.bool(forKey: Keys.analytics)
        hasSeenOnboarding = defaults.bool(forKey: Keys.onboarding)
        autoQuality = defaults.bool(forKey: Keys.autoQuality)
    }

    /// Adaptive default: older / low-memory devices start with the lighter preset.
    static var defaultDensity: SandDensity {
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        if ProcessInfo.processInfo.isLowPowerModeEnabled || gb < 3.5 { return .performance }
        return gb >= 6 ? .quality : .balanced
    }

    /// "Reset all data" (Settings): wipes preferences, library and the active timer.
    func resetAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("settings.") || key.hasPrefix("activeTimer.") {
            defaults.removeObject(forKey: key)
        }
        try? FileManager.default.removeItem(at: LibraryStore.fileURL)
        let fresh = SettingsStore(defaults: defaults)
        alertSound = fresh.alertSound; volume = fresh.volume; vibrationEnabled = fresh.vibrationEnabled
        flipGestureEnabled = fresh.flipGestureEnabled; keepScreenOn = fresh.keepScreenOn; zenByDefault = fresh.zenByDefault
        density = fresh.density; themeID = fresh.themeID; lastDuration = fresh.lastDuration
        analyticsEnabled = fresh.analyticsEnabled; hasSeenOnboarding = false; autoQuality = fresh.autoQuality
    }
}
