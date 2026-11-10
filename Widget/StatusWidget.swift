import WidgetKit
import SwiftUI
import HourglassCore

/// Small / medium widget: static hourglass at the current level + live countdown via `Text(timerInterval:)`.
struct HourglassStatusWidget: Widget {
    let kind = "HourglassStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Hourglass"))
        .description(Text("See how much sand is left."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: TimerSnapshot?

    var engine: TimerEngine? { snapshot.map(TimerEngine.init(snapshot:)) }
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry { StatusEntry(date: Date(), snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: Date(), snapshot: ActiveTimerStore.load()))
    }

    /// While running: ~24 entries across the phase so the static sand level steps down; the digits tick by
    /// themselves (`Text(timerInterval:)`). Refresh at the phase end.
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let now = Date()
        guard var snapshot = ActiveTimerStore.load() else {
            completion(Timeline(entries: [StatusEntry(date: now, snapshot: nil)], policy: .never))
            return
        }
        var engine = TimerEngine(snapshot: snapshot)
        engine.advance(to: now)
        snapshot = engine.snapshot

        guard engine.state == .running, let end = engine.endDate else {
            completion(Timeline(entries: [StatusEntry(date: now, snapshot: snapshot)], policy: .never))
            return
        }
        let steps = 24
        let span = end.timeIntervalSince(now)
        var entries = (0..<steps).map { i in
            StatusEntry(date: now.addingTimeInterval(span * Double(i) / Double(steps)), snapshot: snapshot)
        }
        entries.append(StatusEntry(date: end, snapshot: snapshot))
        completion(Timeline(entries: entries, policy: .after(end.addingTimeInterval(1))))
    }
}

struct StatusWidgetView: View {
    let entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let engine = entry.engine
        let theme = SandTheme.theme(engine?.activeThemeID ?? .goldenSand)
        let progress = engine?.progress(at: entry.date) ?? 1

        HStack(spacing: 12) {
            HourglassGlyph(progress: progress, theme: theme)
                .frame(maxHeight: .infinity)
            if family == .systemMedium || engine == nil {
                VStack(alignment: .leading, spacing: 4) { details(engine, theme: theme) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) { countdown(engine, theme: theme) }
            }
        }
        .padding(family == .systemSmall ? 4 : 0)
        .widgetBackground(WidgetStyle.background)
        .widgetURL(DeepLink.open)
    }

    @ViewBuilder
    private func details(_ engine: TimerEngine?, theme: SandTheme) -> some View {
        if let engine {
            if !engine.snapshot.title.isEmpty {
                Text(verbatim: engine.snapshot.title).font(.headline).foregroundStyle(.white).lineLimit(1)
            }
            if let phase = engine.currentPhase, engine.plan.isSequence {
                Text(verbatim: phase.name).font(.subheadline).foregroundStyle(theme.accent).lineLimit(1)
            }
            countdown(engine, theme: theme)
        } else {
            Text("No timer running").font(.headline).foregroundStyle(.white)
            Text("Open the app and flip the hourglass.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func countdown(_ engine: TimerEngine?, theme: SandTheme) -> some View {
        switch engine?.state {
        case .running?:
            if let end = engine?.endDate {
                Group {
                    if #available(iOSApplicationExtension 16.0, *) {
                        Text(timerInterval: entry.date...max(end, entry.date), countsDown: true)
                    } else {
                        Text(end, style: .timer)          // iOS 15: self-updating countdown
                    }
                }
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
            }
        case .paused?:
            Text(verbatim: DurationFormatter.string(engine?.remaining(at: entry.date) ?? 0))
                .font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(.white)
            Text("Paused").font(.caption).foregroundStyle(.orange)
        case .finished?:
            Text("Time's up!").font(.headline).foregroundStyle(theme.accent)
        default:
            Text(verbatim: DurationFormatter.string(engine?.totalDuration ?? 0))
                .font(.system(.title2, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
        }
    }
}
