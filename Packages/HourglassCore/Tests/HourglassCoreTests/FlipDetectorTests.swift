import XCTest
@testable import HourglassCore

/// Replays recorded `gravity.y` traces (Fixtures/*.csv, "t,gy", 60 Hz). The expected number of flips is encoded
/// in the file name: `<name>__<n>flips.csv`. Drop real device recordings into the folder to extend coverage.
final class FlipDetectorTests: XCTestCase {

    func fixtures() throws -> [URL] {
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "csv" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func load(_ url: URL) throws -> [(t: Double, gy: Double)] {
        try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line in
                let p = line.split(separator: ",")
                guard p.count == 2, let t = Double(p[0]), let gy = Double(p[1]) else { return nil }
                return (t, gy)
            }
    }

    func expectedFlips(_ url: URL) -> Int? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let r = name.range(of: "__") else { return nil }
        return Int(name[r.upperBound...].replacingOccurrences(of: "flips", with: ""))
    }

    func testRecordedTraces() throws {
        let files = try fixtures()
        XCTAssertFalse(files.isEmpty)
        for url in files {
            guard let expected = expectedFlips(url) else { continue }
            var d = FlipDetector()
            var flips = 0
            for s in try load(url) where d.process(gravityY: s.gy, timestamp: s.t) != nil { flips += 1 }
            XCTAssertEqual(flips, expected, url.lastPathComponent)
        }
    }

    func testFlipRequiresHold() {
        var d = FlipDetector()
        var t = 0.0
        for _ in 0..<30 { _ = d.process(gravityY: -0.95, timestamp: t); t += 1 / 60 }
        XCTAssertEqual(d.orientation, .upright)
        // 250 ms upside down → nothing.
        var fired = false
        for _ in 0..<15 { fired = fired || d.process(gravityY: 0.95, timestamp: t) != nil; t += 1 / 60 }
        XCTAssertFalse(fired)
        // Keep holding past 300 ms → flip.
        for _ in 0..<10 { fired = fired || d.process(gravityY: 0.95, timestamp: t) != nil; t += 1 / 60 }
        XCTAssertTrue(fired)
        XCTAssertEqual(d.orientation, .inverted)
    }

    func testCooldownPreventsDoubleTrigger() {
        var config = FlipDetector.Configuration()
        config.cooldown = 2
        var d = FlipDetector(configuration: config)
        var t = 0.0, flips = 0
        func feed(_ gy: Double, _ seconds: Double) {
            for _ in 0..<Int(seconds * 60) { if d.process(gravityY: gy, timestamp: t) != nil { flips += 1 }; t += 1 / 60 }
        }
        feed(-0.95, 0.5); feed(0.95, 0.5); feed(-0.95, 0.5)
        XCTAssertEqual(flips, 1)
        feed(-0.95, 2)
        feed(0.95, 0.5)
        XCTAssertEqual(flips, 2)
    }

    func testShakeDetector() {
        var s = ShakeDetector()
        XCTAssertNil(s.process(userAcceleration: (0.2, 0.1, 0.1), timestamp: 0))
        let strength = s.process(userAcceleration: (2.0, 0.5, 0.3), timestamp: 0.1)
        XCTAssertNotNil(strength)
        XCTAssertNil(s.process(userAcceleration: (2.5, 0, 0), timestamp: 0.2), "refractory period")
        XCTAssertNotNil(s.process(userAcceleration: (2.5, 0, 0), timestamp: 0.5))
    }

    func testLowPassFilterConverges() {
        var f = LowPassFilter(cutoffHz: 5)
        f.update(Vec2(0, 1), dt: 1 / 60)
        for _ in 0..<120 { f.update(Vec2(1, 0), dt: 1 / 60) }
        XCTAssertEqual(f.value.x, 1, accuracy: 0.01)
        XCTAssertEqual(f.value.y, 0, accuracy: 0.01)
    }
}
