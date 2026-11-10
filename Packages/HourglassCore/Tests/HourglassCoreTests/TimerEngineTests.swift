import XCTest
@testable import HourglassCore

final class TimerEngineTests: XCTestCase {

    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testStartAndRemaining() {
        var e = TimerEngine(plan: .single(60))
        XCTAssertEqual(e.state, .idle)
        e.start(at: t0)
        XCTAssertEqual(e.state, .running)
        XCTAssertEqual(e.remaining(at: t0.addingTimeInterval(10)), 50, accuracy: 1e-9)
        XCTAssertEqual(e.endDate, t0.addingTimeInterval(60))
    }

    func testPauseResumeAccumulates() {
        var e = TimerEngine(plan: .single(60))
        e.start(at: t0)
        e.pause(at: t0.addingTimeInterval(10))
        // Time passes while paused — remaining must not change.
        XCTAssertEqual(e.remaining(at: t0.addingTimeInterval(500)), 50, accuracy: 1e-9)
        XCTAssertNil(e.endDate)
        e.resume(at: t0.addingTimeInterval(40))
        XCTAssertEqual(e.remaining(at: t0.addingTimeInterval(45)), 45, accuracy: 1e-9)
        XCTAssertEqual(e.endDate, t0.addingTimeInterval(90))
    }

    func testBackgroundCatchUpFinishesAtEndDateNotNow() {
        var e = TimerEngine(plan: .single(30))
        e.start(at: t0)
        let events = e.advance(to: t0.addingTimeInterval(3600))   // app was in background for an hour
        XCTAssertEqual(events, [.finished(at: t0.addingTimeInterval(30))])
        XCTAssertEqual(e.state, .finished)
        XCTAssertEqual(e.remaining(at: t0.addingTimeInterval(3600)), 0)
    }

    func testSnapshotSurvivesAppKill() throws {
        var e = TimerEngine(plan: .pomodoro(), title: "Work", themeID: .ember)
        e.start(at: t0)
        e.pause(at: t0.addingTimeInterval(100))
        let data = try JSONEncoder().encode(e.snapshot)
        let restored = TimerEngine(snapshot: try JSONDecoder().decode(TimerSnapshot.self, from: data))
        XCTAssertEqual(restored, e)
        XCTAssertEqual(restored.remaining(at: t0.addingTimeInterval(9999)), 25 * 60 - 100, accuracy: 1e-6)
    }

    func testFlipWhileRunningMirrorsRemaining() {
        var e = TimerEngine(plan: .single(100))
        e.start(at: t0)
        let now = t0.addingTimeInterval(30)            // remaining 70
        XCTAssertEqual(e.flip(at: now, physical: true), .reversed(newRemaining: 30))
        XCTAssertEqual(e.remaining(at: now), 30, accuracy: 1e-9)
        XCTAssertEqual(e.endDate, now.addingTimeInterval(30))
        XCTAssertEqual(e.snapshot.sourceChamber, .lower, "physical flip swaps the draining chamber")
    }

    func testFlipWhilePausedStaysPaused() {
        var e = TimerEngine(plan: .single(100))
        e.start(at: t0)
        e.pause(at: t0.addingTimeInterval(80))         // remaining 20
        e.flip(at: t0.addingTimeInterval(200), physical: false)
        XCTAssertEqual(e.state, .paused)
        XCTAssertEqual(e.remaining(at: t0.addingTimeInterval(500)), 80, accuracy: 1e-9)
        XCTAssertEqual(e.snapshot.sourceChamber, .upper, "button flip keeps the chamber (grid is rotated instead)")
        e.resume(at: t0.addingTimeInterval(300))
        XCTAssertEqual(e.remaining(at: t0.addingTimeInterval(310)), 70, accuracy: 1e-9)
    }

    func testFlipIdleStartsAndFinishedRestarts() {
        var e = TimerEngine(plan: .single(10))
        XCTAssertEqual(e.flip(at: t0, physical: true), .started)
        e.advance(to: t0.addingTimeInterval(11))
        XCTAssertEqual(e.state, .finished)
        XCTAssertEqual(e.flip(at: t0.addingTimeInterval(20), physical: true), .restarted)
        XCTAssertEqual(e.remaining(at: t0.addingTimeInterval(20)), 10, accuracy: 1e-9)
    }

    func testDoubleFlipRestoresRemaining() {
        var e = TimerEngine(plan: .single(60))
        e.start(at: t0)
        let now = t0.addingTimeInterval(15)
        e.flip(at: now, physical: true)
        e.flip(at: now, physical: true)
        XCTAssertEqual(e.remaining(at: now), 45, accuracy: 1e-9)
        XCTAssertEqual(e.snapshot.sourceChamber, .upper)
    }

