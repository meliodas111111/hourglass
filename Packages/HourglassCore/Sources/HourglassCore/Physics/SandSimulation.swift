import Foundation

/// Cell types stored in `SandSimulation.cells`.
public enum CellType: UInt8 {
    case empty = 0
    case sand = 1
    case wall = 2
}

/// Time information handed to the simulation every frame by the timer layer.
///
/// The simulation never *decides* time — it only visualises it. `expectedSource` is
/// `N × remaining / total`, computed from dates by `TimerEngine`.
public struct TimeSync: Sendable {
    /// Grains that should still be in the draining chamber right now.
    public var expectedSource: Int
    /// Seconds until the current phase ends (≤ 0 → the source chamber must be empty *this* frame).
    public var remaining: Double
    /// Average flow the timer requires, grains / second (`N / total`).
    public var grainsPerSecond: Double
    /// When `false` the neck gate is closed (idle / paused / finished) and no correction happens.
    public var isRunning: Bool

    public init(expectedSource: Int, remaining: Double, grainsPerSecond: Double, isRunning: Bool) {
        self.expectedSource = expectedSource
        self.remaining = remaining
        self.grainsPerSecond = grainsPerSecond
        self.isRunning = isRunning
    }

    public static let stopped = TimeSync(expectedSource: 0, remaining: .infinity, grainsPerSecond: 0, isRunning: false)
}

/// Per-frame statistics (used by the driver for adaptive quality and by tests / Instruments signposts).
public struct FrameStats: Sendable {
    public var substeps = 0
    public var moved = 0
    public var crossedGate = 0
    public var corrected = 0
    public var isSettled: Bool { moved == 0 && corrected == 0 }
    public init() {}
}

/// Falling-sand cellular automaton inside an hourglass, synchronised to a timer.
///
/// ### Storage
/// Flat row-major `[UInt8]` arrays — `cells` (type) and `shades` (per-grain tint) — for cache efficiency,
/// plus a `stamp` array implementing the "already updated in this sub-step" flag without clearing memory.
///
/// ### Movement rule (one sub-step)
/// 1. try the primary cell: the neighbour of the 8 directions closest to gravity `g`;
/// 2. else one of the two neighbouring diagonals (weighted by the angle between `g` and the primary direction),
///    accepted with probability `diagonalChance` — this is what produces a natural angle of repose;
/// 3. else (axial gravity only) a "knight" slide two cells sideways + one down with probability `knightChance`;
///    mixing 45° diagonal slides and 26.6° knight slides yields piles of ~30–35°;
/// 4. else stay.
///
/// Traversal goes along the dominant gravity axis from the "bottom" up, alternating the lateral direction every
/// sub-step to avoid a left/right bias.
///
/// ### Time synchronisation
/// The neck is a *metering gate*: a grain may cross from the source into the sink chamber only while the gate
/// budget `k = clamp(sourceCount − expectedSource, 0, kMax)` is positive. If grains physically cannot reach the
/// neck while time runs (device lying on its side), an *invisible correction* moves the grains farthest from the
/// neck on the source pile's surface to just below the neck — a few grains per frame, more only when the timer
/// itself requires a faster flow, and everything that is left on the very last frame. Hence the source chamber is
/// empty exactly at `endDate` (± one frame) regardless of orientation.
public final class SandSimulation {

