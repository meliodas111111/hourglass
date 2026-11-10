import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents
import HourglassCore

/// Lock Screen Live Activity + Dynamic Island: remaining time, phase name, sand progress bar, pause / stop
/// buttons (iOS 17+ via `LiveActivityIntent`).
@available(iOSApplicationExtension 16.1, *)
struct HourglassLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HourglassActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let theme = SandTheme.theme(SandTheme.ID(rawValue: context.state.themeID) ?? .goldenSand)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HourglassGlyph(progress: context.state.isPaused ? context.state.pausedProgress : 0.5, theme: theme, showsStream: false)
                        .frame(height: 44)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(verbatim: "\(context.attributes.emoji) \(context.attributes.title)").font(.headline).lineLimit(1)
                        if !context.state.phaseName.isEmpty {
                            Text(verbatim: phaseLine(context.state)).font(.caption).foregroundStyle(theme.accent).lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RemainingText(state: context.state).font(.title3.weight(.semibold)).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        SandProgressBar(state: context.state, theme: theme)
                        ActivityButtons(isPaused: context.state.isPaused)
                    }
                }
            } compactLeading: {
                Image(systemName: "hourglass").foregroundStyle(theme.accent)
            } compactTrailing: {
                RemainingText(state: context.state).monospacedDigit().frame(maxWidth: 56)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "hourglass").foregroundStyle(theme.accent)
            }
            .keylineTint(theme.accent)
        }
    }

    private func phaseLine(_ s: HourglassActivityAttributes.ContentState) -> String {
        s.phaseLabel.isEmpty ? s.phaseName : "\(s.phaseName) · \(s.phaseLabel)"
    }
}

@available(iOSApplicationExtension 16.1, *)
private struct LockScreenActivityView: View {
    let context: ActivityViewContext<HourglassActivityAttributes>

    var body: some View {
        let theme = SandTheme.theme(SandTheme.ID(rawValue: context.state.themeID) ?? .goldenSand)
        HStack(spacing: 14) {
            HourglassGlyph(progress: context.state.isPaused ? context.state.pausedProgress : 0.5, theme: theme, showsStream: !context.state.isPaused)
                .frame(height: 64)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(verbatim: "\(context.attributes.emoji) \(context.attributes.title)").font(.headline).lineLimit(1)
                    Spacer()
                    RemainingText(state: context.state).font(.title2.weight(.semibold)).monospacedDigit()
                }
                if !context.state.phaseName.isEmpty {
                    Text(verbatim: context.state.phaseLabel.isEmpty ? context.state.phaseName : "\(context.state.phaseName) · \(context.state.phaseLabel)")
                        .font(.subheadline).foregroundStyle(theme.accent)
                }
                SandProgressBar(state: context.state, theme: theme)
                ActivityButtons(isPaused: context.state.isPaused)
            }
        }
        .padding()
        .foregroundStyle(.white)
    }
}

@available(iOSApplicationExtension 16.1, *)
private struct RemainingText: View {
    let state: HourglassActivityAttributes.ContentState
    var body: some View {
        if let end = state.endDate, !state.isPaused, end > Date() {
            Text(timerInterval: Date()...end, countsDown: true)
        } else {
            Text(verbatim: DurationFormatter.string(state.pausedRemaining))
        }
    }
}

/// Progress bar styled as a band of sand.
@available(iOSApplicationExtension 16.1, *)
private struct SandProgressBar: View {
    let state: HourglassActivityAttributes.ContentState
    let theme: SandTheme
    var body: some View {
        Group {
            if let start = state.startDate, let end = state.endDate, !state.isPaused, end > start {
                ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            } else {
                ProgressView(value: min(max(state.pausedProgress, 0), 1))
            }
        }
        .progressViewStyle(.linear)
        .tint(theme.accent)
    }
}

@available(iOSApplicationExtension 16.1, *)
private struct ActivityButtons: View {
    let isPaused: Bool
    var body: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            HStack(spacing: 12) {
                Button(intent: ToggleTimerPauseIntent()) {
                    Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                Button(intent: StopTimerIntent()) {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .tint(.red)
            }
            .buttonStyle(.bordered)
            .font(.subheadline.weight(.semibold))
        }
    }
}
