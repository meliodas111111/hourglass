import Foundation

/// The two glass chambers. The grid is fixed: `.upper` is rows `0..<gateRow`, `.lower` is `gateRow..<height`
/// in *grid* coordinates. Which one is currently "on top" in the real world is decided by gravity, and which one
/// is currently *draining* is decided by the timer (see `SandSimulation.sourceChamber`).
public enum Chamber: String, Codable, Sendable {
    case upper, lower
    public var opposite: Chamber { self == .upper ? .lower : .upper }
}

/// Simulation resolution presets ("Sand density" setting).
public enum SandDensity: String, Codable, CaseIterable, Sendable {
    case performance, balanced, quality

    /// Grid size (width × height). Always 1 : 2 so the hourglass silhouette keeps its proportions;
    /// the renderer scales the grid to the screen.
    public var gridSize: (width: Int, height: Int) {
        switch self {
        case .performance: return (212, 424)
        case .balanced:    return (240, 480)
        case .quality:     return (300, 600)
        }
    }

    /// Target number of grains. Clamped by the chamber capacity in `SandSimulation`.
    public var targetGrains: Int {
        switch self {
        case .performance: return 15_000
        case .balanced:    return 22_000
        case .quality:     return 36_000
        }
    }
}

/// Hourglass silhouette defined as a signed distance field (SDF) over the simulation grid.
///
/// * negative SDF → glass interior (sand may live here)
/// * positive SDF → wall / outside
///
/// The SDF is also uploaded to the GPU once and used to shade the glass (rim light, Fresnel, highlights).
public final class HourglassGeometry: @unchecked Sendable {

    public let width: Int
    public let height: Int
    /// Width of the narrow neck in cells (2–3 per spec).
    public let neckCells: Int
    /// First row that belongs to the lower chamber. The neck is centred on this row.
    public let gateRow: Int
    /// Half-height of the straight neck channel, in rows.
    public let neckHalfRows: Int
    /// Rows occupied by the wooden caps (top and bottom). Glass interior lies between them.
    public let capRows: Int
    /// Horizontal centre of the silhouette (in cell units, cell `x` spans `x…x+1`).
    public let centerX: Double
    public let maxHalfWidth: Double

    /// Signed distance per cell (row-major), in cell units.
    public private(set) var sdf: [Float]
    /// 1 where the cell is wall/outside, 0 where it is glass interior.
    public private(set) var wallMask: [UInt8]
    /// Number of interior cells in each chamber.
    public private(set) var upperCapacity = 0
    public private(set) var lowerCapacity = 0

    public init(width: Int, height: Int, neckCells: Int = 3) {
        precondition(width >= 40 && height >= 80, "grid too small")
        let neck = clamp(neckCells, 2, 3)
        // The silhouette must be point-symmetric so a 180° rotation of the cell arrays (button flip) maps walls
        // onto walls: width parity must match neck parity, height must be even.
        self.width = (width % 2) == (neck % 2) ? width : width + 1
        self.height = height + (height % 2)
        self.neckCells = neck
        self.gateRow = self.height / 2
        self.neckHalfRows = max(2, self.height / 120)
        self.capRows = max(3, self.height / 36)
        self.centerX = Double(self.width) / 2
        self.maxHalfWidth = Double(width) * 0.44
        self.sdf = []
        self.wallMask = []
        build()
    }

    public convenience init(density: SandDensity) {
        let s = density.gridSize
        self.init(width: s.width, height: s.height)
    }

    // MARK: Profile

    /// Bulb profile `s(u)` in 0…1 where `u` is the normalised distance from the neck to the cap.
    ///
    /// Up to `u = 0.85` the wall is a sine-shaped funnel whose slope stays **steeper than 45°**
    /// (`dw/dy < 1`) so a draining chamber always empties completely — grains never get stuck on a
    /// shallow shoulder. After that it rounds off into the shoulder that meets the cap.
    @inline(__always)
    public static func profile(_ u: Double) -> Double {
        let u0 = 0.85
        if u <= u0 { return sin(Double.pi / 2 * u / u0) }
        let t = (u - u0) / (1 - u0)
        return 1 - 0.22 * t * t
    }