    public struct Parameters: Sendable {
        /// Cells per second a grain falls at |g| = 1.
        public var cellsPerSecond: Double = 170
        /// Sub-steps per frame at normal frame rates. Long frames (low-power 10–30 Hz, a slow device, a hitch) get as
        /// many as real time needs, up to `maxCatchUpSubsteps`, so grains fall at the same speed at any frame rate.
        public var maxSubsteps = 5
        public var maxCatchUpSubsteps = 45
        /// Longest frame simulated in real time; longer gaps (app was suspended) are skipped, not replayed.
        public var maxFrameTime = 0.25
        /// Max extra sub-steps (× normal) for the band around the neck when a short timer needs more flow than a
        /// 2–3-cell neck passes (~3 grains per sub-step).
        public var maxNeckBoost = 4
        /// Probability (0…255) that a diagonal slide is taken when available.
        public var diagonalChance: UInt8 = 215
        /// Probability (0…255) of the 2-sideways/1-down slide that flattens piles to ~32°.
        public var knightChance: UInt8 = 60
        /// Below this in-plane |g| the device is considered "flat": grains only settle slowly.
        public var flatThreshold = 0.35
        /// Max grains moved by the invisible correction per frame when the flow is stalled.
        public var correctionPerFrame = 4
        /// Frames without any gate crossing (while budget > 0) before we treat the flow as stalled.
        public var stallFrames = 8
        /// Window (seconds) before the end in which the correction is allowed to catch up aggressively.
        public var catchUpWindow = 0.5
        public init() {}
    }

    // MARK: State

    public let geometry: HourglassGeometry
    public var parameters: Parameters
    public let width: Int
    public let height: Int

    public private(set) var cells: [UInt8]
    public private(set) var shades: [UInt8]
    private var stamp: [UInt8]
    private var currentStamp: UInt8 = 1

    /// Total number of grains `N` (constant for the lifetime of the simulation).
    public private(set) var grainCount: Int
    public private(set) var upperCount = 0
    public private(set) var lowerCount = 0

    /// Gravity in *grid* coordinates (y grows downward). In-plane magnitude is in 0…1.
    public var gravity: Vec2 = .down
    /// Chamber that is currently draining (set by the timer / flip logic).
    public var sourceChamber: Chamber = .upper

    public var sinkChamber: Chamber { sourceChamber.opposite }
    public var sourceCount: Int { sourceChamber == .upper ? upperCount : lowerCount }

    private var rng: FastRandom
    private var substepAccumulator = 0.0
    private var alternate = false
    private var stalledFrameCount = 0
    /// Seconds of extra lag tolerance after a flip: the pile needs ~1–2 s to fall to the neck, and that delay must
    /// not be "fixed" by teleporting grains. Decays with time; the end-of-timer guarantee is unaffected.
    private var flipGrace = 0.0
    /// Interior column range per row — lets the row-major traversal skip the outside of the glass.
    private let rowSpan: [(lo: Int, hi: Int)]

    // MARK: Init

    /// - Parameters:
    ///   - geometry: silhouette / grid.
    ///   - targetGrains: requested N; clamped to 62 % of a chamber so a full chamber never reaches the neck.
    ///   - seed: PRNG seed (deterministic tests).
    public init(geometry: HourglassGeometry, targetGrains: Int, seed: UInt64 = 0xC0FFEE, parameters: Parameters = .init()) {
        self.geometry = geometry
        self.parameters = parameters
        self.width = geometry.width
        self.height = geometry.height
        let capacity = min(geometry.upperCapacity, geometry.lowerCapacity)
        self.grainCount = clamp(targetGrains, 1, Int(Double(capacity) * 0.62))
        self.rng = FastRandom(seed: seed)

        let count = geometry.width * geometry.height
        self.cells = geometry.wallMask.map { $0 == 1 ? CellType.wall.rawValue : CellType.empty.rawValue }
        self.shades = [UInt8](repeating: 0, count: count)
        self.stamp = [UInt8](repeating: 0, count: count)

        var spans: [(Int, Int)] = []
        spans.reserveCapacity(geometry.height)
        for y in 0..<geometry.height {
            var lo = geometry.width, hi = -1
            for x in 0..<geometry.width where geometry.wallMask[y * geometry.width + x] == 0 {
                lo = min(lo, x); hi = max(hi, x)
            }
            spans.append((lo, hi))
        }
        self.rowSpan = spans
    }

    // MARK: Layout / restore

