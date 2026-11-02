import CarpoolKit
import UIKit
import UserNotifications

/// Nimmt Gerätetoken und angetippte Push-Nachrichten entgegen (SwiftUI hat dafür keine eigene API).
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let router = AppRouter()
    let push = PushRegistration()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil)
        -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        push.received(token: PushToken.hex(token))
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        push.failed(error)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Auch im Vordergrund als Banner zeigen; die Übersicht aktualisiert sich ohnehin per Realtime.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let kind = info["kind"] as? String
        let carID = (info["car_id"] as? String).flatMap(UUID.init(uuidString:))
        await MainActor.run {
            router.open(DeepLink(notificationKind: kind, carID: carID))
        }
    }
}
