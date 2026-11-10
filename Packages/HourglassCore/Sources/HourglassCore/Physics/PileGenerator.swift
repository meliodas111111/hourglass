import Foundation

/// Procedurally generates *settled* sand piles for a chamber.
///
/// Used when the app launches or returns from background: instead of persisting tens of thousands of cells we
/// recreate a plausible resting state from just two numbers (grains in each chamber) and the current gravity.
///
/// Each interior cell gets a priority key — how far "downhill" it is along gravity — plus a term that shapes
/// the surface:
/// * gravity pointing **away from the neck** (sand rests on the cap): a cone under the neck, ~32° slope;
/// * gravity pointing **towards the neck** (draining chamber): a shallow crater/funnel above the neck.
/// The `n` highest-priority cells are filled. A little jitter breaks up the otherwise perfect surface.
public struct PileGenerator {
    public let geometry: HourglassGeometry

    public init(geometry: HourglassGeometry) { self.geometry = geometry }

    /// Indices of the cells that a settled pile of `count` grains occupies.
    public func settledCells(in chamber: Chamber, count: Int, gravity: Vec2, rng: inout FastRandom) -> [Int] {
        guard count > 0 else { return [] }
        let g = gravity.normalized.length > 0 ? gravity.normalized : Vec2.down
        let perp = Vec2(-g.y, g.x)
        let neck = geometry.neckCenter
        let w = geometry.width
        let rows = chamber == .upper ? 0..<geometry.gateRow : geometry.gateRow..<geometry.height

        // Direction from the chamber towards the neck.
        let towardNeck = chamber == .upper ? Vec2.down : -Vec2.down
        let drainsIntoNeck = towardNeck.dot(g) > 0
        let axialness = abs(g.y)
        let slope = drainsIntoNeck ? 0.40 : -0.62      // crater (+) or cone (−); tan(~32°) ≈ 0.62

        var keyed: [(key: Double, idx: Int)] = []
        keyed.reserveCapacity(rows.count * w / 2)
        for y in rows {
            for x in 0..<w where geometry.wallMask[y * w + x] == 0 {
                let p = Vec2(Double(x) + 0.5, Double(y) + 0.5)
                let rel = p - neck
                let downhill = rel.dot(g)
                let lateral = abs(rel.dot(perp))
                let jitter = (rng.unit() - 0.5) * 1.2
                keyed.append((downhill + slope * lateral * axialness + jitter, y * w + x))
            }
        }
        let n = min(count, keyed.count)
        // Partial selection is enough, but a full sort of ≤ 90k items happens once per restore — fine.
        keyed.sort { $0.key > $1.key }
        return keyed.prefix(n).map(\.idx)
    }
}