    /// Procedurally regenerates settled piles (no per-cell persistence needed).
    /// - Parameter sourceGrains: grains that belong in the source chamber (`expectedSource`).
    public func resetSettled(sourceGrains: Int, gravity g: Vec2? = nil) {
        if let g { gravity = g }
        let src = clamp(sourceGrains, 0, grainCount)
        for i in cells.indices where cells[i] == CellType.sand.rawValue { cells[i] = CellType.empty.rawValue }
        upperCount = 0; lowerCount = 0

        let fillGravity = gravity.length < 0.2
            ? (sourceChamber == .upper ? Vec2.down : -Vec2.down)   // flat: assume source is "up"
            : gravity
        let gen = PileGenerator(geometry: geometry)
        for (chamber, n) in [(sourceChamber, src), (sinkChamber, grainCount - src)] {
            for idx in gen.settledCells(in: chamber, count: n, gravity: fillGravity, rng: &rng) {
                cells[idx] = CellType.sand.rawValue
                shades[idx] = makeShade()
            }
            if chamber == .upper { upperCount += n } else { lowerCount += n }
        }
    }

    /// Call on every flip (physical or on-screen) and on timer start.
    public func noteFlip(grace: Double = 3) { flipGrace = grace }

    /// 180° rotation of the cell content (used by the on-screen "flip" button / animation).
    /// The silhouette is point-symmetric, so walls map onto walls. Chamber counts swap.
    public func rotate180() {
        cells.reverse()
        shades.reverse()
        swap(&upperCount, &lowerCount)
        noteFlip()          // the sand now has to fall the whole bulb to reach the neck
    }

    /// Changes the number of grains (density setting) while preserving the source/sink ratio.
    public func setGrainCount(_ n: Int, sourceGrains: Int) {
        let capacity = min(geometry.upperCapacity, geometry.lowerCapacity)
        grainCount = clamp(n, 1, Int(Double(capacity) * 0.62))
        resetSettled(sourceGrains: sourceGrains)
    }

    // MARK: Shading

    /// Shade byte layout: bits 7…5 palette slot (0…4), bits 4…0 brightness noise (0…31 → ±8 %).
    @inline(__always)
    private func makeShade() -> UInt8 {
        let r = rng.next()
        // Slightly favour the middle palette slots so themes have a dominant tone.
        let slotTable: [UInt8] = [0, 1, 1, 2, 2, 2, 3, 4]
        let slot = slotTable[Int(r & 7)]
        let noise = UInt8(truncatingIfNeeded: (r >> 8) & 31)
        return (slot << 5) | noise
    }

    // MARK: Frame step

