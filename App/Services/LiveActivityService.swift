import Foundation
import HourglassCore
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Starts / updates / ends the Live Activity (Lock Screen + Dynamic Island) for the active timer. iOS 16.1+.
@MainActor
final class LiveActivityService {

    func sync(engine: TimerEngine, emoji: String) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        switch engine.state {
        case .idle, .finished:
            endAll()
        case .running, .paused:
            let state = Self.contentState(engine: engine)
            if let activity = Activity<HourglassActivityAttributes>.activities.first {
                Task { await Self.update(activity, state: state, staleDate: engine.endDate) }
            } else {
                let attributes = HourglassActivityAttributes(title: engine.snapshot.title.isEmpty ? String(localized: "Hourglass") : engine.snapshot.title,
                                                             emoji: emoji)
                do {
                    if #available(iOS 16.2, *) {
                        _ = try Activity.request(attributes: attributes,
                                                 content: ActivityContent(state: state, staleDate: engine.endDate.map { $0.addingTimeInterval(60) }),
                                                 pushType: nil)
                    } else {
                        _ = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
                    }
                } catch {
                    AnalyticsService.shared.record(error: error, context: "liveActivity.request")
                }
            }
        }
        #endif
    }

    func endAll() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<HourglassActivityAttributes>.activities {
            Task {
                if #available(iOS 16.2, *) {
                    await activity.end(nil, dismissalPolicy: .immediate)
                } else {
                    await activity.end(using: nil, dismissalPolicy: .immediate)
                }
            }
        }
        #endif
    }

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private static func update(_ activity: Activity<HourglassActivityAttributes>,
                               state: HourglassActivityAttributes.ContentState, staleDate: Date?) async {
        if #available(iOS 16.2, *) {
            await activity.update(ActivityContent(state: state, staleDate: staleDate.map { $0.addingTimeInterval(60) }))
        } else {
            await activity.update(using: state)
        }
    }

    @available(iOS 16.1, *)
    static func contentState(engine: TimerEngine, now: Date = Date()) -> HourglassActivityAttributes.ContentState {
        let phase = engine.currentPhase
        var label = ""
        if let count = engine.plan.phaseCount, count > 1 { label = "\(engine.phaseIndex + 1) / \(count)" }
        else if engine.plan.phaseCount == nil { label = "\(engine.phaseIndex + 1)" }
        let end = engine.endDate
        return .init(phaseName: phase?.name ?? "",
                     phaseLabel: label,
                     endDate: end,
                     startDate: end.map { $0.addingTimeInterval(-engine.totalDuration) },
                     pausedRemaining: engine.remaining(at: now),
                     phaseDuration: engine.totalDuration,
                     isPaused: engine.state == .paused,
                     themeID: engine.activeThemeID.rawValue)
    }
    #endif
}
