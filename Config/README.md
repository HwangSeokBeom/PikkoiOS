Pikko local configuration

This folder contains local build configuration templates and app runtime configuration.
Do not commit real secrets unless the team explicitly decides they are safe to publish.

## Local secrets

1. Copy `Config/AuthSecrets.example.xcconfig` to one of these local files:
   - `Config/AuthSecrets.xcconfig`
   - `Config/LocalSecrets.xcconfig`
2. Copy `Config/Secrets.xcconfig.sample` to `Config/Secrets.xcconfig` if the build uses `Secrets.xcconfig`.
3. Fill in these values locally:
   - `KAKAO_NATIVE_APP_KEY`
   - `GOOGLE_IOS_CLIENT_ID`
   - `GOOGLE_REVERSED_CLIENT_ID`
   - `PIKKO_BASE_URL`
   - `PIKKO_SESAC_KEY`
   - `PORTONE_USER_CODE`
4. Keep local secret files out of git. `.gitignore` excludes:
   - `Config/AuthSecrets.xcconfig`
   - `Config/LocalSecrets.xcconfig`
   - `Config/Secrets.xcconfig`

For `PIKKO_BASE_URL`, avoid writing `http://...` directly in an xcconfig value because `//` can be parsed as a comment. Use this form:

```xcconfig
PIKKO_URL_SLASH = /
PIKKO_BASE_URL = http:$(PIKKO_URL_SLASH)$(PIKKO_URL_SLASH)pickup.sesac.kr:42678/
```

Both `http://pickup.sesac.kr:42678` and `http://pickup.sesac.kr:42678/` are accepted at runtime.

## PortOne iamport_ios

The current payment bridge uses the `iamport_ios` SDK. This SDK requires `PORTONE_USER_CODE` from the PortOne console and does not use the newer `PORTONE_CHANNEL_KEY` value.

Debug and Release xcconfigs provide placeholders first, then optionally include local secret files. After the includes, `PIKKO_APP_ENV`, `APS_ENVIRONMENT`, and `PAYMENT_TEST_MODE` are set again so a shared local secrets file cannot accidentally switch the build environment.

Expected local payment keys:

```xcconfig
PORTONE_USER_CODE = impXXXXXXXX
PORTONE_PG = html5_inicis
PORTONE_PG_ID = INIpayTest
PORTONE_PAY_METHOD = card
PORTONE_APP_SCHEME = pikko
```

For Release, use production PortOne values and keep `PAYMENT_TEST_MODE = NO` from `Config/Release.xcconfig`.

## GoogleService-Info.plist

`Config/GoogleService-Info.plist` is the iOS client configuration file downloaded from Firebase Console for the `com.pikko.ios` app. `FirebaseApp.configure()` reads this file at app startup.

Place the downloaded file here:

```text
Config/GoogleService-Info.plist
```

The Xcode project has a build phase named `Copy GoogleService-Info.plist`. If the file exists locally, it copies the file into the app bundle as `GoogleService-Info.plist` so Firebase can find it at runtime.

The real plist is ignored by git by default. If team policy later decides this plist is safe to commit, update `.gitignore` intentionally and review the bundle behavior again.

## Firebase Admin SDK JSON

Files such as `pikko-5d57e-firebase-adminsdk-fbsvc-9d11afd2e1.json` are Firebase Admin SDK service account keys for server-side FCM sending only.

Do not:

- Add any Admin SDK JSON file to the iOS app target.
- Add any Admin SDK JSON file to Copy Bundle Resources.
- Commit any Admin SDK JSON file to GitHub.
- Use an Admin SDK JSON file with `FirebaseApp.configure()` in the iOS app.

Admin SDK JSON files contain private keys. They belong on a trusted server, not in an iOS app bundle.

## FCM and APNs

The Pikko app target should have:

- Push Notifications capability enabled.
- Background Modes capability enabled.
- `Remote notifications` checked under Background Modes.
- `Config/Pikko.entitlements` connected for Debug and Release.
- `aps-environment = $(APS_ENVIRONMENT)` in `Config/Pikko.entitlements`.
- `APS_ENVIRONMENT = development` in Debug and Test xcconfig files.
- `APS_ENVIRONMENT = production` in Release xcconfig.
- `UIBackgroundModes` containing `remote-notification` in `Config/Pikko-Info.plist`.

App startup currently configures Firebase and FCM in `App/PikkoApp.swift`:

