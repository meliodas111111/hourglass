import SwiftUI
import HourglassCore

/// Hours / minutes / seconds wheels + quick presets. Enforces 5 s … 24 h.
struct DurationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int
    let onDone: (TimeInterval) -> Void

    static let presets: [TimeInterval] = [30, 60, 3 * 60, 5 * 60, 10 * 60, 15 * 60, 25 * 60, 30 * 60, 45 * 60, 60 * 60]

    init(initial: TimeInterval, onDone: @escaping (TimeInterval) -> Void) {
        let s = Int(DurationLimits.clamp(initial))
        _hours = State(initialValue: s / 3600)
        _minutes = State(initialValue: (s % 3600) / 60)
        _seconds = State(initialValue: s % 60)
        self.onDone = onDone
    }

    private var total: TimeInterval { TimeInterval(hours * 3600 + minutes * 60 + seconds) }
    private var isValid: Bool { total >= DurationLimits.minimum && total <= DurationLimits.maximum }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                HStack(spacing: 0) {
                    wheel($hours, range: 0...24, unit: "h")
                    wheel($minutes, range: 0...59, unit: "min")
                    wheel($seconds, range: 0...59, unit: "s")
                }
                .frame(height: 200)
                .onChange(of: hours) { h in if h == 24 { minutes = 0; seconds = 0 } }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Self.presets, id: \.self) { p in
                            Button(DurationFormatter.string(p)) { set(p) }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("preset-\(Int(p))")
                        }
                    }
                    .padding(.horizontal)
                }

                if !isValid {
                    Text("Choose between 5 seconds and 24 hours.")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Spacer()
            }
            .padding(.top)
            .navigationTitle(Text("Duration"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") { onDone(total); dismiss() }
                        .disabled(!isValid)
                        .accessibilityIdentifier("setDuration")
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func set(_ p: TimeInterval) {
        let s = Int(p)
        hours = s / 3600; minutes = (s % 3600) / 60; seconds = s % 60
    }

    private func wheel(_ value: Binding<Int>, range: ClosedRange<Int>, unit: LocalizedStringKey) -> some View {
        HStack(spacing: 2) {
            Picker(selection: value) {
                ForEach(range, id: \.self) { Text(verbatim: "\($0)").tag($0) }
            } label: { Text(unit) }
            .pickerStyle(.wheel)
            .frame(maxWidth: 80)
            .clipped()
            Text(unit).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
