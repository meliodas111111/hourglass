import XCTest
@testable import HourglassCore

/// Rough CPU budget check of one simulation frame per density preset. On device, profile with Instruments
/// (Time Profiler + the "Sand Step" signpost emitted by `SimulationDriver`); here we just guard regressions.
final class PerformanceTests: XCTestCase {

    func testStepCostPerDensity() {
        #if DEBUG
        throw XCTSkip("Run in release: swift test -c release -Xswiftc -enable-testing")
        #else
        for density in SandDensity.allCases {
            let sim = SandSimulation(geometry: HourglassGeometry(density: density), targetGrains: density.targetGrains)
            sim.sourceChamber = .upper
            sim.resetSettled(sourceGrains: sim.grainCount)
            sim.gravity = Vec2(0.2, 0.98)
            var sync = TimeSync(expectedSource: sim.grainCount, remaining: 600, grainsPerSecond: Double(sim.grainCount) / 600, isRunning: true)
            let frames = 240
            let start = DispatchTime.now().uptimeNanoseconds
            for f in 0..<frames {
                sync.expectedSource = sim.grainCount - f * 8
                sim.step(dt: 1 / 60, sync: sync)
            }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / Double(frames)
            print("⏱ \(density) \(sim.width)×\(sim.height), N=\(sim.grainCount): \(String(format: "%.2f", ms)) ms/frame")
            // Generous ceiling for CI machines; A12-class devices measure well below the 8 ms we budget at 120 Hz.
            XCTAssertLessThan(ms, 25, "\(density)")
        }
        #endif
    }
}
