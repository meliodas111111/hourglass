import Foundation
import MetalKit
import QuartzCore
import HourglassCore

/// Swift mirror of `SandUniforms` in Shaders.metal (layout verified: 112 bytes).
struct SandUniforms {
    var palette: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    var gridSize: SIMD2<Float>
    var capRows: Float
    var time: Float
    var glow: Float
    var gateRow: Float
    var centerX: Float
    var angle: Float
}

/// What the renderer needs from the view model every frame (called on the main thread).
@MainActor
protocol SandFrameSource: AnyObject {
    func frameInputs(now: Date) -> (sync: TimeSync, gravity: Vec2)
}

/// `MTKViewDelegate` that drives the simulation and draws it.
///
/// Frame pacing: 120 Hz on ProMotion (60 elsewhere) while sand moves; drops to 30 Hz for slow streams and to
/// 10 Hz when everything is at rest, so a resting hourglass costs almost nothing. The view is paused entirely
/// in the background.
final class SandRenderer: NSObject, MTKViewDelegate {

    weak var source: SandFrameSource?
    var palette: [RGB] = SandTheme.default.fiveSlots {
        didSet {
            guard palette != oldValue else { return }
            paletteSIMD = Self.simd(palette)
            needsRedraw = true
        }
    }
    /// Screen maximum (60, or 120 on ProMotion). Thermal state / Low Power Mode may cap it further.
    var maxFPS = 60

    private var paletteSIMD = SandRenderer.simd(SandTheme.default.fiveSlots)
    private var geo: SimulationDriver.GeometryInfo?
    /// GPU work happens only when something visible changed (new sand frame, flip, glow, resize, theme).
    private var needsRedraw = true
    private var powerCap = Int.max
    private var powerCheckCountdown = 0

    private static func simd(_ p: [RGB]) -> [SIMD4<Float>] {
        (0..<5).map { i in
            let c = p[i % max(p.count, 1)]
            return SIMD4<Float>(Float(c.r), Float(c.g), Float(c.b), 1)
        }
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let driver: SimulationDriver

    private var sandTexture: MTLTexture?
    private var glassTexture: MTLTexture?
    private var geometryVersion = -1
    private var uploadedVersion = -1
    private var uploadedEpoch = 0
    private var lastTime = CACurrentMediaTime()
    private let startTime = CACurrentMediaTime()
    private var quietFrames = 0

    // Flip animation state (main thread).
    private var flipStart: CFTimeInterval?
    private var flipDuration: CFTimeInterval = 0.6
    private var flipHoldEpoch: Int?
    private var flipCompletion: (() -> Void)?
    private(set) var angle: Float = 0

    // Finish glow.
    private var glowStart: CFTimeInterval?

    init?(view: MTKView, driver: SimulationDriver) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        self.device = device
        self.queue = queue
        self.driver = driver

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "Hourglass"
        desc.vertexFunction = library.makeFunction(name: "sandVertex")
        desc.fragmentFunction = library.makeFunction(name: "sandFragment")
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        self.pipeline = pipeline
        super.init()
        assert(MemoryLayout<SandUniforms>.size == 112, "SandUniforms layout must match Shaders.metal")
    }

    // MARK: Effects

    /// On-screen flip: rotate 0 → π, then rotate the grid content 180° and snap back to 0 on the exact frame
    /// that shows the rotated content — seamless.
    func animateFlip(duration: CFTimeInterval = 0.6, completion: @escaping () -> Void) {
        flipStart = CACurrentMediaTime()
        flipDuration = duration
        flipCompletion = completion
        flipHoldEpoch = nil
    }

    var isFlipping: Bool { flipStart != nil || flipHoldEpoch != nil }

