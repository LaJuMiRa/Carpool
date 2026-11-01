import Foundation

/// Eingaben für „Auto hinzufügen" (F17) und „Auto bearbeiten". Unveränderlich.
/// Ein Feld „Marke und Modell" wird in Marke und Modell geteilt (bekannte Marken auch mit Leerzeichen).
public struct CarForm: Sendable, Equatable {
    /// Lackfarben zur Auswahl (Freitext in `cars.paint`).
    public static let paints = ["schwarz", "weiß", "silber", "blau", "rot", "grau", "grün"]

    /// Marken aus mehreren Wörtern bzw. mit üblichen Schreibweisen.
    static let multiWordMakes = ["Land Rover", "Alfa Romeo", "Aston Martin", "Rolls Royce", "Mercedes Benz"]

    public var name: String
    public var paint: String
    public var nickname: String
    public var plate: String
    public var primaryMemberId: UUID?
    public var pickerlUntil: Date?
    public var serviceDue: Date?
    public var odometerKm: Int?

    public init(name: String = "", paint: String = CarForm.paints[0], nickname: String = "", plate: String = "",
                primaryMemberId: UUID? = nil, pickerlUntil: Date? = nil, serviceDue: Date? = nil,
                odometerKm: Int? = nil) {
        self.name = name
        self.paint = paint
        self.nickname = nickname
        self.plate = plate
        self.primaryMemberId = primaryMemberId
        self.pickerlUntil = pickerlUntil
        self.serviceDue = serviceDue
        self.odometerKm = odometerKm
    }

    /// Vorbelegung zum Bearbeiten.
    public init(car: Car, calendar: Calendar) {
        self.init(name: "\(car.make) \(car.model)", paint: car.paint, nickname: car.nickname ?? "",
                  plate: car.plate ?? "", primaryMemberId: car.primaryMemberId,
                  pickerlUntil: car.pickerlUntil.flatMap { CarDetailState.day(from: $0, calendar: calendar) },
                  serviceDue: car.serviceDue.flatMap { CarDetailState.day(from: $0, calendar: calendar) },
                  odometerKm: car.odometerKm)
    }

    /// Marke und Modell aus dem Eingabefeld: „VW Golf" → („VW", „Golf"), „Land Rover Defender" → („Land Rover", „Defender").
    public var makeAndModel: (make: String, model: String)? {
        let text = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        if let make = Self.multiWordMakes.first(where: { text.lowercased().hasPrefix($0.lowercased() + " ") }) {
            let model = String(text.dropFirst(make.count)).trimmingCharacters(in: .whitespaces)
            return (String(text.prefix(make.count)), model)
        }
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    /// Modell für die Vorschau-Silhouette, auch wenn erst ein Wort getippt ist.
    public var previewModel: String { makeAndModel?.model ?? name }

    /// Hinweis unter dem Feld, solange nur ein Wort da ist.
    public var nameHint: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty || makeAndModel != nil { return nil }
        return "Marke und Modell, z. B. „VW Golf“"
    }

    public func input(calendar: Calendar) -> CarInput? {
        guard let parts = makeAndModel else { return nil }
        let input = CarInput(make: parts.make, model: parts.model, paint: paint, nickname: nickname, plate: plate,
                             primaryMemberId: primaryMemberId,
                             pickerlUntil: pickerlUntil.map { CarDetailState.string(from: $0, calendar: calendar) },
                             serviceDue: serviceDue.map { CarDetailState.string(from: $0, calendar: calendar) },
                             odometerKm: odometerKm)
        return input.isValid ? input : nil
    }
}
