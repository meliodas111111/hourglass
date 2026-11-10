import Foundation
import Combine
import SwiftUI
import HourglassCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Main screen view model: owns the `TimerEngine`, keeps the sand simulation in sync with it and reacts to
/// flips, phase ends and app lifecycle.
@MainActor
final class HourglassViewModel: ObservableObject, SandFrameSource {

    enum Sheet: String, Identifiable {
        case library, settings, themes, paywall, duration
        var id: String { rawValue }
    }

    // MARK: Published UI state

    @Published private(set) var engine: TimerEngine
    @Published var isZen: Bool
    /// Text/controls rotate 180° after a physical flip so they stay readable (iPhone is portrait-locked).
    @Published private(set) var isUpsideDown = false
    /// Rotation used by the Reduce Motion hourglass (Metal path animates inside the shader).
    @Published private(set) var glyphFlipAngle: Double = 0
    /// Brief dim of the hourglass while the sand piles are regenerated (Stop / reset) — hides the jump.
    @Published private(set) var isSandDimmed = false
    @Published var activeSheet: Sheet?
    @Published var showPermissionPrimer = false
    @Published private(set) var emoji = "⏳"

    // MARK: Dependencies

    let driver: SimulationDriver
    private let settings: SettingsStore
    private let motion: MotionService
    private let alarms: AlarmService
    private let feedback: FeedbackService
    private let store: StoreService
    private let persistence: PersistenceService
    private let liveActivity: LiveActivityService
    private weak var renderer: SandRenderer?

    private var bag = Set<AnyCancellable>()
    private var ticker: AnyCancellable?
    private var isFlipping = false
    private(set) var isSceneActive = false
    private var backgroundedAt: Date?
    private var pendingStartAfterPrimer = false
    var reduceMotion = false

    init(settings: SettingsStore, motion: MotionService, alarms: AlarmService, feedback: FeedbackService,
         store: StoreService, persistence: PersistenceService, liveActivity: LiveActivityService, driver: SimulationDriver) {
        self.settings = settings
        self.motion = motion
        self.alarms = alarms
        self.feedback = feedback
        self.store = store
        self.persistence = persistence
        self.liveActivity = liveActivity
        self.driver = driver
        self.isZen = settings.zenByDefault
        if let snap = ActiveTimerStore.load() {
            engine = TimerEngine(snapshot: snap)
        } else {
            engine = TimerEngine(plan: .single(settings.lastDuration), themeID: settings.themeID)
        }
        regenerateSand()
        bind()
    }

