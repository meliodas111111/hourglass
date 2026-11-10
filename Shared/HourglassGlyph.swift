import SwiftUI
import HourglassCore

extension RGB {
    var color: Color { Color(red: r, green: g, blue: b) }
}

extension SandTheme {
    /// Representative colour for UI accents / gradients.
    var accent: Color { palette[palette.count / 2].color }
    var gradient: LinearGradient {
        LinearGradient(colors: palette.map(\.color), startPoint: .top, endPoint: .bottom)
    }
}

/// Glass silhouette as a SwiftUI `Shape`, sampled from the same profile the physics uses.
struct HourglassSilhouette: Shape {
    /// Fraction of the height taken by each cap.
    var capFraction: CGFloat = 0.05

    func path(in rect: CGRect) -> Path {
        let samples = 96
        let top = rect.minY + rect.height * capFraction
        let glassHeight = rect.height * (1 - 2 * capFraction)
        var right: [CGPoint] = []
        for i in 0...samples {
            let v = Double(i) / Double(samples)
            let hw = HourglassGeometry.normalizedHalfWidth(atV: v) * rect.width
            right.append(CGPoint(x: rect.midX + hw, y: top + glassHeight * v))
        }
        var p = Path()
        p.move(to: right[0])
        right.dropFirst().forEach { p.addLine(to: $0) }
        right.reversed().forEach { p.addLine(to: CGPoint(x: 2 * rect.midX - $0.x, y: $0.y)) }
        p.closeSubpath()
        return p
    }
}

/// Region of one chamber filled with sand, for static / reduced-motion rendering.
///
/// The top pile shrinks towards the neck, the bottom pile grows from the cap, with volumes proportional to the
/// silhouette area (so the level looks right, not linear in height).
struct SandFillShape: Shape {
    enum Part { case top, bottom }
    var part: Part
    /// 0 … 1 of the full sand volume that sits in this chamber.
    var amount: Double
    var capFraction: CGFloat = 0.05
    /// Sand volume relative to a chamber (matches `SandSimulation`'s 62 %).
    var fillRatio = 0.62

    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let samples = 64
        let top = rect.minY + rect.height * capFraction
        let glassHeight = rect.height * (1 - 2 * capFraction)
        // v ranges over one chamber: top → [0, 0.5], bottom → [0.5, 1]; integrate area from the "floor".
        let vs: [Double] = (0...samples).map { i in
            let t = Double(i) / Double(samples)
            return part == .top ? 0.5 - 0.5 * t : 1 - 0.5 * t     // from neck upward / from cap upward
        }
        var cumulative: [Double] = [0]
        for i in 1..<vs.count {
            let w = HourglassGeometry.normalizedHalfWidth(atV: (vs[i] + vs[i - 1]) / 2)
            cumulative.append(cumulative[i - 1] + w * abs(vs[i] - vs[i - 1]))
        }
        let target = cumulative.last! * fillRatio * min(max(amount, 0), 1)
        guard target > 0 else { return Path() }
        let k = cumulative.firstIndex { $0 >= target } ?? vs.count - 1

        var p = Path()
        let pts = (0...k).map { i -> (CGFloat, CGFloat) in
            let v = vs[i]
            return (CGFloat(HourglassGeometry.normalizedHalfWidth(atV: v)) * rect.width, top + glassHeight * CGFloat(v))
        }
        p.move(to: CGPoint(x: rect.midX - pts[0].0, y: pts[0].1))
        for pt in pts { p.addLine(to: CGPoint(x: rect.midX - pt.0, y: pt.1)) }
        if part == .bottom {
            // Little cone on top of the bottom pile.
            let surfaceY = pts[k].1
            p.addLine(to: CGPoint(x: rect.midX, y: surfaceY - min(rect.height * 0.04, glassHeight * 0.03 * CGFloat(amount * 2))))
        }
        for pt in pts.reversed() { p.addLine(to: CGPoint(x: rect.midX + pt.0, y: pt.1)) }
        p.closeSubpath()
        return p
    }
}

/// Vector hourglass: used by widgets, Live Activity, theme previews and the Reduce Motion mode.
struct HourglassGlyph: View {
    /// 0 → all sand on top, 1 → all at the bottom.
    var progress: Double
    var theme: SandTheme
    var showsStream = true

    static let wood = LinearGradient(colors: [Color(red: 0.55, green: 0.36, blue: 0.2), Color(red: 0.36, green: 0.22, blue: 0.12)],
                                     startPoint: .top, endPoint: .bottom)

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            ZStack {
                HourglassSilhouette().fill(Color.white.opacity(0.08))
                SandFillShape(part: .top, amount: 1 - progress).fill(theme.gradient)
                SandFillShape(part: .bottom, amount: progress).fill(theme.gradient)
                if showsStream && progress > 0 && progress < 1 {
                    Rectangle()
                        .fill(theme.accent)
                        .frame(width: max(1, rect.width * 0.015), height: rect.height * 0.22)
                        .position(x: rect.midX, y: rect.midY + rect.height * 0.11)
                }
                HourglassSilhouette().stroke(Color.white.opacity(0.55), lineWidth: max(1, rect.width * 0.012))
                // Caps.
                VStack {
                    Capsule().fill(Self.wood).frame(height: rect.height * 0.05)
                    Spacer()
                    Capsule().fill(Self.wood).frame(height: rect.height * 0.05)
                }
            }
        }
        .aspectRatio(0.5, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