    func testPomodoroSequence() {
        let plan = TimerPlan.pomodoro()
        XCTAssertEqual(plan.phaseCount, 8)  // F B F B F B F + Long
        let expectedTotal = TimeInterval(130 * 60)          // 4×25 + 3×5 + 15 minutes
        XCTAssertEqual(plan.totalDuration, expectedTotal)
        XCTAssertEqual(plan.phase(at: 7)?.name, "Long break")
        XCTAssertNil(plan.phase(at: 8))

        var e = TimerEngine(plan: plan)
        e.start(at: t0)
        XCTAssertEqual(e.upcomingPhaseEnds().count, 8)
        XCTAssertEqual(e.upcomingPhaseEnds().last?.date, t0.addingTimeInterval(plan.totalDuration!))
        XCTAssertTrue(e.upcomingPhaseEnds().last!.isLast)

        // Catch up after 40 minutes in background: Focus(25) + Break(5) done, in second Focus.
        let events = e.advance(to: t0.addingTimeInterval(40 * 60))
        XCTAssertEqual(events, [.phaseCompleted(index: 0, next: 1, at: t0.addingTimeInterval(25 * 60)),
                                .phaseCompleted(index: 1, next: 2, at: t0.addingTimeInterval(30 * 60))])
        XCTAssertEqual(e.phaseIndex, 2)
        XCTAssertEqual(e.remaining(at: t0.addingTimeInterval(40 * 60)), 15 * 60, accuracy: 1e-6)

        let rest = e.advance(to: t0.addingTimeInterval(10_000))
        XCTAssertEqual(rest.last, .finished(at: t0.addingTimeInterval(plan.totalDuration!)))
    }

    func testPauseInSequenceShiftsLaterPhases() {
        var e = TimerEngine(plan: .intervals())
        e.start(at: t0)
        e.pause(at: t0.addingTimeInterval(10))
        e.resume(at: t0.addingTimeInterval(20))         // 10 s paused
        XCTAssertEqual(e.upcomingPhaseEnds().first?.date, t0.addingTimeInterval(50))
        XCTAssertEqual(e.upcomingPhaseEnds()[1].date, t0.addingTimeInterval(70))
        XCTAssertEqual(e.upcomingPhaseEnds().count, 16)
    }

    func testInfiniteRepeats() {
        let plan = TimerPlan(cycle: [Phase(name: "A", duration: 10), Phase(name: "B", duration: 5)], repeats: .infinite)
        XCTAssertNil(plan.phaseCount)
        XCTAssertNil(plan.totalDuration)
        XCTAssertEqual(plan.phase(at: 1001)?.name, "B")
        var e = TimerEngine(plan: plan)
        e.start(at: t0)
        XCTAssertEqual(e.upcomingPhaseEnds(limit: 64).count, 64, "notification scheduling is capped")
        e.advance(to: t0.addingTimeInterval(15 * 100 + 1))
        XCTAssertEqual(e.phaseIndex, 200)
        XCTAssertEqual(e.state, .running)
    }

    func testBoundaryDurations() {
        XCTAssertEqual(Phase(name: "", duration: 1).duration, 5)
        XCTAssertEqual(Phase(name: "", duration: 100_000).duration, 86_400)

        var short = TimerEngine(plan: .single(5))
        short.start(at: t0)
        XCTAssertTrue(short.advance(to: t0.addingTimeInterval(4.999)).isEmpty)
        XCTAssertEqual(short.advance(to: t0.addingTimeInterval(5)), [.finished(at: t0.addingTimeInterval(5))])

        var long = TimerEngine(plan: .single(86_400))
        long.start(at: t0)
        XCTAssertEqual(DurationFormatter.string(long.remaining(at: t0)), "24:00:00")
        XCTAssertEqual(long.expectedSourceGrains(total: 30_000, at: t0.addingTimeInterval(43_200)), 15_000)
        XCTAssertEqual(long.advance(to: t0.addingTimeInterval(86_400)), [.finished(at: t0.addingTimeInterval(86_400))])
    }

    func testExpectedGrainsCeilAndZeroAtEnd() {
        var e = TimerEngine(plan: .single(10))
        XCTAssertEqual(e.expectedSourceGrains(total: 1000, at: t0), 0, "idle shows a run-out hourglass")
        e.start(at: t0)
        XCTAssertEqual(e.expectedSourceGrains(total: 1000, at: t0), 1000)
        XCTAssertEqual(e.expectedSourceGrains(total: 1000, at: t0.addingTimeInterval(9.9999)), 1)
        XCTAssertEqual(e.expectedSourceGrains(total: 1000, at: t0.addingTimeInterval(10)), 0)
    }

    func testFormatter() {
        XCTAssertEqual(DurationFormatter.string(0), "00:00")
        XCTAssertEqual(DurationFormatter.string(4.2), "00:05")
        XCTAssertEqual(DurationFormatter.string(59 * 60 + 59), "59:59")
        XCTAssertEqual(DurationFormatter.string(3600), "01:00:00")
    }

    func testStopReturnsToIdleKeepingPlan() {
        var e = TimerEngine(plan: .intervals(), title: "HIIT", themeID: .ocean)
        e.start(at: t0)
        e.advance(to: t0.addingTimeInterval(45))
        e.stop()
        XCTAssertEqual(e.state, .idle)
        XCTAssertEqual(e.phaseIndex, 0)
        XCTAssertEqual(e.plan, .intervals().withSameIDs(as: e.plan))
        XCTAssertEqual(e.snapshot.title, "HIIT")
    }
}

private extension TimerPlan {
    /// Phases get random UUIDs; align them for equality checks.
    func withSameIDs(as other: TimerPlan) -> TimerPlan {
        var copy = self
        for i in copy.cycle.indices where i < other.cycle.count { copy.cycle[i].id = other.cycle[i].id }
        for i in copy.finale.indices where i < other.finale.count { copy.finale[i].id = other.finale[i].id }
        return copy
    }
}
