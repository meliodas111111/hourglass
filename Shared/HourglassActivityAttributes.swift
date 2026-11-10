import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// Live Activity / Dynamic Island payload. Compiled into the app (to start/update) and the widget (to render).
@available(iOS 16.1, *)
struct HourglassActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phaseName: String
        /// "2 / 8" style label for sequences, empty for single timers.
        var phaseLabel: String
        /// End of the current phase; `nil` while paused.
        var endDate: Date?
        /// Phase start (for `ProgressView(timerInterval:)`).
        var startDate: Date?
        var pausedRemaining: TimeInterval
        var phaseDuration: TimeInterval
        var isPaused: Bool
        /// `SandTheme.ID.rawValue`
        var themeID: String

        /// Fraction drained when paused (static rendering).
        var pausedProgress: Double { phaseDuration > 0 ? 1 - pausedRemaining / phaseDuration : 1 }
    }

    var title: String
    var emoji: String
}
#endif