    private func bind() {
        motion.flips
            .sink { [weak self] o in self?.handlePhysicalFlip(to: o) }
            .store(in: &bag)
        motion.shakes
            .sink { [weak self] s in self?.driver.perform { $0.applyShake(strength: s) } }
            .store(in: &bag)
        settings.$flipGestureEnabled
            .sink { [weak self] on in self?.motion.flipGestureEnabled = on }
            .store(in: &bag)
        settings.$density
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] d in
                guard let self else { return }
                let now = Date()
                let n = max(self.driver.grainCount, 1)
                let fraction = Double(self.engine.expectedSourceGrains(total: n, at: now)) / Double(n)
                self.driver.rebuild(density: d, sourceFraction: fraction, source: self.engine.snapshot.sourceChamber)
            }
            .store(in: &bag)
        settings.$keepScreenOn
            .sink { [weak self] _ in self?.updateIdleTimer() }
            .store(in: &bag)
        store.$isSupporter
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
    }

    func attach(renderer: SandRenderer) { self.renderer = renderer }

    // MARK: Derived

    /// Active theme; premium themes fall back to the default when the purchase is missing.
    var theme: SandTheme {
        let t = SandTheme.theme(engine.activeThemeID)
        return t.isUnlocked(isSupporter: store.isSupporter) ? t : .default
    }

    func remaining(at now: Date) -> TimeInterval { engine.remaining(at: now) }
    func progress(at now: Date) -> Double { engine.progress(at: now) }

    var phaseTitle: String? {
        guard engine.plan.isSequence, let phase = engine.currentPhase else { return nil }
        let name = phase.name.isEmpty ? String(localized: "Phase") : phase.name
        if let count = engine.plan.phaseCount { return "\(name) · \(engine.phaseIndex + 1)/\(count)" }
        return "\(name) · \(engine.phaseIndex + 1)"
    }

    // MARK: SandFrameSource (called every display frame by the renderer)

    func frameInputs(now: Date) -> (sync: TimeSync, gravity: Vec2) {
        processTime(now)
        let sync = isFlipping ? TimeSync.stopped : engine.timeSync(total: driver.grainCount, at: now)
        return (sync, motion.gravity)
    }

    // MARK: Lifecycle

    func sceneBecameActive() {
        // Called from scenePhase AND from the screen's onAppear: SwiftUI does not always report the initial
        // `.active`, and without this the sensors never started (sand ignored tilting/flipping).
        motion.start()
        guard !isSceneActive else { return }
        isSceneActive = true
        motion.flipGestureEnabled = settings.flipGestureEnabled
        let wasAwayLong = backgroundedAt.map { Date().timeIntervalSince($0) > 2 } ?? true
        var changedExternally = false
        if let external = ActiveTimerStore.load(), external != engine.snapshot {
            engine = TimerEngine(snapshot: external)    // changed by a widget / Live Activity intent
            changedExternally = true
        }
        // Events that happened while away are silent (the alarm already rang); only state is updated.
        let missed = engine.advance(to: Date())
        if wasAwayLong || changedExternally || !missed.isEmpty { regenerateSand() }
        persist()
        ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
            .sink { [weak self] now in
                self?.processTime(now)
                self?.checkPerformance()
            }
        Task { await alarms.refreshStatus() }
    }

    func sceneEnteredBackground() {
        isSceneActive = false
        backgroundedAt = Date()
        ticker = nil
        motion.stop()
        feedback.stopAlert()
        ActiveTimerStore.save(engine.snapshot)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Adaptive quality

    private var slowTicks = 0

    /// Steps the sand density down when the simulation can't keep up (older phones) or the phone overheats.
    /// Sampled 4x/s; acts after ~3 s of sustained trouble so a single hitch never changes quality.
    private func checkPerformance() {
        guard settings.autoQuality, isSceneActive else { slowTicks = 0; return }
        let hot = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        let slow = driver.averageStepMilliseconds > 9     // CPU ms per step on the sim thread
        slowTicks = (hot || slow) ? slowTicks + 1 : 0
        guard slowTicks >= 12 else { return }
        slowTicks = 0
        switch settings.density {
        case .quality: settings.density = .balanced
        case .balanced: settings.density = .performance
        case .performance: break
        }
    }

    /// Recreates settled piles from the timer state (no per-cell persistence).
    private func regenerateSand() {
        let snapshot = engine
        let now = Date()
        let gravity = motion.gravity
        driver.perform { sim in
            sim.sourceChamber = snapshot.snapshot.sourceChamber
            sim.resetSettled(sourceGrains: snapshot.expectedSourceGrains(total: sim.grainCount, at: now), gravity: gravity)
        }
    }

    // MARK: Time

    private func processTime(_ now: Date) {
        let events = engine.advance(to: now)
        guard !events.isEmpty else { return }
        for e in events { handle(event: e) }
        persist()
    }

    private func handle(event: TimerEvent) {
        let ringsInApp = isSceneActive && alarms.backend == .notifications
        switch event {
        case .phaseCompleted:
            if ringsInApp {
                feedback.playAlert(sound: settings.alertSound, volume: settings.volume, vibrate: settings.vibrationEnabled, isFinal: false)
            }
            // The previous phase must end with an empty top, then the hourglass turns itself over.
            driver.perform { $0.flushSource() }
            runFlipAnimation()
        case .finished:
            if ringsInApp {
                feedback.playAlert(sound: settings.alertSound, volume: settings.volume, vibrate: settings.vibrationEnabled, isFinal: true)
            }
            renderer?.pulseFinish()
            AnalyticsService.shared.log(.timerFinished(isSequence: engine.plan.isSequence))
        }
    }

    // MARK: User actions

    /// Main button: start (idle / finished), or an on-screen flip while running / paused.
    func flipButtonTapped() {
        guard !isFlipping else { return }
        if (engine.state == .idle || engine.state == .finished) && alarms.needsPermissionPrompt && !AppEnvironment.shared.isUITesting {
            pendingStartAfterPrimer = true
            showPermissionPrimer = true
            return
        }
        let wasIdle = engine.state == .idle || engine.state == .finished
        if wasIdle { driver.perform { $0.flushSource() } }     // make sure all sand is at the bottom first
        let outcome = engine.flip(at: Date(), physical: false)
        feedback.flipHaptic(enabled: settings.vibrationEnabled)
        runFlipAnimation()
        logStart(outcome, viaFlip: false)
        persist()
    }

    /// Permission explainer finished (either choice).
    func permissionPrimerFinished(granted: Bool) async {
        if granted { await alarms.requestAuthorization() }
        showPermissionPrimer = false
        if pendingStartAfterPrimer {
            pendingStartAfterPrimer = false
            // Even if the user declined, start the timer — the in-app alert still works.
            alarms.markPrimerShown()
            flipButtonTapped()
        }
    }

    func pauseResume() {
        let now = Date()
        switch engine.state {
        case .running: engine.pause(at: now)
        case .paused: engine.resume(at: now)
        default: return
        }
        feedback.lightHaptic(enabled: settings.vibrationEnabled)
        persist()
    }

    func stop() {
        engine.stop()
        feedback.stopAlert()
        // Idle shows a "run-out" hourglass (all sand below). Moving thousands of grains in one frame looked like a
        // teleport, so dim the glass, regenerate the settled piles at the darkest point, then fade back in.
        withAnimation(.easeIn(duration: 0.2)) { isSandDimmed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if self.engine.state == .idle { self.regenerateSand() }
            withAnimation(.easeOut(duration: 0.25)) { self.isSandDimmed = false }
        }
        persist()
    }

    func setDuration(_ seconds: TimeInterval) {
        let d = DurationLimits.clamp(seconds)
        settings.lastDuration = d
        if engine.state == .running || engine.state == .paused { stop() }
        engine.configure(plan: .single(d), title: "", themeID: settings.themeID)
        emoji = "⏳"
        persist()
    }

    func setTheme(_ id: SandTheme.ID) {
        guard SandTheme.theme(id).isUnlocked(isSupporter: store.isSupporter) else {
            activeSheet = .paywall
            AnalyticsService.shared.log(.paywallShown)
            return
        }
        settings.themeID = id
        var snap = engine.snapshot
        snap.themeID = id
        engine = TimerEngine(snapshot: snap)
        AnalyticsService.shared.log(.themeSelected(id.rawValue))
        persist()
    }

    /// Library → start a saved timer / sequence.
    func load(_ saved: SavedTimer, autostart: Bool) {
        if engine.state == .running || engine.state == .paused { stop() }
        engine.configure(plan: saved.plan, title: saved.name, themeID: saved.themeID)
        emoji = saved.emoji
        persist()
        if autostart { flipButtonTapped() }
    }

    func toggleZen() {
        withAnimation(.easeInOut(duration: 0.35)) { isZen.toggle() }
        AnalyticsService.shared.log(.zenToggled(isZen))
    }

    /// Commands from Live Activity buttons / widgets / deep links.
    func handle(_ command: TimerCommand) async {
        switch command {
        case .togglePause: pauseResume()
        case .stop: stop()
        case .startSaved(let id):
            if let saved = persistence.timer(id: id) { load(saved, autostart: true) }
        }
    }

    // MARK: Flip

    private func handlePhysicalFlip(to orientation: FlipDetector.Orientation) {
        guard settings.flipGestureEnabled, !isFlipping else { return }
        isUpsideDown = orientation == .inverted        // animated per element by readableWhenFlipped
        let wasIdle = engine.state == .idle || engine.state == .finished
        let outcome = engine.flip(at: Date(), physical: true)
        let chamber = engine.snapshot.sourceChamber
        driver.perform { sim in
            if wasIdle {
                // Starting from rest: everything must be in the chamber that is now on top.
                sim.flushSource()
            }
            sim.sourceChamber = chamber
            sim.noteFlip()     // pile needs ~1–2 s to reach the neck: don't teleport meanwhile
        }
        feedback.flipHaptic(enabled: settings.vibrationEnabled)
        logStart(outcome, viaFlip: true)
        persist()
    }

    private func runFlipAnimation() {
        isFlipping = true
        if reduceMotion || renderer == nil {
            driver.rotate180 { _ in }
            withAnimation(.easeInOut(duration: 0.5)) { glyphFlipAngle = 180 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.glyphFlipAngle = 0
                self.isFlipping = false
            }
        } else {
            renderer?.animateFlip { [weak self] in self?.isFlipping = false }
        }
    }

    private func logStart(_ outcome: FlipOutcome, viaFlip: Bool) {
        switch outcome {
        case .started, .restarted:
            AnalyticsService.shared.log(.timerStarted(durationBucket: AnalyticsService.bucket(engine.plan.totalDuration ?? engine.totalDuration),
                                                      isSequence: engine.plan.isSequence, viaFlip: viaFlip))
        case .reversed: break
        }
    }

    // MARK: Persistence & side effects

    private func persist() {
        ActiveTimerStore.save(engine.snapshot)
        let engine = self.engine
        let sound = settings.alertSound
        Task { await alarms.schedule(engine: engine, sound: sound) }
        liveActivity.sync(engine: engine, emoji: emoji)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "HourglassStatusWidget")
        #endif
        updateIdleTimer()
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = isSceneActive && settings.keepScreenOn && engine.state == .running
    }
}
