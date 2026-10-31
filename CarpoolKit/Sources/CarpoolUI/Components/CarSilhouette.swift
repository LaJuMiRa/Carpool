import SwiftUI

/// Karosserieform für die neutrale Silhouette, bis ein Bildanbieter feststeht.
public enum CarBodyStyle: Sendable, CaseIterable {
    case sedan, hatchback, wagon

    private static let wagonHints = ["octavia", "passat", "variant", "kombi", "combi", "touring",
                                     "avant", "estate", "superb", "sportswagon", "cx-5", "x3", "suv"]
    private static let hatchbackHints = ["yaris", "polo", "fiesta", "corsa", "clio", "fabia", "up",
                                         "i10", "i20", "aygo", "twingo", "micra", "swift", "500", "panda"]

    /// Grobe Schätzung aus dem Modellnamen.
    public static func guess(model: String) -> CarBodyStyle {
        let words = model.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" })
            .map(String.init)
        if words.contains(where: wagonHints.contains) { return .wagon }
        if words.contains(where: hatchbackHints.contains) { return .hatchback }
        return .sedan
    }
}

/// Lackfarbe aus dem Freitext („silber", „dunkelgrau").
public enum PaintColor {
    private static let table: [(String, UInt32)] = [
        ("dunkelgrau", 0x4A4F55), ("anthrazit", 0x3A3D41), ("hellgrau", 0xB9BDC1),
        ("silber", 0xC9CED3), ("grau", 0x8A8F95), ("schwarz", 0x2B2D30), ("weiß", 0xEFEFEC),
        ("weiss", 0xEFEFEC), ("dunkelblau", 0x2F4A6E), ("blau", 0x5B7FA8), ("rot", 0xB5483F),
        ("grün", 0x4F7F5F), ("gruen", 0x4F7F5F), ("gelb", 0xD8B54A), ("beige", 0xCBBD9F),
        ("braun", 0x7A5C45), ("orange", 0xD9813F)
    ]
    private static let fallback: UInt32 = 0xB8BCC0

    /// RGB-Wert; längste passende Bezeichnung gewinnt („dunkelgrau" vor „grau").
    public static func rgb(for paint: String) -> UInt32 {
        let text = paint.lowercased()
        return table.first { text.contains($0.0) }?.1 ?? fallback
    }

    public static func color(for paint: String) -> Color {
        let value = rgb(for: paint)
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }

    /// Dunkle Lacke bekommen hellere Scheiben, damit die Form lesbar bleibt.
    static func isDark(_ paint: String) -> Bool {
        let value = rgb(for: paint)
        let luminance = 0.299 * Double((value >> 16) & 0xFF) + 0.587 * Double((value >> 8) & 0xFF)
            + 0.114 * Double(value & 0xFF)
        return luminance < 110
    }
}

/// Neutrale Seitenansicht eines Autos in Lackfarbe.
public struct CarSilhouette: View {
    private let style: CarBodyStyle
    private let paint: String

    public init(style: CarBodyStyle, paint: String) {
        self.style = style
        self.paint = paint
    }

    public init(model: String, paint: String) {
        self.init(style: .guess(model: model), paint: paint)
    }

    public var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 240, size.height / 90)
            let offset = CGPoint(x: (size.width - 240 * scale) / 2, y: (size.height - 90 * scale) / 2)
            context.translateBy(x: offset.x, y: offset.y)
            context.scaleBy(x: scale, y: scale)

            context.fill(Path(ellipseIn: CGRect(x: 14, y: 76, width: 212, height: 7)),
                         with: .color(.hairline))
            let body = CarShapes.body(style)
            context.fill(body, with: .color(PaintColor.color(for: paint)))
            if PaintColor.isDark(paint) {
                // Kontur, damit dunkle Lacke auf dunklem Grund lesbar bleiben.
                context.stroke(body, with: .color(.hairlineStrong), lineWidth: 1 / scale)
            }
            let glass = PaintColor.isDark(paint) ? Color(white: 0.62) : Color(white: 0.5).opacity(0.75)
            for window in CarShapes.windows(style) {
                context.fill(window, with: .color(glass))
            }
            for x in CarShapes.wheelCenters(style) {
                context.fill(Path(ellipseIn: CGRect(x: x - 13, y: 55, width: 26, height: 26)),
                             with: .color(Color(white: 0.13)))
                context.fill(Path(ellipseIn: CGRect(x: x - 6, y: 62, width: 12, height: 12)),
                             with: .color(Color(white: 0.6)))
            }
        }
        .aspectRatio(240 / 90, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Pfade in einem 240 × 90-Raster, Front links.
private enum CarShapes {
    static func body(_ style: CarBodyStyle) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 10, y: 66))
            p.addLine(to: CGPoint(x: 10, y: 52))
            p.addQuadCurve(to: CGPoint(x: 30, y: 41), control: CGPoint(x: 12, y: 42))
            p.addLine(to: CGPoint(x: 72, y: 37))
            switch style {
            case .sedan:
                p.addQuadCurve(to: CGPoint(x: 112, y: 13), control: CGPoint(x: 90, y: 15))
                p.addLine(to: CGPoint(x: 168, y: 13))
                p.addQuadCurve(to: CGPoint(x: 204, y: 37), control: CGPoint(x: 190, y: 15))
                p.addLine(to: CGPoint(x: 226, y: 40))
            case .hatchback:
                p.addQuadCurve(to: CGPoint(x: 108, y: 12), control: CGPoint(x: 88, y: 14))
                p.addLine(to: CGPoint(x: 174, y: 12))
                p.addQuadCurve(to: CGPoint(x: 212, y: 30), control: CGPoint(x: 204, y: 13))
                p.addLine(to: CGPoint(x: 216, y: 40))
            case .wagon:
                p.addQuadCurve(to: CGPoint(x: 110, y: 14), control: CGPoint(x: 88, y: 16))
                p.addLine(to: CGPoint(x: 214, y: 14))
                p.addQuadCurve(to: CGPoint(x: 226, y: 36), control: CGPoint(x: 224, y: 16))
                p.addLine(to: CGPoint(x: 227, y: 40))
            }
            let tail: CGFloat = style == .hatchback ? 220 : 232
            p.addQuadCurve(to: CGPoint(x: tail, y: 54), control: CGPoint(x: tail, y: 42))
            p.addLine(to: CGPoint(x: tail, y: 66))
            p.closeSubpath()
        }
    }

    static func windows(_ style: CarBodyStyle) -> [Path] {
        switch style {
        case .sedan:
            [polygon([(94, 35), (113, 18), (148, 18), (148, 35)]),
             polygon([(154, 35), (154, 18), (167, 18), (190, 35)])]
        case .hatchback:
            [polygon([(92, 35), (110, 17), (144, 17), (144, 35)]),
             polygon([(150, 35), (150, 17), (172, 17), (198, 35)])]
        case .wagon:
            [polygon([(92, 35), (111, 19), (146, 19), (146, 35)]),
             polygon([(152, 35), (152, 19), (186, 19), (186, 35)]),
             polygon([(192, 35), (192, 19), (210, 19), (216, 35)])]
        }
    }

    static func wheelCenters(_ style: CarBodyStyle) -> [CGFloat] {
        style == .hatchback ? [56, 184] : [60, 194]
    }

    private static func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        Path { p in
            p.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
            p.closeSubpath()
        }
    }
}