    /// Advances the simulation by `dt` seconds.
    @discardableResult
    public func step(dt: Double, sync: TimeSync) -> FrameStats {
        var stats = FrameStats()
        let dt = clamp(dt, 0, parameters.maxFrameTime)
        let g = gravity
        let gLen = min(g.length, 1)

        // Gate budget for this frame: k = clamp(currentTop − expectedTop, 0, kMax).
        let lag = sourceCount - sync.expectedSource
        var budget = sync.isRunning ? max(0, lag) : 0

        // Sub-steps ∝ |g|·dt (frame-rate independent: 60 and 120 Hz look the same).
        substepAccumulator += max(gLen, 0.05) * parameters.cellsPerSecond * dt
        var n = Int(substepAccumulator)
        substepAccumulator -= Double(n)
        // Regression: capping at 5 per frame made sand fall 3× slower at 10 Hz and the correction did the work.
        n = min(n, min(parameters.maxCatchUpSubsteps, max(parameters.maxSubsteps, Int((parameters.cellsPerSecond * dt).rounded(.up)))))

        if n > 0 && gLen > 0.01 {
            // Lying flat → grains only creep (probability per attempt scales with |g|).
            let moveChance: UInt8 = gLen >= parameters.flatThreshold ? 255 : UInt8(255 * gLen / parameters.flatThreshold)
            let dirs = DirectionSet(gravity: g)
            for _ in 0..<n {
                let (moved, crossed) = substep(dirs: dirs, moveChance: moveChance, budget: &budget)
                stats.moved += moved
                stats.crossedGate += crossed
            }
            // Neck boost: when the timer needs more grains/s than the neck passes at this gravity, the band around the
            // neck gets extra sub-steps — grains there move faster and the stream gets denser; the bulk is untouched.
            // Without it, timers ≤ 10 s were mostly fed by the invisible correction (58–81 % of the sand).
            if sync.isRunning && dirs.rowMajor {
                let neckCapacity = Double(geometry.neckCells) * parameters.cellsPerSecond * gLen
                let wanted = Int((sync.grainsPerSecond * 1.15 / max(neckCapacity, 1)).rounded(.up)) - 1
                let extra = min(parameters.maxNeckBoost, max(0, wanted))
                if extra > 0 {
                    let band = max(12, height / 15)
                    let rows = max(0, geometry.gateRow - band)..<min(height, geometry.gateRow + band)
                    for _ in 0..<(n * extra) {
                        let (moved, crossed) = substep(dirs: dirs, moveChance: moveChance, budget: &budget, rows: rows)
                        stats.moved += moved
                        stats.crossedGate += crossed
                    }
                }
            }
            stats.substeps = n
        }

        // Invisible correction.
        if sync.isRunning {
            stats.corrected = correct(sync: sync, dt: dt, crossedThisFrame: stats.crossedGate, movedThisFrame: stats.moved)
        } else {
            stalledFrameCount = 0
        }
        flipGrace = max(0, flipGrace - dt)
        return stats
    }

    // MARK: Sub-step

    /// Precomputed movement directions for the current gravity vector.
    struct DirectionSet {
        static let ring: [(Int, Int)] = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
        let primary: (Int, Int)
        let sideA: (Int, Int)
        let sideB: (Int, Int)
        /// 0…255 probability of trying `sideA` first.
        let sideAChance: UInt8
        let isAxial: Bool
        /// Traverse rows (true) or columns (false) as the outer loop.
        let rowMajor: Bool
        /// Outer loop runs from high index to low (true) — i.e. gravity points to increasing index.
        let outerDescending: Bool

        init(gravity g: Vec2) {
            let angle = atan2(g.y, g.x)
            let step = Double.pi / 4
            var o = Int((angle / step).rounded())
            let residual = angle - Double(o) * step               // −π/8 … π/8
            o = ((o % 8) + 8) % 8
            primary = Self.ring[o]
            sideA = Self.ring[(o + 1) % 8]
            sideB = Self.ring[(o + 7) % 8]
            sideAChance = UInt8(clamp(0.5 + residual / step, 0, 1) * 255)
            isAxial = o % 2 == 0
            rowMajor = abs(g.y) >= abs(g.x)
            outerDescending = rowMajor ? g.y > 0 : g.x > 0
        }
    }

