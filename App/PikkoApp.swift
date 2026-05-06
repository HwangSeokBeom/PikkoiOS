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
    private static var hasAssignedAPNsToken = false
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
        Self.hasAssignedAPNsToken = true
        Logger(category: "Push").debug("[Push] didRegisterForRemoteNotifications apnsTokenLength=\(deviceToken.count)")
        Logger(category: "Push").debug("[Push] apnsToken assigned to FirebaseMessaging=true")
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
        Logger(category: "Push").error("[Push] didFailToRegisterForRemoteNotifications error=\(error.localizedDescription)")
        Self.logDebug("APNs device token registration failed error=\(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let payload = Self.stringPayload(from: userInfo)
        Logger(category: "RemotePush").debug("[RemotePush] received foreground=false messageId=\(Self.messageID(from: payload)) type=\(Self.payloadType(from: payload)) source=\(Self.payloadSource(from: payload))")
        Task { @MainActor in
            Self.notificationService?.handleRemoteNotificationPayload(payload)
            completionHandler(.newData)
        }
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Self.logToken(event: "registrationToken received", token: fcmToken, source: "messagingDelegate")
        Self.publishFCMToken(fcmToken, source: "messagingDelegate")
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let payload = Self.stringPayload(from: notification.request.content.userInfo)
        let isRemotePush = notification.request.trigger is UNPushNotificationTrigger
        let notificationIdentifier = notification.request.identifier
        let source = Self.notificationSource(for: notification.request.trigger)
        let keys = Self.notificationKeySummary(from: notification.request.content.userInfo)
        Logger(category: "NotificationPresentation").debug("[NotificationPresentation] willPresent source=\(source) keys=\(keys)")
        if isRemotePush {
            Logger(category: "RemotePush").debug("[RemotePush] received foreground=true messageId=\(Self.messageID(from: payload)) type=\(Self.payloadType(from: payload)) source=\(Self.payloadSource(from: payload))")
        }
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
                Logger(category: "NotificationPresentation").debug("[NotificationPresentation] foreground banner presented source=remoteFCM")
                await MainActor.run {
                    Self.notificationDiagnosticsStore?.recordForegroundPresentation(source: source, result: "presented")
                }
                return [.banner, .list, .sound, .badge]
            }
        } else {
            Logger(category: "NotificationPresentation").debug("[NotificationPresentation] foreground banner presented source=localNotification")
            Logger(category: "LocalNotification").debug("[LocalNotification] delivered foreground=true id=\(notificationIdentifier) keys=\(keys) source=localNotification")
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
        let source = Self.notificationSource(for: response.notification.request.trigger)
        if isRemotePush {
            Logger(category: "NotificationResponse").debug("[NotificationResponse] didReceive source=remoteFCM actionIdentifier=\(response.actionIdentifier) messageId=\(Self.messageID(from: payload)) type=\(Self.payloadType(from: payload))")
            await MainActor.run {
                Self.notificationService?.handleRemoteNotificationTapPayload(payload)
            }
        } else {
            Logger(category: "NotificationResponse").debug("[NotificationResponse] didReceive source=\(source) actionIdentifier=\(response.actionIdentifier) type=\(Self.payloadType(from: payload))")
            Logger(category: "LocalNotification").debug("[LocalNotification] tapped id=\(response.notification.request.identifier) keys=\(Self.notificationKeySummary(from: response.notification.request.content.userInfo)) source=localNotification")
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
            let diagnostics = firebaseConfigurationDiagnostics()
            Logger(category: "FirebaseConfig").debug("[FirebaseConfig] configured=true projectId=\(diagnostics.projectID) gcmSenderId=\(diagnostics.gcmSenderID) bundleId=\(diagnostics.bundleID) googleAppId=\(diagnostics.googleAppID)")
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
                Logger(category: "Push").debug("[Push] registerForRemoteNotifications requested")
                application.registerForRemoteNotifications()
            }
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let statusText = Self.authorizationStatusText(settings.authorizationStatus)
            Logger(category: "Push").debug("[Push] authorization status=\(statusText)")
            Self.logDebug("notification authorization status=\(statusText)")
            Task { @MainActor in
                Self.notificationDiagnosticsStore?.recordAuthorizationStatus(statusText)
            }
        }
    }

    private func fetchFCMTokenAfterAPNsRegistration() {
        Logger(category: "FCM").debug("[FCM] token fetch after APNs start apnsAssigned=\(Self.hasAssignedAPNsToken)")
        Messaging.messaging().token { token, error in
            if let error {
                Logger(category: "FCM").error("[FCM] token fetch after APNs failed error=\(error.localizedDescription)")
                return
            }

            guard let token else {
                Logger(category: "FCM").warning("[FCM] token fetched after APNs nil")
                return
            }

            Self.logToken(event: "token fetched after APNs", token: token, source: "afterAPNs")
            Self.publishFCMToken(token, source: "afterAPNs")
        }
    }

    static func fetchCurrentFCMTokenForAuthenticatedSession() {
        guard hasConfiguredFirebase, FirebaseApp.app() != nil else { return }

        Logger(category: "FCM").debug("[FCM] token fetch after auth start apnsAssigned=\(hasAssignedAPNsToken)")
        Messaging.messaging().token { token, error in
            if let error {
                Logger(category: "FCM").error("[FCM] token fetch after auth failed error=\(error.localizedDescription)")
                return
            }

            guard let token else {
                Logger(category: "FCM").warning("[FCM] token fetched after auth nil")
                return
            }

            Self.logToken(event: "token fetched after auth", token: token, source: "authStateChanged")
            Self.publishFCMToken(token, source: "authStateChanged")
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

    nonisolated private static func logToken(event: String, token: String?, source: String) {
        let diagnostics = firebaseConfigurationDiagnostics()
        Logger(category: "FCM").debug("[FCM] \(event) length=\(token?.count ?? 0) maskedToken=\(maskedToken(token)) source=\(source) apnsAssigned=\(hasAssignedAPNsToken) bundleId=\(diagnostics.bundleID) projectId=\(diagnostics.projectID) gcmSenderId=\(diagnostics.gcmSenderID)")
    }

    nonisolated private static func logDebug(_ message: String) {
        Logger(category: "FCM").debugVerbose("[FCM] \(message)")
    }

    nonisolated private static func tokenSummary(_ token: String?) -> String {
        let token = token ?? ""
        return "exists=\(!token.isEmpty) length=\(token.count) maskedToken=\(maskedToken(token))"
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
        NotificationRouteParser.flattenedPayload(from: userInfo)
    }

    nonisolated private static func payloadType(from payload: [String: String]) -> String {
        value(for: ["type", "notification_type", "event", "category"], in: payload) ?? "unknown"
    }

    nonisolated private static func payloadSource(from payload: [String: String]) -> String {
        value(for: ["source", "debug_source"], in: payload) ?? "unknown"
    }

    nonisolated private static func messageID(from payload: [String: String]) -> String {
        value(for: ["gcm.message_id", "google.message_id", "message_id", "messageId"], in: payload) ?? "unknown"
    }

    nonisolated private static func payloadRouteID(from payload: [String: String]) -> String {
        value(
            for: [
                "order_code", "orderCode", "order_id", "orderId",
                "room_id", "roomId", "chat_room_id", "chatRoomId",
                "post_id", "postId", "community_post_id", "communityPostId"
            ],
            in: payload
        ) ?? "unknown"
    }

    nonisolated private static func value(for keys: [String], in payload: [String: String]) -> String? {
        for key in keys {
            let value = payload[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    nonisolated private static func notificationSource(for trigger: UNNotificationTrigger?) -> String {
        if trigger is UNPushNotificationTrigger {
            return "remoteFCM"
        }
        if trigger is UNTimeIntervalNotificationTrigger || trigger is UNCalendarNotificationTrigger {
            return "localNotification"
        }
        return "localNotification"
    }

    nonisolated private static func notificationKeySummary(from userInfo: [AnyHashable: Any]) -> String {
        userInfo.keys
            .compactMap { $0 as? String }
            .sorted()
            .joined(separator: ",")
    }

    nonisolated private static func maskedToken(_ token: String?) -> String {
        let token = token ?? ""
        guard !token.isEmpty else { return "nil" }
        guard token.count > 16 else { return "\(token.prefix(4))...\(token.suffix(4))" }
        return "\(token.prefix(8))...\(token.suffix(8))"
    }

    nonisolated private static func firebaseConfigurationDiagnostics() -> (projectID: String, gcmSenderID: String, bundleID: String, googleAppID: String) {
        let options = FirebaseApp.app()?.options ?? FirebaseOptions.defaultOptions()
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let googleAppID = options?.googleAppID ?? "unknown"
        let maskedGoogleAppID = googleAppID.count > 12 ? "\(googleAppID.prefix(8))...\(googleAppID.suffix(4))" : googleAppID
        return (
            projectID: options?.projectID ?? "unknown",
            gcmSenderID: options?.gcmSenderID ?? "unknown",
            bundleID: bundleID,
            googleAppID: maskedGoogleAppID
        )
    }
}
