import CarpoolKit
import SwiftUI

/// Zeile in „Andere Autos": Bild, Name, Status, eine Zeile Kontext, optional Aktion.
public struct CarRow<Action: View>: View {
    private let naming: CarNaming
    private let paint: String
    private let status: CarStatus
    private let detail: String?
    private let hasOpenDamage: Bool
    private let action: Action

    public init(naming: CarNaming, paint: String, status: CarStatus, detail: String? = nil,
                hasOpenDamage: Bool = false, @ViewBuilder action: () -> Action) {
        self.naming = naming
        self.paint = paint
        self.status = status
        self.detail = detail
        self.hasOpenDamage = hasOpenDamage
        self.action = action()
    }

    public var body: some View {
        HStack(spacing: Spacing.m) {
            CarSilhouette(model: naming.model, paint: paint)
                .frame(width: 84)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(naming.title).font(.headline).foregroundStyle(Color.ink)
                    if hasOpenDamage {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.danger)
                            .accessibilityLabel("offener Schaden")
                    }
                }
                StatusLabel(status)
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(Color.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
            action
        }
        .padding(.vertical, Spacing.s)
    }

    private var accessibilityText: String {
        [naming.spokenName, status.label, hasOpenDamage ? "offener Schaden" : nil, detail]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

public extension CarRow where Action == EmptyView {
    init(naming: CarNaming, paint: String, status: CarStatus, detail: String? = nil,
         hasOpenDamage: Bool = false) {
        self.init(naming: naming, paint: paint, status: status, detail: detail,
                  hasOpenDamage: hasOpenDamage) { EmptyView() }
    }
}

/// Kachel zur Autoauswahl im Reservieren-Formular (bis ca. 3 Autos).
public struct CarTile: View {
    private let naming: CarNaming
    private let paint: String
    private let status: CarStatus
    private let statusText: String?
    private let isSelected: Bool
    private let action: () -> Void

    public init(naming: CarNaming, paint: String, status: CarStatus, statusText: String? = nil,
                isSelected: Bool, action: @escaping () -> Void) {
        self.naming = naming
        self.paint = paint
        self.status = status
        self.statusText = statusText
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                CarSilhouette(model: naming.model, paint: paint)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Spacing.xxs)
                Text(naming.title).font(.headline).foregroundStyle(Color.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                StatusLabel(status, text: statusText)
            }
            .padding(Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(isSelected ? Color.ink : Color.hairline, lineWidth: isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(Motion.gesture, value: isSelected)
        .accessibilityLabel("\(naming.spokenName), \(statusText ?? status.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Auswahlzeile bei vielen Autos (F13): Bild, Name, Tankstand, Auswahlkreis.
public struct CarSelectRow: View {
    private let naming: CarNaming
    private let paint: String
    private let fuel: FuelLevel
    private let isSelected: Bool
    private let action: () -> Void

    public init(naming: CarNaming, paint: String, fuel: FuelLevel, isSelected: Bool,
                action: @escaping () -> Void) {
        self.naming = naming
        self.paint = paint
        self.fuel = fuel
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.m) {
                CarSilhouette(model: naming.model, paint: paint).frame(width: 64)
                CarTitle(naming)
                    .frame(maxWidth: .infinity, alignment: .leading)
                FuelGauge(fuel, style: .dots)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.ink : Color.hairlineStrong)
            }
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(naming.spokenName), Tank \(fuel.spokenLabel)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
