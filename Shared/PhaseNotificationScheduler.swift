import Foundation
import UserNotifications
import HourglassCore

/// Alert sounds bundled with the app (≤ 30 s, required by `UNNotificationSound`).
enum AlertSound: String, CaseIterable, Identifiable, Codable {
    case chime, bell, gong, marimba

    var id: String { rawValue }
    var fileName: String { "\(rawValue).wav" }

    /// Localisation key of the display name.
    var nameKey: String {
        switch self {
        case .chime: return "Chime"
        case .bell: return "Bell"
        case .gong: return "Gong"
        case .marimba: return "Marimba"
        }
    }

    static var current: AlertSound {
        AppGroup.defaults.string(forKey: SharedKeys.alertSound).flatMap(AlertSound.init(rawValue:)) ?? .chime
    }
}

/// Local-notification fallback for alarms (iOS 15 … 25, extensions, or when AlarmKit is not authorised).
///
/// * one request per upcoming phase end (sequences), capped below the system limit of 64 pending requests;
/// * `.timeSensitive` interruption level → breaks through Focus (needs the Time Sensitive entitlement);
/// * pending requests survive reboots — the system persists them.
enum PhaseNotificationScheduler {
    static let idPrefix = "hourglass.phase."
    static let categoryID = "hourglass.timer"

    static func schedule(engine: TimerEngine, sound: AlertSound = .current) async {
        await cancelAll()
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let title = engine.snapshot.title.isEmpty ? String(localized: "Hourglass") : engine.snapshot.title
        for end in engine.upcomingPhaseEnds(limit: 60) where end.date > Date() {
            let content = UNMutableNotificationContent()
            content.title = title
            if end.isLast {
                content.body = String(localized: "Time's up!")
            } else if let next = engine.plan.phase(at: end.index + 1) {
                let nextName = next.name.isEmpty ? String(localized: "Next phase") : next.name
                content.body = String(format: String(localized: "%@ is over. Next: %@"),
                                      end.phase.name.isEmpty ? String(localized: "Phase") : end.phase.name, nextName)
            }
            content.sound = UNNotificationSound(named: UNNotificationSoundName(sound.fileName))
            content.categoryIdentifier = categoryID
            content.threadIdentifier = "hourglass"
            content.interruptionLevel = .timeSensitive          // iOS 15+: breaks through Focus
            content.relevanceScore = end.isLast ? 1 : 0.6
            let interval = max(1, end.date.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: idPrefix + "\(end.index)", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}
