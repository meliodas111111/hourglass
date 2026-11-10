import SwiftUI
import HourglassCore

/// 7 sand themes with a live mini-hourglass preview. Locked (premium) themes lead to the paywall.
struct ThemePickerView: View {
    @EnvironmentObject private var vm: HourglassViewModel
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 16)]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(SandTheme.all) { theme in card(theme) }
                }
                .padding()
            }
            .navigationTitle(Text("Sand themes"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showPaywall) { PaywallView().withAppEnvironment() }
        }
        .navigationViewStyle(.stack)
    }

    private func card(_ theme: SandTheme) -> some View {
        let unlocked = theme.isUnlocked(isSupporter: store.isSupporter)
        let selected = vm.engine.snapshot.themeID == theme.id
        return Button {
            if unlocked { vm.setTheme(theme.id) } else {
                AnalyticsService.shared.log(.paywallShown)
                showPaywall = true
            }
        } label: {
            VStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    // Slowly cycling preview so the colours are seen both as a pile and as a stream.
                    let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) / 12
                    HourglassGlyph(progress: t, theme: theme)
                        .animation(.linear(duration: 1), value: t)
                }
                .frame(height: 110)
                .overlay(alignment: .topTrailing) {
                    if !unlocked {
                        Image(systemName: "lock.fill")
                            .padding(6)
                            .background(Circle().fill(.black.opacity(0.6)))
                    }
                }
                Text(LocalizedStringKey(theme.nameKey)).font(.subheadline.weight(.medium))
                if theme.isPremium {
                    Text("Supporter").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("theme-\(theme.id.rawValue)")
        .accessibilityLabel(Text(LocalizedStringKey(theme.nameKey)))
        .accessibilityValue(unlocked ? (selected ? Text("Selected") : Text("")) : Text("Locked"))
    }
}
