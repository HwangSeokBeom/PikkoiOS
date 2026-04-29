import FirebaseCore
import FirebaseMessaging
import SwiftUI
import UIKit
import UserNotifications
import iamport_ios

@main
struct PikkoApp: App {
    @UIApplicationDelegateAdaptor(PikkoAppDelegate.self) private var appDelegate

    private let container: AppDIContainer
    private let bootstrapper: AppBootstrapper
    private let featureBuilderFactory: FeatureBuilderFactory

    @StateObject private var appState: AppState

    init() {
        _ = PikkoAppDelegate.configureFirebaseIfNeeded(shouldLogConfigured: false)

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
                // 결제 복귀 URL은 PortOne SDK가 먼저 처리한다.
                if url.scheme == container.appConfiguration.portOneAppScheme {
                    Iamport.shared.receivedURL(url)
                    if Self.isPortOnePaymentReturnURL(url) {
                        return
                    }
                }

                // 소셜 로그인 URL은 기존 Kakao/Google 처리 흐름을 유지한다.
                if !container.socialAuthService.handleOpenURL(url) {
                    // 결제/소셜 외 URL은 앱 딥링크로 넘긴다.
                    appState.pendingDeepLink = url
                }
            }
        }
    }

    private static func isPortOnePaymentReturnURL(_ url: URL) -> Bool {
        let searchableText = [
            url.host,
            url.path,
            url.query,
            url.fragment
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        return searchableText.contains("imp_uid")
            || searchableText.contains("imp_success")
            || searchableText.contains("merchant_uid")
            || searchableText.contains("error_msg")
            || searchableText.contains("iamport")
            || searchableText.contains("payment")
            || searchableText.contains("payments")
    }
}

final class PikkoAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    private static var hasConfiguredFirebase = false

    private var isFirebaseConfigured = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        isFirebaseConfigured = Self.configureFirebaseIfNeeded(shouldLogConfigured: true)

        if isFirebaseConfigured {
            UNUserNotificationCenter.current().delegate = self
            Messaging.messaging().delegate = self
            requestNotificationPermission(application: application)
        } else {
            print("DEBUG [FCM] notification setup skipped because Firebase is not configured")
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

    static func configureFirebaseIfNeeded(shouldLogConfigured: Bool) -> Bool {
        if !hasConfiguredFirebase {
            guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
                print("DEBUG [FCM] Firebase configure skipped missing GoogleService-Info.plist")
                return false
            }

            FirebaseApp.configure()
            hasConfiguredFirebase = FirebaseApp.app() != nil
        }

        guard hasConfiguredFirebase, FirebaseApp.app() != nil else {
            print("DEBUG [FCM] Firebase configure failed app=nil")
            return false
        }

        if shouldLogConfigured {
            print("DEBUG [FCM] Firebase configured")
        }
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
