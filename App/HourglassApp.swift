import SwiftUI
import UserNotifications
import HourglassCore

@main
struct HourglassApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let env = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .withAppEnvironment()
                .onOpenURL(perform: handle(url:))
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                env.hourglass.sceneBecameActive()
                Task {
                    await env.store.start()
                    await env.ads.prepare(isSupporter: env.store.isSupporter)
                }
            case .background:
                env.hourglass.sceneEnteredBackground()
            default:
                break
            }
        }
    }

    /// `hourglass://start?id=<uuid>` (Quick Start widget on iOS 15–16), `hourglass://open`.
    private func handle(url: URL) {
        guard url.scheme == "hourglass" else { return }
        if url.host == "start",
           let idString = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
           let id = UUID(uuidString: idString) {
            Task { await env.hourglass.handle(.startSaved(id)) }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let category = UNNotificationCategory(identifier: PhaseNotificationScheduler.categoryID, actions: [],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
        return true
    }

    /// While the app is open the hourglass plays its own alert — suppress the duplicate banner/sound.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.content.categoryIdentifier == PhaseNotificationScheduler.categoryID {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
