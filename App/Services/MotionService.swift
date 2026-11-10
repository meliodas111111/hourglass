import Foundation
import Combine
import CoreMotion
import UIKit
import HourglassCore

/// CoreMotion front-end (60 Hz).
///
/// * gravity comes from `CMDeviceMotion` — the gyroscope + accelerometer sensor fusion (smooth, no hand jitter);
///   devices without device motion fall back to the raw accelerometer, low-pass filtered into a gravity estimate;
/// * gravity is projected onto the screen plane (in *interface* coordinates, y down) and low-pass filtered;
///   the simulation thread reads it lock-protected via `gravity`;
/// * flip gesture: `FlipDetector` on the device-frame `gravity.y` (iPhone only — iPad autorotates);
/// * shake: `ShakeDetector` on `userAcceleration`.
///
/// Fully stopped while the app is in the background (`stop()`), so it costs no battery there.
final class MotionService: ObservableObject {

    /// Orientation used to keep text readable after a physical flip.
    @Published private(set) var deviceOrientation: FlipDetector.Orientation = .upright

    let flips = PassthroughSubject<FlipDetector.Orientation, Never>()
    let shakes = PassthroughSubject<Double, Never>()

    var isAvailable: Bool { manager.isDeviceMotionAvailable || manager.isAccelerometerAvailable }
    /// Whether updates are currently flowing (start() is idempotent).
    var isRunning: Bool { manager.isDeviceMotionActive || manager.isAccelerometerActive }

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.meliodas.hourglass.motion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()

    private let lock = NSLock()
    private var _gravity: Vec2 = .down
    private var _interfaceOrientation: UIInterfaceOrientation = .portrait
    private var _flipEnabled = true

    // Confined to `queue`.
    private var filter = LowPassFilter(cutoffHz: 6)
    private var detector = FlipDetector()
    private var shakeDetector = ShakeDetector()
    private var lastTimestamp: TimeInterval = 0
    private let isPhone = UIDevice.current.userInterfaceIdiom == .phone

    /// Smoothed in-plane gravity in interface coordinates (|g| ≤ 1). `.down` when no sensor (Mac, visionOS, Simulator).
    var gravity: Vec2 {
        lock.lock(); defer { lock.unlock() }
        return _gravity
    }

    var interfaceOrientation: UIInterfaceOrientation {
        get { lock.lock(); defer { lock.unlock() }; return _interfaceOrientation }
        set { lock.lock(); _interfaceOrientation = newValue; lock.unlock() }
    }

    var flipGestureEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _flipEnabled }
        set { lock.lock(); _flipEnabled = newValue; lock.unlock() }
    }

    /// Idempotent: safe to call from every place that may be first (scene activation, screen appearance).
    func start() {
        guard !isRunning else { return }
        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 1.0 / 60.0
            // .xArbitraryZVertical: gyro + accelerometer fusion, no magnetometer (no compass calibration prompts,
            // less power). Gravity is independent of the yaw reference.
            manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, _ in
                guard let self, let m = motion else { return }
                let g = m.gravity, a = m.userAcceleration
                self.process(gravity: (g.x, g.y, g.z), userAcceleration: (a.x, a.y, a.z), timestamp: m.timestamp)
            }
        } else if manager.isAccelerometerAvailable {
            // Fallback (no gyroscope fusion): the accelerometer measures gravity + hand motion; the low-pass filter
            // below turns it into a usable gravity estimate. Shake = deviation from that estimate.
            manager.accelerometerUpdateInterval = 1.0 / 60.0
            manager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
                guard let self, let d = data else { return }
                let a = d.acceleration
                let len = max((a.x * a.x + a.y * a.y + a.z * a.z).squareRoot(), 1e-6)
                let g = (a.x / len, a.y / len, a.z / len)
                self.process(gravity: g, userAcceleration: (a.x - g.0, a.y - g.1, a.z - g.2), timestamp: d.timestamp)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        manager.stopDeviceMotionUpdates()
        manager.stopAccelerometerUpdates()
        queue.addOperation { [weak self] in self?.detector.reset(); self?.lastTimestamp = 0 }
    }

    private func process(gravity g: (x: Double, y: Double, z: Double),
                         userAcceleration a: (x: Double, y: Double, z: Double), timestamp t: TimeInterval) {
        let dt = lastTimestamp > 0 ? min(max(t - lastTimestamp, 1.0 / 240), 0.1) : 1.0 / 60
        lastTimestamp = t

        let screen = Self.project(gravity: CMAcceleration(x: g.x, y: g.y, z: g.z), orientation: interfaceOrientation)
        let smoothed = filter.update(screen, dt: dt)
        lock.lock(); _gravity = smoothed; lock.unlock()

        if isPhone, flipGestureEnabled, let o = detector.process(gravityY: g.y, timestamp: t) {
            DispatchQueue.main.async {
                self.deviceOrientation = o
                self.flips.send(o)
            }
        }
        if let s = shakeDetector.process(userAcceleration: a, timestamp: t) {
            DispatchQueue.main.async { self.shakes.send(s) }
        }
    }

    /// Device-frame gravity (x right, y towards the top edge, z out of the screen) → interface coordinates (y down).
    static func project(gravity g: CMAcceleration, orientation: UIInterfaceOrientation) -> Vec2 {
        switch orientation {
        case .portraitUpsideDown: return Vec2(-g.x, g.y)
        case .landscapeLeft:      return Vec2(g.y, g.x)
        case .landscapeRight:     return Vec2(-g.y, -g.x)
        default:                  return Vec2(g.x, -g.y)
        }
    }
}
