import XCTest
@testable import HourglassCore

final class LibraryTests: XCTestCase {

    func testRoundTripCurrentSchema() throws {
        let file = LibraryFile.starter()
        let decoded = try LibraryCodec.decode(try LibraryCodec.encode(file))
        XCTAssertEqual(decoded, file)
        XCTAssertEqual(decoded.schemaVersion, LibraryFile.currentSchema)
    }

    func testMigrationFromV1() throws {
        let v1 = """
        {
          "version": 1,
          "timers": [
            { "id": "6F1E5C3A-1111-4C3B-9C1E-000000000001", "name": "Eggs", "duration": 420, "theme": "ocean" },
            { "id": "6F1E5C3A-1111-4C3B-9C1E-000000000002", "name": "Nap", "duration": 1200 }
          ],
          "sequences": [
            { "id": "6F1E5C3A-1111-4C3B-9C1E-000000000003", "name": "Loop", "repeats": 0,
              "phases": [ { "name": "A", "duration": 30 }, { "name": "B", "duration": 2 } ] }
          ]
        }
        """
        let file = try LibraryCodec.decode(Data(v1.utf8))
        XCTAssertEqual(file.schemaVersion, 2)
        XCTAssertEqual(file.timers.count, 3)
        XCTAssertEqual(file.timers[0].themeID, .ocean)
        XCTAssertEqual(file.timers[1].themeID, .goldenSand)
        XCTAssertEqual(file.timers[0].plan.cycle.first?.duration, 420)
        XCTAssertEqual(file.timers[2].plan.repeats, .infinite)
        XCTAssertEqual(file.timers[2].plan.cycle[1].duration, 5, "migrated durations are clamped to the 5 s minimum")
    }

    func testFutureSchemaIsRejected() {
        XCTAssertThrowsError(try LibraryCodec.decode(Data(#"{"schemaVersion": 99, "timers": []}"#.utf8))) {
            XCTAssertEqual($0 as? LibraryCodecError, .unsupportedSchema(99))
        }
    }

    func testDuplicateGetsFreshIdentity() {
        let t = SavedTimer(name: "Run", plan: .intervals(), isFavorite: true)
        let d = t.duplicated()
        XCTAssertNotEqual(d.id, t.id)
        XCTAssertNotEqual(d.plan.cycle[0].id, t.plan.cycle[0].id)
        XCTAssertFalse(d.isFavorite)
        XCTAssertEqual(d.plan.cycle.map(\.duration), t.plan.cycle.map(\.duration))
    }

    func testThemes() {
        XCTAssertEqual(SandTheme.all.count, 7)
        XCTAssertEqual(SandTheme.all.filter(\.isPremium).map(\.id), [.roseQuartz, .jade])
        for t in SandTheme.all { XCTAssertTrue((3...5).contains(t.palette.count)); XCTAssertEqual(t.fiveSlots.count, 5) }
        XCTAssertFalse(SandTheme.theme(.jade).isUnlocked(isSupporter: false))
        XCTAssertTrue(SandTheme.theme(.jade).isUnlocked(isSupporter: true))
    }
}
