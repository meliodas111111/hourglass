import Foundation

/// RGB colour in 0…1, platform independent (converted to `Color` / `SIMD4<Float>` in the app layer).
public struct RGB: Codable, Hashable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }
}

/// A sand theme is a palette of 3–5 colours; every grain picks one palette slot plus ±8 % brightness noise.
public struct SandTheme: Identifiable, Hashable, Sendable {
    public enum ID: String, Codable, CaseIterable, Sendable {
        case goldenSand, desert, ocean, ember, lavender, roseQuartz, jade
    }

    public let id: ID
    /// Localisation key of the display name.
    public let nameKey: String
    public let palette: [RGB]
    /// Premium themes require the "Supporter" purchase.
    public let isPremium: Bool

    /// Palette padded/repeated to exactly 5 slots (the shader always reads 5).
    public var fiveSlots: [RGB] { (0..<5).map { palette[$0 % palette.count] } }

    public static let all: [SandTheme] = [
        SandTheme(id: .goldenSand, nameKey: "Golden Sand",
                  palette: [RGB(hex: 0xB8862F), RGB(hex: 0xD4A443), RGB(hex: 0xE6BE62), RGB(hex: 0xF2D58C), RGB(hex: 0xC99638)], isPremium: false),
        SandTheme(id: .desert, nameKey: "Desert",
                  palette: [RGB(hex: 0xA65A2E), RGB(hex: 0xC47A44), RGB(hex: 0xD99A62), RGB(hex: 0xE8B585)], isPremium: false),
        SandTheme(id: .ocean, nameKey: "Ocean",
                  palette: [RGB(hex: 0x1E5F8C), RGB(hex: 0x2E86B5), RGB(hex: 0x58A9D3), RGB(hex: 0x9CD3EA), RGB(hex: 0xE8F4F8)], isPremium: false),
        SandTheme(id: .ember, nameKey: "Ember",
                  palette: [RGB(hex: 0x8C1C13), RGB(hex: 0xBF3B1E), RGB(hex: 0xE8662A), RGB(hex: 0xF59E3D), RGB(hex: 0xFFD166)], isPremium: false),
        SandTheme(id: .lavender, nameKey: "Lavender",
                  palette: [RGB(hex: 0x6B5B95), RGB(hex: 0x8E7CC3), RGB(hex: 0xB4A7D6), RGB(hex: 0xD9D2E9)], isPremium: false),
        SandTheme(id: .roseQuartz, nameKey: "Rose Quartz",
                  palette: [RGB(hex: 0xC97B8E), RGB(hex: 0xE3A1B0), RGB(hex: 0xF2C4CE), RGB(hex: 0xF9E0E6), RGB(hex: 0xD98E9F)], isPremium: true),
        SandTheme(id: .jade, nameKey: "Jade",
                  palette: [RGB(hex: 0x1F5E4A), RGB(hex: 0x2F8063), RGB(hex: 0x4FA383), RGB(hex: 0x86C5A8), RGB(hex: 0xC2E3D2)], isPremium: true),
    ]

    public static func theme(_ id: ID) -> SandTheme { all.first { $0.id == id } ?? all[0] }
    public static let `default` = theme(.goldenSand)

    /// Whether the user may use this theme.
    public func isUnlocked(isSupporter: Bool) -> Bool { !isPremium || isSupporter }
}
