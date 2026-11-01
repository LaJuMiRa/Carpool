import CarpoolKit
import CarpoolUI
import SwiftUI

/// Wiederholen: Wochentage und optionales Ende. Nur wöchentlich (siehe CLAUDE.md).
struct RepeatScreen: View {
    let model: ReservationModel

    /// Standard-Ende, wenn „Endet" eingeschaltet wird.
    private static let defaultWeeks = 8

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(spacing: 0) {
                    ForEach(Array(Weekday.allCases.enumerated()), id: \.element) { index, day in
                        if index > 0 { Hairline() }
                        dayRow(day)
                    }
                }
                .cardStyle(padding: Spacing.m)

                VStack(spacing: 0) {
                    Toggle("Endet", isOn: endsBinding)
                        .frame(minHeight: 48)
                    if let until = model.draft.repeatUntil {
                        Hairline()
                        DatePicker("Am", selection: Binding(get: { until }, set: { setUntil($0) }),
                                   in: model.draft.startsAt..., displayedComponents: .date)
                            .frame(minHeight: 48)
                    }
                }
                .font(.body)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, Spacing.m)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: ControlSize.hairline))
                .disabled(model.draft.repeatDays.isEmpty)

                Text("Belegte Termine werden übersprungen; du bekommst dann eine Nachricht.")
                    .metaStyle()
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, Spacing.m)
        }
        .background(Color.paper)
        .navigationTitle("Wiederholen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dayRow(_ day: Weekday) -> some View {
        let selected = model.draft.repeatDays.contains(day)
        return Button {
            let days = selected ? model.draft.repeatDays.subtracting([day]) : model.draft.repeatDays.union([day])
            model.setRepeat(days, until: model.draft.repeatUntil)
        } label: {
            HStack {
                Text("Jeden \(day.name)").font(.body).foregroundStyle(Color.ink)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.ink)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var endsBinding: Binding<Bool> {
        Binding(get: { model.draft.repeatUntil != nil }, set: { on in
            let calendar = model.text.calendar
            let until = on ? calendar.date(byAdding: .weekOfYear, value: Self.defaultWeeks,
                                           to: calendar.startOfDay(for: model.draft.startsAt)) : nil
            model.setRepeat(model.draft.repeatDays, until: until)
        })
    }

    private func setUntil(_ date: Date) {
        model.setRepeat(model.draft.repeatDays, until: model.text.calendar.startOfDay(for: date))
    }
}
