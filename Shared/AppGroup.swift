import Foundation
import HourglassCore

/// Shared container between the app and the widget extension.
///
/// ▶ MANUAL: the identifier must match the App Group capability of BOTH targets (see project.yml / README).
enum AppGroup {
    static let identifier = "group.com.meliodas.hourglass"

    static var defaults: UserDefaults { UserDefaults(suiteName: identifier) ?? .standard }

    /// `<group container>/Library/Application Support` (falls back to the app sandbox, e.g. in previews).
    static var applicationSupportURL: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)?
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}

/// Persists the *active* timer snapshot. Lives in the App Group so widget intents can start/pause timers
/// and the app picks the state up on next launch.
enum ActiveTimerStore {
    private static let key = "activeTimer.snapshot.v1"

    static func load() -> TimerSnapshot? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TimerSnapshot.self, from: data)
    }

    static func save(_ snapshot: TimerSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        AppGroup.defaults.set(data, forKey: key)
    }

    static func clear() { AppGroup.defaults.removeObject(forKey: key) }
}

/// Library JSON file (`Library.json`) — shared so the Quick Start widget can list favourites.
enum LibraryStore {
    static var fileURL: URL { AppGroup.applicationSupportURL.appendingPathComponent("Library.json") }

    static func load() -> LibraryFile? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do { return try LibraryCodec.decode(data) } catch {
            // Keep the unreadable file for diagnostics instead of silently overwriting user data.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return nil
        }
    }

    static func save(_ file: LibraryFile) throws {
        let data = try LibraryCodec.encode(file)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// Keys of settings that both processes read.
enum SharedKeys {
    static let alertSound = "settings.alertSound"
    static let isSupporter = "store.isSupporter.cached"
}

/// Deep links: `hourglass://start?id=<uuid>`, `hourglass://open`.
enum DeepLink {
    static func start(timerID: UUID) -> URL { URL(string: "hourglass://start?id=\(timerID.uuidString)")! }
    static let open = URL(string: "hourglass://open")!
}
