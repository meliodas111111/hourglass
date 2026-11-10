import Foundation
import UserNotifications
import SwiftUI
import HourglassCore
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Alarm-grade alerts for phase ends.
///
/// * **iOS 26+ (AlarmKit)** — real alarms: ring over Silent mode and Focus, survive reboots.
/// * **iOS 15–25 / Mac / visionOS / not authorised** — `.timeSensitive` local notifications with a bundled
///   ≤ 30 s sound (`PhaseNotificationScheduler`); pending requests survive reboots as well.
///
/// Everything is cancelled on pause / stop and rescheduled on resume / flip.
@MainActor
final class AlarmService: ObservableObject {

    enum Backend: Equatable { case alarmKit, notifications }

    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var alarmKitAuthorized = false

    private let scheduledAlarmIDsKey = "alarms.scheduledIDs"

    var backend: Backend {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), Self.alarmKitSupported, alarmKitAuthorized { return .alarmKit }
        #endif
        return .notifications
    }

    /// AlarmKit is not available to iPad apps running on Mac / Vision Pro.
    static var alarmKitSupported: Bool {
        if ProcessInfo.processInfo.isiOSAppOnMac { return false }
        if #available(iOS 17.0, *), UIDevice.current.userInterfaceIdiom == .vision { return false }
        return true
    }

    func refreshStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), Self.alarmKitSupported {
            alarmKitAuthorized = AlarmManager.shared.authorizationState == .authorized
        }
        #endif
    }

    /// Ask for permissions right before the first timer starts (the app shows an explainer first, see
    /// `PermissionPrimerView`). Returns `true` when at least one alert path works.
    @discardableResult
    func requestAuthorization() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), Self.alarmKitSupported {
            do {
                let state = try await AlarmManager.shared.requestAuthorization()
                alarmKitAuthorized = state == .authorized
            } catch {
                alarmKitAuthorized = false
            }
        }
        #endif
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshStatus()
        return granted || alarmKitAuthorized
    }

    /// Show our explainer once, before the system prompt (never nag after the user declined it).
    var needsPermissionPrompt: Bool {
        notificationStatus == .notDetermined && !UserDefaults.standard.bool(forKey: primerShownKey)
    }

    func markPrimerShown() { UserDefaults.standard.set(true, forKey: primerShownKey) }

    private let primerShownKey = "alarms.primerShown"

    // MARK: Scheduling

    func schedule(engine: TimerEngine, sound: AlertSound) async {
        await cancelAll()
        guard engine.state == .running else { return }
        switch backend {
        case .alarmKit:
            #if canImport(AlarmKit)
            if #available(iOS 26.0, *) {
                let ok = await scheduleAlarmKit(engine: engine, sound: sound)
                if ok { return }
            }
            #endif
            await PhaseNotificationScheduler.schedule(engine: engine, sound: sound)
        case .notifications:
            await PhaseNotificationScheduler.schedule(engine: engine, sound: sound)
        }
    }

    func cancelAll() async {
        await PhaseNotificationScheduler.cancelAll()
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), Self.alarmKitSupported {
            let ids = (UserDefaults.standard.stringArray(forKey: scheduledAlarmIDsKey) ?? []).compactMap(UUID.init(uuidString:))
            for id in ids { try? AlarmManager.shared.cancel(id: id) }
            UserDefaults.standard.removeObject(forKey: scheduledAlarmIDsKey)
        }
        #endif
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func scheduleAlarmKit(engine: TimerEngine, sound: AlertSound) async -> Bool {
        var ids: [String] = []
        let tint = SandTheme.theme(engine.activeThemeID).accent
        // AlarmKit alarms are heavier than notifications: schedule the next 16 phase ends, the app tops up on resume.
        for end in engine.upcomingPhaseEnds(limit: 16) where end.date > Date() {
            let title: LocalizedStringResource = end.isLast
                ? "Time's up!"
                : LocalizedStringResource(stringLiteral: end.phase.name.isEmpty ? String(localized: "Phase complete") : end.phase.name)
            let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
            let alert = AlarmPresentation.Alert(title: title, stopButton: stop)
            let attributes = AlarmAttributes<HourglassAlarmMetadata>(presentation: AlarmPresentation(alert: alert),
                                                                     metadata: HourglassAlarmMetadata(),
                                                                     tintColor: tint)
            let configuration = AlarmManager.AlarmConfiguration<HourglassAlarmMetadata>(
                schedule: .fixed(end.date),
                attributes: attributes,
                sound: .named(sound.fileName))
            let id = UUID()
            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                ids.append(id.uuidString)
            } catch {
                for s in ids { if let u = UUID(uuidString: s) { try? AlarmManager.shared.cancel(id: u) } }
                return false
            }
        }
        UserDefaults.standard.set(ids, forKey: scheduledAlarmIDsKey)
        return true
    }
    #endif
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct HourglassAlarmMetadata: AlarmMetadata {}
#endif
