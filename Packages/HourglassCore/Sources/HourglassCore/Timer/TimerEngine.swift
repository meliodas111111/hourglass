import Foundation

/// Events produced while advancing the timer (used for sounds, haptics, auto-flip and notifications).
public enum TimerEvent: Equatable, Sendable {
    /// Phase `index` ended at `date` and phase `next` started immediately.
    case phaseCompleted(index: Int, next: Int, at: Date)
    /// The last phase ended at `date`.
    case finished(at: Date)
}

/// What a flip did (UI reacts with haptics / labels).
public enum FlipOutcome: Equatable, Sendable {
    case started
    case restarted
    /// Running/paused flip: `remaining_new = total − remaining_old`.
    case reversed(newRemaining: TimeInterval)
}

/// Wall-clock based timer state machine: idle → running ⇄ paused → finished.
///
/// Pure value type; every mutating call receives `now` so tests can drive time deterministically.
/// The sand simulation only *visualises* `remaining(at:)` — it is never the source of truth.
public struct TimerEngine: Equatable, Sendable {

    public private(set) var snapshot: TimerSnapshot

    public init(snapshot: TimerSnapshot) { self.snapshot = snapshot }

    public init(plan: TimerPlan, title: String = "", themeID: SandTheme.ID = .goldenSand) {
        self.snapshot = TimerSnapshot(plan: plan, title: title, themeID: themeID)
    }

    // MARK: Queries

    public var state: TimerState { snapshot.state }
    public var plan: TimerPlan { snapshot.plan }
    public var phaseIndex: Int { snapshot.phaseIndex }
    public var currentPhase: Phase? { snapshot.plan.phase(at: snapshot.phaseIndex) }
    public var totalDuration: TimeInterval { snapshot.totalDuration }

    /// Active theme: per-phase colour if set, else the timer's theme.
    public var activeThemeID: SandTheme.ID { currentPhase?.themeID ?? snapshot.themeID }

    public func elapsed(at now: Date) -> TimeInterval {
        switch snapshot.state {
        case .idle: return 0
        case .finished: return snapshot.totalDuration
        case .running:
            guard let start = snapshot.startDate else { return 0 }
            return clamp(now.timeIntervalSince(start) - snapshot.pausedAccumulated, 0, snapshot.totalDuration)
        case .paused:
            guard let start = snapshot.startDate, let p = snapshot.pauseStartedAt else { return 0 }
            return clamp(p.timeIntervalSince(start) - snapshot.pausedAccumulated, 0, snapshot.totalDuration)
        }
    }

    public func remaining(at now: Date) -> TimeInterval { snapshot.totalDuration - elapsed(at: now) }

    /// 0 → full source chamber, 1 → drained.
    public func progress(at now: Date) -> Double {
        snapshot.totalDuration > 0 ? elapsed(at: now) / snapshot.totalDuration : 1
    }

    /// End of the current phase (running only).
    public var endDate: Date? {
        guard snapshot.state == .running, let start = snapshot.startDate else { return nil }
        return start.addingTimeInterval(snapshot.pausedAccumulated + snapshot.totalDuration)
    }

    /// Grains that should be in the draining chamber: `ceil(N × remaining / total)`.
    /// Ceil guarantees ≥ 1 grain while any time is left and exactly 0 at `endDate`.
    /// In idle/finished the hourglass shows "ran out" (everything in the sink) — flipping it starts the timer.
    public func expectedSourceGrains(total n: Int, at now: Date) -> Int {
        switch snapshot.state {
        case .idle, .finished: return 0
        case .running, .paused:
            let r = remaining(at: now)
            guard r > 0, snapshot.totalDuration > 0 else { return 0 }
            return min(n, Int((Double(n) * r / snapshot.totalDuration).rounded(.up)))
        }
    }

    public func timeSync(total n: Int, at now: Date) -> TimeSync {
        let rate = snapshot.totalDuration > 0 ? Double(n) / snapshot.totalDuration : 0
        switch snapshot.state {
        case .running:
            return TimeSync(expectedSource: expectedSourceGrains(total: n, at: now), remaining: remaining(at: now),
                            grainsPerSecond: rate, isRunning: true)
        case .finished:
            // Keep the gate "open with zero remaining": on the frame the timer ends whatever is still on top is
            // flushed, so the chamber is empty exactly at endDate. Afterwards it is a no-op.
            return TimeSync(expectedSource: 0, remaining: 0, grainsPerSecond: rate, isRunning: true)
        case .idle, .paused:
            return TimeSync(expectedSource: expectedSourceGrains(total: n, at: now), remaining: .infinity,
                            grainsPerSecond: rate, isRunning: false)
        }
    }

