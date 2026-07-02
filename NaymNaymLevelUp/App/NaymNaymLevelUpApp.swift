import SwiftUI
import UIKit
import UserNotifications

@main
struct NaymNaymLevelUpApp: App {
    @UIApplicationDelegateAdaptor(NaymNaymLevelUpAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .onReceive(NotificationCenter.default.publisher(for: ParentPushNotificationBridge.deviceTokenDidUpdate)) { notification in
                    guard let token = notification.object as? String else { return }
                    Task { await appState.registerParentPushDeviceToken(token) }
                }
                .onReceive(NotificationCenter.default.publisher(for: ParentPushNotificationBridge.registrationDidFail)) { notification in
                    let message = (notification.object as? String) ?? "알림 기기 등록에 실패했어요."
                    appState.parentNotificationMessage = message
                    appState.parentNotificationError = message
                }
        }
    }
}

enum ParentPushNotificationBridge {
    static let deviceTokenDidUpdate = Notification.Name("ParentPushNotificationBridge.deviceTokenDidUpdate")
    static let registrationDidFail = Notification.Name("ParentPushNotificationBridge.registrationDidFail")

    static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    static func requestAuthorizationAndRegister() async throws -> Bool {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else { return false }
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return true
    }

    static func tokenString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

final class NaymNaymLevelUpAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationCenter.default.post(
            name: ParentPushNotificationBridge.deviceTokenDidUpdate,
            object: ParentPushNotificationBridge.tokenString(from: deviceToken)
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationCenter.default.post(
            name: ParentPushNotificationBridge.registrationDidFail,
            object: "알림 기기 등록 실패: \(error.localizedDescription)"
        )
    }
}
