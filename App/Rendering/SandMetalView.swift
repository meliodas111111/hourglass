import SwiftUI
import MetalKit
import HourglassCore

/// MTKView subclass that picks up the screen's max refresh rate (ProMotion) once it is in a window.
final class SandMTKView: MTKView {
    var onMaxFPS: ((Int) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let screen = window?.windowScene?.screen else { return }
        // The sand grid is ~240 cells wide, so 3x Retina only adds fill cost: render at <= 2x (-55 % pixels on
        // Pro Max models). Glass highlights stay sharp at 2x.
        contentScaleFactor = min(screen.nativeScale, 2)
        let fps = screen.maximumFramesPerSecond
        preferredFramesPerSecond = fps
        onMaxFPS?(fps)
    }
}

/// SwiftUI wrapper. Give it the grid's aspect ratio (`driver.geometry.width / height`); flip animations happen
/// inside the shader, so SwiftUI never has to re-layout during a flip.
struct SandMetalView: UIViewRepresentable {
    let driver: SimulationDriver
    let source: SandFrameSource
    var theme: SandTheme
    var isActive: Bool
    /// Registers the renderer so the view model can trigger flip / glow effects.
    var onRendererReady: (SandRenderer) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SandMTKView {
        let view = SandMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.enableSetNeedsDisplay = false
        view.autoResizeDrawable = true
        view.isPaused = !isActive
        view.accessibilityIdentifier = "sandView"

        if let renderer = SandRenderer(view: view, driver: driver) {
            renderer.source = source
            renderer.palette = theme.fiveSlots
            view.delegate = renderer
            view.onMaxFPS = { [weak renderer] fps in renderer?.maxFPS = fps }
            context.coordinator.renderer = renderer
            onRendererReady(renderer)
        }
        return view
    }

    func updateUIView(_ view: SandMTKView, context: Context) {
        context.coordinator.renderer?.palette = theme.fiveSlots
        // Battery: fully stop the display link when not visible / in background.
        if view.isPaused == isActive { view.isPaused = !isActive }
    }

    final class Coordinator {
        var renderer: SandRenderer?
    }
}
