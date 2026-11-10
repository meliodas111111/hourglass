import Foundation
import HourglassCore
#if canImport(AppIntents)
import AppIntents
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Commands that can arrive from outside the main UI (Live Activity buttons, widgets, deep links).
enum TimerCommand: Equatable {
    case togglePause
    case stop
    case startSaved(UUID)
}

/// Routes commands to the running app. The app installs `handler` at launch; in the widget extension it stays
/// `nil` and `TimerCommandRouter` falls back to editing the shared snapshot directly.
@MainActor
enum TimerCommandRouter {
    static var handler: ((TimerCommand) async -> Void)?

    static func perform(_ command: TimerCommand) async {
        if let handler {
            await handler(command)
        } else {
            await performHeadless(command)
        }
    }

    /// Extension-side implementation: mutate the App Group snapshot, (re)schedule notifications, refresh widgets.
    /// The app reconciles everything (sand, alarms, Live Activity) the next time it becomes active.
    private static func performHeadless(_ command: TimerCommand) async {
        let now = Date()
        var engine: TimerEngine
        switch command {
        case .startSaved(let id):
            guard let saved = LibraryStore.load()?.timers.first(where: { $0.id == id }) else { return }
            engine = TimerEngine(plan: saved.plan, title: saved.name, themeID: saved.themeID)
            engine.start(at: now)
        case .togglePause:
            guard let snap = ActiveTimerStore.load() else { return }
            engine = TimerEngine(snapshot: snap)
            engine.advance(to: now)
            if engine.state == .running { engine.pause(at: now) } else if engine.state == .paused { engine.resume(at: now) }
        case .stop:
            guard let snap = ActiveTimerStore.load() else { return }
            engine = TimerEngine(snapshot: snap)
            engine.stop()
        }
        ActiveTimerStore.save(engine.snapshot)
        if engine.state == .running {
            await PhaseNotificationScheduler.schedule(engine: engine)
        } else {
            await PhaseNotificationScheduler.cancelAll()
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

#if canImport(AppIntents)

/// Live Activity "Pause / Resume" button. `LiveActivityIntent` runs in the **app** process.
@available(iOS 17.0, *)
struct ToggleTimerPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or Resume Timer"
    static var isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await TimerCommandRouter.perform(.togglePause)
        return .result()
    }
}

/// Live Activity "Stop" button.
@available(iOS 17.0, *)
struct StopTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Timer"
    static var isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await TimerCommandRouter.perform(.stop)
        return .result()
    }
}

/// Interactive widget button "start this favourite" (iOS 17+). Runs in the widget process without opening the app.
@available(iOS 17.0, *)
struct StartSavedTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Saved Timer"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Timer ID")
    var timerID: String

    init() {}
    init(timerID: UUID) { self.timerID = timerID.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: timerID) else { return .result() }
        await TimerCommandRouter.perform(.startSaved(id))
        return .result()
    }
}

#endif
