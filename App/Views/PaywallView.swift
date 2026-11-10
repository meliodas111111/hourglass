import SwiftUI
import HourglassCore

/// "Supporter" one-time purchase screen.
struct PaywallView: View {
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var ads: AdsService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    HStack(spacing: 16) {
                        HourglassGlyph(progress: 0.35, theme: .theme(.roseQuartz)).frame(height: 140)
                        HourglassGlyph(progress: 0.65, theme: .theme(.jade)).frame(height: 140)
                    }
                    .padding(.top, 24)

                    Text("Become a Supporter").font(.title.bold())
                    Text("A one-time purchase that keeps Hourglass independent.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 14) {
                        benefit("nosign", "No ads")
                        benefit("paintpalette.fill", "Premium sand themes: Rose Quartz and Jade")
                        benefit("heart.fill", "Support future updates")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))

                    if store.isSupporter {
                        Label("Thank you! You are a Supporter.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .accessibilityIdentifier("supporterThanks")
                    } else {
                        Button {
                            Task {
                                await store.purchase()
                                if store.isSupporter { ads.disableForSupporter() }
                            }
                        } label: {
                            Group {
                                if store.isBusy { ProgressView() }
                                else if let product = store.product { Text("Unlock for \(product.displayPrice)") }
                                else { Text("Store unavailable") }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(store.isBusy)
                        .accessibilityIdentifier("buySupporter")

                        Button("Restore purchases") { Task { await store.restore() } }
                            .disabled(store.isBusy)
                            .accessibilityIdentifier("restorePurchases")
                    }
                    Text("One-time payment. No subscription. Purchases are tied to your Apple ID and restored on all your devices.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .alert(Text("Purchase"), isPresented: Binding(get: { !(store.errorMessage ?? "").isEmpty },
                                                           set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(verbatim: store.errorMessage ?? "")
            }
            .task { if store.product == nil { await store.loadProduct() } }
        }
        .navigationViewStyle(.stack)
    }

    private func benefit(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label { Text(text) } icon: { Image(systemName: symbol).foregroundStyle(.orange) }
    }
}
