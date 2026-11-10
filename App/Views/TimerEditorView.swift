import SwiftUI
import HourglassCore

/// Editor for a saved timer or multi-phase sequence.
struct TimerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreService
    @State private var timer: SavedTimer
    @State private var infinite: Bool
    @State private var repeats: Int
    @State private var pickingDuration: PhaseRef?
    let onSave: (SavedTimer) -> Void

    struct PhaseRef: Identifiable { let id: UUID; let inFinale: Bool }

    init(timer: SavedTimer, onSave: @escaping (SavedTimer) -> Void) {
        _timer = State(initialValue: timer)
        _infinite = State(initialValue: timer.plan.repeats == .infinite)
        _repeats = State(initialValue: timer.plan.repeats.count ?? 1)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        TextField("⏳", text: Binding(get: { timer.emoji }, set: { timer.emoji = String($0.prefix(1)) }))
                            .frame(width: 44)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                        TextField("Name", text: $timer.name)
                            .accessibilityIdentifier("timerName")
                    }
                    themeRow
                }

                Section {
                    ForEach($timer.plan.cycle) { $phase in phaseRow($phase, inFinale: false) }
                        .onMove { timer.plan.cycle.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { offsets in
                            guard timer.plan.cycle.count > offsets.count else { return }   // keep ≥ 1 phase
                            timer.plan.cycle.remove(atOffsets: offsets)
                        }
                    Button {
                        timer.plan.cycle.append(Phase(name: String(localized: "Phase"), duration: 60))
                    } label: { Label("Add phase", systemImage: "plus.circle") }
                        .accessibilityIdentifier("addPhase")
                } header: { Text("Phases") }

                if timer.plan.cycle.count > 1 || repeats > 1 || infinite {
                    Section {
                        Toggle("Repeat forever", isOn: $infinite)
                        if !infinite {
                            Stepper(value: $repeats, in: 1...99) {
                                Text("Rounds: \(repeats)")
                            }
                        }
                        if timer.plan.cycle.count > 1 && !infinite {
                            Toggle("Skip last phase of the final round", isOn: $timer.plan.dropLastPhaseOfFinalCycle)
                        }
                    } header: { Text("Repeats") }
                }

                Section {
                    ForEach($timer.plan.finale) { $phase in phaseRow($phase, inFinale: true) }
                        .onMove { timer.plan.finale.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { timer.plan.finale.remove(atOffsets: $0) }
                    Button {
                        timer.plan.finale.append(Phase(name: String(localized: "Long break"), duration: 15 * 60))
                    } label: { Label("Add final phase", systemImage: "flag.checkered") }
                } header: { Text("After all rounds") } footer: {
                    Text("Total: \(totalText)")
                }
            }
            .navigationTitle(Text("Edit timer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(timer.name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("saveTimer")
                }
                ToolbarItem(placement: .bottomBar) { EditButton() }
            }
            .sheet(item: $pickingDuration) { ref in
                DurationPickerView(initial: phase(ref)?.duration ?? 60) { d in
                    updatePhase(ref) { $0.duration = DurationLimits.clamp(d) }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var totalText: String {
        var plan = timer.plan
        plan.repeats = infinite ? .infinite : .times(repeats)
        return plan.totalDuration.map { DurationFormatter.string($0) } ?? "∞"
    }

    private var themeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SandTheme.all) { theme in
                    let unlocked = theme.isUnlocked(isSupporter: store.isSupporter)
                    Button { if unlocked { timer.themeID = theme.id } } label: {
                        ZStack(alignment: .topTrailing) {
                            HourglassGlyph(progress: 0.4, theme: theme, showsStream: false)
                                .frame(height: 54)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 10)
                                    .stroke(timer.themeID == theme.id ? theme.accent : .clear, lineWidth: 2))
                            if !unlocked { Image(systemName: "lock.fill").font(.caption2) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(LocalizedStringKey(theme.nameKey)))
                }
            }
        }
    }

    private func phaseRow(_ phase: Binding<Phase>, inFinale: Bool) -> some View {
        HStack {
            Menu {
                Button { phase.wrappedValue.themeID = nil } label: { Text("Timer theme") }
                ForEach(SandTheme.all.filter { $0.isUnlocked(isSupporter: store.isSupporter) }) { t in
                    Button { phase.wrappedValue.themeID = t.id } label: { Text(LocalizedStringKey(t.nameKey)) }
                }
            } label: {
                Circle()
                    .fill(SandTheme.theme(phase.wrappedValue.themeID ?? timer.themeID).accent)
                    .frame(width: 18, height: 18)
            }
            .accessibilityLabel(Text("Phase colour"))
            TextField("Phase name", text: phase.name)
            Spacer()
            Button(DurationFormatter.string(phase.wrappedValue.duration)) {
                pickingDuration = PhaseRef(id: phase.wrappedValue.id, inFinale: inFinale)
            }
            .monospacedDigit()
            .buttonStyle(.bordered)
        }
    }

    private func phase(_ ref: PhaseRef) -> Phase? {
        (ref.inFinale ? timer.plan.finale : timer.plan.cycle).first { $0.id == ref.id }
    }

    private func updatePhase(_ ref: PhaseRef, _ change: (inout Phase) -> Void) {
        if ref.inFinale, let i = timer.plan.finale.firstIndex(where: { $0.id == ref.id }) { change(&timer.plan.finale[i]) }
        if !ref.inFinale, let i = timer.plan.cycle.firstIndex(where: { $0.id == ref.id }) { change(&timer.plan.cycle[i]) }
    }

    private func save() {
        timer.plan.repeats = infinite ? .infinite : .times(repeats)
        if infinite { timer.plan.dropLastPhaseOfFinalCycle = false }
        if timer.emoji.isEmpty { timer.emoji = "⏳" }
        onSave(timer)
        dismiss()
    }
}
