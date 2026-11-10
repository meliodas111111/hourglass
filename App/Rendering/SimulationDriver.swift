import Foundation
import os.signpost
import HourglassCore

/// Runs `SandSimulation` on its own serial queue and hands finished frames to the renderer.
///
/// * the render loop calls `step(...)` once per display frame; if the previous step is still running the frame's
///   `dt` is accumulated instead of queueing work (no backlog, no thermal runaway);
/// * results are double-buffered: the sim writes into `back`, swaps under a lock, the renderer uploads `front`;
/// * commands (rotate, reset, shake, density change) are serialised on the same queue, so the simulation is
///   only ever touched by one thread.
final class SimulationDriver {

    struct GeometryInfo {
        let width: Int
        let height: Int
        let capRows: Int
        let gateRow: Int
        let centerX: Double
        /// RG8Snorm bytes: R = SDF / 8 cells, G = horizontal position across the glass (−1 … 1).
        let glassField: [Int8]
        let version: Int
    }

    private let queue = DispatchQueue(label: "com.meliodas.hourglass.sand", qos: .userInteractive)
    private let log = OSLog(subsystem: "com.meliodas.hourglass", category: .pointsOfInterest)

    // Queue-confined.
    private var sim: SandSimulation
    private var back: [UInt8]

    // Lock-protected shared state.
    private let lock = NSLock()
    private var front: [UInt8]
    private var frontVersion = 0
    private var frontEpoch = 0
    private var inFlight = false
    private var pendingDt = 0.0
    private var _geometry: GeometryInfo
    private var _grainCount: Int
    private var _sourceCount = 0
    private var _lastStats = FrameStats()
    private var _avgStepMs = 0.0
    private var epoch = 0                   // bumped by rotate180 (renderer resets its flip angle on it)
    private var lastGravity = Vec2(0, 0)
    private var forceStep = true

    init(density: SandDensity) {
        let geo = HourglassGeometry(density: density)
        sim = SandSimulation(geometry: geo, targetGrains: density.targetGrains, seed: UInt64(Date().timeIntervalSince1970))
        back = [UInt8](repeating: 0, count: geo.width * geo.height * 2)
        front = back
        _geometry = Self.makeGeometryInfo(geo, version: 1)
        _grainCount = sim.grainCount
    }

    // MARK: Thread-safe reads

    var geometry: GeometryInfo { lock.lock(); defer { lock.unlock() }; return _geometry }
    /// Cheap per-frame check (the full `geometry` carries the glass field array).
    var geometryVersion: Int { lock.lock(); defer { lock.unlock() }; return _geometry.version }
    var grainCount: Int { lock.lock(); defer { lock.unlock() }; return _grainCount }
    var sourceCount: Int { lock.lock(); defer { lock.unlock() }; return _sourceCount }
    var lastStats: FrameStats { lock.lock(); defer { lock.unlock() }; return _lastStats }
    /// Exponential moving average of the CPU cost of one step (ms) — drives adaptive quality.
    var averageStepMilliseconds: Double { lock.lock(); defer { lock.unlock() }; return _avgStepMs }

    /// Gives the renderer the newest frame if it is newer than `afterVersion`.
    /// `body` runs under the driver lock — it must not call back into the driver.
    func withLatestFrame(newerThan afterVersion: Int,
                         _ body: (UnsafeRawPointer, _ version: Int, _ epoch: Int, _ width: Int) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard frontVersion != afterVersion else { return }
        front.withUnsafeBytes { body($0.baseAddress!, frontVersion, frontEpoch, _geometry.width) }
    }

    // MARK: Frame