- `FirebaseApp.configure()` runs once at launch if `GoogleService-Info.plist` exists in the bundle.
- `FirebaseAppDelegateProxyEnabled = NO` is set because APNs and FCM delegate handling is wired manually.
- `UNUserNotificationCenter.current().delegate` is set.
- `Messaging.messaging().delegate` is set.
- Notification permission is requested at launch.
- `application.registerForRemoteNotifications()` is called after the permission response.
- `Messaging.messaging().apnsToken = deviceToken` is set in `didRegisterForRemoteNotificationsWithDeviceToken`.
- FCM token callbacks and the APNs-gated manual token fetch print masked debug logs.
- `Messaging.messaging().token` is not called at launch before APNs registration.

Expected debug logs on a real device:

```text
DEBUG [FCM] Firebase configured
DEBUG [FCM] notification permission granted=true/false
DEBUG [FCM] APNs device token registered
DEBUG [FCM] token fetch after APNs success exists=true prefix=... suffix=... length=...
DEBUG [FCM] didReceiveRegistrationToken exists=true prefix=... suffix=... length=...
```

## Real-device FCM test

1. Confirm Firebase Console has the APNs authentication key uploaded for the iOS app `com.pikko.ios`.
2. Place the iOS client plist at `Config/GoogleService-Info.plist`.
3. Open `Pikko.xcodeproj` and select the `Pikko` scheme.
4. Run on a physical iPhone. APNs registration and push receipt must be verified on a real device.
5. Accept the notification permission prompt.
6. Check the Xcode console for the FCM debug logs above.
7. In Firebase Console or the server sending tool, send a test FCM message to the logged FCM token.
8. For Release/TestFlight, confirm the App ID, provisioning profile, and APNs environment match the Release signing setup.

## Firebase package checks

The app uses Swift Package Manager.

Basic checks:

```sh
xcodebuild -list -project Pikko.xcodeproj
xcodebuild -resolvePackageDependencies -project Pikko.xcodeproj -scheme Pikko
```

The package root `firebase-ios-sdk` can appear grey in Xcode when it is just the package container. The important checks are:

- `Package.resolved` contains `firebase-ios-sdk`.
- The Pikko app target links Firebase products.
- `FirebaseCore` and `FirebaseMessaging` appear under the Pikko target package product dependencies.
- `import FirebaseCore` and `import FirebaseMessaging` compile.
- A Debug simulator build succeeds.

Debug build command:

```sh
xcodebuild -project Pikko.xcodeproj -scheme Pikko -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## XcodeGen

`project.yml` is the source of truth for regenerating the Xcode project when project structure or package dependencies change.

After editing `project.yml`, run:

```sh
xcodegen generate
```

Then re-run package resolve and the Debug build check.

## Runtime guardrails

- Missing or invalid `PIKKO_BASE_URL` stops request creation and surfaces a configuration error instead of falling back to `http://v1/...`.
- Missing `PIKKO_SESAC_KEY` stops protected API calls before the request is sent.
- `$(PIKKO_BASE_URL)`, `<base_url>`, `v1`, `/v1`, and `http://v1` are treated as invalid.

## Info.plist exposure

The app keeps `PIKKO_BASE_URL` / `PIKKO_SESAC_KEY` keys and also exposes camel-case aliases:

- `PIKKOBaseURL`
- `PIKKOSeSACKey`
- `KakaoNativeAppKey`
- `GoogleIOSClientID`
- `GoogleReversedClientID`

`AppConfiguration` reads both forms, so xcconfig -> Build Settings -> Info.plist -> runtime stays aligned.

## ATS exception policy

`Config/Pikko-Info.plist` allows insecure HTTP loads only for `pickup.sesac.kr`.

This is limited to the current training server that responds on `http://pickup.sesac.kr:42678/`.

Do not widen this to `NSAllowsArbitraryLoads`. Replace this exception with HTTPS before production release if the backend supports TLS.

## App Review notes

- If review requires authenticated flows, prepare review notes with a test account or keep guest browsing available.
- `Sign in with Apple` capability is declared in `Config/Pikko.entitlements`, but the App ID and signing assets still need to be verified in the Apple Developer portal.

## Remaining TODOs

- 실제 로그인 구현 연결
- 회원가입 구현
- Google 포함 social login endpoint path 최종 확정
- `/v1/auth/refresh` 포함 서버 세션 복원 정책 최종 확정
- restoreSession 실제화 및 서버 세션 복원 정책 확정
- refresh token 자동 갱신 시점과 401/419/420 정책 정교화
- logout 시 provider SDK logout/revoke 연동
- 사용자 주문 내역 API 인증 정책 세부 고도화
- Community 작성/댓글 인증 UX를 더 자연스럽게 다듬기
- Community pending action 재개 UX와 draft persistence 확장
- 글 작성 이미지 업로드 실제화
- Apple Developer capability와 release signing 실제 계정 설정 확인
- CI/Release secret 주입 방식 확정
- 전용 pickup tracking root 구현 시 현재 Home fallback 교체
