import Foundation

/// Detects a 180° flip of the device from `CMDeviceMotion.gravity.y` samples.
///
/// Rules (spec §3):
/// * a flip is a change of sign of `gravity.y` that then **stays beyond ±0.8 for ≥ 300 ms**;
/// * hysteresis: once a candidate started, it is only cancelled if |gy| drops below `releaseThreshold`
///   (or the sign goes back), so small wobbles around 0.8 don't restart the hold timer;
/// * a cooldown prevents double triggers when the user "fiddles" with the device;
/// * the very first stable orientation is adopted silently (no event at launch).
///
/// CoreMotion convention: portrait upright → `gravity.y ≈ −1`, upside down → `≈ +1`.
public struct FlipDetector: Sendable {

    public enum Orientation: Equatable, Sendable {
        case upright, inverted
        public var opposite: Orientation { self == .upright ? .inverted : .upright }
        init?(gravityY gy: Double, threshold: Double) {
            if gy <= -threshold { self = .upright } else if gy >= threshold { self = .inverted } else { return nil }
        }
    }

    public struct Configuration: Sendable {
        public var threshold = 0.8
        public var releaseThreshold = 0.65
        public var holdDuration: TimeInterval = 0.3
        public var cooldown: TimeInterval = 0.8
        public init() {}
    }

    public let configuration: Configuration
    public private(set) var orientation: Orientation?
    private var candidate: Orientation?
    private var candidateSince: TimeInterval = 0
    private var lastFlipAt: TimeInterval = -.infinity

    public init(configuration: Configuration = .init()) { self.configuration = configuration }

    /// Feeds one sample. Returns the new orientation when a flip is confirmed, otherwise `nil`.
    public mutating func process(gravityY gy: Double, timestamp t: TimeInterval) -> Orientation? {
        let c = configuration
        let beyond = Orientation(gravityY: gy, threshold: c.threshold)

        // Candidate maintenance with hysteresis.
        if let cand = candidate {
            let sameSide = cand == .upright ? gy < 0 : gy > 0
            if !sameSide || abs(gy) < c.releaseThreshold { candidate = nil }
        }
        if candidate == nil, let b = beyond, b != orientation {
            candidate = b
            candidateSince = t
        }

        guard let cand = candidate, t - candidateSince >= c.holdDuration else { return nil }

        candidate = nil
        guard let current = orientation else {
            orientation = cand              // first stable reading: adopt silently
            return nil
        }
        guard cand != current, t - lastFlipAt >= c.cooldown else { return nil }
        orientation = cand
        lastFlipAt = t
        return cand
    }

    /// Forget state (e.g. when the gesture is toggled in Settings).
    public mutating func reset() {
        orientation = nil
        candidate = nil
    }
}

/// Converts `userAcceleration` magnitude into a 0…1 shake strength with a threshold and refractory period.
public struct ShakeDetector: Sendable {
    public var threshold = 1.3       // g
    public var saturation = 3.0      // g
    public var refractory: TimeInterval = 0.25
    private var lastShake: TimeInterval = -.infinity

    public init() {}

    public mutating func process(userAcceleration a: (x: Double, y: Double, z: Double), timestamp t: TimeInterval) -> Double? {
        let m = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        guard m > threshold, t - lastShake >= refractory else { return nil }
        lastShake = t
        return min(1, (m - threshold) / (saturation - threshold))
    }
}
