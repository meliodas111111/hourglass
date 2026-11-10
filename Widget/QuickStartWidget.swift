import WidgetKit
import SwiftUI
import AppIntents
import HourglassCore

/// Start a favourite timer in one tap. iOS 17+: interactive `Button(intent:)` (no app launch);
/// iOS 15–16: deep link `hourglass://start?id=…` opens the app.
struct QuickStartWidget: Widget {
    let kind = "HourglassQuickStartWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FavoritesProvider()) { entry in
            QuickStartView(entry: entry)
        }
        .configurationDisplayName(Text("Quick Start"))
        .description(Text("Start your favourite timers."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FavoritesEntry: TimelineEntry {
    let date: Date
    let favorites: [SavedTimer]
}

struct FavoritesProvider: TimelineProvider {
    func placeholder(in context: Context) -> FavoritesEntry {
        FavoritesEntry(date: Date(), favorites: Array(LibraryFile.starter().timers.prefix(3)))
    }

    func getSnapshot(in context: Context, completion: @escaping (FavoritesEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoritesEntry>) -> Void) {
        // The app reloads timelines whenever the library changes.
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> FavoritesEntry {
        let timers = LibraryStore.load()?.timers ?? LibraryFile.starter().timers
        let favs = timers.filter(\.isFavorite)
        return FavoritesEntry(date: Date(), favorites: favs.isEmpty ? Array(timers.prefix(3)) : favs)
    }
}

struct QuickStartView: View {
    let entry: FavoritesEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let items = Array(entry.favorites.prefix(family == .systemSmall ? 1 : 3))
        Group {
            if items.isEmpty {
                Text("Add favourites in the Library.").font(.caption).foregroundStyle(.secondary)
            } else if family == .systemSmall, let t = items.first {
                startControl(t) {
                    VStack(spacing: 6) {
                        HourglassGlyph(progress: 0, theme: .theme(t.themeID), showsStream: false).frame(height: 64)
                        Text(verbatim: "\(t.emoji) \(t.name)").font(.caption.weight(.semibold)).lineLimit(1)
                        Text(verbatim: DurationFormatter.string(t.plan.cycle[0].duration)).font(.caption2).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ForEach(items) { t in
                        startControl(t) {
                            VStack(spacing: 4) {
                                Text(verbatim: t.emoji).font(.title2)
                                Text(verbatim: t.name).font(.caption.weight(.semibold)).lineLimit(1)
                                Text(verbatim: DurationFormatter.string(t.plan.cycle[0].duration)).font(.caption2).monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12).fill(SandTheme.theme(t.themeID).accent.opacity(0.25)))
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .widgetBackground(WidgetStyle.background)
    }

    @ViewBuilder
    private func startControl<L: View>(_ t: SavedTimer, @ViewBuilder label: () -> L) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            Button(intent: StartSavedTimerIntent(timerID: t.id)) { label() }
                .buttonStyle(.plain)
        } else {
            Link(destination: DeepLink.start(timerID: t.id)) { label() }
        }
    }
}
