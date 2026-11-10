import XCTest
@testable import HourglassCore

/// Physics ⇄ timer synchronisation: whatever the tilt, the source chamber must be empty on the frame the timer
/// ends (± 1 frame) and never run *ahead* of time; grains are conserved.
final class SandSyncTests: XCTestCase {

    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Small grid keeps the tests fast in Debug builds; the algorithm is resolution independent.
    /// Grid used by `run`; individual tests may switch to the real app size.
    var gridSize = (width: 80, height: 160, grains: 2_000)

    func makeSim(seed: UInt64 = 7) -> SandSimulation {
        SandSimulation(geometry: HourglassGeometry(width: gridSize.width, height: gridSize.height),
                       targetGrains: gridSize.grains, seed: seed)
    }

    struct RunResult {
        var framesLateAfterEnd = 0
        var corrected = 0
        var maxAheadOfTime = 0
        var correctedBeforeFlip = 0
    }

    /// Runs one timer at `fps` with a fixed gravity and returns sync metrics.
    func run(duration: TimeInterval, gravity: Vec2, fps: Double = 60, flipAt: TimeInterval? = nil,
             file: StaticString = #filePath, line: UInt = #line) -> RunResult {
        let sim = makeSim()
        var engine = TimerEngine(plan: .single(duration))
        sim.gravity = .down
        sim.sourceChamber = engine.snapshot.sourceChamber
        sim.resetSettled(sourceGrains: 0)                 // idle: everything in the sink
        // On-screen start: rotate the sand into the top chamber and start.
        sim.rotate180()
        engine.flip(at: t0, physical: false)
        sim.gravity = gravity

        var result = RunResult()
        let dt = 1 / fps
        var now = t0
        var flipped = false
        var ended = false
        for _ in 0..<Int((duration + 1) * fps) {
            now = now.addingTimeInterval(dt)
            if let f = flipAt, !flipped, now.timeIntervalSince(t0) >= f {
                engine.flip(at: now, physical: true)
                sim.sourceChamber = engine.snapshot.sourceChamber
                sim.noteFlip()
                sim.gravity = -gravity
                flipped = true
                result.correctedBeforeFlip = result.corrected
            }
            engine.advance(to: now)
            let sync = engine.timeSync(total: sim.grainCount, at: now)
            let stats = sim.step(dt: dt, sync: sync)
            result.corrected += stats.corrected

            // Never ahead of time (expected uses ceil ⇒ source ≥ expected).
            result.maxAheadOfTime = max(result.maxAheadOfTime, sync.expectedSource - sim.sourceCount)
            // Conservation.
            XCTAssertEqual(sim.upperCount + sim.lowerCount, sim.grainCount, file: file, line: line)

            if engine.state == .finished {
                if sim.sourceCount > 0 { result.framesLateAfterEnd += 1 }
                if !ended { ended = true }
            }
        }
        let recount = sim.countGrains()
        XCTAssertEqual(recount.upper, sim.upperCount, "incremental counters drift", file: file, line: line)
        XCTAssertEqual(recount.lower, sim.lowerCount, file: file, line: line)
        XCTAssertTrue(ended, file: file, line: line)
        return result
    }

    func testUprightEmptiesOnTimeMostlyPhysically() {
        let r = run(duration: 12, gravity: .down)
        XCTAssertEqual(r.framesLateAfterEnd, 0)
        XCTAssertEqual(r.maxAheadOfTime, 0)
        XCTAssertLessThan(r.corrected, 2_000 / 4, "upright flow should be mostly physical, not corrected")
    }

    func testAnyTiltEmptiesOnTime() {
        let angles: [Double] = [15, 35, 60, 90, 120, 150, 180]   // degrees from "down"
        for deg in angles {
            let a = deg * .pi / 180
            let g = Vec2(sin(a), cos(a))
            let r = run(duration: 8, gravity: g)
            XCTAssertEqual(r.framesLateAfterEnd, 0, "tilt \(deg)° finished late")
            XCTAssertEqual(r.maxAheadOfTime, 0, "tilt \(deg)° ran ahead of time")
        }
    }

    func testFlatOnTableEmptiesOnTime() {
        let r = run(duration: 6, gravity: Vec2(0.03, 0.05))
        XCTAssertEqual(r.framesLateAfterEnd, 0)
    }

    func testShortestTimerAt120Hz() {
        let r = run(duration: DurationLimits.minimum, gravity: .down, fps: 120)
        XCTAssertEqual(r.framesLateAfterEnd, 0)
        XCTAssertEqual(r.maxAheadOfTime, 0)
    }

