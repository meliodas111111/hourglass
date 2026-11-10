import Foundation
import Combine
import HourglassCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Library persistence: Codable JSON in `Application Support` (App Group container), schema-versioned
/// (`LibraryCodec` migrates older files). Writes are debounced and atomic.
@MainActor
final class PersistenceService: ObservableObject {

    @Published private(set) var timers: [SavedTimer] = []

    private var saveWork: DispatchWorkItem?

    init() {
        if let file = LibraryStore.load() {
            timers = file.timers
        } else {
            timers = LibraryFile.starter(names: Self.localizedStarterNames).timers
            saveNow()
        }
    }

    static var localizedStarterNames: LibraryFile.StarterNames {
        var n = LibraryFile.StarterNames()
        n.tea = String(localized: "Tea")
        n.pomodoro = String(localized: "Pomodoro")
        n.intervals = String(localized: "Intervals")
        n.meditation = String(localized: "Meditation")
        n.focus = String(localized: "Focus")
        n.shortBreak = String(localized: "Short break")
        n.longBreak = String(localized: "Long break")
        n.work = String(localized: "Work")
        n.rest = String(localized: "Rest")
        return n
    }

    var favorites: [SavedTimer] { timers.filter(\.isFavorite) }

    func timer(id: UUID) -> SavedTimer? { timers.first { $0.id == id } }

    // MARK: CRUD

    func upsert(_ timer: SavedTimer) {
        if let i = timers.firstIndex(where: { $0.id == timer.id }) { timers[i] = timer } else { timers.append(timer) }
        scheduleSave()
    }

    func delete(at offsets: IndexSet) {
        timers.remove(atOffsets: offsets)
        scheduleSave()
    }

    func delete(id: UUID) {
        timers.removeAll { $0.id == id }
        scheduleSave()
    }

    func move(from source: IndexSet, to destination: Int) {
        timers.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    @discardableResult
    func duplicate(id: UUID) -> SavedTimer? {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return nil }
        let copy = timers[i].duplicated(nameSuffix: " " + String(localized: "copy"))
        timers.insert(copy, at: i + 1)
        scheduleSave()
        return copy
    }

    func toggleFavorite(id: UUID) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[i].isFavorite.toggle()
        scheduleSave()
    }

    func resetToStarter() {
        timers = LibraryFile.starter(names: Self.localizedStarterNames).timers
        saveNow()
    }

    // MARK: Saving

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in Task { @MainActor in self?.saveNow() } }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        do {
            try LibraryStore.save(LibraryFile(timers: timers))
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch {
            AnalyticsService.shared.record(error: error, context: "library.save")
        }
    }
}