    func pulseFinish() { glowStart = CACurrentMediaTime() }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { needsRedraw = true }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTime, 0.25)   // the simulation keeps real-time speed up to 4 fps
        lastTime = now

        // 1. Simulation step (async on the sim queue; we draw the newest finished frame).
        // MTKView draws on the main thread (display link), so main-actor state can be read synchronously.
        if let source {
            let inputs = MainActor.assumeIsolated { source.frameInputs(now: Date()) }
            driver.step(dt: dt, sync: inputs.sync, gravity: inputs.gravity)
        }

        // 2. Upload textures.
        ensureTextures()
        uploadSandIfNeeded()
        advanceFlip(now: now)

        // 3. Draw - only if something visible changed; the last presented frame simply stays on screen.
        if isFlipping || glowStart != nil { needsRedraw = true }
        guard needsRedraw else { adaptFrameRate(view); return }
        guard let geo,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let sand = sandTexture, let glass = glassTexture,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        needsRedraw = false
        let p = paletteSIMD
        var glow: Float = 0
        if let g = glowStart {
            let t = now - g
            glow = t < 2.5 ? Float(sin(min(t / 2.5, 1) * .pi)) : 0
            if t >= 2.5 { glowStart = nil }
        }
        var u = SandUniforms(palette: (p[0], p[1], p[2], p[3], p[4]),
                             gridSize: SIMD2(Float(geo.width), Float(geo.height)),
                             capRows: Float(geo.capRows),
                             time: Float(now - startTime),
                             glow: glow,
                             gateRow: Float(geo.gateRow),
                             centerX: Float(geo.centerX),
                             angle: angle)
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(sand, index: 0)
        enc.setFragmentTexture(glass, index: 1)
        enc.setFragmentBytes(&u, length: MemoryLayout<SandUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()

        adaptFrameRate(view)
    }

    // MARK: Internals

    private func ensureTextures() {
        guard driver.geometryVersion != geometryVersion else { return }
        let geo = driver.geometry
        self.geo = geo
        needsRedraw = true
        geometryVersion = geo.version
        uploadedVersion = -1

        let sd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg8Uint, width: geo.width, height: geo.height, mipmapped: false)
        sd.usage = .shaderRead
        sd.storageMode = .shared
        sandTexture = device.makeTexture(descriptor: sd)

        let gd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg8Snorm, width: geo.width, height: geo.height, mipmapped: false)
        gd.usage = .shaderRead
        glassTexture = device.makeTexture(descriptor: gd)
        geo.glassField.withUnsafeBytes {
            glassTexture?.replace(region: MTLRegionMake2D(0, 0, geo.width, geo.height), mipmapLevel: 0,
                                  withBytes: $0.baseAddress!, bytesPerRow: geo.width * 2)
        }
    }

    private func uploadSandIfNeeded() {
        guard let tex = sandTexture else { return }
        let w = tex.width, h = tex.height
        driver.withLatestFrame(newerThan: uploadedVersion) { bytes, version, epoch, width in
            // Right after a density rebuild the texture is re-created on the next frame — skip mismatched sizes.
            guard width == w else { return }
            tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: bytes, bytesPerRow: w * 2)
            uploadedVersion = version
            uploadedEpoch = epoch
            needsRedraw = true
        }
    }

    private func advanceFlip(now: CFTimeInterval) {
        if let start = flipStart {
            let t = min((now - start) / flipDuration, 1)
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            angle = Float(eased * .pi)
            if t >= 1 {
                flipStart = nil
                angle = .pi
                flipHoldEpoch = -1       // waiting for the rotated content
                driver.rotate180 { [weak self] epoch in self?.flipHoldEpoch = epoch }
            }
        } else if let hold = flipHoldEpoch, hold >= 0, uploadedEpoch >= hold {
            // The rotated content is on screen in this very frame → snap the angle back.
            angle = 0
            flipHoldEpoch = nil
            let c = flipCompletion
            flipCompletion = nil
            c?()
        }
    }

    private func adaptFrameRate(_ view: MTKView) {
        // About once a second: respect overheating and Low Power Mode (no heat, no battery drain on any phone).
        if powerCheckCountdown <= 0 {
            powerCheckCountdown = 60
            let info = ProcessInfo.processInfo
            switch info.thermalState {
            case .critical: powerCap = 20
            case .serious: powerCap = 30
            default: powerCap = info.isLowPowerModeEnabled ? 30 : .max
            }
        } else {
            powerCheckCountdown -= 1
        }
        let top = min(maxFPS, powerCap)
        let stats = driver.lastStats
        let busy = isFlipping || glowStart != nil
        if busy || stats.moved > 200 || stats.corrected > 0 {
            quietFrames = 0
            if view.preferredFramesPerSecond != top { view.preferredFramesPerSecond = top }
        } else {
            quietFrames += 1
            let target = stats.moved == 0 && quietFrames > 45 ? 10 : 30
            if quietFrames > 20, view.preferredFramesPerSecond != target { view.preferredFramesPerSecond = target }
        }
    }
}