    func step(dt: Double, sync: TimeSync, gravity: Vec2) {
        lock.lock()
        if inFlight {
            pendingDt += dt
            lock.unlock()
            return
        }
        // Idle skip: sand at rest, timer not flowing and the phone not moving -> the automaton would do nothing.
        // Any command (shake, flip, reset) sets `forceStep`, so grains it disturbs are never frozen mid-air.
        let gravityChanged = abs(gravity.x - lastGravity.x) + abs(gravity.y - lastGravity.y) > 0.01
        if !forceStep && !gravityChanged && !sync.isRunning && _lastStats.moved == 0 && _lastStats.corrected == 0 {
            lock.unlock()
            return
        }
        forceStep = false
        lastGravity = gravity
        inFlight = true
        let total = dt + pendingDt
        pendingDt = 0
        lock.unlock()

        queue.async { [self] in
            let id = OSSignpostID(log: log)
            os_signpost(.begin, log: log, name: "Sand Step", signpostID: id)
            let t0 = DispatchTime.now().uptimeNanoseconds
            sim.gravity = gravity
            let stats = sim.step(dt: total, sync: sync)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
            os_signpost(.end, log: log, name: "Sand Step", signpostID: id, "moved=%d corrected=%d", stats.moved, stats.corrected)
            publish(stats: stats, stepMs: ms)
        }
    }

    /// Runs `body` on the simulation queue, then publishes a fresh frame.
    func perform(_ body: @escaping (SandSimulation) -> Void) {
        queue.async { [self] in
            body(sim)
            publish(stats: nil, stepMs: nil)
        }
    }

    /// 180° content rotation (end of an on-screen flip animation). `completion` gets the new epoch.
    func rotate180(completion: @escaping (Int) -> Void) {
        queue.async { [self] in
            sim.rotate180()
            lock.lock(); epoch += 1; let e = epoch; lock.unlock()
            publish(stats: nil, stepMs: nil)
            DispatchQueue.main.async { completion(e) }
        }
    }

    /// Density setting changed: rebuild grid, keep the source fraction, regenerate settled piles.
    func rebuild(density: SandDensity, sourceFraction: Double, source: Chamber) {
        queue.async { [self] in
            let geo = HourglassGeometry(density: density)
            let gravity = sim.gravity
            let newSim = SandSimulation(geometry: geo, targetGrains: density.targetGrains)
            newSim.sourceChamber = source
            newSim.gravity = gravity
            newSim.resetSettled(sourceGrains: Int((Double(newSim.grainCount) * sourceFraction).rounded()))
            sim = newSim
            back = [UInt8](repeating: 0, count: geo.width * geo.height * 2)
            lock.lock()
            front = back
            _geometry = Self.makeGeometryInfo(geo, version: _geometry.version + 1)
            _grainCount = newSim.grainCount
            lock.unlock()
            publish(stats: nil, stepMs: nil)
        }
    }

    private func publish(stats: FrameStats?, stepMs: Double?) {
        // Nothing moved -> the front buffer is still current: skip the 200-360 KB copy and, downstream, the texture
        // upload and the GPU redraw. A resting hourglass then costs almost nothing.
        let changed = stats.map { $0.moved > 0 || $0.corrected > 0 } ?? true
        if changed { back.withUnsafeMutableBufferPointer { sim.writeInterleaved(into: $0.baseAddress!) } }
        lock.lock()
        if stats == nil { forceStep = true }      // a command changed the sand: let it settle
        if changed {
            swap(&front, &back)
            frontVersion &+= 1
            frontEpoch = epoch
        }
        _sourceCount = sim.sourceCount
        if let stats {
            _lastStats = stats
            inFlight = false
        }
        if let stepMs { _avgStepMs = _avgStepMs * 0.95 + stepMs * 0.05 }
        lock.unlock()
    }

    // MARK: Glass field

    private static func makeGeometryInfo(_ g: HourglassGeometry, version: Int) -> GeometryInfo {
        var field = [Int8](repeating: 0, count: g.width * g.height * 2)
        for y in 0..<g.height {
            let hw = max(g.halfWidth(atY: Double(y) + 0.5), 1)
            for x in 0..<g.width {
                let i = y * g.width + x
                let d = Double(g.sdf[i]) / 8
                let u = (Double(x) + 0.5 - g.centerX) / hw
                field[2 * i] = Int8(clamping: Int((min(max(d, -1), 1) * 127).rounded()))
                field[2 * i + 1] = Int8(clamping: Int((min(max(u, -1), 1) * 127).rounded()))
            }
        }
        return GeometryInfo(width: g.width, height: g.height, capRows: g.capRows, gateRow: g.gateRow,
                            centerX: g.centerX, glassField: field, version: version)
    }
}