    /// One CA sweep. Returns (#moves, #gate crossings).
    private func substep(dirs: DirectionSet, moveChance: UInt8, budget: inout Int, rows rowRange: Range<Int>? = nil) -> (Int, Int) {
        currentStamp = currentStamp == 255 ? 1 : currentStamp + 1
        alternate.toggle()
        let st = currentStamp
        let w = width, h = height
        let gate = geometry.gateRow
        let source = sourceChamber
        var moved = 0, crossed = 0
        var upper = upperCount, lower = lowerCount
        var rng = self.rng
        let p = parameters

        cells.withUnsafeMutableBufferPointer { cellsBuf in
        shades.withUnsafeMutableBufferPointer { shadeBuf in
        stamp.withUnsafeMutableBufferPointer { stampBuf in
            let c = cellsBuf.baseAddress!, s = shadeBuf.baseAddress!, f = stampBuf.baseAddress!

            /// Attempts to move grain at (x, y) by (dx, dy). Handles gate metering and chamber counts.
            @inline(__always)
            func tryMove(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int) -> Bool {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < w, ny < h else { return false }
                let ni = ny * w + nx
                guard c[ni] == CellType.empty.rawValue else { return false }
                let fromUpper = y < gate, toUpper = ny < gate
                if fromUpper != toUpper {
                    // Crossing the neck: only source → sink, only with budget.
                    let fromChamber: Chamber = fromUpper ? .upper : .lower
                    guard fromChamber == source, budget > 0 else { return false }
                    budget -= 1
                    crossed += 1
                    if fromUpper { upper -= 1; lower += 1 } else { lower -= 1; upper += 1 }
                }
                let i = y * w + x
                c[ni] = CellType.sand.rawValue
                s[ni] = s[i]
                f[ni] = st
                c[i] = CellType.empty.rawValue
                moved += 1
                return true
            }

            @inline(__always)
            func update(_ x: Int, _ y: Int) {
                let i = y * w + x
                guard c[i] == CellType.sand.rawValue, f[i] != st else { return }
                if moveChance < 255 && rng.byte() > moveChance { return }
                // (1) primary
                if tryMove(x, y, dirs.primary.0, dirs.primary.1) { return }
                // (2) diagonals, weighted by angle, accepted with repose probability
                guard rng.byte() <= p.diagonalChance else { return }
                let aFirst = rng.byte() < dirs.sideAChance
                let first = aFirst ? dirs.sideA : dirs.sideB
                let second = aFirst ? dirs.sideB : dirs.sideA
                if tryMove(x, y, first.0, first.1) { return }
                if tryMove(x, y, second.0, second.1) { return }
                // (3) knight slide (axial gravity only): 2 sideways + 1 along g, path must be clear
                guard dirs.isAxial, rng.byte() <= p.knightChance else { return }
                let latX = first.0 - dirs.primary.0, latY = first.1 - dirs.primary.1
                let mx = x + latX, my = y + latY
                guard mx >= 0, my >= 0, mx < w, my < h, c[my * w + mx] == CellType.empty.rawValue else { return }
                _ = tryMove(x, y, 2 * latX + dirs.primary.0, 2 * latY + dirs.primary.1)
            }

            if dirs.rowMajor {
                let r = rowRange ?? 0..<h
                let rows: StrideThrough<Int> = dirs.outerDescending ? stride(from: r.upperBound - 1, through: r.lowerBound, by: -1)
                                                                     : stride(from: r.lowerBound, through: r.upperBound - 1, by: 1)
                let leftToRight = alternate
                for y in rows {
                    let span = rowSpan[y]
                    guard span.hi >= span.lo else { continue }
                    if leftToRight {
                        var x = span.lo; while x <= span.hi { update(x, y); x += 1 }
                    } else {
                        var x = span.hi; while x >= span.lo { update(x, y); x -= 1 }
                    }
                }
            } else {
                let cols: StrideThrough<Int> = dirs.outerDescending ? stride(from: w - 1, through: 0, by: -1)
                                                                     : stride(from: 0, through: w - 1, by: 1)
                let topToBottom = alternate
                for x in cols {
                    if topToBottom {
                        var y = 0; while y < h { update(x, y); y += 1 }
                    } else {
                        var y = h - 1; while y >= 0 { update(x, y); y -= 1 }
                    }
                }
            }
        }}}

        self.rng = rng
        upperCount = upper
        lowerCount = lower
        return (moved, crossed)
    }

    // MARK: Invisible correction

