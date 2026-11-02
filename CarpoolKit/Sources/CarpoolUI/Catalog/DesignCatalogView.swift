import CarpoolKit
import SwiftUI

/// Vorschau-Seite mit allen Bausteinen des Design Systems.
public struct DesignCatalogView: View {
    @State private var fuel = FuelLevel(quarters: 2)
    @State private var chip = "Morgen"
    @State private var selectedTile = 1
    @State private var selectedRow = 0
    @State private var splashRun = 0

    private let radieschen = CarNaming(make: "VW", model: "Golf", nickname: "Radieschen")
    private let octavia = CarNaming(make: "Škoda", model: "Octavia", nickname: nil)
    private let flitzer = CarNaming(make: "Toyota", model: "Yaris", nickname: "Flitzer")

    private let initialSection: String?

    /// - Parameter initialSection: Abschnitt, zu dem beim Öffnen gesprungen wird
    ///   (Überschrift, z. B. „Autos").
    public init(initialSection: String? = nil) {
        self.initialSection = initialSection
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    Text("Bausteine").screenTitleStyle()
                    colors
                    typography
                    buttons
                    statusAndAvatars
                    cars
                    booking
                    fuelSection
                    cardSection
                    splashSection
                }
                .padding(.horizontal, Spacing.page)
                .padding(.vertical, Spacing.l)
            }
            .background(Color.paper)
            .onAppear {
                if let initialSection { proxy.scrollTo(initialSection, anchor: .top) }
            }
        }
    }

    // MARK: Abschnitte

    private var colors: some View {
        CatalogSection("Farben") {
            let tokens: [(String, Color)] = [
                ("paper", .paper), ("surface", .surface), ("ink", .ink), ("ink-secondary", .inkSecondary),
                ("ink-muted", .inkMuted), ("hairline", .hairline), ("hairline-strong", .hairlineStrong),
                ("status-free", .statusFree), ("status-reserved", .statusReserved),
                ("status-busy", .statusBusy), ("danger", .danger)
            ]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Spacing.s)], spacing: Spacing.s) {
                ForEach(tokens, id: \.0) { name, color in
                    Swatch(name: name, color: color)
                }
                ForEach(1...CarColor.setCount, id: \.self) { slot in
                    let car = CarColor(slot: slot)
                    Swatch(name: "car-\(slot)", color: car.base)
                    Swatch(name: "car-\(slot)-tint", color: car.tint)
                    Swatch(name: "car-\(slot)-ink", color: car.ink)
                }
            }
        }
    }

    private var typography: some View {
        CatalogSection("Schrift") {
            Text("1 von 3 frei").screenTitleStyle()
            Text("Radieschen zurückgeben").sheetTitleStyle()
            Text("Jonas braucht ihn ab 18:00").font(.headline).foregroundStyle(Color.ink)
            Text("Fließtext in body").font(.body).foregroundStyle(Color.ink)
            Text("Sekundär in callout").font(.callout).foregroundStyle(Color.inkSecondary)
            Text("Label in caption").metaStyle()
            Text("K7P-2QX").font(.title3.monospaced().weight(.semibold)).foregroundStyle(Color.ink)
        }
    }

    private var buttons: some View {
        CatalogSection("Buttons") {
            Button("Zurückgeben") {}.buttonStyle(.carpoolPrimary)
            Button("Octavia ist belegt") {}.buttonStyle(.carpoolPrimary).disabled(true)
            Button("Reservieren") {}.buttonStyle(.carpoolSecondary)
            Button("Übernehmen") {}.buttonStyle(.carpoolDestructive)
            HStack {
                Button("Nehmen") {}.buttonStyle(.carpoolCompact)
                Spacer()
                Button {} label: { Image(systemName: "xmark") }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .accessibilityLabel("Schließen")
                Button {} label: { Image(systemName: "plus") }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(Color.ink)
                    .accessibilityLabel("Reservieren")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(["Jetzt", "Heute Abend", "Morgen", "…"], id: \.self) { title in
                        Chip(title, isSelected: chip == title) { chip = title }
                    }
                }
            }
        }
    }

    private var statusAndAvatars: some View {
        CatalogSection("Status und Avatare") {
            HStack(spacing: Spacing.l) {
                ForEach(CarStatus.allCases, id: \.self) { StatusLabel($0) }
            }
            StatusLabel(.busy, text: "bei dir")
            HStack(spacing: Spacing.s) {
                Avatar(short: "Pa", size: .large)
                Avatar(short: "Ma")
                Avatar(short: "Li", size: .small)
                ForEach(1...3, id: \.self) { CarDot(CarColor(slot: $0)) }
            }
        }
    }

    private var cars: some View {
        CatalogSection("Autos") {
            HStack(spacing: Spacing.m) {
                ForEach(CarBodyStyle.allCases, id: \.self) { style in
                    CarSilhouette(style: style, paint: style == .wagon ? "dunkelgrau" : "silber")
                }
            }
            CarTitle(radieschen, size: .large)
            CarDetailTitle(radieschen)
            CarDetailTitle(octavia)
            VStack(spacing: 0) {
                CarRow(naming: octavia, paint: "dunkelgrau", status: .busy, detail: "Mama, zurück um 17:30")
                Hairline()
                CarRow(naming: flitzer, paint: "blau", status: .free, detail: "Frei bis 14:00, dann Felix",
                       hasOpenDamage: true) {
                    Button("Nehmen") {}.buttonStyle(.carpoolCompact)
                }
            }
            HStack(spacing: Spacing.xs) {
                CarTile(naming: radieschen, paint: "silber", status: .free, isSelected: selectedTile == 0) {
                    selectedTile = 0
                }
                CarTile(naming: octavia, paint: "dunkelgrau", status: .reserved, statusText: "belegt",
                        isSelected: selectedTile == 1) { selectedTile = 1 }
                CarTile(naming: flitzer, paint: "blau", status: .free, isSelected: selectedTile == 2) {
                    selectedTile = 2
                }
            }
            VStack(spacing: 0) {
                CarSelectRow(naming: radieschen, paint: "silber", fuel: FuelLevel(quarters: 3),
                             isSelected: selectedRow == 0) { selectedRow = 0 }
                Hairline()
                CarSelectRow(naming: CarNaming(make: "BMW", model: "X3", nickname: nil), paint: "schwarz",
                             fuel: FuelLevel(quarters: 2), isSelected: selectedRow == 1) { selectedRow = 1 }
            }
            .cardStyle(padding: Spacing.s)
        }
    }

    private var booking: some View {
        CatalogSection("Buchungen und Hinweise") {
            BookingBlock(time: "08:00–17:30", carName: "Octavia", personShort: "Ma",
                         color: CarColor(slot: 2), marker: .driving)
            BookingBlock(time: "seit 09:12", carName: "Radieschen", personShort: "Li",
                         color: CarColor(slot: 1), marker: .driving)
            BookingBlock(time: "14:00–19:00", carName: "Flitzer", personShort: "Fe", color: CarColor(slot: 3))
            BookingBlock(time: "Mo–Do, 07:00–17:00", carName: "Radieschen", personShort: "Pa",
                         personName: "Papa, jede Woche", color: CarColor(slot: 1), marker: .repeating)
            InfoBanner(personShort: "Jo", text: "Jonas braucht ihn ab 18:00", color: CarColor(slot: 1))
            InfoBanner(personShort: "Fe", text: "Felix hat Octavia von 10:00 bis 16:00.",
                       background: CarColor(slot: 2).tint, foreground: CarColor(slot: 2).ink) {
                HStack(spacing: Spacing.xs) {
                    Button {} label: { Label { Text("Radieschen") } icon: { CarDot(CarColor(slot: 1)) } }
                        .buttonStyle(.carpoolSecondary)
                    Button {} label: { Label { Text("Flitzer") } icon: { CarDot(CarColor(slot: 3)) } }
                        .buttonStyle(.carpoolSecondary)
                }
            }
        }
    }

    private var fuelSection: some View {
        CatalogSection("Tank") {
            FuelPicker(level: $fuel)
            FuelGauge(FuelLevel(quarters: 3))
            FuelGauge(FuelLevel(quarters: 1), style: .dots)
        }
    }

    private var cardSection: some View {
        CatalogSection("Karten") {
            SectionHeader("Zustand")
            VStack(spacing: 0) {
                PropertyRow("Tank") { FuelGauge(FuelLevel(quarters: 3)) }
                Hairline()
                PropertyRow("Pickerl", value: "bis März 2027")
                Hairline()
                PropertyRow("Service") { Text("in 3 Wochen").foregroundStyle(Color.statusReserved) }
                Hairline()
                PropertyRow("Kennzeichen", value: "BN-123AB")
            }
            .cardStyle(padding: Spacing.m)
            SectionHeader("Schäden") {
                Button("Melden") {}.font(.headline).foregroundStyle(Color.ink)
            }
        }
    }
}

extension DesignCatalogView {
    /// Splash (F01) verkleinert; „Abspielen" startet den Ablauf neu.
    var splashSection: some View {
        CatalogSection("Splash") {
            SplashView(hold: 3600) {}
                .id(splashRun)
                .allowsHitTesting(false)
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Color.hairline))
            Button("Abspielen") { splashRun += 1 }.buttonStyle(.carpoolSecondary)
            SectionHeader("App-Icon")
            HStack(spacing: Spacing.m) {
                AppIconArtwork().scaleEffect(96 / AppIconArtwork.side).frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.hairline))
                AppIconArtwork().environment(\.colorScheme, .dark)
                    .scaleEffect(96 / AppIconArtwork.side).frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            }
        }
    }
}

// MARK: Hilfen

private struct CatalogSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title)
            content
        }
        .id(title)
    }
}

private struct Swatch: View {
    let name: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(color)
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: ControlSize.hairline))
            Text(name).font(.caption2).foregroundStyle(Color.inkMuted).lineLimit(1)
        }
    }
}

#Preview("Hell") {
    DesignCatalogView()
}

#Preview("Dunkel") {
    DesignCatalogView().preferredColorScheme(.dark)
}
