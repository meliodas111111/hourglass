import SwiftUI
import HourglassCore

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var ads: AdsService
    @EnvironmentObject private var alarms: AlarmService
    @EnvironmentObject private var library: PersistenceService
    @EnvironmentObject private var vm: HourglassViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmReset = false
    @State private var showPaywall = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Form {
                    alarmSection
                    hourglassSection
                    supporterSection
                    privacySection
                    Section {
                        Button("Reset all data", role: .destructive) { confirmReset = true }
                            .accessibilityIdentifier("resetData")
                    }
                    Section {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text(verbatim: Self.version).foregroundStyle(.secondary)
                        }
                    }
                }
                BannerAdView()
            }
            .navigationTitle(Text("Settings"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog(Text("Delete all your data?"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    vm.stop()
                    settings.resetAll()
                    library.resetToStarter()
                }
            } message: {
                Text("Your saved timers, sequences and settings will be deleted. Purchases are not affected.")
            }
            .sheet(isPresented: $showPaywall) { PaywallView().withAppEnvironment() }
            .task { await alarms.refreshStatus() }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: Sections

    private var alarmSection: some View {
        Section {
            Picker("Alert sound", selection: $settings.alertSound) {
                ForEach(AlertSound.allCases) { s in Text(LocalizedStringKey(s.nameKey)).tag(s) }
            }
            .onChange(of: settings.alertSound) { AppEnvironment.shared.feedback.preview(sound: $0, volume: settings.volume) }
            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $settings.volume, in: 0...1) { Text("Volume") }
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            Toggle("Vibration", isOn: $settings.vibrationEnabled)
            permissionRow
        } header: { Text("Alarm") } footer: {
            if alarms.backend == .alarmKit {
                Text("Alarms ring even in Silent mode and with Focus on.")
            } else {
                Text("Alerts are delivered as Time Sensitive notifications.")
            }
        }
    }

    @ViewBuilder private var permissionRow: some View {
        switch alarms.notificationStatus {
        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: { Label("Alerts are off — open Settings", systemImage: "exclamationmark.triangle") }
            .foregroundStyle(.orange)
        case .notDetermined:
            Button("Allow alerts") { Task { await alarms.requestAuthorization() } }
        default:
            EmptyView()
        }
    }

    private var hourglassSection: some View {
        Section {
            Toggle("Flip to start", isOn: $settings.flipGestureEnabled)
                .accessibilityIdentifier("flipToggle")
            Toggle("Keep screen on while running", isOn: $settings.keepScreenOn)
            Toggle("Zen mode by default", isOn: $settings.zenByDefault)
            Toggle("Automatic quality", isOn: $settings.autoQuality)
            Picker("Sand density", selection: $settings.density) {
                Text("Performance").tag(SandDensity.performance)
                Text("Balanced").tag(SandDensity.balanced)
                Text("Quality").tag(SandDensity.quality)
            }
        } header: { Text("Hourglass") } footer: {
            Text("Flip the device upside down to start, restart or turn the hourglass over. Higher density means more grains and more battery use.")
        }
    }

    private var supporterSection: some View {
        Section {
            if store.isSupporter {
                Label("Supporter — thank you!", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
                Button { showPaywall = true } label: { Label("Become a Supporter", systemImage: "heart") }
                    .accessibilityIdentifier("openPaywall")
            }
            Button("Restore purchases") { Task { await store.restore() } }
        } header: { Text("Purchases") }
    }

    private var privacySection: some View {
        Section {
            Toggle("Share anonymous usage & crash data", isOn: $settings.analyticsEnabled)
                .onChange(of: settings.analyticsEnabled) { AnalyticsService.shared.setCollection($0) }
            if ads.privacyOptionsRequired {
                Button("Ad privacy choices") { Task { await ads.presentPrivacyOptions() } }
            }
        } header: { Text("Privacy") } footer: {
            Text("No account, no server: your timers stay on this device.")
        }
    }

    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}
