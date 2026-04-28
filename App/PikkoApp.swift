import FirebaseCore
import FirebaseMessaging
import SwiftUI
import UIKit
import UserNotifications

@main
struct PikkoApp: App {
    @UIApplicationDelegateAdaptor(PikkoAppDelegate.self) private var appDelegate

    private let container: AppDIContainer
    private let bootstrapper: AppBootstrapper
    private let featureBuilderFactory: FeatureBuilderFactory

    @StateObject private var appState: AppState

    init() {
        let container = AppDIContainer()
        let appState = container.makeAppState()

        self.container = container
        self.bootstrapper = container.makeAppBootstrapper(appState: appState)
        self.featureBuilderFactory = container.makeFeatureBuilderFactory(appState: appState)
        _appState = StateObject(wrappedValue: appState)
        container.socialAuthService.prepareIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootScene(
                appState: appState,
                bootstrapper: bootstrapper,
                featureBuilderFactory: featureBuilderFactory
            )
            .environmentObject(appState)
            .environmentObject(appState.sessionStore)
            .environmentObject(appState.cartStore)
            .onOpenURL { url in
                if !container.socialAuthService.handleOpenURL(url) {
                    appState.pendingDeepLink = url
                }
            }
        }
    }
}

final class PikkoAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    private var isFirebaseConfigured = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        isFirebaseConfigured = configureFirebaseIfNeeded()

        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission(application: application)

        if isFirebaseConfigured {
            Messaging.messaging().delegate = self
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard isFirebaseConfigured else {
            return
        }

        Messaging.messaging().apnsToken = deviceToken
        print("DEBUG [FCM] APNs device token registered")
        fetchFCMTokenAfterAPNsRegistration()
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("DEBUG [FCM] APNs device token registration failed error=\(error.localizedDescription)")
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Self.logToken(event: "didReceiveRegistrationToken", token: fcmToken)
        Self.publishFCMToken(fcmToken)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    private func configureFirebaseIfNeeded() -> Bool {
        if FirebaseApp.app() == nil {
            guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
                print("DEBUG [FCM] Firebase configure skipped missing GoogleService-Info.plist")
                return false
            }

            FirebaseApp.configure()
        }

        print("DEBUG [FCM] Firebase configured")
        return true
    }

    private func requestNotificationPermission(application: UIApplication) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            print("DEBUG [FCM] notification permission granted=\(granted)")

            if let error {
                print("DEBUG [FCM] notification permission error=\(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }

    private func fetchFCMTokenAfterAPNsRegistration() {
        Messaging.messaging().token { token, error in
            if let error {
                print("DEBUG [FCM] token fetch after APNs failed error=\(error.localizedDescription)")
                return
            }

            Self.logToken(event: "token fetch after APNs success", token: token)
            Self.publishFCMToken(token)
        }
    }

    nonisolated private static func publishFCMToken(_ token: String?) {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return
        }

        NotificationCenter.default.post(
            name: .pikkoFCMTokenDidRefresh,
            object: nil,
            userInfo: [FCMTokenNotificationUserInfoKey.token: token]
        )
    }

    nonisolated private static func logToken(event: String, token: String?) {
        print("DEBUG [FCM] \(event) \(tokenSummary(token))")

#if DEBUG
        if ProcessInfo.processInfo.environment["PIKKO_DEBUG_LOG_FULL_FCM_TOKEN"] == "1",
           let token,
           !token.isEmpty {
            print("DEBUG [FCM] \(event) fullToken=\(token)")
        }
#endif
    }

    nonisolated private static func tokenSummary(_ token: String?) -> String {
        let token = token ?? ""
        let prefix = String(token.prefix(8))
        let suffix = String(token.suffix(8))
        return "exists=\(!token.isEmpty) prefix=\(prefix) suffix=\(suffix) length=\(token.count)"
    }
}
