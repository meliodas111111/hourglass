import SwiftUI
import HourglassCore

/// Main screen: the hourglass, the digital read-out and the controls. No ads here, ever.
struct HourglassScreen: View {
    @EnvironmentObject private var vm: HourglassViewModel
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                VStack(spacing: 0) {
                    if !vm.isZen {
                        topBar.readableWhenFlipped(vm.isUpsideDown).transition(.move(edge: .top).combined(with: .opacity))
                        readout.readableWhenFlipped(vm.isUpsideDown).padding(.top, 8).transition(.opacity)
                    }
                    Spacer(minLength: 8)
                    // The hourglass is NEVER rotated with the UI: gravity is measured in screen coordinates, so the
                    // glass must stay fixed to the screen (the user's hand turns it). Rotating it too would make the
                    // sand fall "upwards" after a physical flip.
                    HourglassStage(maxHeight: geo.size.height * (vm.isZen ? 0.86 : 0.62))
                    Spacer(minLength: 8)
                    if !vm.isZen {
                        controls.readableWhenFlipped(vm.isUpsideDown).padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if vm.isZen { vm.toggleZen() } }
        }
        .onAppear {
            vm.reduceMotion = reduceMotion
            if scenePhase == .active { vm.sceneBecameActive() }   // the initial .active is not always delivered
        }
        .onChange(of: reduceMotion) { vm.reduceMotion = $0 }
        .statusBarHidden(vm.isZen)
        .modifier(HideSystemOverlays(hidden: vm.isZen))
    }

    private var background: some View {
        RadialGradient(colors: [vm.theme.accent.opacity(0.22), Color.black],
                       center: .center, startRadius: 20, endRadius: 600)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1), value: vm.theme.id)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 4) {
            iconButton("list.bullet", label: "Library", id: "libraryButton") { vm.activeSheet = .library }
            iconButton("paintpalette", label: "Themes", id: "themesButton") { vm.activeSheet = .themes }
            Spacer()
            iconButton("eye.slash", label: "Zen mode", id: "zenButton") { vm.toggleZen() }
            iconButton("gearshape", label: "Settings", id: "settingsButton") { vm.activeSheet = .settings }
        }
        .padding(.horizontal, 12)
    }

    private func iconButton(_ symbol: String, label: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.white.opacity(0.85))
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(id)
    }

    // MARK: Read-out

    private var readout: some View {
        VStack(spacing: 4) {
            if !vm.engine.snapshot.title.isEmpty {
                Text(verbatim: "\(vm.emoji) \(vm.engine.snapshot.title)")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            if let phase = vm.phaseTitle {
                Text(verbatim: phase)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(vm.theme.accent)
                    .accessibilityIdentifier("phaseLabel")
            }
            TimelineView(.periodic(from: .now, by: 0.2)) { context in
                let remaining = vm.remaining(at: context.date)
                Button {
                    if vm.engine.state == .idle || vm.engine.state == .finished { vm.activeSheet = .duration }
                } label: {
                    Text(verbatim: DurationFormatter.string(remaining))
                        .font(.system(size: 64, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .modifier(NumericTextTransition())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("timeLabel")
                .accessibilityLabel(Text("Time remaining"))
                .accessibilityValue(Text(SpokenDuration.string(remaining)))
                .accessibilityHint(vm.engine.state == .idle ? Text("Double-tap to change the duration") : Text(""))
            }
            stateHint
        }
    }

    @ViewBuilder private var stateHint: some View {
        switch vm.engine.state {
        case .idle:
            Group {
                if AppEnvironment.shared.motion.isAvailable && settings.flipGestureEnabled && UIDevice.current.userInterfaceIdiom == .phone {
                    Text("Flip your phone or tap Start")
                } else {
                    Text("Tap Start to begin")
                }
            }
            .font(.footnote).foregroundStyle(.secondary)
        case .paused:
            Text("Paused").font(.footnote.weight(.semibold)).foregroundStyle(.orange)
        case .finished:
            Text("Time's up!").font(.footnote.weight(.semibold)).foregroundStyle(vm.theme.accent)
                .accessibilityIdentifier("finishedLabel")
        case .running:
            Text(" ").font(.footnote)
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 20) {
            if vm.engine.state == .running || vm.engine.state == .paused {
                roundButton(vm.engine.state == .paused ? "play.fill" : "pause.fill",
                            label: vm.engine.state == .paused ? "Resume" : "Pause", id: "pauseButton") { vm.pauseResume() }
            }
            Button {
                vm.flipButtonTapped()
            } label: {
                Label(primaryTitle, systemImage: "hourglass")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(vm.theme.accent.opacity(0.9)))
                    .foregroundStyle(.black)
            }
            .accessibilityIdentifier("primaryButton")
            if vm.engine.state == .running || vm.engine.state == .paused {
                roundButton("stop.fill", label: "Stop", id: "stopButton") { vm.stop() }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.engine.state)
    }

    private var primaryTitle: LocalizedStringKey {
        switch vm.engine.state {
        case .idle: return "Start"
        case .finished: return "Restart"
        case .running, .paused: return "Flip"
        }
    }

    private func roundButton(_ symbol: String, label: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 56, height: 56)
                .background(Circle().fill(.white.opacity(0.12)))
                .foregroundStyle(.white)
        }
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(id)
    }
}

/// The hourglass itself: Metal sand, or a vector glyph when Reduce Motion is on.
struct HourglassStage: View {
    @EnvironmentObject private var vm: HourglassViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var maxHeight: CGFloat

    var body: some View {
        let geo = vm.driver.geometry
        let aspect = CGFloat(geo.width) / CGFloat(geo.height)
        Group {
            if reduceMotion {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HourglassGlyph(progress: vm.progress(at: context.date), theme: vm.theme, showsStream: false)
                        .animation(.linear(duration: 1), value: vm.progress(at: context.date))
                }
                .rotationEffect(.degrees(vm.glyphFlipAngle))
            } else {
                SandMetalView(driver: vm.driver, source: vm, theme: vm.theme,
                              isActive: scenePhase == .active) { renderer in
                    vm.attach(renderer: renderer)
                }
                .aspectRatio(aspect, contentMode: .fit)
            }
        }
        .frame(maxHeight: maxHeight)
        .opacity(vm.isSandDimmed ? 0.08 : 1)
        .accessibilityElement()
        .accessibilityLabel(Text("Hourglass"))
        .accessibilityValue(Text(SpokenDuration.string(vm.remaining(at: Date()))))
        .accessibilityIdentifier("hourglass")
    }
}

/// Spoken duration ("4 minutes, 30 seconds").
enum SpokenDuration {
    static func string(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .full
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        return f.string(from: max(0, seconds.rounded(.up))) ?? ""
    }
}

extension View {
    /// Turns a piece of UI 180° *in place* after a physical flip so it stays readable. Each element rotates around its
    /// own centre (a quick cross-fade instead of a swing), so text never sweeps across the hourglass.
    func readableWhenFlipped(_ flipped: Bool) -> some View {
        rotationEffect(.degrees(flipped ? 180 : 0))
            .animation(.easeInOut(duration: 0.25), value: flipped)
    }
}

/// `.contentTransition(.numericText())` on iOS 16+, no-op on iOS 15.
struct NumericTextTransition: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) { content.contentTransition(.numericText()) } else { content }
    }
}

/// Hides the home indicator in Zen mode (iOS 16+).
struct HideSystemOverlays: ViewModifier {
    var hidden: Bool
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) { content.persistentSystemOverlays(hidden ? .hidden : .automatic) } else { content }
    }
}
