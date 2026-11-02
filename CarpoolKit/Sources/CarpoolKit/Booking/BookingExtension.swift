import Foundation

/// Kontextmenü F11 „Verlängern" und „An jemand übergeben". Regeln stehen auch in CLAUDE.md.
public enum BookingExtension {
    public struct Option: Sendable, Equatable, Identifiable {
        /// „Bis 19:30"
        public let title: String
        public let endsAt: Date

        public var id: Date { endsAt }
    }

    /// Schritte ab dem bisherigen Ende.
    static let steps: [TimeInterval] = [30 * 60, 60 * 60, 2 * 60 * 60]

    /// Reservierung: ab ihrem Ende. Laufende Fahrt: ab dem geplanten Ende, ohne Plan ab jetzt
    /// (auf 5 min aufgerundet).
    public static func options(for booking: Booking, now: Date, text: TimeText) -> [Option] {
        let base: Date
        if booking.kind == .reservation, let endsAt = booking.endsAt {
            base = endsAt
        } else {
            base = ReservationDraft.roundedUp(max(booking.plannedEndsAt ?? now, now), calendar: text.calendar)
        }
        return steps.map { step in
            let end = base.addingTimeInterval(step)
            return Option(title: "Bis \(text.time(end))", endsAt: end)
        }
    }

    /// An wen man eine Reservierung übergeben kann: alle anderen, nicht entfernten Mitglieder.
    public static func transferTargets(in snapshot: FamilySnapshot) -> [Member] {
        snapshot.activeMembers.filter { $0.id != snapshot.me.id }
    }
}
