import Foundation

/// Allowed timer range (spec: 5 seconds … 24 hours).
public enum DurationLimits {
    public static let minimum: TimeInterval = 5
    public static let maximum: TimeInterval = 24 * 60 * 60
    public static func clamp(_ d: TimeInterval) -> TimeInterval { min(max(d, minimum), maximum) }
}

/// One phase of a (possibly single-phase) timer.
public struct Phase: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var duration: TimeInterval
    /// Optional per-phase sand colour. `nil` → the timer's theme.
    public var themeID: SandTheme.ID?

    public init(id: UUID = UUID(), name: String, duration: TimeInterval, themeID: SandTheme.ID? = nil) {
        self.id = id
        self.name = name
        self.duration = DurationLimits.clamp(duration)
        self.themeID = themeID
    }
}

/// How many times the phase cycle is played.
public enum RepeatCount: Codable, Hashable, Sendable {
    case times(Int)
    case infinite

    public var count: Int? { if case .times(let n) = self { return max(1, n) } else { return nil } }
}

/// A timer plan: `cycle` repeated `repeats` times, then an optional `finale` played once.
///
/// * single timer → `cycle = [one phase]`, `repeats = .times(1)`
/// * Pomodoro    → cycle `[Focus 25, Break 5]` × 4, `dropLastPhaseOfFinalCycle`, finale `[Long break 15]`
/// * Intervals   → cycle `[Work 40 s, Rest 20 s]` × 8
public struct TimerPlan: Codable, Hashable, Sendable {
    public var cycle: [Phase]
    public var repeats: RepeatCount
    public var finale: [Phase]
    /// Pomodoro-style: the last short break is replaced by the finale.
    public var dropLastPhaseOfFinalCycle: Bool

    public init(cycle: [Phase], repeats: RepeatCount = .times(1), finale: [Phase] = [], dropLastPhaseOfFinalCycle: Bool = false) {
        precondition(!cycle.isEmpty, "a plan needs at least one phase")
        self.cycle = cycle
        self.repeats = repeats
        self.finale = finale
        self.dropLastPhaseOfFinalCycle = dropLastPhaseOfFinalCycle
    }

    public static func single(_ duration: TimeInterval, name: String = "") -> TimerPlan {
        TimerPlan(cycle: [Phase(name: name, duration: duration)])
    }

    public var isSequence: Bool { cycle.count > 1 || (repeats.count ?? 2) > 1 || !finale.isEmpty }

    /// Number of phases, `nil` when infinite.
    public var phaseCount: Int? {
        guard let r = repeats.count else { return nil }
        let cyc = cycle.count * r - (dropLastPhaseOfFinalCycle && cycle.count > 1 ? 1 : 0)
        return cyc + finale.count
    }

    /// Phase at flattened index `k` (`nil` past the end).
    public func phase(at k: Int) -> Phase? {
        guard k >= 0 else { return nil }
        guard let r = repeats.count else { return cycle[k % cycle.count] }
        let cyc = cycle.count * r - (dropLastPhaseOfFinalCycle && cycle.count > 1 ? 1 : 0)
        if k < cyc { return cycle[k % cycle.count] }
        let f = k - cyc
        return f < finale.count ? finale[f] : nil
    }

    /// 1-based round number of phase `k` within the cycle repetitions (for "Round 2/4" labels).
    public func round(ofPhase k: Int) -> Int { k / cycle.count + 1 }

    /// Total duration, `nil` when infinite.
    public var totalDuration: TimeInterval? {
        guard let n = phaseCount else { return nil }
        return (0..<n).reduce(0) { $0 + (phase(at: $1)?.duration ?? 0) }
    }

    // MARK: Templates

    public static func pomodoro(focus: String = "Focus", shortBreak: String = "Short break", longBreak: String = "Long break") -> TimerPlan {
        TimerPlan(cycle: [Phase(name: focus, duration: 25 * 60, themeID: .ember),
                          Phase(name: shortBreak, duration: 5 * 60, themeID: .ocean)],
                  repeats: .times(4),
                  finale: [Phase(name: longBreak, duration: 15 * 60, themeID: .jade)],
                  dropLastPhaseOfFinalCycle: true)
    }

    public static func intervals(work: String = "Work", rest: String = "Rest") -> TimerPlan {
        TimerPlan(cycle: [Phase(name: work, duration: 40, themeID: .ember),
                          Phase(name: rest, duration: 20, themeID: .ocean)],
                  repeats: .times(8))
    }
}

public enum TimerState: String, Codable, Sendable {
    case idle, running, paused, finished
}

/// Everything needed to reconstruct a timer after the app was killed — persisted as JSON (App Group defaults).
///
/// Dates, not ticks, are the source of truth: `elapsed = now − startDate − pausedAccumulated`.
public struct TimerSnapshot: Codable, Equatable, Sendable {
    public static let currentSchema = 1

    public var schemaVersion: Int = TimerSnapshot.currentSchema
    public var state: TimerState
    public var plan: TimerPlan
    public var title: String
    public var themeID: SandTheme.ID
    /// Flattened index of the current phase.
    public var phaseIndex: Int
    /// Effective start of the current phase.
    public var startDate: Date?
    /// Paused time accumulated *within the current phase*.
    public var pausedAccumulated: TimeInterval
    public var pauseStartedAt: Date?
    /// Duration of the current phase.
    public var totalDuration: TimeInterval
    /// Grid chamber that is currently draining (needed to regenerate the sand on restore).
    public var sourceChamber: Chamber

    public init(plan: TimerPlan, title: String = "", themeID: SandTheme.ID = .goldenSand) {
        self.state = .idle
        self.plan = plan
        self.title = title
        self.themeID = themeID
        self.phaseIndex = 0
        self.startDate = nil
        self.pausedAccumulated = 0
        self.pauseStartedAt = nil
        self.totalDuration = plan.phase(at: 0)?.duration ?? DurationLimits.minimum
        self.sourceChamber = .upper
    }
}
