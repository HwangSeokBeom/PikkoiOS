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
        PikkoAppDelegate.orderBackgroundRefreshCoordinator = container.orderBackgroundRefreshCoordinator

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
            .tint(PikkoColor.primary)
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
    nonisolated(unsafe) private static var hasAssignedAPNsToken = false
    @MainActor static weak var notificationService: DefaultAppNotificationService?
    @MainActor static weak var notificationDiagnosticsStore: NotificationDiagnosticsStore?
    @MainActor static weak var orderBackgroundRefreshCoordinator: OrderBackgroundRefreshing?

    private var isFirebaseConfigured = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Logger(category: "AppLifecycle").debug("[AppLifecycle] didFinishLaunching")
        isFirebaseConfigured = Self.configureFirebaseIfNeeded(shouldLogConfigured: true)

        if isFirebaseConfigured {
            UNUserNotificationCenter.current().delegate = self
            Messaging.messaging().delegate = self
            requestNotificationPermission(application: application)
            if let remotePayload = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
                let event = PushNotificationEventFactory.makeEvent(
                    userInfo: remotePayload,
                    actionIdentifier: nil,
                    lifecycle: .launchOptions,
                    source: .remoteFCM,
                    isTap: true
                )
                Logger(category: "PushDeepLink").debug("[PushDeepLink] received lifecycle=launchOptions source=remote keys=\(Self.notificationKeySummary(from: remotePayload)) hasAps=\(remotePayload["aps"] != nil)")
                Logger(category: "PushTap").debug("[PushTap] received notificationId=\(event.logMessageId) action=launchOptions appState=\(UIApplication.shared.applicationState.notificationLogValue)")
                Logger(category: "PushLifecycle").debug("[PushLifecycle] coldStart messageId=\(event.logMessageId) action=storePending")
                Task { @MainActor in
                    Logger(category: "PushDeepLink").debug("[PushDeepLink] handlingOnMainActor isMainThread=\(Self.isCurrentMainThreadForLog()) messageId=\(event.logMessageId)")
                    Self.notificationService?.handlePushNotificationEvent(event)
                }
            }
        } else {
            Self.logDebug("notification setup skipped because Firebase is not configured")
        }
        Task { @MainActor in
            Self.orderBackgroundRefreshCoordinator?.register()
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
        Logger(category: "PushToken").debug("[PushToken] apns token received exists=true length=\(deviceToken.count)")
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
        let event = PushNotificationEventFactory.makeEvent(
            rawPayload: payload,
            actionIdentifier: nil,
            lifecycle: .didReceiveRemoteNotification,
            source: .remoteFCM,
            isTap: false
        )
        Logger(category: "PushDeepLink").debug("[PushDeepLink] received lifecycle=didReceiveRemoteNotification source=remote keys=\(Self.notificationKeySummary(from: userInfo)) hasAps=\(userInfo["aps"] != nil)")
        Logger(category: "RemotePush").debug("[RemotePush] received foreground=false messageId=\(Self.messageID(from: payload)) type=\(Self.payloadType(from: payload)) source=\(Self.payloadSource(from: payload))")
        Task { @MainActor in
            Logger(category: "PushDeepLink").debug("[PushDeepLink] handlingOnMainActor isMainThread=\(Self.isCurrentMainThreadForLog()) messageId=\(event.logMessageId)")
            Self.notificationService?.handlePushNotificationEvent(event)
            Logger(category: "RemotePush").debug("[RemotePush] fetchCompletionHandler result=newData")
            completionHandler(.newData)
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Logger(category: "AppLifecycle").debug("[AppLifecycle] applicationDidBecomeActive")
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Logger(category: "AppLifecycle").debug("[AppLifecycle] applicationDidEnterBackground")
        Task { @MainActor in
            Self.orderBackgroundRefreshCoordinator?.schedule()
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        Logger(category: "AppLifecycle").debug("[AppLifecycle] applicationWillEnterForeground")
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Self.logToken(event: "registrationToken received", token: fcmToken, source: "messagingDelegate")
        Self.publishFCMToken(fcmToken, source: "messagingDelegate")
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        let snapshot = Self.makePresentationSnapshot(from: notification)
        Logger(category: "PushDeepLink").debug("[PushDeepLink] received lifecycle=willPresent source=remote keys=\(snapshot.keySummary) hasAps=\(snapshot.hasAps)")
        Logger(category: "NotificationPresentation").debug("[NotificationPresentation] willPresent source=\(snapshot.source) keys=\(snapshot.keySummary)")
        if snapshot.isRemotePush {
            Logger(category: "RemotePush").debug("[RemotePush] received foreground=true messageId=\(Self.messageID(from: snapshot.payload)) type=\(Self.payloadType(from: snapshot.payload)) source=\(Self.payloadSource(from: snapshot.payload))")
        }

        Task { @MainActor in
            let options = Self.handlePresentationSnapshot(snapshot)
            completionHandler(options)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let snapshot = Self.makeResponseSnapshot(from: response)
        Logger(category: "PushDeepLink").debug("[PushDeepLink] received lifecycle=didReceive source=remote keys=\(snapshot.keySummary) hasAps=\(snapshot.hasAps)")
        Logger(category: "NotificationResponse").debug("[NotificationResponse] didReceive entry isMainThread=\(Self.isCurrentMainThreadForLog()) appState=capturedOnMainActor")
        Logger(category: "NotificationResponse").debug("[NotificationResponse] dispatchToMainActor messageId=\(Self.messageID(from: snapshot.payload))")

        Task { @MainActor in
            Self.handleResponseSnapshot(snapshot)
            completionHandler()
        }
    }

    @MainActor
    private static func handlePresentationSnapshot(_ snapshot: NotificationPresentationSnapshot) -> UNNotificationPresentationOptions {
        MainActorStateAssertions.assertMainThreadForUIStateMutation(context: "PikkoAppDelegate.handlePresentationSnapshot")
        let event = PushNotificationEventFactory.makeEvent(
            rawPayload: snapshot.payload,
            actionIdentifier: nil,
            lifecycle: .willPresent,
            source: .remoteFCM,
            isTap: false
        )
        Logger(category: "PushLifecycle").debug("[PushLifecycle] willPresent messageId=\(event.logMessageId) action=saveAndPresentBanner")
        Logger(category: "PushLifecycle").debug("[PushLifecycle] navigationSkipped reason=willPresentDoesNotNavigate messageId=\(event.logMessageId)")
        notificationDiagnosticsStore?.recordForegroundPresentation(source: snapshot.source, result: "willPresent")

        if snapshot.isRemotePush {
            notificationService?.handlePushNotificationEvent(event)
            if notificationService?.shouldSuppressForegroundBanner(for: snapshot.payload) ?? false {
                notificationDiagnosticsStore?.recordForegroundPresentation(source: snapshot.source, result: "suppressed")
                return [.list, .sound, .badge]
            }
            Logger(category: "NotificationPresentation").debug("[NotificationPresentation] foreground banner presented source=remoteFCM")
            notificationDiagnosticsStore?.recordForegroundPresentation(source: snapshot.source, result: "presented")
            return [.banner, .list, .sound, .badge]
        }

        Logger(category: "NotificationPresentation").debug("[NotificationPresentation] foreground banner presented source=localNotification")
        Logger(category: "LocalNotification").debug("[LocalNotification] delivered foreground=true id=\(snapshot.requestIdentifier) keys=\(snapshot.keySummary) source=localNotification")
        notificationDiagnosticsStore?.recordForegroundPresentation(source: snapshot.source, result: "presented")
        notificationDiagnosticsStore?.recordLocalNotification(id: snapshot.requestIdentifier)
        return [.banner, .list, .sound, .badge]
    }

    @MainActor
    private static func handleResponseSnapshot(_ snapshot: NotificationResponseSnapshot) {
        MainActorStateAssertions.assertMainThreadForUIStateMutation(context: "PikkoAppDelegate.handleResponseSnapshot")
        let appStateLogValue = UIApplication.shared.applicationState.notificationLogValue
        Logger(category: "NotificationResponse").debug("[NotificationResponse] handlingOnMainActor isMainThread=\(isCurrentMainThreadForLog()) appState=\(appStateLogValue)")
        guard snapshot.isRemotePush else {
            Logger(category: "NotificationResponse").debug("[NotificationResponse] didReceive source=\(snapshot.source) actionIdentifier=\(snapshot.actionIdentifier) type=\(payloadType(from: snapshot.payload))")
            Logger(category: "LocalNotification").debug("[LocalNotification] tapped id=\(snapshot.requestIdentifier) keys=\(snapshot.keySummary) source=localNotification")
            return
        }

        let event = PushNotificationEventFactory.makeEvent(
            rawPayload: snapshot.payload,
            actionIdentifier: snapshot.actionIdentifier,
            lifecycle: .didReceive,
            source: .remoteFCM,
            isTap: true
        )
        Logger(category: "PushTap").debug("[PushTap] received notificationId=\(event.logMessageId) action=\(snapshot.actionIdentifier) appState=\(appStateLogValue)")
        Logger(category: "PushLifecycle").debug("[PushLifecycle] didReceive messageId=\(event.logMessageId) appState=\(appStateLogValue) action=navigate")
        Logger(category: "NotificationResponse").debug("[NotificationResponse] didReceive source=remoteFCM actionIdentifier=\(snapshot.actionIdentifier) messageId=\(event.logMessageId) type=\(payloadType(from: snapshot.payload))")
        Logger(category: "PushDeepLink").debug("[PushDeepLink] handlingOnMainActor isMainThread=\(isCurrentMainThreadForLog()) messageId=\(event.logMessageId)")
        notificationService?.handlePushNotificationEvent(event)
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
            Logger(category: "PushToken").debug("[PushToken] authorization status=\(statusText)")
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
        Logger(category: "PushToken").debug("[PushToken] fcm token received exists=\(token?.isEmpty == false) length=\(token?.count ?? 0)")
    }

    nonisolated private static func logDebug(_ message: String) {
        Logger(category: "FCM").debugVerbose("[FCM] \(message)")
    }

    nonisolated private static func isCurrentMainThreadForLog() -> Bool {
        pthread_main_np() == 1
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

    private struct NotificationPresentationSnapshot: Sendable {
        let payload: [String: String]
        let isRemotePush: Bool
        let source: String
        let requestIdentifier: String
        let keySummary: String
        let hasAps: Bool
    }

    private struct NotificationResponseSnapshot: Sendable {
        let payload: [String: String]
        let isRemotePush: Bool
        let source: String
        let requestIdentifier: String
        let actionIdentifier: String
        let keySummary: String
        let hasAps: Bool
    }

    nonisolated private static func makePresentationSnapshot(from notification: UNNotification) -> NotificationPresentationSnapshot {
        let userInfo = notification.request.content.userInfo
        return NotificationPresentationSnapshot(
            payload: stringPayload(from: userInfo),
            isRemotePush: notification.request.trigger is UNPushNotificationTrigger,
            source: notificationSource(for: notification.request.trigger),
            requestIdentifier: notification.request.identifier,
            keySummary: notificationKeySummary(from: userInfo),
            hasAps: userInfo["aps"] != nil
        )
    }

    nonisolated private static func makeResponseSnapshot(from response: UNNotificationResponse) -> NotificationResponseSnapshot {
        let request = response.notification.request
        let userInfo = request.content.userInfo
        return NotificationResponseSnapshot(
            payload: stringPayload(from: userInfo),
            isRemotePush: request.trigger is UNPushNotificationTrigger,
            source: notificationSource(for: request.trigger),
            requestIdentifier: request.identifier,
            actionIdentifier: response.actionIdentifier,
            keySummary: notificationKeySummary(from: userInfo),
            hasAps: userInfo["aps"] != nil
        )
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
        NotificationRouteParser.messageID(from: payload) ?? "unknown"
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

private extension UIApplication.State {
    var notificationLogValue: String {
        switch self {
        case .active:
            return "foreground"
        case .background:
            return "background"
        case .inactive:
            return "inactive"
        @unknown default:
            return "unknown"
        }
    }
}
