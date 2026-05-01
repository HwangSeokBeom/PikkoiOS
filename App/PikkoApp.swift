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
        PikkoAppDelegate.notificationService = container.appNotificationService
        PikkoAppDelegate.notificationDiagnosticsStore = container.notificationDiagnosticsStore

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
    @MainActor static weak var notificationService: DefaultAppNotificationService?
    @MainActor static weak var notificationDiagnosticsStore: NotificationDiagnosticsStore?

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
            if let remotePayload = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
                let payload = Self.stringPayload(from: remotePayload)
                Task { @MainActor in
                    Self.notificationService?.handleRemoteNotificationTapPayload(payload)
                }
            }
        } else {
            Self.logDebug("notification setup skipped because Firebase is not configured")
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
        Self.logDebug("APNs device token registered")
        Task { @MainActor in
            Self.notificationDiagnosticsStore?.recordAPNsTokenRegistered()
        }
        fetchFCMTokenAfterAPNsRegistration()
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Self.logDebug("APNs device token registration failed error=\(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let payload = Self.stringPayload(from: userInfo)
        Task { @MainActor in
            Self.notificationService?.handleRemoteNotificationPayload(payload)
            completionHandler(.newData)
        }
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Self.logToken(event: "didReceiveRegistrationToken", token: fcmToken)
        Self.publishFCMToken(fcmToken, source: "messagingDelegate")
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let payload = Self.stringPayload(from: notification.request.content.userInfo)
        let isRemotePush = notification.request.trigger is UNPushNotificationTrigger
        let notificationIdentifier = notification.request.identifier
        let source = isRemotePush ? "remote" : "local"
        Logger(category: "NotificationPresentation").debug("[NotificationPresentation] willPresent source=\(source) keys=\(payload.keys.sorted().joined(separator: ","))")
        await MainActor.run {
            Self.notificationDiagnosticsStore?.recordForegroundPresentation(source: source, result: "willPresent")
        }

        if isRemotePush {
            await MainActor.run {
                Self.notificationService?.handleRemoteNotificationPayload(payload)
            }
            let shouldSuppressBanner = await MainActor.run {
                Self.notificationService?.shouldSuppressForegroundBanner(for: payload) ?? false
            }
            if shouldSuppressBanner {
                await MainActor.run {
                    Self.notificationDiagnosticsStore?.recordForegroundPresentation(source: source, result: "suppressed")
                }
                return [.list, .sound, .badge]
            } else {
                Logger(category: "NotificationPresentation").debug("[NotificationPresentation] foreground banner presented source=remote")
                await MainActor.run {
                    Self.notificationDiagnosticsStore?.recordForegroundPresentation(source: source, result: "presented")
                }
                return [.banner, .list, .sound, .badge]
            }
        } else {
            Logger(category: "NotificationPresentation").debug("[NotificationPresentation] foreground banner presented source=local")
            Logger(category: "LocalNotification").debug("[LocalNotification] delivered foreground=true id=\(notificationIdentifier) keys=\(payload.keys.sorted().joined(separator: ",")) source=localNotification")
            await MainActor.run {
                Self.notificationDiagnosticsStore?.recordForegroundPresentation(source: source, result: "presented")
                Self.notificationDiagnosticsStore?.recordLocalNotification(id: notificationIdentifier)
            }
            return [.banner, .list, .sound, .badge]
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = Self.stringPayload(from: response.notification.request.content.userInfo)
        let isRemotePush = response.notification.request.trigger is UNPushNotificationTrigger
        if isRemotePush {
            Self.logDebug("notification tap source=remote keys=\(payload.keys.sorted().joined(separator: ","))")
            await MainActor.run {
                Self.notificationService?.handleRemoteNotificationTapPayload(payload)
            }
        } else {
            Logger(category: "LocalNotification").debug("[LocalNotification] tapped id=\(response.notification.request.identifier) keys=\(payload.keys.sorted().joined(separator: ","))")
        }
    }

    static func configureFirebaseIfNeeded(shouldLogConfigured: Bool) -> Bool {
        if !hasConfiguredFirebase {
            guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
                logDebug("Firebase configure skipped missing GoogleService-Info.plist")
                return false
            }

            FirebaseApp.configure()
            hasConfiguredFirebase = FirebaseApp.app() != nil
        }

        guard hasConfiguredFirebase, FirebaseApp.app() != nil else {
            logDebug("Firebase configure failed app=nil")
            return false
        }

        if shouldLogConfigured {
            logDebug("Firebase configured")
        }
        return true
    }

    private func requestNotificationPermission(application: UIApplication) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            Self.logDebug("notification permission granted=\(granted)")

            if let error {
                Self.logDebug("notification permission error=\(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let statusText = Self.authorizationStatusText(settings.authorizationStatus)
            Self.logDebug("notification authorization status=\(statusText)")
            Task { @MainActor in
                Self.notificationDiagnosticsStore?.recordAuthorizationStatus(statusText)
            }
        }
    }

    private func fetchFCMTokenAfterAPNsRegistration() {
        Messaging.messaging().token { token, error in
            if let error {
                Self.logDebug("token fetch after APNs failed error=\(error.localizedDescription)")
                return
            }

            Self.logToken(event: "token fetch after APNs success", token: token)
            Self.publishFCMToken(token, source: "manualFetch")
        }
    }

    nonisolated private static func publishFCMToken(_ token: String?, source: String) {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return
        }

        NotificationCenter.default.post(
            name: .pikkoFCMTokenDidRefresh,
            object: nil,
            userInfo: [
                FCMTokenNotificationUserInfoKey.token: token,
                FCMTokenNotificationUserInfoKey.source: source
            ]
        )
    }

    nonisolated static func publishFCMTokenForDiagnostics(_ token: String?) {
        publishFCMToken(token, source: "diagnosticsManualFetch")
    }

    nonisolated private static func logToken(event: String, token: String?) {
        logDebug("\(event) \(tokenSummary(token))")
    }

    nonisolated private static func logDebug(_ message: String) {
        Logger(category: "FCM").debugVerbose("[FCM] \(message)")
    }

    nonisolated private static func tokenSummary(_ token: String?) -> String {
        let token = token ?? ""
        let prefix = String(token.prefix(8))
        let suffix = String(token.suffix(8))
        return "exists=\(!token.isEmpty) prefix=\(prefix) suffix=\(suffix) length=\(token.count)"
    }

    nonisolated static func tokenSummaryForDiagnostics(_ token: String?) -> String {
        tokenSummary(token)
    }

    nonisolated private static func authorizationStatusText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .provisional:
            return "provisional"
        case .ephemeral:
            return "ephemeral"
        @unknown default:
            return "unknown"
        }
    }

    nonisolated private static func stringPayload(from userInfo: [AnyHashable: Any]) -> [String: String] {
        var values: [String: String] = [:]
        for (key, value) in userInfo {
            guard let key = key as? String else { continue }
            if let string = value as? String {
                values[key] = string
            } else if let number = value as? NSNumber {
                values[key] = number.stringValue
            } else if let dictionary = value as? [String: Any] {
                for (nestedKey, nestedValue) in dictionary {
                    if let string = nestedValue as? String {
                        values[nestedKey] = string
                    }
                }
            }
        }
        return values
    }
}