    /// Inner half-width of the glass at (continuous) row coordinate `yc`.
    public func halfWidth(atY yc: Double) -> Double {
        let neckHalf = Double(neckCells) / 2
        let d = abs(yc - Double(gateRow))
        if d <= Double(neckHalfRows) { return neckHalf }
        let bulbExtent = Double(gateRow - capRows - neckHalfRows)
        let u = clamp((d - Double(neckHalfRows)) / bulbExtent, 0, 1)
        return neckHalf + (maxHalfWidth - neckHalf) * Self.profile(u)
    }

    private func build() {
        var sdf = [Float](repeating: 0, count: width * height)
        var mask = [UInt8](repeating: 1, count: width * height)
        let topLimit = Double(capRows)
        let bottomLimit = Double(height - capRows)
        var upper = 0, lower = 0

        for y in 0..<height {
            let yc = Double(y) + 0.5
            let hw = halfWidth(atY: yc)
            // Derivative of the profile → convert horizontal distance into (approximate) Euclidean distance.
            let slope = (halfWidth(atY: yc + 0.5) - halfWidth(atY: yc - 0.5))
            let norm = 1 / (1 + slope * slope).squareRoot()
            for x in 0..<width {
                let xc = Double(x) + 0.5
                var d = (abs(xc - centerX) - hw) * norm
                d = max(d, topLimit - yc, yc - bottomLimit)       // caps
                let i = y * width + x
                sdf[i] = Float(d)
                if d < 0 {
                    mask[i] = 0
                    if y < gateRow { upper += 1 } else { lower += 1 }
                }
            }
        }
        self.sdf = sdf
        self.wallMask = mask
        self.upperCapacity = upper
        self.lowerCapacity = lower
    }

    /// Resolution-independent silhouette for vector renderers (widgets, Reduce Motion, theme previews).
    /// - Parameter v: vertical position 0 (top cap) … 1 (bottom cap) of the *glass* region.
    /// - Returns: inner half-width as a fraction of the total width.
    public static func normalizedHalfWidth(atV v: Double) -> Double {
        let neckHalf = 0.0075, maxHalf = 0.44, neckRows = 0.008
        let d = abs(v - 0.5)
        if d <= neckRows { return neckHalf }
        let u = clamp((d - neckRows) / (0.5 - neckRows), 0, 1)
        return neckHalf + (maxHalf - neckHalf) * profile(u)
    }

    // MARK: Helpers

    @inline(__always) public func index(_ x: Int, _ y: Int) -> Int { y * width + x }

    @inline(__always) public func chamber(ofRow y: Int) -> Chamber { y < gateRow ? .upper : .lower }

    @inline(__always) public func isInterior(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height && wallMask[y * width + x] == 0
    }

    /// Row range of the straight neck channel.
    public var neckRows: ClosedRange<Int> { (gateRow - neckHalfRows)...(gateRow + neckHalfRows - 1) }

    /// Neck centre in grid coordinates.
    public var neckCenter: Vec2 { Vec2(centerX, Double(gateRow)) }

    /// First row *outside* the neck on the side of `chamber` — where grains emerge into that chamber.
    public func neckExitRow(into chamber: Chamber) -> Int {
        chamber == .lower ? gateRow + neckHalfRows : gateRow - neckHalfRows - 1
    }

    /// Normalised level helper for the reduced-motion / widget renderers: rows of `chamber` sorted from
    /// the cap towards the neck, with the interior-cell count per row.
    public func rowCapacities(of chamber: Chamber) -> [(row: Int, cells: Int)] {
        let rows: [Int] = chamber == .lower ? Array((gateRow..<height).reversed()) : Array(0..<gateRow)
        return rows.map { y in
            var c = 0
            for x in 0..<width where wallMask[y * width + x] == 0 { c += 1 }
            return (y, c)
        }
    }
}