    /// Regression: after a flip the pile falls ~1–2 s before reaching the neck; that delay used to be "fixed" by
    /// teleporting hundreds of grains below the neck (visible as sand vanishing from the top).
    func testNoTeleportBurstAfterFlip() {
        let r = run(duration: 30, gravity: .down, flipAt: 15)
        XCTAssertEqual(r.framesLateAfterEnd, 0)
        XCTAssertLessThan(r.corrected - r.correctedBeforeFlip, 30, "grains teleported after the flip")
        XCTAssertLessThan(r.corrected, 60)
    }

    /// Regression: at low frame rates (battery-saving 10–30 Hz, slow devices) sub-steps were capped at 5 per frame,
    /// sand fell up to 3× slower than real time and the invisible correction did most of the work.
    func testFrameRateIndependentFlow() {
        for fps in [10.0, 30.0, 60.0, 120.0] {
            let r = run(duration: 30, gravity: .down, fps: fps)
            XCTAssertEqual(r.framesLateAfterEnd, 0, "\(fps) fps")
            XCTAssertLessThan(r.corrected, 100, "\(fps) fps: flow must stay physical")
        }
    }

    /// Short timers need more grains/s than a 3-cell neck passes; the neck boost keeps them physical
    /// (previously 58–81 % of the sand was moved by the invisible correction).
    func testShortTimersFlowPhysically() {
        gridSize = (181, 360, 11_000)          // app-sized grid: 5–10 s timers need 1 100–2 200 grains/s
        let n = makeSim().grainCount
        for duration in [5.0, 10.0] {
            let r = run(duration: duration, gravity: .down)
            XCTAssertEqual(r.framesLateAfterEnd, 0)
            XCTAssertLessThan(r.corrected, n / 20, "\(duration) s timer: correction should be ≲ 5 %")
        }
    }

    func testPhysicalFlipMidRun() {
        let r = run(duration: 10, gravity: .down, flipAt: 4)
        XCTAssertEqual(r.framesLateAfterEnd, 0)
        // Right after a flip the grains that were "in flight" (≤ lag tolerance + ceil rounding) count for the
        // other side — like a real hourglass. The gate then simply waits for time to catch up.
        XCTAssertLessThanOrEqual(r.maxAheadOfTime, 30)
    }

    func testPausedGateIsClosed() {
        let sim = makeSim()
        sim.resetSettled(sourceGrains: sim.grainCount)
        let before = sim.sourceCount
        for _ in 0..<120 { sim.step(dt: 1 / 60, sync: .stopped) }
        XCTAssertEqual(sim.sourceCount, before)
    }

    func testRestoreGeneratesSettledPiles() {
        let sim = makeSim()
        sim.sourceChamber = .upper
        sim.resetSettled(sourceGrains: 700, gravity: Vec2(0.5, 0.86))
        XCTAssertEqual(sim.upperCount, 700)
        XCTAssertEqual(sim.lowerCount, sim.grainCount - 700)
        let recount = sim.countGrains()
        XCTAssertEqual(recount.upper, 700)
        // Nothing inside walls.
        for i in sim.cells.indices where sim.cells[i] == CellType.sand.rawValue {
            XCTAssertEqual(sim.geometry.wallMask[i], 0)
        }
        // A settled pile barely moves.
        sim.gravity = Vec2(0.5, 0.86)
        var moved = 0
        for _ in 0..<30 { moved += sim.step(dt: 1 / 60, sync: .stopped).moved }
        XCTAssertLessThan(moved, sim.grainCount / 5)
    }

    func testRotate180MapsWallsOntoWalls() {
        for g in [HourglassGeometry(width: 80, height: 160, neckCells: 3), HourglassGeometry(width: 81, height: 161, neckCells: 2)] {
            let m = g.wallMask
            XCTAssertEqual(m, Array(m.reversed()), "silhouette must be point-symmetric")
            XCTAssertEqual(g.upperCapacity, g.lowerCapacity)
            // Neck really is `neckCells` wide.
            let open = (0..<g.width).filter { g.isInterior($0, g.gateRow) }.count
            XCTAssertEqual(open, g.neckCells)
        }
    }

    func testFunnelIsSteeperThan45Degrees() {
        let g = HourglassGeometry(density: .balanced)
        var y = Double(g.gateRow + g.neckHalfRows)
        while y < Double(g.height - g.capRows) * 0.9 {
            let slope = g.halfWidth(atY: y + 1) - g.halfWidth(atY: y)
            XCTAssertLessThan(slope, 1.0, "wall shallower than 45° at row \(y) — sand could get stuck")
            y += 1
        }
    }

    func testDensityPresetsGrainCounts() {
        for d in SandDensity.allCases {
            let sim = SandSimulation(geometry: HourglassGeometry(density: d), targetGrains: d.targetGrains)
            XCTAssertGreaterThanOrEqual(sim.grainCount, 15_000, "\(d)")
            XCTAssertLessThanOrEqual(sim.grainCount, 40_000, "\(d)")
        }
    }
}
