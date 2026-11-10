import Foundation

/// Minimal 2-D vector. We deliberately avoid `simd` so the package compiles on Linux too.
public struct Vec2: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    public static let zero = Vec2(0, 0)
    /// "Down" in grid / screen coordinates (y grows downward).
    public static let down = Vec2(0, 1)

    public var length: Double { (x * x + y * y).squareRoot() }
    public var normalized: Vec2 { let l = length; return l > 1e-9 ? Vec2(x / l, y / l) : .zero }

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }
    public func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
}

/// First-order IIR low-pass filter used to smooth the gravity vector coming from CoreMotion.
///
/// `alpha` is derived from a cut-off frequency so the behaviour does not depend on the sample rate.
public struct LowPassFilter: Sendable {
    public private(set) var value: Vec2
    public let cutoffHz: Double
    private var initialised = false

    public init(cutoffHz: Double = 6, initial: Vec2 = .down) {
        self.cutoffHz = cutoffHz
        self.value = initial
    }

    @discardableResult
    public mutating func update(_ sample: Vec2, dt: Double) -> Vec2 {
        guard initialised else { value = sample; initialised = true; return value }
        let rc = 1.0 / (2 * Double.pi * cutoffHz)
        let alpha = dt / (rc + dt)
        value = value + (sample - value) * alpha
        return value
    }
}

/// Fast deterministic PRNG (xorshift64*). Deterministic seeding makes simulation tests reproducible.
public struct FastRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64 = 0x9E37_79B9_7F4A_7C15) { state = seed == 0 ? 0xDEADBEEF : seed }

    @inline(__always)
    public mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }

    /// Uniform in [0, 1).
    @inline(__always)
    public mutating func unit() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }

    /// Uniform integer in [0, bound).
    @inline(__always)
    public mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(max(bound, 1))) }

    /// Cheap 0…255 value for probability tests in hot loops.
    @inline(__always)
    public mutating func byte() -> UInt8 { UInt8(truncatingIfNeeded: next() >> 56) }
}

@inline(__always) func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }
