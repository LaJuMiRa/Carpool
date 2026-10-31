import CoreGraphics

/// Abstände 4 / 8 / 12 / 16 / 24 / 40 pt.
public enum Spacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 40

    /// Seitenrand.
    public static let page: CGFloat = l
    /// Innenabstand von Karten.
    public static let card: CGFloat = m
}

/// Eckenradien. Kapsel (Avatare, Chips) über `Capsule()`.
public enum Radius {
    /// Buchungsblöcke, Segmente.
    public static let small: CGFloat = 6
    /// Karten, Buttons.
    public static let card: CGFloat = 14
}

public enum ControlSize {
    /// Höhe von Primär- und Sekundär-Buttons.
    public static let buttonHeight: CGFloat = 50
    /// Kompakte Buttons in Zeilen („Nehmen").
    public static let compactButtonHeight: CGFloat = 40
    public static let hairline: CGFloat = 1
}