    private func correct(sync: TimeSync, dt: Double, crossedThisFrame: Int, movedThisFrame: Int) -> Int {
        let lag = sourceCount - sync.expectedSource
        guard lag > 0 else { stalledFrameCount = 0; return 0 }

        // "Stalled" = nothing crosses AND the sand is (almost) at rest. Right after a flip the grains are still in
        // free fall towards the neck for a second or two — that is not a stall and must not trigger teleports.
        let atRest = movedThisFrame < max(8, grainCount / 50)
        stalledFrameCount = crossedThisFrame == 0 && atRest ? stalledFrameCount + 1 : 0
        let frameDt = max(dt, 1.0 / 240)
        let framesLeft = sync.remaining / frameDt
        let requiredPerFrame = sync.grainsPerSecond * frameDt
        // Cap scales with the flow the timer needs: "a few grains" for long timers, more for 5-second timers.
        let cap = max(parameters.correctionPerFrame, Int((requiredPerFrame * 1.5).rounded(.up)))
        // Lag tolerated before correcting a *flowing* (but too slow) stream.
        // Lag tolerated before correcting a flowing stream: covers grains "in flight" (≈0.75 s of the required flow),
        // so the start of a run and normal neck jitter stay purely physical.
        let tolerance = max(12, grainCount / 400, Int(sync.grainsPerSecond * (0.75 + flipGrace)))

        var amount = 0
        if stalledFrameCount >= parameters.stallFrames && flipGrace <= 0 { amount = min(lag, cap) }
        if lag > tolerance { amount = max(amount, min(lag - tolerance, cap)) }
        if sync.remaining <= parameters.catchUpWindow {
            // Guarantee: the source is empty on the frame `remaining` reaches zero.
            amount = framesLeft <= 1 ? lag : max(amount, Int((Double(lag) / framesLeft).rounded(.up)))
        }
        amount = min(amount, lag)
        guard amount > 0 else { return 0 }
        return transferFromSurface(count: amount)
    }

    /// Moves every grain still in the source chamber to the sink (used at a phase boundary of a sequence,
    /// right before the automatic flip, so the previous phase also ends exactly on time).
    @discardableResult
    public func flushSource() -> Int {
        let n = sourceCount
        return n > 0 ? transferFromSurface(count: n) : 0
    }

    /// Moves `count` grains from the surface of the source pile (farthest from the neck) to just below the neck.
    @discardableResult
    func transferFromSurface(count: Int) -> Int {
        let w = width
        let gate = geometry.gateRow
        let up = DirectionSet(gravity: gravity.length > 0.05 ? -gravity : (sourceChamber == .upper ? -Vec2.down : Vec2.down)).primary
        let rows = sourceChamber == .upper ? 0..<gate : gate..<height
        let neck = geometry.neckCenter

        // 1. Collect surface grains (empty or out-of-chamber cell "above" them w.r.t. gravity).
        var candidates: [(d2: Double, idx: Int)] = []
        candidates.reserveCapacity(1024)
        for y in rows {
            let span = rowSpan[y]
            guard span.hi >= span.lo else { continue }
            for x in span.lo...span.hi {
                let i = y * w + x
                guard cells[i] == CellType.sand.rawValue else { continue }
                let ax = x + up.0, ay = y + up.1
                let exposed = ax < 0 || ay < 0 || ax >= w || ay >= height || cells[ay * w + ax] == CellType.empty.rawValue
                guard exposed else { continue }
                let dx = Double(x) + 0.5 - neck.x, dy = Double(y) + 0.5 - neck.y
                candidates.append((dx * dx + dy * dy, i))
            }
        }
        // Fallback (should not happen): any source grain.
        if candidates.count < count {
            for y in rows { for x in 0..<w where cells[y * w + x] == CellType.sand.rawValue { candidates.append((0, y * w + x)) } }
        }
        candidates.sort { $0.d2 > $1.d2 }

        // 2. Re-spawn below the neck.
        var moved = 0
        for cand in candidates where moved < count {
            // The fallback list may contain surface grains twice — skip cells already emptied.
            guard cells[cand.idx] == CellType.sand.rawValue else { continue }
            guard let dest = spawnCellBelowNeck() else { break }
            cells[dest] = CellType.sand.rawValue
            shades[dest] = shades[cand.idx]
            stamp[dest] = currentStamp
            cells[cand.idx] = CellType.empty.rawValue
            if sourceChamber == .upper { upperCount -= 1; lowerCount += 1 } else { lowerCount -= 1; upperCount += 1 }
            moved += 1
        }
        return moved
    }

