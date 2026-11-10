import Foundation

/// A named timer in the library. Single timers and multi-phase sequences share this type — the difference is
/// only in `plan`.
public struct SavedTimer: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var emoji: String
    public var plan: TimerPlan
    public var themeID: SandTheme.ID
    public var isFavorite: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, emoji: String = "⏳", plan: TimerPlan,
                themeID: SandTheme.ID = .goldenSand, isFavorite: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.plan = plan
        self.themeID = themeID
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }

    /// Copy with a new identity ("Duplicate" action).
    public func duplicated(nameSuffix: String = " 2") -> SavedTimer {
        var copy = self
        copy.id = UUID()
        copy.name += nameSuffix
        copy.isFavorite = false
        copy.createdAt = Date()
        // Phases get new ids too so list diffing in the editor stays stable.
        copy.plan.cycle = copy.plan.cycle.map { var p = $0; p.id = UUID(); return p }
        copy.plan.finale = copy.plan.finale.map { var p = $0; p.id = UUID(); return p }
        return copy
    }
}

/// On-disk document: `Application Support/Library.json` inside the App Group container.
public struct LibraryFile: Codable, Equatable, Sendable {
    public static let currentSchema = 2
    public var schemaVersion: Int
    public var timers: [SavedTimer]

    public init(timers: [SavedTimer]) {
        self.schemaVersion = Self.currentSchema
        self.timers = timers
    }

    /// First-launch content.
    public static func starter(names: StarterNames = .init()) -> LibraryFile {
        LibraryFile(timers: [
            SavedTimer(name: names.tea, emoji: "🍵", plan: .single(3 * 60), themeID: .desert, isFavorite: true),
            SavedTimer(name: names.pomodoro, emoji: "🍅",
                       plan: .pomodoro(focus: names.focus, shortBreak: names.shortBreak, longBreak: names.longBreak),
                       themeID: .ember),
            SavedTimer(name: names.intervals, emoji: "🏃", plan: .intervals(work: names.work, rest: names.rest), themeID: .ocean),
            SavedTimer(name: names.meditation, emoji: "🧘", plan: .single(10 * 60), themeID: .lavender),
        ])
    }

    /// Localised names for the starter content (provided by the app layer).
    public struct StarterNames: Sendable {
        public var tea = "Tea", pomodoro = "Pomodoro", intervals = "Intervals", meditation = "Meditation"
        public var focus = "Focus", shortBreak = "Short break", longBreak = "Long break", work = "Work", rest = "Rest"
        public init() {}
    }
}

public enum LibraryCodecError: Error, Equatable {
    case unsupportedSchema(Int)
}

/// JSON encoding with versioned migrations.
///
/// v1 (legacy prototype): `{ "version": 1, "timers": [{id,name,duration,theme}], "sequences": [{id,name,phases:[{name,duration}],repeats}] }`
/// v2 (current): `LibraryFile` — unified `SavedTimer` with `TimerPlan`, emoji and favourites.
public enum LibraryCodec {

    public static func encode(_ file: LibraryFile) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .deferredToDate   // exact round-trip (ISO-8601 drops fractions)
        return try enc.encode(file)
    }

    public static func decode(_ data: Data) throws -> LibraryFile {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .deferredToDate
        let probe = try dec.decode(VersionProbe.self, from: data)
        let version = probe.schemaVersion ?? probe.version ?? 1
        switch version {
        case 1:
            return migrateV1(try dec.decode(V1.File.self, from: data))
        case 2:
            return try dec.decode(LibraryFile.self, from: data)
        default:
            throw LibraryCodecError.unsupportedSchema(version)
        }
    }

    // MARK: v1 → v2

    private struct VersionProbe: Decodable { var schemaVersion: Int?; var version: Int? }

    enum V1 {
        struct File: Decodable { var timers: [Timer]; var sequences: [Sequence]? }
        struct Timer: Decodable { var id: UUID; var name: String; var duration: TimeInterval; var theme: String? }
        struct Sequence: Decodable { var id: UUID; var name: String; var phases: [P]; var repeats: Int }
        struct P: Decodable { var name: String; var duration: TimeInterval }
    }

    static func migrateV1(_ v1: V1.File) -> LibraryFile {
        var out: [SavedTimer] = v1.timers.map {
            SavedTimer(id: $0.id, name: $0.name, emoji: "⏳", plan: .single($0.duration),
                       themeID: $0.theme.flatMap(SandTheme.ID.init(rawValue:)) ?? .goldenSand)
        }
        for s in v1.sequences ?? [] where !s.phases.isEmpty {
            let plan = TimerPlan(cycle: s.phases.map { Phase(name: $0.name, duration: $0.duration) },
                                 repeats: s.repeats <= 0 ? .infinite : .times(s.repeats))
            out.append(SavedTimer(id: s.id, name: s.name, emoji: "🔁", plan: plan))
        }
        return LibraryFile(timers: out)
    }
}
