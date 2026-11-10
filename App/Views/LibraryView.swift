import SwiftUI
import HourglassCore

/// Saved timers & sequences: start, edit, duplicate, favourite, swipe-delete, drag-to-reorder.
struct LibraryView: View {
    @EnvironmentObject private var vm: HourglassViewModel
    @EnvironmentObject private var library: PersistenceService
    @Environment(\.dismiss) private var dismiss
    @State private var editing: SavedTimer?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                List {
                    ForEach(library.timers) { timer in
                        row(timer)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                vm.load(timer, autostart: true)
                                dismiss()
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { library.delete(id: timer.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button { library.duplicate(id: timer.id) } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .leading) {
                                Button { library.toggleFavorite(id: timer.id) } label: {
                                    Label("Favorite", systemImage: timer.isFavorite ? "star.slash" : "star")
                                }
                                .tint(.yellow)
                                Button { editing = timer } label: { Label("Edit", systemImage: "pencil") }
                                    .tint(.gray)
                            }
                            .contextMenu {
                                Button { editing = timer } label: { Label("Edit", systemImage: "pencil") }
                                Button { library.duplicate(id: timer.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                Button { library.toggleFavorite(id: timer.id) } label: { Label("Favorite", systemImage: "star") }
                                Button(role: .destructive) { library.delete(id: timer.id) } label: { Label("Delete", systemImage: "trash") }
                            }
                            .accessibilityIdentifier("libraryRow-\(timer.name)")
                    }
                    .onMove(perform: library.move)
                    .onDelete { library.delete(at: $0) }
                }
                .listStyle(.insetGrouped)
                BannerAdView()
            }
            .navigationTitle(Text("Library"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { editing = SavedTimer(name: String(localized: "New timer"), plan: .single(5 * 60)) } label: {
                            Label("New timer", systemImage: "hourglass")
                        }
                        Button {
                            editing = SavedTimer(name: String(localized: "New sequence"), emoji: "🔁",
                                                 plan: TimerPlan(cycle: [Phase(name: String(localized: "Work"), duration: 60),
                                                                         Phase(name: String(localized: "Rest"), duration: 30)],
                                                                 repeats: .times(3)))
                        } label: { Label("New sequence", systemImage: "repeat") }
                        Divider()
                        Button {
                            editing = SavedTimer(name: String(localized: "Pomodoro"), emoji: "🍅",
                                                 plan: .pomodoro(focus: String(localized: "Focus"),
                                                                 shortBreak: String(localized: "Short break"),
                                                                 longBreak: String(localized: "Long break")), themeID: .ember)
                        } label: { Label("Pomodoro 25/5 ×4", systemImage: "timer") }
                        Button {
                            editing = SavedTimer(name: String(localized: "Intervals"), emoji: "🏃",
                                                 plan: .intervals(work: String(localized: "Work"), rest: String(localized: "Rest")),
                                                 themeID: .ocean)
                        } label: { Label("Intervals 40/20 ×8", systemImage: "figure.run") }
                    } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("addTimer")
                    .accessibilityLabel(Text("Add"))
                }
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
            }
            .sheet(item: $editing) { timer in
                TimerEditorView(timer: timer) { library.upsert($0) }.withAppEnvironment()
            }
        }
        .navigationViewStyle(.stack)
    }

    private func row(_ t: SavedTimer) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: t.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: t.name).font(.body.weight(.medium))
                    if t.isFavorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                }
                Text(verbatim: Self.summary(t.plan)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HourglassGlyph(progress: 0.3, theme: SandTheme.theme(t.themeID), showsStream: false)
                .frame(height: 36)
        }
        .padding(.vertical, 4)
    }

    /// "25:00 / 05:00 ×4 + 15:00", "∞" for infinite.
    static func summary(_ plan: TimerPlan) -> String {
        let cycle = plan.cycle.map { DurationFormatter.string($0.duration) }.joined(separator: " / ")
        var s = cycle
        switch plan.repeats {
        case .infinite: s += " ×∞"
        case .times(let n) where n > 1: s += " ×\(n)"
        default: break
        }
        if !plan.finale.isEmpty { s += " + " + plan.finale.map { DurationFormatter.string($0.duration) }.joined(separator: " / ") }
        return s
    }
}
