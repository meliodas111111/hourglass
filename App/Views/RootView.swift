import SwiftUI
import HourglassCore

/// Root: the hourglass screen plus all sheets.
struct RootView: View {
    @EnvironmentObject private var vm: HourglassViewModel

    var body: some View {
        HourglassScreen()
            .sheet(item: $vm.activeSheet) { sheet in
                Group {
                    switch sheet {
                    case .library: LibraryView()
                    case .settings: SettingsView()
                    case .themes: ThemePickerView()
                    case .paywall: PaywallView()
                    case .duration:
                        DurationPickerView(initial: vm.engine.totalDuration) { vm.setDuration($0) }
                    }
                }
                .withAppEnvironment()
            }
            .sheet(isPresented: $vm.showPermissionPrimer) {
                PermissionPrimerView().withAppEnvironment()
            }
            .preferredColorScheme(.dark)
    }
}

extension View {
    /// Re-injects the shared services. Sheets inherit environment objects on recent iOS versions, but doing it
    /// explicitly keeps iOS 15 and nested sheets (Library → Editor, Themes → Paywall) safe.
    @MainActor
    func withAppEnvironment() -> some View {
        let env = AppEnvironment.shared
        return self
            .environmentObject(env.hourglass)
            .environmentObject(env.settings)
            .environmentObject(env.store)
            .environmentObject(env.ads)
            .environmentObject(env.alarms)
            .environmentObject(env.persistence)
    }
}

/// Explains *why* we ask before the system prompt appears (App Review guideline 5.1.1).
struct PermissionPrimerView: View {
    @EnvironmentObject private var vm: HourglassViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "alarm.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
                .padding(.top, 40)
            Text("Never miss the last grain")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Allow alerts so the timer can ring when it ends — even when the app is closed, the phone is locked or in Silent mode.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await vm.permissionPrimerFinished(granted: true) }
            } label: {
                Text("Allow alerts").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("allowAlerts")
            Button("Not now") {
                Task { await vm.permissionPrimerFinished(granted: false) }
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
        .interactiveDismissDisabled()
    }
}