    /// Future phase ends (for local notifications / alarms). Empty unless running.
    public func upcomingPhaseEnds(limit: Int = 48) -> [(date: Date, index: Int, phase: Phase, isLast: Bool)] {
        guard var date = endDate else { return [] }
        var result: [(Date, Int, Phase, Bool)] = []
        var k = snapshot.phaseIndex
        while result.count < limit, let phase = snapshot.plan.phase(at: k) {
            let isLast = snapshot.plan.phase(at: k + 1) == nil
            result.append((date, k, phase, isLast))
            guard let next = snapshot.plan.phase(at: k + 1) else { break }
            date = date.addingTimeInterval(next.duration)
            k += 1
        }
        return result
    }

    // MARK: Mutations

    /// Replaces the plan (only while idle/finished).
    public mutating func configure(plan: TimerPlan, title: String, themeID: SandTheme.ID) {
        let chamber = snapshot.sourceChamber
        snapshot = TimerSnapshot(plan: plan, title: title, themeID: themeID)
        snapshot.sourceChamber = chamber
    }

    public mutating func start(at now: Date) {
        snapshot.phaseIndex = 0
        beginPhase(0, at: now)
    }

    public mutating func pause(at now: Date) {
        guard snapshot.state == .running else { return }
        snapshot.state = .paused
        snapshot.pauseStartedAt = now
    }

    public mutating func resume(at now: Date) {
        guard snapshot.state == .paused, let p = snapshot.pauseStartedAt else { return }
        snapshot.pausedAccumulated += max(0, now.timeIntervalSince(p))
        snapshot.pauseStartedAt = nil
        snapshot.state = .running
    }

    /// Cancels and returns to idle (plan kept).
    public mutating func stop() {
        let chamber = snapshot.sourceChamber
        snapshot = TimerSnapshot(plan: snapshot.plan, title: snapshot.title, themeID: snapshot.themeID)
        snapshot.sourceChamber = chamber
    }

    /// Hourglass flip.
    /// - Parameter physical: `true` when the device itself was turned over (the draining grid chamber swaps);
    ///   `false` for an on-screen flip, where the sand grid is rotated 180° instead and the chamber stays.
    @discardableResult
    public mutating func flip(at now: Date, physical: Bool) -> FlipOutcome {
        if physical { snapshot.sourceChamber = snapshot.sourceChamber.opposite }
        switch snapshot.state {
        case .idle:
            start(at: now)
            return .started
        case .finished:
            start(at: now)
            return .restarted
        case .running, .paused:
            // Real hourglass: what was left on top is now at the bottom → remaining_new = total − remaining_old.
            let remainingOld = remaining(at: now)
            let elapsedNew = remainingOld
            snapshot.startDate = now.addingTimeInterval(-elapsedNew)
            snapshot.pausedAccumulated = 0
            if snapshot.state == .paused { snapshot.pauseStartedAt = now }
            return .reversed(newRemaining: snapshot.totalDuration - elapsedNew)
        }
    }

    /// Advances phases whose end lies in the past. Handles catching up after background / app kill:
    /// next phase start = previous phase *end*, never `now`, so sequences never drift.
    @discardableResult
    public mutating func advance(to now: Date) -> [TimerEvent] {
        var events: [TimerEvent] = []
        while snapshot.state == .running, let end = endDate, end <= now {
            let next = snapshot.phaseIndex + 1
            if snapshot.plan.phase(at: next) != nil {
                events.append(.phaseCompleted(index: snapshot.phaseIndex, next: next, at: end))
                beginPhase(next, at: end)
            } else {
                snapshot.state = .finished
                snapshot.pauseStartedAt = nil
                events.append(.finished(at: end))
            }
            if events.count > 10_000 { break }   // safety for absurd catch-ups with infinite plans
        }
        return events
    }

    private mutating func beginPhase(_ k: Int, at date: Date) {
        snapshot.phaseIndex = k
        snapshot.totalDuration = snapshot.plan.phase(at: k)?.duration ?? DurationLimits.minimum
        snapshot.startDate = date
        snapshot.pausedAccumulated = 0
        snapshot.pauseStartedAt = nil
        snapshot.state = .running
    }
}

/// Digital read-out: `mm:ss` below an hour, `hh:mm:ss` above. Rounds *up* so "00:01" shows until the very end.
public enum DurationFormatter {
    public static func string(_ seconds: TimeInterval, roundUp: Bool = true) -> String {
        let s = max(0, Int(roundUp ? seconds.rounded(.up) : seconds.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}