    /// Free cell in the sink chamber as close to the neck exit as possible (inside the falling stream).
    private func spawnCellBelowNeck() -> Int? {
        let w = width
        let sink = sinkChamber
        let exitRow = geometry.neckExitRow(into: sink)
        let stepY = sink == .lower ? 1 : -1
        let cx = Int(geometry.centerX)
        let limitRows = sink == .lower ? height - exitRow : exitRow + 1
        // Search expanding "stream" columns, a few rows deep first, then wider.
        for radius in 0..<max(width / 2, 1) {
            let jitter = rng.int(2 * radius + 1) - radius
            for k in 0..<min(limitRows, 12 + radius * 3) {
                let y = exitRow + k * stepY
                for dx in [jitter, -jitter] {
                    let x = cx + dx
                    guard x >= 0, x < w else { continue }
                    let i = y * w + x
                    if cells[i] == CellType.empty.rawValue { return i }
                }
            }
        }
        // Exhaustive fallback.
        let rows: [Int] = sink == .lower ? Array(exitRow..<height) : Array((0...exitRow).reversed())
        for y in rows { for x in 0..<w where cells[y * w + x] == CellType.empty.rawValue { return y * w + x } }
        return nil
    }

    // MARK: Shake

    /// Shake impulse: surface grains jump 1–3 cells against gravity (with sideways jitter) and avalanche back down.
    /// - Parameter strength: 0…1 (from userAcceleration magnitude above the threshold).
    public func applyShake(strength: Double) {
        let strength = clamp(strength, 0, 1)
        guard strength > 0 else { return }
        let w = width
        let gate = geometry.gateRow
        let up = DirectionSet(gravity: gravity.length > 0.05 ? -gravity : -Vec2.down).primary
        let chance = UInt8(min(255, 60 + 180 * strength))
        let maxJump = 1 + Int(strength * 3)
        for y in 0..<height {
            let span = rowSpan[y]
            guard span.hi >= span.lo else { continue }
            for x in span.lo...span.hi {
                let i = y * w + x
                guard cells[i] == CellType.sand.rawValue, rng.byte() < chance else { continue }
                let ax = x + up.0, ay = y + up.1
                guard ax >= 0, ay >= 0, ax < w, ay < height, cells[ay * w + ax] == CellType.empty.rawValue else { continue }
                let jump = 1 + rng.int(maxJump)
                var tx = x, ty = y
                for _ in 0..<jump {
                    let nx = tx + up.0 + (rng.int(3) - 1) * (up.0 == 0 ? 1 : 0)
                    let ny = ty + up.1 + (rng.int(3) - 1) * (up.1 == 0 ? 1 : 0)
                    guard nx >= 0, ny >= 0, nx < w, ny < height,
                          cells[ny * w + nx] == CellType.empty.rawValue,
                          (ny < gate) == (y < gate) else { break }          // never cross the neck
                    tx = nx; ty = ny
                }
                if tx != x || ty != y {
                    let ni = ty * w + tx
                    cells[ni] = CellType.sand.rawValue
                    shades[ni] = shades[i]
                    cells[i] = CellType.empty.rawValue
                }
            }
        }
    }

    // MARK: Export

    /// Packs (type, shade) pairs into an RG8 buffer of `width × height × 2` bytes for GPU upload.
    public func writeInterleaved(into dst: UnsafeMutablePointer<UInt8>) {
        cells.withUnsafeBufferPointer { c in
            shades.withUnsafeBufferPointer { s in
                for i in 0..<c.count {
                    dst[2 * i] = c[i]
                    dst[2 * i + 1] = s[i]
                }
            }
        }
    }

    /// Recount (debug / test helper).
    public func countGrains() -> (upper: Int, lower: Int) {
        var u = 0, l = 0
        let gate = geometry.gateRow * width
        for i in 0..<cells.count where cells[i] == CellType.sand.rawValue { if i < gate { u += 1 } else { l += 1 } }
        return (u, l)
    }
}
