# Pikko iOS Codebase Interview Study Guide

이 문서는 Pikko iOS 앱을 만든 개발자가 면접 또는 코드 리뷰에서 자신의 코드를 설명할 수 있도록 정리한 학습용 문서이다. 기준 코드는 현재 저장소의 Swift/iOS 코드이며, 앱 동작을 변경하지 않고 정적 분석한 내용만 담았다.

## 1. Project Overview

Pikko는 위치 기반 가게 탐색, 주문/결제, 커뮤니티, 채팅, 숏폼/영상 재생, 알림을 포함한 iOS 클라이언트 앱이다. iOS 앱 관점에서 사용자는 소셜/이메일 인증 후 홈에서 주변 가게와 인기 가게를 보고, 장바구니와 주문/결제를 진행하며, 커뮤니티 게시글을 작성하거나 댓글을 달고, 가게 또는 사용자와 채팅하고, 영상 목록에서 HLS 영상을 재생한다.

- 주요 사용자 기능: 인증, 홈/가게 탐색, 장바구니, 주문/결제, 커뮤니티 목록/상세/댓글, 채팅 목록/방/전송, 영상 목록/재생, 푸시 알림, 위치 기반 거리 계산.
- 주요 기술 영역: SwiftUI 앱 구조, UIKit 기반 앱 델리게이트 연동, MVVM/Presenter 스타일 상태 관리, 수동 DI, Repository/RemoteDataSource/Mapper, URLSession 네트워크, Keychain/UserDefaults/CoreData 저장소, Socket.IO, Firebase Messaging, AVPlayer/HLS, CoreLocation, PortOne 결제.
- 전체 아키텍처: `App/DI/AppDIContainer.swift`가 전역 의존성을 만들고 `FeatureBuilderFactory.swift`가 기능별 화면을 구성한다. `Features/*`의 Presenter/ViewModel이 UI 상태를 소유하고, `Domain/*`의 UseCase/Repository 프로토콜을 통해 `Data/*` 구현체와 통신한다.
- 데이터 흐름: API/Socket/CoreData/UserDefaults/Keychain에서 가져온 데이터가 DTO 또는 저장 모델로 들어오고, Mapper가 Domain Entity로 변환한다. Presenter/ViewModel은 Entity를 화면 상태로 가공하고 SwiftUI View가 `@ObservedObject`, `@StateObject`, `@EnvironmentObject`로 렌더링한다.

면접에서 설명하기 좋은 표현:

> “Pikko iOS는 SwiftUI 기반 앱이지만 AppDelegate를 함께 사용해 Firebase Messaging, APNs, URL callback 같은 UIKit 라이프사이클 기능을 처리합니다. 기능별로 Presenter/ViewModel, UseCase, Repository, RemoteDataSource, Mapper를 나누어 API DTO와 UI 상태가 직접 섞이지 않도록 구성했습니다.”

## 2. High-Level Architecture

### SwiftUI + UIKit AppDelegate Bridge

- 무엇인가: 화면은 SwiftUI 중심이고, Firebase/APNs/URL callback은 `UIApplicationDelegate`로 처리한다.
- 코드 위치: `App/PikkoApp.swift`, `App/PikkoAppDelegate.swift`, `App/Root/RootScene.swift`.
- 실무적인 이유: SwiftUI 앱에서도 푸시 토큰, UNUserNotificationCenter, Firebase Messaging delegate, APNs 등록은 UIKit delegate가 가장 명확하다.
- 장점: SwiftUI 화면 구성과 UIKit 시스템 이벤트 처리를 분리할 수 있다.
- 단점: 앱 시작점이 `PikkoApp`과 `PikkoAppDelegate`로 나뉘어 초기화 순서를 이해해야 한다.
- 대안: 순수 UIKit SceneDelegate 구조, 또는 SwiftUI lifecycle만 사용하고 AppDelegate adaptor 최소화.
- 현재 프로젝트에서 괜찮은 이유: FCM, APNs, Kakao/Google URL callback, PortOne 결제 callback이 있어 AppDelegate bridge가 현실적인 선택이다.
- 앞으로 개선한다면: AppDelegate의 로그/알림 처리 일부를 더 작은 서비스로 분리해 테스트 가능성을 높일 수 있다.
- 면접 설명 스크립트: “SwiftUI App lifecycle을 쓰지만 iOS 시스템 이벤트는 AppDelegate adaptor로 받아 Firebase와 APNs 연동을 안정적으로 처리했습니다.”

### MVVM/Presenter State Management

- 무엇인가: SwiftUI View는 렌더링을 담당하고 `Presenter` 또는 `ViewModel`이 상태와 액션 처리를 담당한다.
- 코드 위치: `Features/Auth/AuthPresenter.swift`, `Features/Community/CommunityPresenter.swift`, `Features/Chat/ChatPresenter.swift`, `Features/Video/VideoListPresenter.swift`, `Features/VideoPlayer/VideoPlayerViewModel.swift`.
- 실무적인 이유: SwiftUI View에 네트워크/비즈니스 로직을 넣지 않고 상태 전이를 한 곳에 모으기 위함이다.
- 장점: 화면 상태, 로딩, 에러, 낙관적 업데이트, requestID/generation 방어를 테스트하거나 추적하기 쉽다.
- 단점: Presenter가 커지면 화면 로직과 도메인 조합 로직이 한 파일에 몰릴 수 있다. `ChatInteractor.swift`처럼 한 파일 안에 모델/DTO/Repository/Interactor가 함께 있는 영역은 분리가 더 필요하다.
- 대안: Reducer 기반 TCA, Combine store, 기능별 module package, 더 엄격한 Clean Architecture.
- 현재 프로젝트에서 괜찮은 이유: 기능 수가 많고 서버 연동이 복잡해 View와 상태 소유자를 나눈 효과가 크다.
- 앞으로 개선한다면: Chat/Community처럼 큰 Presenter는 action reducer와 effect layer로 나누거나 테스트 대상 단위를 더 작게 만들 수 있다.
- 면접 설명 스크립트: “View는 상태를 표시하고 사용자 이벤트를 전달하며, Presenter/ViewModel이 async 작업과 상태 전이를 담당합니다.”

### Repository / RemoteDataSource / Mapper

- 무엇인가: API 호출 구현은 RemoteDataSource, 비즈니스 접근점은 Repository, DTO-Domain 변환은 Mapper가 담당한다.
- 코드 위치: `Data/Remote/AuthRemoteDataSource.swift`, `Data/Repositories/AuthRepositoryImpl.swift`, `Data/Mappers/VideoMapper.swift`, `Data/Remote/CommunityRemoteDataSource.swift`, `Data/Mappers/CommunityMapper.swift`.
- 실무적인 이유: 서버 응답 형식 변경과 화면 모델 변경의 영향을 줄이기 위해서다.
- 장점: DTO decoding fallback, URL normalization, domain sanitizing을 UI 밖에서 처리할 수 있다.
- 단점: 파일 수와 계층이 늘어나 단순 API에는 다소 무겁다.
- 대안: 작은 앱에서는 APIClient가 Domain Entity를 바로 반환하거나, feature-local service만 둘 수 있다.
- 현재 프로젝트에서 괜찮은 이유: 영상 DTO, 커뮤니티 DTO, 이미지 URL, 인증 토큰, 채팅 메시지처럼 서버 응답 예외가 많아 Mapper 계층이 유용하다.
- 앞으로 개선한다면: Chat처럼 feature 파일에 몰린 DTO/Repository를 `Data/Remote`, `Data/Mappers`, `Domain`으로 분리하면 일관성이 좋아진다.
- 면접 설명 스크립트: “서버 DTO는 앱 도메인과 다르기 때문에 Mapper에서 누락 필드, 경로 보정, 중복 제거를 처리해 UI가 안정적인 Domain 모델만 보도록 했습니다.”

### Manual Dependency Injection

- 무엇인가: 외부 DI 프레임워크 없이 `AppDIContainer`와 `FeatureBuilderFactory`가 의존성을 직접 생성/주입한다.
- 코드 위치: `App/DI/AppDIContainer.swift`, `App/DI/FeatureBuilderFactory.swift`.
- 실무적인 이유: 앱 규모 대비 런타임 DI 프레임워크 없이 의존성 흐름을 명시적으로 관리하기 위함이다.
- 장점: 생성 순서와 소유권이 코드에 드러난다. 테스트에서 mock repository/usecase를 주입하기 쉽다.
- 단점: `AppDIContainer`가 커지고 기능이 추가될수록 composition root가 비대해진다.
- 대안: Factory 모듈 분리, protocol 기반 assembler, Swift package 단위 feature module, Resolver/Swinject 같은 DI 프레임워크.
- 현재 프로젝트에서 괜찮은 이유: 전역 상태, 인증 토큰, APIClient, 알림, 위치, 이미지 로더처럼 공유 의존성이 많아 중앙 composition root가 이해하기 쉽다.
- 앞으로 개선한다면: Auth/Video/Chat/Community 별 builder를 별도 파일로 나누고 `AppDIContainer`는 shared dependency만 보유하도록 줄일 수 있다.
- 면접 설명 스크립트: “명시적 DI를 선택해 앱 시작 시점에 공통 인프라를 만들고 기능 builder에서 화면별 의존성을 조립했습니다.”

### Coordinator / Router Style

- 무엇인가: 완전한 UIKit Coordinator는 아니지만, 기능별 Router 객체와 `RootTabView`의 `NavigationPath`가 화면 이동을 담당한다.
- 코드 위치: `App/Root/RootTabView.swift`, `Features/Community/CommunityRouter.swift`, `Features/Video/VideoListRouter.swift`, `Features/Chat/ChatRouter.swift`, `Features/Auth/AuthRouter.swift`.
- 실무적인 이유: SwiftUI View 내부에서 직접 많은 destination을 만들면 화면 전환 책임이 섞이므로 route 상태를 분리하기 위함이다.
- 장점: 알림 route, 탭 선택, sheet/detail 이동을 한 곳에서 처리하기 쉽다.
- 단점: 탭별 path와 sheet 상태가 늘어나면 `RootTabView`가 복잡해진다.
- 대안: enum 기반 AppRoute store, NavigationStack coordinator, deep link router 전용 모듈.
- 현재 프로젝트에서 괜찮은 이유: 탭 기반 앱이고 알림에서 주문/채팅/커뮤니티로 진입하는 요구가 있어 중앙 routing이 필요하다.
- 앞으로 개선한다면: notification route와 일반 route를 공통 AppRoute enum으로 통합하고 deep link 파서를 분리할 수 있다.
- 면접 설명 스크립트: “탭별 NavigationPath를 유지하고 알림이나 내부 이벤트가 들어오면 RootTabView가 올바른 탭을 선택한 뒤 destination을 push/sheet로 보여줍니다.”

## 3. App Startup and Lifecycle

앱 시작은 `App/PikkoApp.swift`의 `@main PikkoApp`에서 시작된다. `@UIApplicationDelegateAdaptor(PikkoAppDelegate.self)`로 UIKit delegate를 연결하고, init에서 Firebase 설정, DI container 생성, `AppState` 생성, social auth 준비를 수행한다.

시작 흐름:

1. `PikkoApp.init`이 `PikkoAppDelegate.configureFirebaseIfNeeded`를 호출한다.
2. `AppDIContainer`가 `AppConfiguration`, `TokenStore`, `APIClient`, repositories, notification service, location/image/payment/socket 관련 의존성을 만든다.
3. `RootScene`이 `AppBootstrapper.bootstrapIfNeeded()`를 실행한다.
4. `SessionRestorer.restoreIfAvailable()`가 Keychain의 토큰과 UserDefaults의 session snapshot을 이용해 세션을 복원한다.
5. 복원 성공 시 `SessionStore.establishAuthenticatedSession` 또는 profile fetch 결과로 인증 상태가 구성되고, 실패 시 `clearSession`으로 인증 화면을 보여준다.
6. `RootScene`은 `launchPhase == .ready` 이후 `sessionStore.isAuthenticated`에 따라 `RootTabView` 또는 `AuthGateView`를 표시한다.
7. FCM device token이 있고 로그인 상태이면 `FeatureBuilderFactory.syncCurrentDeviceTokenIfNeeded`가 서버에 `PUT /v1/users/deviceToken`을 호출한다.

주요 파일:

- `App/PikkoApp.swift`: 앱 엔트리, DI, URL callback.
- `App/PikkoAppDelegate.swift`: Firebase, APNs, FCM, notification delegate.
- `App/Root/RootScene.swift`: splash/auth/main gate.
- `App/Bootstrap/AppBootstrapper.swift`: bootstrap one-shot guard.
- `App/Bootstrap/SessionRestorer.swift`: session restore.
- `App/State/SessionStore.swift`: 인증 상태와 토큰 저장 연동.
- `Config/Pikko-Info.plist`: URL scheme, Firebase proxy 비활성화, 위치 권한 문구, ATS/media 설정.

초기 화면 결정 로직:

- `RootScene`은 `.idle` 또는 `.restoringSession` 동안 `SplashScreenView`를 보여준다.
- `.ready`가 되면 `sessionStore.isAuthenticated`가 true이면 `RootTabView`, false이면 `AuthGateView`를 보여준다.
- 인증 상태는 `SessionStore.currentSession != nil`과 Keychain/UserDefaults 복원 결과에 의해 결정된다.

푸시 알림 초기화:

- `PikkoAppDelegate`가 `UNUserNotificationCenter.current().delegate`와 `Messaging.messaging().delegate`를 설정한다.
- 사용자가 권한을 허용하면 `UIApplication.shared.registerForRemoteNotifications()`를 호출한다.
- APNs token을 `Messaging.messaging().apnsToken`에 전달하고, FCM token을 가져와 `.pikkoFCMTokenDidRefresh` NotificationCenter 이벤트로 전달한다.
- `SessionStore`가 device token을 저장하고 로그인 후 서버 동기화를 트리거한다.

환경/빌드 설정:

- `project.yml`의 `PIKKO_BASE_URL`, `PIKKO_SESAC_KEY`, Kakao/Google/PortOne 키가 Info.plist로 주입된다.
- `Config/README.md`는 로컬 secrets와 `GoogleService-Info.plist` 배치 방법을 설명한다.
- `FirebaseAppDelegateProxyEnabled=false`이므로 APNs/FCM delegate 연결을 앱이 직접 처리한다.

면접 질문과 답변:

- “What happens when the app launches?”
  - `PikkoApp`이 Firebase와 DI를 구성하고 `RootScene`이 세션 복원을 수행한 뒤 인증 여부에 따라 `RootTabView` 또는 `AuthGateView`를 표시한다.
- “How do you decide whether to show login or main screen?”
  - `SessionStore.isAuthenticated`와 `launchPhase`를 기준으로 한다. 세션 복원은 `SessionRestorer`가 Keychain token과 snapshot/profile API를 이용한다.
- “Where are global dependencies initialized?”
  - `App/DI/AppDIContainer.swift`가 composition root이고, 화면별 의존성은 `FeatureBuilderFactory.swift`에서 만든다.
- “What would you improve in the startup flow?”
  - AppDelegate 알림 처리, DI 생성, notification routing이 커져 있으므로 service별 파일과 test seam을 늘리고, configuration validation 실패를 더 명확한 startup error로 노출할 수 있다.

## 4. Navigation and Routing

Pikko는 SwiftUI `NavigationStack`과 탭별 `NavigationPath`를 사용한다. 메인 탭은 `RootTab` enum의 `.home`, `.order`, `.video`, `.community`, `.profile`이다.

주요 파일:

- `App/Root/RootTab.swift`: 탭 정의.
- `App/Root/RootTabView.swift`: 탭별 NavigationPath, notification route, sheet/detail presentation.
- `App/DI/FeatureBuilderFactory.swift`: destination view 생성.
- `Features/*/*Router.swift`: 기능별 pending route.

### Main Tab Flow

- Entry point: `RootScene`에서 인증 성공 후 `RootTabView`.
- Destination: Home, Order, Video, Community, Profile.
- Required parameters: 탭 자체는 없음. 상세 화면은 storeID, orderID, videoID, postID, chat room context 등이 필요하다.
- Ownership: `RootTabView`가 탭 선택과 destination view 조립을 소유한다.
- Potential risks: 탭별 path, sheet state, notification route가 한 파일에 많아지면 추적이 어려워진다.
- Improvement ideas: `AppRoute` enum과 route reducer를 만들어 알림/딥링크/탭 라우팅을 통합한다.

### Video Detail Flow

- Entry point: `VideoListPresenter.didSelectVideo`.
- Destination: `FeatureBuilderFactory.makeVideoPlayerView`.
- Required parameters: `Video` 또는 `videoID`.
- Ownership: 목록 Presenter는 선택 이벤트를 Router에 전달하고, 실제 화면 생성은 builder가 담당한다.
- Potential risks: 선택한 영상의 stream fetch 실패와 list refresh가 겹칠 수 있으므로 player generation/request guard가 중요하다.
- Improvement ideas: video detail route를 stable id 기반으로 통일하고, stream prefetch 여부를 정책화한다.

### Community Detail Flow

- Entry point: community list item tap, notification route `.communityPost`, compose/edit completion.
- Destination: community detail view.
- Required parameters: `postID`.
- Ownership: `CommunityRouter`와 `RootTabView`/builder가 분담한다.
- Potential risks: 알림으로 들어온 postID와 현재 active post tracking이 충돌하면 foreground notification suppression이 오동작할 수 있다.
- Improvement ideas: active tracker lifecycle을 ViewModel scope에 더 명확히 묶고 route source를 기록한다.

### Chat Flow

- Entry point: profile/chat list, store detail inquiry, user chat, notification route `.chatRoom`.
- Destination: chat room.
- Required parameters: roomID 또는 opponentID/storeID context.
- Ownership: `ChatPresenter`가 방 생성/조회와 로컬 캐시 scope를 준비하고, `ChatRouter`/builder가 화면을 연다.
- Potential risks: roomID만으로는 store-scoped chat 충돌이 가능해 `ChatRoomStoreContext`와 local cache key가 필요하다.
- Improvement ideas: chat scope를 Domain 타입으로 분리하고 모든 repository/local/socket API가 동일 scope를 받도록 더 강제한다.

### Notification Routing

- Entry point: `PikkoAppDelegate` remote notification tap 또는 foreground payload.
- Destination: order detail, payment receipt, chat room, community post/list, order list.
- Required parameters: payload에서 추출한 orderID, chatRoomID, postID 등.
- Ownership: `DefaultAppNotificationService`가 payload를 `AppNotificationRoute`로 변환하고, `AppNotificationRouter`가 `AppState` 또는 pending store에 전달한다.
- Potential risks: payload key가 서버에서 바뀌면 route 추출 실패. 미인증 상태에서는 pending route 저장/복원이 중요하다.
- Improvement ideas: notification payload schema test를 추가하고, unknown payload diagnostics를 샘플링 로그로 남긴다.

딥링크는 `PikkoApp.onOpenURL`에서 PortOne payment return, Kakao/Google social login URL을 먼저 처리하고, 그 외 URL은 `appState.pendingDeepLink`에 저장한다. 구체적인 deep link parser는 현재 코드에서 찾지 못했다.

## 5. Authentication Flow

Pikko 인증은 Kakao/Apple 소셜 로그인, 이메일 로그인/회원가입, debug stub sign-in을 포함한다. Google SDK 의존성은 있지만 `GoogleSignInService.swift`에 현재 Swagger 기준으로 Google backend login은 노출하지 않는다는 placeholder가 있다.

주요 파일:

- `Features/Auth/AuthPresenter.swift`: 인증 화면 상태와 액션.
- `Features/Auth/AuthInteractor.swift`: provider 가시성, 입력 검증, social credential 처리.
- `Core/Platform/Auth/SocialAuthService.swift`: provider별 로그인 service dispatch.
- `Core/Platform/Auth/KakaoLoginService.swift`: Kakao SDK login.
- `Core/Platform/Auth/AppleSignInService.swift`: Apple Sign In, nonce/id token.
- `Data/Remote/AuthRemoteDataSource.swift`: auth/profile/deviceToken API endpoint.
- `Data/Repositories/AuthRepositoryImpl.swift`: session restore, login, logout, profile.
- `App/State/SessionStore.swift`: 인증 상태, token/snapshot/device token.
- `Core/Storage/KeychainTokenStore.swift`: access/refresh token Keychain 저장.

토큰 저장:

- access token과 refresh token은 `KeychainTokenStore`가 Keychain generic password item으로 저장한다.
- 사용자 profile snapshot은 `UserDefaultsSessionSnapshotStore`가 UserDefaults에 저장한다.
- FCM device token도 UserDefaults에 저장하고, 사용자별 sync signature로 중복 서버 호출을 막는다.

인증 API:

- Kakao login: `POST /v1/users/login/kakao`, body `oauthToken`, `deviceToken`, auth `.none`.
- Apple login: `POST /v1/users/login/apple`, body `idToken`, `deviceToken`, auth `.none`.
- Email login: `POST /v1/users/login`.
- Signup: `POST /v1/users/join`.
- Email validation: `POST /v1/users/validation/email`.
- Profile: `GET/PUT /v1/users/me/profile`.
- Profile image: multipart `/v1/users/profile/image`.
- Device token: `PUT /v1/users/deviceToken`.
- Logout: `POST /v1/users/logout`.

인증된 요청:

- `RequestBuilder`가 `AuthorizationPolicy.accessToken`이면 Keychain의 access token을 읽어 `Authorization` header를 붙인다.
- 모든 요청에는 `SesacKey` header가 들어간다. 사용자 문서에서는 SeSACKey라고 부르지만 현재 코드의 실제 header 이름은 `SesacKey`이다.
- 401/419는 `APIClient`가 `TokenRefreshCoordinator`를 통해 refresh를 한 번 시도하고 원 요청을 재실행한다.
- refresh 실패 또는 인증 만료는 `.pikkoSessionDidInvalidate`를 통해 `SessionStore`가 세션을 비운다.

로그아웃:

- `AuthRepositoryImpl.logout`은 서버 logout 호출 중 인증 실패가 나도 클라이언트 세션 정리를 계속한다.
- `SessionStore.clearSession`은 token, session snapshot, device token sync state를 지운다.

면접 답변:

- “How is authentication state managed?”
  - `SessionStore`가 단일 인증 상태 소유자이다. Keychain token, UserDefaults snapshot, NotificationCenter token refresh/session invalidation 이벤트를 관리한다.
- “Where are tokens stored?”
  - access/refresh token은 `Core/Storage/KeychainTokenStore.swift`의 Keychain에 저장된다. profile snapshot은 UserDefaults다.
- “How do authenticated requests attach headers?”
  - `RequestBuilder`가 endpoint의 `AuthorizationPolicy`를 보고 `Authorization`, `RefreshToken`, `SesacKey`를 구성한다.
- “How would you make this more secure?”
  - DEBUG 영상 stream URL 전체 출력 제거, 민감 로그 redaction 검증 테스트 추가, refresh token lifecycle 강화, Keychain accessibility 옵션 검토가 필요하다.
- “How do you prevent invalid sessions from showing protected screens?”
  - `RootScene`이 `SessionStore.isAuthenticated`를 기준으로 auth/main gate를 나누고, `APIClient` 인증 실패 시 session invalidation notification을 발생시킨다.

## 6. Networking Layer

네트워크 계층은 `Endpoint`, `RequestBuilder`, `APIClient`, `TokenRefreshCoordinator`, `HTTPStatusMapper`, `NetworkCoding`, `URLBuilder`로 구성된다.

핵심 파일:

- `Core/Network/Endpoint.swift`: path, method, query, body, authorization policy, timeout을 담는 endpoint 타입.
- `Core/Network/RequestBuilder.swift`: URLRequest 생성, header injection, body encoding.
- `Core/Network/APIClient.swift`: URLSession 실행, response decoding, token refresh retry, error mapping.
- `Core/Network/TokenRefreshCoordinator.swift`: refresh 중복 방지 actor.
- `Core/Network/HTTPStatusMapper.swift`: status code를 `NetworkError`로 변환.
- `Core/Network/NetworkCoding.swift`: JSON encoder/decoder, 날짜 parsing.
- `Core/Network/URLBuilder.swift`: base URL/path 결합과 origin URL 생성.
- `Core/Network/AuthorizationPolicy.swift`: `.none`, `.accessToken`, `.refreshToken`, `.fileAuthorized`.

요청 생성:

- endpoint path는 base URL과 결합된다.
- query는 `URLQueryItem`으로 구성된다.
- `SesacKey`는 모든 요청에 붙는다.
- access-token API는 `Authorization` header를 붙인다.
- refresh API는 `Authorization`과 `RefreshToken` header를 모두 붙인다.
- file authorized image request도 `.fileAuthorized` policy를 사용한다.

응답 처리:

- 2xx는 `NetworkCoding.decode`로 DTO를 decoding한다.
- 401/419는 access-token/file-auth 요청에서 refresh를 한 번 시도한다.
- 403 video stream은 session invalidation을 하지 않도록 예외 처리한다.
- 444는 path/method mismatch 성격의 notFound로 로깅한다.
- transport error는 안전한 method에서 제한적으로 한 번 retry한다.

중요 API 모듈:

### AuthRemoteDataSource

- Responsibility: 로그인, 회원가입, profile, device token, logout.
- Request path/method: `/v1/users/login/kakao`, `/v1/users/login/apple`, `/v1/users/login`, `/v1/users/join`, `/v1/users/me/profile`, `/v1/users/deviceToken`.
- DTO shape: login response는 token과 user profile을 포함해 `UserSession`으로 mapping된다.
- Domain mapping: `AuthRepositoryImpl`이 DTO를 `UserSession`/profile entity로 변환한다.
- Error behavior: auth 실패는 화면 에러 또는 session invalidation으로 이어진다.
- UI impact: `AuthPresenter`와 `RootScene`의 auth/main gate가 바뀐다.

### VideoRemoteDataSource

- Responsibility: 영상 목록, stream URL, like.
- Request path/method: `GET /v1/videos`, `GET /v1/videos/{videoId}/stream`, `POST /v1/videos/{videoId}/like`.
- DTO shape: list root array/data/videos/items/results fallback, stream_url/qualities/subtitles.
- Domain mapping: `VideoMapper`가 duplicate/empty ID 제거, thumbnail URL 보정, stream quality URL 보정을 수행한다.
- Error behavior: empty videoID는 client error, 403 stream은 session invalidation 없이 player error로 처리.
- UI impact: `VideoListPresenter`, `VideoPlayerViewModel`.

### CommunityRemoteDataSource

- Responsibility: 게시글 CRUD, 파일 업로드, 댓글, geolocation feed, search, like.
- Request path/method: `GET /v1/posts/geolocation`, `GET /v1/posts/{postID}`, `POST /v1/posts`, `POST /v1/posts/{postID}/comments`, `POST /v1/posts/{postID}/like`.
- DTO shape: posts, comments/replies, cursor.
- Domain mapping: `CommunityMapper`가 이미지 경로와 cursor를 정규화한다.
- Error behavior: list/location failure는 Presenter가 empty/error state로 변환한다.
- UI impact: feed reload, detail/comment state, notification snapshot.

### ChatRemoteDataSource

- Responsibility: 채팅방 목록/생성, 메시지 조회/전송, 파일 업로드.
- Request path/method: `GET /v1/chats`, `POST /v1/chats`, `GET /v1/chats/{roomID}`, `POST /v1/chats/{roomID}`.
- DTO shape: room/message/sender/files.
- Domain mapping: `ChatMapper`가 sender와 file URL을 Domain으로 변환한다.
- Error behavior: `ChatFeatureError`로 인증/네트워크/일반 오류를 구분한다.
- UI impact: room list, optimistic message replacement, socket merge.

### Store/Order/Checkout

- Responsibility: 가게 검색/상세/좋아요, 장바구니/주문/결제.
- Main files: `Data/Remote/StoreRemoteDataSource.swift`, `Data/Remote/OrderRemoteDataSource.swift`, `Features/StoreDetail/*`, `Features/Checkout/*`, `Core/Platform/Payment/PortOnePaymentGateway.swift`.
- UI impact: 홈/상세/주문 탭/결제 sheet.

강점:

- endpoint policy와 request builder가 분리되어 header injection이 일관적이다.
- token refresh가 actor로 dedupe되어 동시 refresh 폭주를 줄인다.
- status code mapping과 debug logging이 있어 서버/API 문제를 추적하기 좋다.
- DTO decoding이 서버 응답 변형에 관대해 앱 crash 가능성을 줄인다.

약점:

- 일부 DTO/Repository가 feature 파일에 몰려 있다. 특히 Chat은 `Features/Chat/ChatInteractor.swift`가 매우 많은 책임을 가진다.
- DEBUG 로그 중 영상 stream URL 전체 출력은 민감 정보 노출 위험이 있다.
- retry 정책이 일부 인프라에 있고 feature별 재시도 정책과 분리되어 있어 일관성 설명이 필요하다.

개선:

- Chat DTO/Remote/Mapper/Repository를 Data/Domain 계층으로 이동.
- status code별 사용자 메시지 정책을 별도 mapper로 분리.
- network logging redaction 테스트 확대.
- 영상/HLS diagnostic logger에서 full token URL 출력 제거.

## 7. Video Feature

영상 기능은 목록 API, stream URL API, HLS URL 정규화, AVPlayer 재생, 품질 선택, HLS probe/error classification으로 구성된다.

주요 파일:

- `Data/Remote/VideoEndpoint.swift`
- `Data/Remote/VideoRemoteDataSource.swift`
- `Data/DTOs/Video/VideoDTO.swift`
- `Data/Mappers/VideoMapper.swift`
- `Domain/Entities/Video/Video.swift`
- `Domain/Entities/Video/VideoStream.swift`
- `Features/Video/VideoListPresenter.swift`
- `Features/Video/VideoListViewState.swift`
- `Features/VideoPlayer/VideoPlayerViewModel.swift`
- `Features/VideoPlayer/VideoPlayerView.swift`
- `Tests/VideoFeatureTests.swift`

### Video List API Flow

`VideoListPresenter`가 onAppear/refresh/retry/pagination 액션을 받으면 `FetchVideosUseCase`를 통해 repository를 호출한다. RemoteDataSource는 `GET /v1/videos?limit=&next=`를 호출하고, DTO는 root array 또는 `data`, `videos`, `items`, `results` key를 모두 허용한다. `VideoMapper`는 빈 ID와 중복 ID를 제거하고, thumbnail 경로를 `AuthorizedFileURLResolver`로 보정한다.

상태 관리는 `VideoListViewState`가 담당한다. 목록은 `videos`, `nextCursor`, `isLoading`, `isRefreshing`, `isPaging`, `errorMessage` 등을 가진다. 좋아요는 optimistic update 후 실패 시 rollback한다.

### Playback Start Flow

1. 사용자가 영상 목록에서 셀을 탭한다.
2. `VideoListPresenter`가 선택한 `Video`를 router에 전달한다.
3. `FeatureBuilderFactory.makeVideoPlayerView`가 `VideoPlayerViewModel`을 생성한다.
4. `VideoPlayerView.task`가 `loadStreamIfNeeded()`를 호출한다.
5. ViewModel이 `FetchVideoStreamUseCase`로 `GET /v1/videos/{video_id}/stream`을 호출한다.
6. 응답의 `stream_url`과 `qualities`를 `VideoMapper.VideoURLResolver`가 재생 가능한 URL로 보정한다.
7. `HLSProbeService`가 token-only HLS URL을 probe해 playable candidate를 고른다.
8. `AVURLAsset(url:)`, `AVPlayerItem`, `AVPlayer`를 만들어 재생한다.

### HLS Streaming Flow

중요한 현재 구현:

- 앱은 `GET /v1/videos/{video_id}/stream`을 호출한다.
- 이 요청에는 access token `Authorization`과 앱 키 `SesacKey` header가 포함된다.
- stream API 응답에는 `stream_url`과 `qualities`가 있고, HLS m3u8 URL에는 token query가 포함된다.
- HLS m3u8 URL은 token query만으로 재생 가능해야 한다.
- AVPlayer에 custom Authorization header를 붙이는 방식은 child playlist/segment 요청까지 안정적으로 보장하기 어렵기 때문에 token query URL을 선호한다.
- 클라이언트는 상대 HLS URL을 API origin 기준으로 해석하되 raw path, raw query, token 길이를 보존한다.
- quality URL에 query가 없으면 stream URL의 token query를 복사한다.
- HLS 요청이 420이고 body에 “This service ... only”가 포함되면 `serverServiceRoutingMismatch`로 분류한다. 이는 클라이언트 header 문제가 아니라 서버가 발급한 token/path/origin이 HLS service guard와 맞지 않는 상황으로 본다.

관련 코드:

- `VideoURLResolver` in `Data/Mappers/VideoMapper.swift`: 상대 URL 해석, query 보존, token query 복사.
- `HLSProbeClient` in `Features/VideoPlayer/VideoPlayerViewModel.swift`: Authorization/SeSAC/Sesac header를 제거하고 Range probe 요청.
- `HLSProbeService`: master/media playlist 판별, status code classification.
- `HLSPlaylistDiagnostics`: DEBUG 환경 변수 `PIKKO_HLS_DEBUG_DIAGNOSTICS=1`일 때 variant/segment token 누락 여부 점검.

### AVPlayer와 URL 책임

AVPlayer는 최종적으로 재생 가능한 HLS playlist URL을 받아야 한다. AVPlayer가 첫 m3u8을 읽은 뒤 variant playlist와 segment를 이어서 요청하기 때문에, 인증 정보가 첫 요청에만 있거나 query가 손실되면 재생 중간에 실패할 수 있다. 그래서 이 앱은 `Authorization` header를 AVPlayer에 의존하지 않고 서버가 발급한 token query URL을 사용한다.

클라이언트 책임:

- stream API를 인증 header로 호출한다.
- 응답 URL을 정확히 보존하고 상대 URL을 올바른 origin에 붙인다.
- query/token을 손실하지 않는다.
- HLS probe 결과를 바탕으로 사용자에게 적절한 에러를 보여준다.
- 무한 retry를 막는다.
- generation/request guard로 오래된 재생 결과가 UI를 덮어쓰지 않게 한다.

서버 책임:

- stream API가 실제 HLS 서비스에서 허용되는 origin/path/token 조합을 발급한다.
- playlist 내부 variant/segment URI에도 필요한 token을 유지한다.
- 420 service guard가 발생하지 않도록 API와 HLS service routing을 일치시킨다.

### Retry, Cancel, Generation

`VideoPlayerViewModel`은 다음 방어 장치를 갖는다.

- `activeStreamRequestKey`: 같은 video/quality에 대한 중복 stream fetch 방지.
- `playbackGeneration`: player item 교체/취소 시 generation을 증가시켜 stale async 결과를 무시.
- `attemptedFallbackQualities`: transient 404/5xx/network에서만 품질 fallback을 제한적으로 시도.
- `didRefreshAfterServerServiceRoutingMismatch`: 420 service mismatch 후 stream re-fetch를 한 번만 허용해 무한 루프를 막는다.
- 420/444 같은 terminal error는 품질 fallback이나 무한 retry 대상에서 제외한다.

무한 retry가 위험한 이유:

- 서버 발급 URL 자체가 잘못된 경우 재시도해도 같은 실패가 반복된다.
- AVPlayer item 교체와 probe 요청이 겹치면 UI 상태가 흔들릴 수 있다.
- 사용자의 데이터/배터리 소모와 서버 부하가 증가한다.
- 실제 원인을 가리는 noisy log가 생긴다.

### Error States

- missing authenticated session: tokenStore에 인증 token이 없으면 stream fetch 전에 막는다.
- unauthorized/token expired: APIClient refresh 또는 player error로 처리.
- file missing: HLS 404.
- server returned JSON: m3u8 대신 JSON이 오면 서버 응답/라우팅 문제로 분류.
- `serverServiceRoutingMismatch`: 420 “This service ... only”.
- player item failed/stalled: `VideoPlayerView`가 AVPlayerItem notifications와 error/access logs를 관찰한다.

면접 질문:

- “How does video playback start from tapping a video?”
  - 목록 Presenter가 Video를 route로 넘기고, Player ViewModel이 stream API를 호출해 HLS URL을 보정/probe한 뒤 AVPlayerItem을 만든다.
- “Why do you fetch a stream URL separately from the video list?”
  - 목록은 metadata와 thumbnail 중심이고, 재생 URL은 인증/만료/token이 걸린 리소스라 실제 재생 시점에 별도 발급받는 것이 안전하다.
- “How do you handle HLS token URLs?”
  - stream API 응답의 raw query를 보존하고 상대 URL은 API origin에 붙인다. quality URL에 token이 없으면 stream URL query를 복사한다.
- “Why not attach Authorization headers directly to AVPlayer?”
  - AVPlayer가 내부적으로 playlist/segment를 추가 요청하므로 custom header가 모든 하위 요청에 안정적으로 유지된다고 가정하기 어렵다. token query 방식이 HLS에 더 적합하다.
- “What caused the 420 service mismatch?”
  - HLS 서비스 guard가 “이 service 전용” 조건을 검사하는데 서버가 발급한 path/origin/token 조합이 그 조건과 맞지 않는 경우다.
- “How did you distinguish client URL bugs from server routing bugs?”
  - HLS probe에서 Authorization/SeSAC header를 제거한 token-only 요청을 보내고, raw query/token 길이 보존 로그와 420 body를 함께 확인해 URL 손실이 아니라 서버 발급/라우팅 불일치로 분류했다.
- “How would you improve the video playback architecture?”
  - HLS probe/classification을 별도 파일/서비스로 분리하고, full URL debug log를 제거하며, playback state reducer와 더 많은 단위 테스트를 추가한다.

## 8. Chat Feature

채팅 기능은 채팅방 목록, 방 생성/조회, 메시지 REST 전송, Socket.IO 실시간 수신, optimistic UI, CoreData 로컬 캐시, store-scoped chat policy로 구성된다.

주요 파일:

- `Features/Chat/ChatInteractor.swift`
- `Features/Chat/ChatPresenter.swift`
- `Features/Chat/ChatSocketIOClient.swift`
- `Features/Chat/ChatRootView.swift`
- `App/DI/FeatureBuilderFactory.swift`
- `Core/Notification/NotificationTrackingStores.swift`

현재 코드 구조상 채팅의 Domain model, DTO, RemoteDataSource, Repository, Mapper, local cache helper가 `Features/Chat/ChatInteractor.swift`에 함께 있다. 기능은 동작 관점에서 잘 모여 있지만 계층 일관성 측면에서는 분리 여지가 있다.

### Chat List

`ChatPresenter.loadRooms`가 `ChatInteractor.loadRooms`를 호출한다. Interactor는 인증 상태를 확인한 뒤 repository에서 room list를 가져오고, 로컬 conversation summary와 store context를 함께 반영한다. Room list는 “가게 문의”와 “일반 채팅” 섹션으로 렌더링된다.

### Chat Room Open

방 진입 방식:

- 기존 roomID로 진입.
- store detail에서 ownerID/storeID 기반으로 create-or-fetch.
- userID 기반 일반 채팅 create-or-fetch.
- notification route에서 chatRoomID로 진입.

store-scoped chat은 `ChatRoomStoreContext`와 `localCacheKey = room:...|store:...|opponent:...`를 사용한다. 이는 같은 roomID가 여러 store context에서 충돌할 수 있는 상황을 줄이기 위한 정책이다.

### Message Sending

전송 흐름:

1. 사용자가 메시지를 입력하고 send.
2. `ChatPresenter.sendMessage`가 `local-UUID` 기반 pending message를 만든다.
3. UI에 optimistic append한다.
4. `CoreDataChatLocalDataSource.savePending`으로 로컬 저장한다.
5. REST `POST /v1/chats/{roomID}`로 서버 전송한다.
6. 성공하면 서버 메시지의 `serverChatID`로 pending message를 replace한다.
7. 실패하면 해당 메시지 sendStatus를 failed로 표시한다.

Optimistic UI를 쓰는 이유:

- 네트워크 왕복을 기다리지 않고 즉시 메시지를 보여줘 채팅 UX가 자연스럽다.
- 소켓 echo가 늦거나 REST 응답이 늦어도 사용자는 전송 동작을 즉시 확인한다.

위험:

- REST 성공 응답과 socket echo가 모두 들어오면 중복 메시지가 생길 수 있다.
- localTemporaryID와 serverChatID reconciliation이 실패하면 pending 메시지가 남을 수 있다.
- store-scoped room context가 모호하면 다른 가게 문의와 섞일 수 있다.

### Duplicate Prevention and Echo Merge

`ChatMessageMergePolicy`가 중복을 막는다.

- 같은 `serverChatID`가 있으면 중복으로 판단한다.
- 현재 사용자/같은 content/files/시간 window 내 server echo는 optimistic sending message를 대체한다.
- 같은 localTemporaryID도 중복으로 제거한다.
- 결과는 `createdAt`과 `renderID` 기준으로 정렬한다.
- DEBUG 로그로 `skipDuplicate`, `replaceOptimistic`을 남긴다.

localTemporaryId to serverChatId:

- pending message는 `localTemporaryID`와 `id = localTemporaryID`를 가진다.
- 서버 응답 또는 socket echo가 오면 `serverChatID`가 있는 메시지로 교체한다.
- `renderID`는 local/server 양쪽 상태에서 SwiftUI list identity를 안정화하는 데 사용된다.

### Socket Room Subscription

`ChatSocketIOClient`는 namespace `/chats-{roomID}`에 연결한다.

- origin: `AppConfiguration.baseURL`에서 `URLBuilder.makeOriginURL`로 생성.
- headers: `SesacKey`, `Authorization`.
- config: `.forceWebsockets(true)`, `.compress`, debug env에 따라 `.log(true)`.
- event: `"chat"` event.
- decode: `chat`, `message`, `data`, `payload` nested key를 허용.
- filter: 수신 메시지의 roomID가 현재 active roomID와 맞는지 확인한다.
- callback: main actor에서 Presenter merge 호출.
- disconnect: handler 제거, socket/manager disconnect.

### Local Persistence

`CoreDataChatLocalDataSource`는 actor이고 programmatic Core Data model을 사용한다. 저장소는 Application Support의 `PikkoChat.sqlite`이며, uniqueness constraint는 `[chatID, localCacheKey]`이다. Pending, server message, failed status, scoped cache를 관리한다.

### Unread/Room Updates

채팅 이벤트는 `.pikkoChatRoomDidUpdate` notification으로 room list 갱신과 app notification service에 전달된다. Foreground remote notification은 `ActiveChatRoomTracker`가 현재 열린 roomID와 맞으면 banner를 억제한다.

면접 질문:

- “How does the chat send flow work?”
  - local temporary message를 즉시 append하고 CoreData에 저장한 뒤 REST 전송한다. 서버 응답이나 socket echo가 오면 merge policy로 pending을 server message로 대체한다.
- “What is optimistic rendering?”
  - 서버 응답 전에 사용자의 의도에 맞춰 UI를 먼저 업데이트하고 실패 시 rollback 또는 failed 상태로 바꾸는 방식이다.
- “How do you prevent duplicated messages?”
  - serverChatID, localTemporaryID, content/files/time-window 기반 `ChatMessageMergePolicy`로 REST 응답과 socket echo를 병합한다.
- “How do you handle socket echo?”
  - socket에서 받은 메시지를 현재 roomID로 필터링하고, optimistic pending과 matching되면 replace한다.
- “How would you debug missing or duplicated chat messages?”
  - REST send log, socket connect/event log, merge policy `replaceOptimistic/skipDuplicate` log, CoreData local cache key를 함께 확인한다.
- “What would you improve in the chat architecture?”
  - `ChatInteractor.swift`에 몰린 DTO/Repository/Mapper/CoreData 관련 타입을 Data/Domain 계층으로 분리하고 chat merge 단위 테스트를 추가한다.

## 9. Community Feature

커뮤니티는 위치 기반 게시글 목록, 카테고리/정렬/거리 필터, 검색, 상세, 댓글, 작성/수정, 파일 업로드, 좋아요, 알림 snapshot을 포함한다.

주요 파일:

- `Data/Remote/CommunityRemoteDataSource.swift`
- `Data/Mappers/CommunityMapper.swift`
- `Features/Community/CommunityPresenter.swift`
- `Features/Community/CommunityInteractor.swift`
- `Features/Community/CommunityDetailPresenter.swift`
- `Features/Community/CommunityComposerPresenter.swift`
- `Features/Community/CommunityComposerInteractor.swift`
- `Features/Community/CommunityRouter.swift`
- `Tests/CommunityFeatureTests.swift`
- `Tests/CommunityDetailFeatureTests.swift`
- `Tests/CommunityComposerFeatureTests.swift`
- `Tests/CommunityDataMappingTests.swift`

### List Loading

`CommunityPresenter`가 onAppear/refresh/filter/sort/pagination 이벤트를 받는다. 일반 목록은 `GET /v1/posts/geolocation`을 사용하고 query로 `category`, `longitude`, `latitude`, `maxDistance`, `next`, `limit`, `order_by`를 전달한다. 검색은 `GET /v1/posts/search?title=`을 사용한다.

### Category / Sort / Filter

- 카테고리: 서버 query `category`.
- 정렬: latest/popularity는 서버 `order_by=createdAt/likes`.
- 거리 정렬: Swagger가 createdAt/likes만 지원하므로 client-side distance sort.
- nearbyOnly: 500m 이내 local filter.
- videoOnly: `MediaTypeResolver` 기반 local filter.
- storeTag: local filter.

### Location / Distance

`CommunityInteractor`는 `SelectedLocationStore.shared`의 수동 선택 위치를 우선 사용하고, 없으면 `LocationService`의 현재 위치를 사용한다. 권한 미결정/거부/위치 없음일 때 목록을 완전히 막지 않고 “location pending/unavailable, skip distance error”로 처리해 거리 없이 목록을 표시할 수 있게 한다. 단, composer submit에는 게시글 위치가 필요하므로 위치가 더 중요하다.

### Pagination

`CommunityPresenter`는 `nextCursor`, `isPaging`, `feedRequestID`를 사용한다.

- `isPaging`: 중복 pagination 요청 방지.
- `feedRequestID`: 오래된 응답이 최신 상태를 덮지 않도록 방지.
- limit: 현재 feed는 5개 단위.
- `CommunityMapper`는 empty/`0` cursor를 nil로 정규화한다.

### Detail and Comments

`CommunityDetailPresenter`는 detail 로드 후 comments를 불러온다. 현재 `CommunityRemoteDataSource.fetchComments`는 TODO 형태로 별도 comments endpoint가 아니라 detail endpoint의 `comments`를 반환하며 `next`는 nil이다. 댓글 생성/수정/삭제는 `/v1/posts/{postID}/comments/{commentID}` 계열 endpoint를 사용한다.

### Image Loading

게시글 파일 경로는 `CommunityMapper`가 `AuthorizedFileURLResolver`로 보정하고, UI에서는 `AuthorizedAsyncImage`/authorized image loading 계층을 사용한다.

### Error and Empty States

Presenter가 loading/error/empty state를 가진다. 위치 실패는 목록 전체 실패가 아니라 degrade 가능한 상태로 취급한다. 좋아요는 optimistic update 후 실패 시 rollback한다.

면접 질문:

- “How does the community list reload?”
  - 현재 query/filter/location context를 기준으로 geolocation feed API를 다시 호출하고 `feedRequestID`로 stale response를 무시한다.
- “How do you handle sorting/filtering?”
  - 서버가 지원하는 latest/popularity는 query로 보내고, 거리/video/storeTag 같은 조건은 client-side로 보정한다.
- “How is location used?”
  - 선택 위치 또는 현재 위치를 기준으로 geolocation API와 거리 계산에 사용한다. 권한이 없으면 목록을 막지 않는다.
- “How would you avoid duplicated pagination requests?”
  - `isPaging` flag와 cursor 확인, requestID guard를 함께 사용한다.
- “How would you improve empty/error states?”
  - 위치 권한 없음, 서버 empty, 필터 결과 없음, 네트워크 실패를 별도 user-facing state로 분리한다.

## 10. Realtime / Socket Layer

Realtime 통신은 현재 채팅에 사용된다. Socket.IO dependency는 `project.yml`에 있고 실제 클라이언트는 `Features/Chat/ChatSocketIOClient.swift`이다.

Socket connection lifecycle:

- Chat room 진입 후 `ChatPresenter`가 `ChatInteractor.startRealtime`을 호출한다.
- Interactor가 roomID, store context, 현재 session을 검증한 뒤 socket client를 연결한다.
- namespace는 `/chats-{roomID}`이다.
- View disappear 또는 room 이탈 시 disconnect한다.

Event names:

- `"chat"` event를 수신한다.
- payload는 `chat`, `message`, `data`, `payload` 중첩 구조를 유연하게 decoding한다.

Subscription/unsubscription:

- 연결 시 해당 room namespace에만 붙는다.
- disconnect 시 모든 handler를 제거하고 socket/manager를 disconnect한다.

Reconnection:

- Socket.IO client 기본 재연결 기능을 일부 활용할 수 있으나, 명시적 custom reconnection/backoff 정책은 현재 코드에서 자세히 확인되지 않는다.

Threading:

- socket callback은 main actor로 전달되어 Presenter state 변경이 UI thread에서 일어나도록 한다.

Risks:

- 같은 메시지가 REST 응답과 socket echo로 두 번 들어올 수 있다.
- roomID/storeID context가 모호하면 잘못된 room 메시지를 받을 수 있다.
- disconnect 누락 시 이전 room 이벤트를 받을 수 있다.
- 네트워크 재연결 중 missed message가 생길 수 있어 REST sync와 함께 써야 한다.

개선:

- socket lifecycle state를 enum으로 노출해 UI/diagnostics에서 확인.
- reconnection 후 `synchronizeMessages`를 자동 실행.
- socket event decoding과 room filtering 단위 테스트 추가.
- namespace와 roomID validation 강화.

면접 질문:

- “Where is the socket connected?”
  - `ChatInteractor.startRealtime`에서 `ChatSocketIOClient`를 통해 room namespace `/chats-{roomID}`에 연결한다.
- “How do you manage socket lifecycle?”
  - room 진입 시 connect, disappear/이탈 시 disconnect하고 handler를 제거한다.
- “How do you prevent receiving messages for the wrong room?”
  - namespace를 roomID별로 나누고, 수신 payload의 roomID도 현재 roomID와 비교해 필터링한다.
- “How do you handle reconnection?”
  - 현재는 Socket.IO 기본 동작에 의존하는 부분이 있고, 개선한다면 reconnect 후 REST sync로 누락 메시지를 보정한다.
- “How would you test socket behavior?”
  - socket client protocol을 mock으로 만들고 connect/disconnect/event delivery/duplicate echo를 Presenter 단위 테스트로 검증한다.

## 11. Push Notification / FCM

Pikko는 Firebase Messaging과 APNs를 직접 연동한다.

주요 파일:

- `App/PikkoAppDelegate.swift`
- `Core/Notification/AppNotificationService.swift`
- `Core/Notification/NotificationTrackingStores.swift`
- `App/State/SessionStore.swift`
- `App/DI/FeatureBuilderFactory.swift`
- `Data/Remote/AuthRemoteDataSource.swift`
- `Config/Pikko-Info.plist`
- `Config/Pikko.entitlements`
- `Config/README.md`

Firebase initialization:

- `PikkoAppDelegate.configureFirebaseIfNeeded`가 `GoogleService-Info.plist` 존재 여부를 확인하고 Firebase를 설정한다.
- 파일이 없으면 notification setup을 skip하고 로그를 남긴다.

APNs token handling:

- `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`에서 APNs token을 받는다.
- `Messaging.messaging().apnsToken = deviceToken`으로 FCM에 전달한다.
- APNs 등록 이후 FCM token을 fetch한다.

FCM token registration:

- `MessagingDelegate.messaging(_:didReceiveRegistrationToken:)` 또는 fetch 결과로 FCM token을 받는다.
- token은 `.pikkoFCMTokenDidRefresh` notification으로 `SessionStore`에 전달된다.
- `RootScene`의 task가 인증 상태와 device token sync state를 보고 `FeatureBuilderFactory.syncCurrentDeviceTokenIfNeeded`를 호출한다.
- 서버 등록 API는 `PUT /v1/users/deviceToken`이다.

Token refresh/deduplication:

- `SessionStore`가 device token을 저장하고 `deviceTokenSyncStateID`를 변경한다.
- 이미 같은 `userID|deviceToken` signature를 sync했다면 서버 호출을 건너뛴다.
- logout/session clear 시 sync state도 초기화한다.

Foreground/background handling:

- foreground remote/local notification은 `UNUserNotificationCenterDelegate`에서 처리한다.
- `DefaultAppNotificationService`가 remote payload를 앱 내부 notification으로 저장하고 route를 만든다.
- active chat room 또는 active community post와 관련된 foreground 알림은 banner를 억제할 수 있다.
- tap route는 미인증 상태이면 `PendingNotificationRouteStore`에 저장했다가 인증 후 실행한다.

왜 APNs와 FCM이 모두 필요한가:

- iOS 실제 push 전송은 APNs가 담당한다.
- FCM은 서버가 플랫폼별 push를 관리하기 쉽게 해주는 provider이고, iOS에서는 APNs token과 연결되어 FCM registration token을 발급한다.

보안/개인정보:

- FCM token은 사용자/기기 식별에 쓰일 수 있으므로 로그에서는 redaction 대상이다.
- `SensitiveLogRedactor`에 `deviceToken`, `fcmToken`이 포함되어 있다.
- 서버 등록은 인증 후 수행하므로 token과 user binding이 명확하다.

면접 질문:

- “How does push notification registration work on iOS?”
  - 권한 요청 후 APNs 등록, APNs token을 Firebase Messaging에 전달, FCM token을 받아 서버에 등록한다.
- “What is the difference between APNs token and FCM token?”
  - APNs token은 Apple push 식별자이고, FCM token은 Firebase가 서버 전송용으로 발급하는 registration token이다.
- “Where do you send the token to the server?”
  - `FeatureBuilderFactory.syncCurrentDeviceTokenIfNeeded`가 `AuthRepository.updateDeviceToken`을 통해 `/v1/users/deviceToken`으로 보낸다.
- “How do you handle token refresh?”
  - Messaging delegate가 새 token을 받고 `SessionStore`가 저장한 뒤 sync state를 갱신한다.
- “How would you debug notifications not arriving?”
  - Firebase 설정 파일, APNs entitlement, 권한 상태, APNs 등록 callback, FCM token fetch, 서버 device token registration, remote payload route log를 순서대로 확인한다.

## 12. Location Handling

위치 기능은 홈 주변 가게, 커뮤니티 geolocation feed, 게시글 작성 위치, 가게 상세 거리 계산에 사용된다.

주요 파일:

- `Core/Platform/Location/LocationService.swift`
- `Core/Platform/Location/SelectedLocationStore.swift`
- `Core/Platform/Location/ReverseGeocoder.swift`
- `Core/Platform/Location/MapLauncher.swift`
- `Features/Home/HomeInteractor.swift`
- `Features/Community/CommunityInteractor.swift`
- `Features/StoreDetail/StoreDetailPresenter.swift`
- `Config/Pikko-Info.plist`

Permission request:

- `LocationService`가 `CLLocationManager`를 감싸고 `requestWhenInUseAuthorization`을 사용한다.
- `NSLocationWhenInUseUsageDescription`은 Info.plist에 있다.

Current location fetching:

- `requestCurrentLocation`은 continuation 기반 async API로 현재 위치를 요청한다.
- `LocationService`는 `@MainActor NSObject`이며 `CLLocationManagerDelegate` callback을 처리한다.

Distance filter:

- 커뮤니티는 `maxDistance` query와 local distance filter를 사용한다.
- 홈은 선택 위치/현재 위치/기본 위치를 바탕으로 주변 가게를 요청한다.
- 가게 상세는 현재 위치와 가게 좌표를 이용해 거리를 계산한다.

Fallback behavior:

- `SelectedLocationStore`에 저장된 수동 선택 위치가 우선이다.
- 위치가 없으면 기본 SeSAC Yeongdeungpo 위치를 사용할 수 있다.
- 커뮤니티 목록은 위치 실패로 전체 UI를 막지 않고 거리 없는 목록으로 degrade한다.
- 작성/지도/길찾기처럼 위치가 핵심인 기능은 별도 오류 처리가 필요하다.

Privacy:

- 위치 권한은 필요 시 요청한다.
- 위치 정보는 API query로 전송되므로 개인정보 민감 영역이다.
- 개선한다면 위치 사용 시점과 목적을 UI에서 더 명확히 설명하고, precise location이 필요 없는 기능은 선택 위치를 우선 사용한다.

면접 질문:

- “When do you request location permission?”
  - 홈/커뮤니티/작성 등 위치가 필요한 흐름에서 현재 위치가 필요할 때 요청한다.
- “What happens if the user denies location?”
  - 선택 위치 또는 기본 위치로 fallback하고, 커뮤니티 목록은 위치 오류로 막지 않는다.
- “How do you avoid blocking the UI while waiting for location?”
  - async request를 사용하고 위치 실패를 non-fatal state로 처리한다.
- “How would you improve privacy and UX?”
  - 위치 목적 안내, 수동 위치 선택 우선, 권한 거부 시 명확한 CTA, 불필요한 좌표 전송 최소화가 필요하다.

## 13. Image Loading and Caching

이미지 로딩은 인증이 필요한 파일 URL과 fallback placeholder를 고려해 구현되어 있다.

주요 파일:

- `Core/Platform/Image/AuthorizedFileURLResolver.swift`
- `Core/Platform/Image/AuthorizedImageLoader.swift`
- `Core/Platform/Image/AuthorizedAsyncImage.swift`
- `Core/Platform/Image/ImageCache.swift`
- `Data/Mappers/CommunityMapper.swift`
- `Data/Mappers/VideoMapper.swift`

Image loader abstraction:

- `AuthorizedFileURLResolver`가 서버 파일 경로를 absolute URL로 변환한다.
- absolute URL은 유지하고, 상대 `/data` 경로는 `/v1/data` 기준으로 정규화한다.
- `AuthorizedImageLoader`가 URLRequest를 만들고 `.fileAuthorized` policy로 인증 header를 붙인다.

Cache strategy:

- `ImageCache`는 in-memory cache를 제공한다.
- loader actor가 in-flight request를 dedupe한다.
- 실패한 URL은 TTL 300초 캐시에 저장해 반복 실패 요청을 줄인다.

Placeholder/fallback:

- URL이 없거나 서버 파일이 아닌 seed path인 경우 `FallbackAuthorizedImageLoader`가 deterministic placeholder 이미지를 만든다.
- 444 또는 blocked image는 fallback placeholder로 이어진다.

Reuse/flickering prevention:

- `AuthorizedAsyncImage`는 SwiftUI `.task(id: path)`로 path 변경 시 새 load를 시작한다.
- SwiftUI task cancellation에 기대고 있어 UIKit cell reuse 문제보다는 적지만, 빠른 스크롤에서 이전 요청 결과가 늦게 도착하는 케이스는 계속 주의해야 한다.

Memory:

- in-memory cache는 성능에 유리하지만 memory pressure 대응 정책이 중요하다.
- 개선한다면 NSCache cost/limit, disk cache, image resizing/downsampling을 명확히 둘 수 있다.

면접 질문:

- “How are images loaded?”
  - Mapper가 파일 경로를 보정하고 `AuthorizedAsyncImage`가 `AuthorizedImageLoader`를 통해 인증 request로 이미지를 가져온다.
- “How do you prevent wrong images appearing in reused cells?”
  - path를 task identity로 사용해 경로가 바뀌면 새 task가 실행된다. 더 강화하려면 result 적용 전 current path 검증을 추가한다.
- “How do you handle failed image URLs?”
  - 444/실패 URL은 실패 캐시에 넣고 fallback placeholder를 보여준다.
- “How would you improve image caching?”
  - disk cache, downsampling, memory warning 대응, cache invalidation 정책을 추가한다.

## 14. Local Persistence / Cache

Pikko는 Keychain, UserDefaults, CoreData, in-memory cache를 함께 사용한다.

### Keychain

- 파일: `Core/Storage/KeychainTokenStore.swift`.
- 저장 데이터: access token, refresh token.
- 이유: 인증 token은 민감 정보이므로 UserDefaults보다 Keychain이 적합하다.
- lifetime/invalidation: login/refresh 시 저장, logout/session invalidation 시 삭제.
- security: Keychain accessibility 옵션과 migration 정책은 추가 검토 가능하다.

### UserDefaults

- 파일: `App/State/SessionStore.swift`, `Core/Storage/UserDefaultsSessionSnapshotStore.swift`, `Core/Notification/NotificationTrackingStores.swift`, `Core/Platform/Location/SelectedLocationStore.swift`.
- 저장 데이터: session profile snapshot, FCM device token, token sync signature, selected location, notification list/pending route/order/community snapshot.
- 이유: 비민감 설정/캐시/복원용 데이터 저장에 적합하다.
- risk: session snapshot은 token은 아니지만 사용자 정보이므로 최소화와 삭제 정책이 필요하다.

### CoreData

- 파일: `Features/Chat/ChatInteractor.swift` 안의 `CoreDataChatLocalDataSource`.
- 저장 데이터: chat messages, localTemporaryID, serverChatID, roomID, files, sendStatus, localCacheKey.
- 이유: 채팅은 offline/cache/optimistic pending 상태가 있어 구조적 로컬 저장이 필요하다.
- invalidation: store-scoped localCacheKey와 room sync로 서버 상태와 병합한다. 오래된 메시지 purge 정책은 현재 코드에서 명확히 찾지 못했다.

### In-memory Cache

- 파일: `Core/Platform/Image/ImageCache.swift`, image loader in-flight cache.
- 저장 데이터: 이미지.
- 이유: 반복 이미지 요청과 flickering을 줄인다.
- invalidation: memory limit/expiry 정책은 더 강화 가능하다.

면접 질문:

- “What do you persist locally?”
  - token은 Keychain, session/profile/device/location/notification snapshot은 UserDefaults, chat messages는 CoreData, 이미지는 memory cache에 저장한다.
- “Why did you choose this storage?”
  - 민감도와 데이터 구조에 따라 선택했다. token은 Keychain, 구조적 메시지는 CoreData, 가벼운 설정/스냅샷은 UserDefaults다.
- “What should be stored in Keychain instead of UserDefaults?”
  - access/refresh token, 장기 인증 credential, 민감한 user secret은 Keychain에 있어야 한다.
- “How do you invalidate cached data?”
  - logout/session invalidation 시 token/snapshot을 지우고, device token sync state도 초기화한다. 채팅/이미지 cache는 추가 purge 정책이 개선점이다.

## 15. State Management

상태 관리는 SwiftUI `ObservableObject`, `@Published`, `@EnvironmentObject`, async/await, requestID/generation guard를 조합한다.

주요 상태 소유자:

- `AppState`: launch phase, selected tab, pending route, toast.
- `SessionStore`: auth/session/token/device token.
- `CartStore`: 장바구니 상태.
- `AuthPresenter`: 인증 화면 상태.
- `HomePresenter`: 홈 섹션/위치/검색/좋아요.
- `CommunityPresenter`: feed/filter/pagination/like.
- `CommunityDetailPresenter`: detail/comment/like.
- `ChatPresenter`: room list/detail/messages/composer/socket.
- `VideoListPresenter`: video list/pagination/like.
- `VideoPlayerViewModel`: playback/player/stream/HLS state.

State enum/struct patterns:

- `LaunchPhase`: `.idle`, `.restoringSession`, `.ready`.
- `VideoPlayerViewState`: playbackState, detailReason, stream, quality, toast.
- `VideoListViewState`: list/loading/error/pagination.
- Chat message status: `.sending`, `.sent`, `.failed` 계열.

MainActor/main queue:

- app state/session store/presenters 대부분은 `@MainActor` 또는 main actor callback을 사용한다.
- socket event도 main actor로 전달된다.
- `CoreDataChatLocalDataSource`와 `KeychainTokenStore`는 actor로 background-safe하게 분리한다.

Cancellation/race prevention:

- Community: `feedRequestID`, `isPaging`.
- Chat: `roomLoadRequestID`, merge policy, active room tracker.
- VideoPlayer: `playbackGeneration`, `activeStreamRequestKey`, fallback attempt tracking.
- Home: async let partial loading, location fallback.

장점:

- stale response가 최신 UI를 덮는 문제를 줄인다.
- View는 상태 렌더링에 집중한다.
- 기능별 상태 소유자가 명확하다.

약점:

- Presenter가 커지면 reducer/action/effect 구분이 흐려진다.
- 일부 상태는 NotificationCenter와 EnvironmentObject를 함께 사용해 추적 경로가 길다.
- 명시적 Task cancellation이 모든 feature에 균일하게 적용되지는 않는다.

개선:

- 주요 Presenter에 action reducer와 side-effect method를 분리.
- requestID/generation pattern을 공통 helper로 정리.
- ViewModel tests에서 stale response/cancel 케이스를 더 많이 검증.

면접 질문:

- “How does the ViewModel communicate with the View?”
  - `@Published` state를 SwiftUI View가 observe하고, View는 사용자 action을 Presenter/ViewModel method로 전달한다.
- “How do you prevent stale API responses from overriding new state?”
  - requestID/generation을 저장하고 응답 시 현재 ID와 비교해 오래된 응답을 무시한다.
- “How do you handle loading and error states?”
  - 각 ViewState가 loading/error/empty/success 상태를 갖고 Presenter가 API 결과를 state로 mapping한다.
- “How would you test ViewModels?”
  - mock repository/usecase를 주입해 loading-success-error, cancellation/stale response, optimistic rollback을 검증한다.

## 16. Debug Logging and Diagnostics

로깅은 `Core/Utils/Logger.swift`의 OSLog wrapper와 feature별 DEBUG 로그를 조합한다.

주요 파일:

- `Core/Utils/Logger.swift`
- `Core/Network/APIClient.swift`
- `Core/Network/RequestBuilder.swift`
- `Data/DTOs/Video/VideoDTO.swift`
- `Data/Mappers/VideoMapper.swift`
- `Features/VideoPlayer/VideoPlayerViewModel.swift`
- `Features/Chat/ChatInteractor.swift`
- `Features/Chat/ChatSocketIOClient.swift`
- `Core/Notification/AppNotificationService.swift`

Log categories:

- network request/response/decoding/auth refresh.
- video stream DTO/HLS URL/HLS probe/player item.
- chat send/merge/socket/local cache.
- notification payload/routing/suppression.
- location fallback.

Redaction:

- `SensitiveLogRedactor`는 access/refresh/id token, oauth token, authorizationCode, deviceToken, fcmToken, Authorization, SeSAC/Sesac key 등을 masking한다.
- token summary는 길이와 앞/뒤 일부만 보여주는 식으로 debug에 도움을 준다.

HLS diagnostics:

- stream API 응답의 token query 존재 여부, token length, URL resolution 결과를 로그로 확인한다.
- HLS probe는 token-only 요청에서 Authorization/SeSACKey가 빠졌다는 점을 명시해 header 기반 인증 문제와 구분한다.
- 420 body가 service mismatch이면 `serverIssuedTokenOrServiceRoutingMismatch`로 진단한다.

Chat diagnostics:

- optimistic append, REST success, socket echo, merge replace/skip duplicate 로그가 중복 메시지 분석에 유용하다.
- socket namespace와 active room filtering 로그가 잘못된 room 수신 여부를 확인하게 해준다.

주의할 로그:

- `VideoStreamingDebugLogger`는 DEBUG에서 full stream URL을 출력하는 코드가 있고 TODO로 TestFlight/AppStore 전 제거가 표시되어 있다. HLS token query가 민감할 수 있으므로 개선 필요하다.
- simulator/system log처럼 앱 제어 밖의 noisy log는 핵심 진단에서 제외해야 한다.

면접 질문:

- “How did you debug the HLS playback issue?”
  - stream API 응답, URL resolution token length, token-only HLS probe status/body를 함께 로깅해 client query 손실인지 server routing mismatch인지 구분했다.
- “How do you decide which logs to keep?”
  - 재현이 어려운 인증/stream/socket merge처럼 원인 분석에 필요한 구조화 로그는 남기고, 민감 값과 반복 노이즈는 redaction/dedupe/gating한다.
- “How do you avoid noisy logs?”
  - `debugVerbose` env gate, `DebugLogDeduplicator`, category별 로그, 민감 정보 redaction을 사용한다.
- “What would you log in production?”
  - 개인 정보와 token은 제외하고 status category, request id, feature state transition, failure classification 정도만 샘플링한다.

## 17. Error Handling

오류 처리는 network status mapping, feature-level error mapping, user-facing state, debug diagnostics로 나뉜다.

Network errors:

- `HTTPStatusMapper`가 400/401/403/404/418/419/420/429/444/445/5xx를 `NetworkError`로 변환한다.
- `APIClient`가 decoding error와 payload shape를 debug 로그로 남긴다.

Auth errors:

- 401/419는 token refresh를 한 번 시도한다.
- refresh 실패는 session invalidation으로 이어진다.
- auth 화면은 provider cancellation, network, configuration, Kakao conflict/unauthorized 등을 사용자 메시지로 mapping한다.

HLS playback errors:

- HLS probe가 401, 418/419, 404, 420, 444, JSON 응답, invalid playlist를 분류한다.
- 420 “This service ... only”는 `serverServiceRoutingMismatch`이다.
- retry는 transient 오류에 제한하고 terminal 오류에서는 무한 반복하지 않는다.

Socket errors:

- socket connect/disconnect/error 로그를 남긴다.
- missed message는 REST synchronize와 local cache가 보정한다.
- 사용자-facing socket error 정책은 현재 코드에서 강하게 드러나지 않으며 개선 가능하다.

Empty states:

- 목록 feature는 empty/error/loading을 ViewState로 가진다.
- community location unavailable은 전체 실패가 아니라 degrade state로 처리한다.

User-facing vs developer-facing:

- 사용자에게는 “재시도”, “로그인이 필요합니다”, “영상을 재생할 수 없습니다” 같은 행동 가능한 메시지가 적합하다.
- 개발자에게는 status code, endpoint, token query preservation, merge reason 같은 detail log가 필요하다.

Retry policy:

- 적절한 retry: 네트워크 일시 실패, token refresh 후 원 요청 1회, HLS transient 5xx/일부 404 fallback.
- 해로운 retry: 420 service mismatch, invalid token URL, 잘못된 endpoint 444, validation error, 인증 없는 상태.

면접 질문:

- “How are API errors mapped?”
  - `HTTPStatusMapper`가 status code를 네트워크 오류로 변환하고, 각 feature Presenter가 user-facing state로 바꾼다.
- “How do you decide whether to retry?”
  - 일시적이고 성공 가능성이 있는 오류만 제한적으로 retry한다. 서버 발급 URL 자체 오류나 validation/auth terminal error는 retry하지 않는다.
- “How do you avoid infinite retry loops?”
  - token refresh 1회, HLS service mismatch refresh 1회, fallback quality set 기록처럼 attempt state를 둔다.
- “What error should the user see when video playback fails?”
  - token 만료/로그인 필요, 파일 없음, 서버 재생 준비 오류, 네트워크 오류를 구분하되 내부 status code/token detail은 노출하지 않는다.

## 18. Concurrency

이 프로젝트는 async/await, actor, SwiftUI task, NotificationCenter callback, Socket.IO callback을 함께 사용한다.

async/await:

- APIClient는 `URLSession.data(for:)` 기반 async API를 사용한다.
- Presenter/Interactor는 `Task` 또는 async method로 데이터를 로드한다.
- `HomeInteractor`는 `async let`으로 홈 섹션을 병렬 요청하고 부분 실패를 허용한다.

Actors:

- `KeychainTokenStore`: token read/write serialize.
- `TokenRefreshCoordinator`: refresh dedupe.
- `CoreDataChatLocalDataSource`: chat local persistence serialize.
- `AuthorizedImageLoader`: image request/cache/in-flight dedupe.

Task cancellation:

- VideoPlayer는 generation 방식으로 취소/교체 후 stale 결과를 막는다.
- SwiftUI `.task(id:)`는 view/path lifecycle에 따라 자동 취소된다.
- 모든 feature에 명시적 task cancellation이 균일하게 적용되지는 않는다.

Main thread updates:

- `@MainActor` state owner가 많다.
- socket event는 main actor로 전달된다.
- CoreLocation delegate wrapper도 main actor 기반이다.

Race condition prevention:

- token refresh: in-flight task 공유.
- video: active request key/generation.
- community: requestID/isPaging.
- chat: merge policy/local cache key.
- FCM sync: userID/deviceToken signature.

면접 질문:

- “Where do you use async work?”
  - API 호출, session restore, image loading, location request, home section 병렬 로드, chat sync/send, video stream fetch에서 사용한다.
- “How do you cancel stale requests?”
  - feature별 requestID/generation으로 stale response를 무시하고 SwiftUI task lifecycle을 활용한다.
- “How do you ensure UI updates happen on the main thread?”
  - state owner를 `@MainActor`로 두고 socket callback도 main actor에서 merge한다.
- “How would you improve concurrency safety?”
  - Presenter별 active Task를 보관해 cancel을 명시화하고, requestID/generation pattern을 공통화하며 Sendable 경고를 정리한다.

## 19. Security Considerations

보안 민감 영역은 token storage, auth headers, HLS token query, push token, location, logs, local persistence이다.

안전한 부분:

- access/refresh token은 Keychain에 저장된다.
- `RequestBuilder`가 인증 header injection을 중앙화한다.
- `SensitiveLogRedactor`가 주요 token/key 이름을 masking한다.
- FCM token sync는 인증 후 사용자와 묶어서 수행한다.
- HLS probe는 Authorization/SeSAC header를 제거하고 token-only URL 검증으로 책임을 분리한다.

위험한 부분:

- `VideoStreamingDebugLogger`가 DEBUG에서 full stream URL을 출력한다. HLS token query가 포함될 수 있어 TestFlight/AppStore 전 반드시 제거 또는 masking해야 한다.
- HLS token query는 URL이므로 proxy/log/crash report에 남을 수 있다.
- UserDefaults session snapshot, notification payload, selected location은 개인정보일 수 있다.
- ATS 설정에서 media arbitrary loads와 특정 HTTP exception이 있어 production 보안 정책 검토가 필요하다.

redaction 필요:

- accessToken, refreshToken, idToken, oauthToken.
- Authorization, RefreshToken, SesacKey.
- HLS token query.
- FCM device token.
- precise location.
- payment/order identifiers는 상황에 따라 masking.

Keychain으로 옮길 후보:

- 현재 token은 이미 Keychain이다.
- 장기 민감 credential이나 결제 관련 secret이 추가된다면 Keychain이 적합하다.
- session profile snapshot은 token은 아니므로 UserDefaults 가능하지만 최소화가 좋다.

면접 질문:

- “Where are access tokens stored?”
  - `KeychainTokenStore`가 Keychain에 JSON encoded `StoredTokens`로 저장한다.
- “Do logs expose sensitive information?”
  - 대부분은 redactor가 masking하지만 DEBUG 영상 stream full URL 로그는 token query 노출 위험이 있어 개선 대상이다.
- “Why do you mask HLS token queries?”
  - URL query token은 재생 권한을 포함할 수 있어 로그/크래시/프록시에서 노출되면 보안 문제가 된다.
- “How would you improve security?”
  - full URL 로그 제거, ATS 정책 재검토, local 개인정보 보존기간 설정, production logging 샘플링/redaction 강화가 필요하다.

## 20. Testing Strategy

현재 테스트 target `PikkoTests`가 있고, 여러 기능의 unit test가 존재한다.

확인된 테스트 파일:

- `Tests/AppBootstrapperTests.swift`
- `Tests/AppStartFlowTests.swift`
- `Tests/AppConfigurationTests.swift`
- `Tests/AuthFeatureTests.swift`
- `Tests/NetworkInfrastructureTests.swift`
- `Tests/VideoFeatureTests.swift`
- `Tests/CommunityFeatureTests.swift`
- `Tests/CommunityDetailFeatureTests.swift`
- `Tests/CommunityComposerFeatureTests.swift`
- `Tests/CommunityDataMappingTests.swift`
- `Tests/HomePresenterTests.swift`
- `Tests/HomeDataMappingTests.swift`
- `Tests/StoreDetail*`
- `Tests/Order*`
- `Tests/Checkout*`
- `Tests/CartFeatureTests.swift`
- `Tests/CorePlatformStorageTests.swift`

강한 테스트 영역:

- app bootstrap/session/device token sync.
- app configuration.
- auth provider/email/profile.
- network header injection/token refresh/error mapping.
- video DTO decoding, URL resolution, stream retry, optimistic like.
- community list/detail/composer/data mapping.
- home/store/order/checkout/cart 일부.

부족한 테스트 영역:

- 채팅 merge/socket/CoreData local cache에 대한 dedicated test를 현재 코드에서 찾지 못했다.
- HLS probe의 420 body classification은 문서/코드상 중요하지만 dedicated test 여부는 더 보강할 수 있다.
- UI test/XCUITest target은 현재 코드에서 찾지 못했다.

추가 테스트 아이디어:

- Stream URL preserves token query.
- Relative HLS URL resolves against API origin.
- 420 service mismatch is classified correctly.
- Chat optimistic message is replaced by server message.
- Duplicate socket echo is ignored.
- Store-scoped chat localCacheKey collision is prevented.
- Expired session routes to auth gate.
- FCM token unchanged does not call server repeatedly.
- Image 444 uses fallback and avoids repeated fetch within TTL.
- Community pagination ignores stale response and duplicate paging.

면접 질문:

- “What would you test first?”
  - 인증/session restore, token refresh, video URL resolution/HLS classification, chat duplicate merge처럼 사용자 영향과 장애 가능성이 큰 흐름부터 테스트한다.
- “How would you test video URL resolution?”
  - base API origin, relative path, encoded token query, quality URL query missing 케이스를 mock DTO로 넣고 최종 URL raw query가 보존되는지 검증한다.
- “How would you test chat duplicate prevention?”
  - pending local message, REST success, socket echo를 순서만 바꿔 입력하고 최종 messages에 하나만 남는지 확인한다.
- “How would you mock the API layer?”
  - Repository 또는 RemoteDataSource protocol mock을 Presenter에 주입하고, network infrastructure는 custom URLProtocol/session mock으로 검증한다.

## 21. Feature-by-Feature Summary Table

| Feature | Main files/classes | Main responsibility | Data source | State owner | Important implementation detail | Possible interview question | Improvement idea |
|---|---|---|---|---|---|---|---|
| App Startup | `PikkoApp`, `PikkoAppDelegate`, `RootScene`, `AppBootstrapper` | 앱 초기화, Firebase, session gate | Keychain, UserDefaults, profile API | `AppState`, `SessionStore` | `launchPhase`와 `isAuthenticated`로 splash/auth/main 분기 | 앱 실행 시 무슨 일이 일어나나요? | AppDelegate service 분리 |
| DI | `AppDIContainer`, `FeatureBuilderFactory` | 전역/기능 의존성 조립 | Config, shared services | DI container | 수동 composition root | 왜 DI 프레임워크를 쓰지 않았나요? | feature별 builder 분리 |
| Authentication | `AuthPresenter`, `AuthInteractor`, `AuthRepositoryImpl`, `KeychainTokenStore` | 로그인/회원가입/session restore/logout | Auth API, Keychain | `SessionStore`, `AuthPresenter` | token은 Keychain, snapshot은 UserDefaults | 토큰은 어디 저장하나요? | 보안 로그와 Keychain 옵션 강화 |
| Networking | `APIClient`, `RequestBuilder`, `TokenRefreshCoordinator` | 요청 생성/실행/decoding/refresh | URLSession | APIClient | 401/419 refresh 1회, `SesacKey` header | 인증 header는 어디서 붙나요? | error message mapper 분리 |
| Home | `HomePresenter`, `HomeInteractor` | 홈 섹션/위치/가게 목록 | Store API, location | `HomePresenter` | `async let` partial loading | 홈 데이터는 어떻게 로드하나요? | section cache/pagination 정책 |
| Store Detail | `StoreDetailPresenter`, `StoreRepository` | 가게 상세, 리뷰, 장바구니, 좋아요 | Store/Review API, CartStore | `StoreDetailPresenter` | 상세/리뷰/평점 병렬 로드 | 가게 상세 상태는 누가 소유하나요? | 상세 화면 usecase 분리 |
| Order/Checkout | `OrderRemoteDataSource`, `CheckoutPresenter`, `PortOnePaymentGateway` | 주문/결제/영수증 | Order API, PortOne URL callback | Order/Checkout presenters | `onOpenURL`에서 PortOne return 처리 | 결제 callback은 어디서 받나요? | payment state machine 강화 |
| Video List | `VideoListPresenter`, `VideoRemoteDataSource`, `VideoMapper` | 영상 목록/페이지/좋아요 | `/v1/videos` | `VideoListPresenter` | DTO fallback decoding, duplicate ID 제거 | 영상 목록 pagination은 어떻게 하나요? | list prefetch 정책 |
| Video Player | `VideoPlayerViewModel`, `HLSProbeService`, `VideoURLResolver` | stream fetch/HLS probe/AVPlayer | stream API, HLS URL | `VideoPlayerViewModel` | token query 보존, 420 mismatch 분류, generation guard | HLS 420을 어떻게 진단했나요? | HLS 서비스 파일 분리, full URL 로그 제거 |
| Chat List/Room | `ChatPresenter`, `ChatInteractor`, `ChatSocketIOClient` | 채팅방/메시지/소켓 | Chat API, Socket.IO, CoreData | `ChatPresenter` | optimistic append와 merge policy | socket echo 중복은 어떻게 막나요? | Chat 계층 분리와 테스트 추가 |
| Community List | `CommunityPresenter`, `CommunityInteractor`, `CommunityRemoteDataSource` | 위치 기반 feed/filter/pagination | Community API, location | `CommunityPresenter` | `feedRequestID`, `isPaging`, local distance sort | 중복 pagination을 어떻게 막나요? | empty/error state 세분화 |
| Community Detail | `CommunityDetailPresenter` | 게시글 상세/댓글/좋아요 | Post detail/comment API | `CommunityDetailPresenter` | comments fetch는 detail endpoint 기반 TODO | 댓글 pagination은 어떻게 되나요? | comments 전용 endpoint 반영 |
| Push Notification | `PikkoAppDelegate`, `DefaultAppNotificationService`, `AppNotificationRouter` | APNs/FCM/token sync/route | APNs, FCM, UserDefaults | `SessionStore`, `AppState` | 미인증 route pending 저장 | FCM token은 언제 서버로 보내나요? | payload schema test |
| Location | `LocationService`, `SelectedLocationStore` | 위치 권한/현재 위치/선택 위치 | CoreLocation, UserDefaults | feature presenters | 위치 실패 시 community list degrade | 위치 거부 시 어떻게 하나요? | privacy UX 강화 |
| Image Loading | `AuthorizedImageLoader`, `AuthorizedAsyncImage`, `ImageCache` | 인증 이미지 로딩/cache/fallback | File API, memory cache | loader actor | failed URL TTL, in-flight dedupe | 재사용 셀 이미지 오류를 어떻게 막나요? | disk cache/downsampling |
| Local Cache | `CoreDataChatLocalDataSource`, UserDefaults stores | chat/session/notification/location cache | CoreData, UserDefaults | actors/stores | chat localCacheKey scope | 어떤 데이터를 로컬 저장하나요? | purge/invalidation 정책 |

## 22. Technology-by-Technology Summary Table

| Technology / Pattern | Where used | Why used | Advantages | Disadvantages | Alternatives | Interview explanation |
|---|---|---|---|---|---|---|
| SwiftUI | `PikkoApp`, `RootScene`, `Features/*View` | 선언형 UI와 상태 기반 렌더링 | 상태와 UI 연결이 간결 | 복잡한 navigation은 관리 필요 | UIKit, mixed coordinator | “화면은 SwiftUI로 만들고 상태 객체를 observe합니다.” |
| UIKit AppDelegate | `PikkoAppDelegate` | APNs/FCM/notification delegate | iOS system event 처리 명확 | SwiftUI entry와 분리되어 복잡 | SceneDelegate, pure SwiftUI hooks | “시스템 delegate가 필요한 영역만 bridge했습니다.” |
| MVVM/Presenter | `*Presenter`, `VideoPlayerViewModel` | View와 로직 분리 | 테스트/상태 추적 용이 | Presenter 비대화 가능 | TCA, Redux, MVC | “View는 렌더링, Presenter는 상태 전이를 맡습니다.” |
| Coordinator/Router style | `RootTabView`, `*Router` | 탭/상세/알림 이동 관리 | navigation 책임 분리 | route가 여러 객체에 분산 | AppRoute reducer | “알림 route도 RootTabView에서 탭 선택 후 처리합니다.” |
| Repository | `AuthRepositoryImpl`, `VideoRepository`, `CommunityRepository`, Chat repository | data source 추상화 | mock 주입 쉬움 | 단순 API에는 파일 증가 | service direct call | “UI는 서버 DTO가 아닌 repository/usecase를 봅니다.” |
| UseCase | `FetchVideoStreamUseCase`, `SetVideoLikeUseCase` 등 | 기능별 도메인 작업 표현 | 의존성/테스트 단위 명확 | pass-through usecase는 중복 | repository direct | “복잡한 기능은 usecase로 의도를 드러냅니다.” |
| Manual DI | `AppDIContainer`, `FeatureBuilderFactory` | 의존성 명시 조립 | 런타임 magic 없음 | container 비대화 | Swinject, Resolver, factory modules | “composition root에서 앱 전체 의존성을 만듭니다.” |
| URLSession | `APIClient`, image loader, HLS probe | HTTP API 호출 | 표준/async 지원 | mock setup 필요 | Alamofire | “APIClient가 URLSession을 감싸 공통 처리합니다.” |
| AVPlayer | `VideoPlayerViewModel`, `VideoPlayerView` | HLS 영상 재생 | iOS native player | 상태/KVO/error 복잡 | custom player SDK | “stream URL을 AVPlayerItem으로 만들어 재생합니다.” |
| HLS | video stream flow | adaptive streaming | 품질 선택/스트리밍 적합 | URL/token/playlist 진단 필요 | MP4 progressive | “token query가 포함된 m3u8을 재생합니다.” |
| Socket.IO | `ChatSocketIOClient` | 채팅 실시간 수신 | 서버 push형 메시지 | 재연결/중복/room lifecycle 관리 필요 | WebSocket native, SSE | “REST sync와 socket echo merge를 함께 사용합니다.” |
| Firebase Messaging | `PikkoAppDelegate` | FCM push token/notification | cross-platform push 관리 | APNs 설정과 함께 봐야 함 | APNs 직접 | “APNs token을 FCM에 연결하고 FCM token을 서버에 등록합니다.” |
| Keychain | `KeychainTokenStore` | token 보관 | 민감 정보 저장 적합 | async wrapper/에러 처리 필요 | UserDefaults는 부적합 | “access/refresh token은 Keychain에 저장합니다.” |
| UserDefaults | session snapshot, location, notifications | 가벼운 캐시/설정 | 간단하고 빠름 | 민감 정보 부적합 | file DB, CoreData | “비민감 snapshot과 설정만 저장합니다.” |
| CoreData | chat local cache | 구조적 메시지 저장 | query/update/unique constraint | 모델/마이그레이션 복잡 | SQLite, Realm | “채팅 pending/server message를 로컬에 유지합니다.” |
| async/await | API/location/home/video/chat | 비동기 로직 | callback보다 읽기 쉬움 | cancellation 설계 필요 | Combine, closures | “API와 상태 전이를 async 함수로 표현합니다.” |
| actor | token refresh, Keychain, image, chat local | 공유 상태 직렬화 | race 감소 | MainActor와 경계 필요 | serial queue/lock | “refresh와 cache 중복을 actor로 막습니다.” |
| NotificationCenter | session/token/chat/community notifications | loosely-coupled event | 기존 iOS 방식과 호환 | 추적 어려움 | typed event bus, Combine publisher | “전역 이벤트는 NotificationCenter로 전달합니다.” |
| OSLog/structured logging | `Logger`, feature diagnostics | 디버깅 | category/redaction 가능 | 과하면 noisy | analytics/crash logging | “민감 정보는 redaction하고 HLS/채팅은 구조화 로그를 둡니다.” |

현재 코드에서 찾지 못함 / not applicable:

- RxSwift 사용은 확인되지 않음.
- SwiftData 사용은 확인되지 않음.
- XCUITest/UI test target은 현재 코드에서 찾지 못함.
- Google backend login 활성 사용은 현재 코드에서 찾지 못함.

## 23. Common Interview Questions and Model Answers

### Architecture

Q. 이 앱의 전체 구조를 설명해 주세요.

- Expected answer: SwiftUI 화면, AppDelegate bridge, 수동 DI, Presenter/ViewModel, UseCase/Repository/RemoteDataSource/Mapper 구조이다. `AppDIContainer`가 공통 인프라를 만들고 `FeatureBuilderFactory`가 기능 화면을 조립한다.
- Relevant files: `App/PikkoApp.swift`, `App/DI/AppDIContainer.swift`, `App/DI/FeatureBuilderFactory.swift`.
- Interviewer intent: 계층 분리와 의존성 방향을 이해하는지 확인.
- Stronger follow-up: “영상/커뮤니티는 DTO 변형이 많아 Mapper를 두었고, 채팅은 현재 feature 파일에 책임이 몰려 있어 다음 개선 대상입니다.”

Q. 왜 수동 DI를 선택했나요?

- Expected answer: 앱 규모에서 생성 순서와 의존성을 코드로 명확히 드러내고 외부 DI 프레임워크 의존을 줄이기 위해서다.
- Relevant files: `App/DI/AppDIContainer.swift`.
- Interviewer intent: 기술 선택의 실무적 이유와 trade-off 인식.
- Stronger follow-up: “단점은 container가 커지는 것이므로 feature별 builder로 나누는 개선을 계획할 수 있습니다.”

### App Lifecycle

Q. 앱 실행 시 어떤 순서로 초기화되나요?

- Expected answer: `PikkoApp` init에서 Firebase/DI/AppState를 만들고, `RootScene` task에서 session restore를 실행한 뒤 splash/auth/main을 결정한다.
- Relevant files: `App/PikkoApp.swift`, `App/Root/RootScene.swift`, `App/Bootstrap/AppBootstrapper.swift`.
- Interviewer intent: entry point와 session gate 이해.
- Stronger follow-up: “FCM device token sync는 로그인 이후 별도 task에서 수행해 startup을 막지 않습니다.”

Q. 전역 의존성은 어디서 초기화하나요?

- Expected answer: `AppDIContainer`가 APIClient, token store, repositories, notification, location, image loader 등을 만들고 `FeatureBuilderFactory`가 화면별로 주입한다.
- Relevant files: `App/DI/AppDIContainer.swift`, `App/DI/FeatureBuilderFactory.swift`.
- Interviewer intent: composition root 파악.
- Stronger follow-up: “전역 singleton을 최소화하고 테스트 mock 주입이 가능하도록 builder 경계를 둡니다.”

### Navigation

Q. 메인 탭과 상세 화면 이동은 어떻게 관리하나요?

- Expected answer: `RootTabView`가 탭별 `NavigationPath`를 가지고, 기능 router 또는 notification route가 destination을 요청한다.
- Relevant files: `App/Root/RootTabView.swift`, `App/Root/RootTab.swift`.
- Interviewer intent: SwiftUI navigation과 route state 이해.
- Stronger follow-up: “알림으로 들어온 route는 인증 상태에 따라 pending 저장 후 로그인 뒤 실행됩니다.”

Q. 알림 탭으로 특정 화면을 여는 흐름은요?

- Expected answer: AppDelegate가 payload를 notification service에 전달하고, service가 route를 만들며, router가 AppState/RootTabView를 통해 탭 선택과 sheet/push를 수행한다.
- Relevant files: `PikkoAppDelegate.swift`, `AppNotificationService.swift`, `RootTabView.swift`.
- Interviewer intent: deep link/notification routing edge case 이해.
- Stronger follow-up: “미인증 상태 route는 `PendingNotificationRouteStore`에 저장합니다.”

### Networking

Q. 인증 header는 어디서 붙나요?

- Expected answer: `RequestBuilder`가 `AuthorizationPolicy`에 따라 Authorization/RefreshToken/SesacKey를 붙인다.
- Relevant files: `Core/Network/RequestBuilder.swift`, `Core/Network/AuthorizationPolicy.swift`.
- Interviewer intent: cross-cutting concern 위치 확인.
- Stronger follow-up: “stream API는 Authorization+SesacKey로 호출하지만 HLS m3u8은 token query만 사용합니다.”

Q. token refresh는 어떻게 처리하나요?

- Expected answer: `APIClient`가 401/419를 만나면 `TokenRefreshCoordinator` actor로 refresh를 한 번 수행하고 원 요청을 재시도한다.
- Relevant files: `Core/Network/APIClient.swift`, `Core/Network/TokenRefreshCoordinator.swift`.
- Interviewer intent: 인증 만료와 동시성 대응.
- Stronger follow-up: “actor가 in-flight refresh task를 공유해 여러 요청이 동시에 refresh를 때리는 문제를 줄입니다.”

### Authentication

Q. 세션 복원은 어떻게 하나요?

- Expected answer: Keychain token과 UserDefaults profile snapshot을 읽고 profile API로 유효성을 확인한다. 인증 실패면 token/snapshot을 지우고 로그인 화면으로 간다.
- Relevant files: `SessionRestorer.swift`, `AuthRepositoryImpl.swift`, `SessionStore.swift`.
- Interviewer intent: 앱 재실행/만료 세션 처리.
- Stronger follow-up: “일시적 profile API 실패 시 snapshot fallback을 허용해 UX를 유지합니다.”

Q. 소셜 로그인 provider는 무엇을 지원하나요?

- Expected answer: 현재 Kakao와 Apple이 visible provider이고, Google SDK는 있으나 backend login은 현재 코드에서 활성화되어 있지 않다.
- Relevant files: `AuthInteractor.swift`, `KakaoLoginService.swift`, `AppleSignInService.swift`, `GoogleSignInService.swift`.
- Interviewer intent: 실제 구현과 dependency 차이 구분.
- Stronger follow-up: “Swagger/API 지원 여부에 따라 provider를 노출하지 않는 식으로 client 기능을 제한했습니다.”

### Video/HLS

Q. 영상 재생은 어떤 흐름인가요?

- Expected answer: 목록에서 video를 선택하면 player가 stream API를 호출하고, 응답 HLS URL을 보정/probe한 뒤 AVPlayer로 재생한다.
- Relevant files: `VideoListPresenter.swift`, `VideoPlayerViewModel.swift`, `VideoMapper.swift`.
- Interviewer intent: API와 playback 연결 이해.
- Stronger follow-up: “stream URL은 token이 포함된 재생 권한이므로 목록과 분리해 재생 시점에 가져옵니다.”

Q. HLS token URL을 왜 query로 쓰나요?

- Expected answer: AVPlayer의 하위 playlist/segment 요청까지 custom Authorization header가 유지된다고 보장하기 어렵기 때문에 token query가 더 안정적이다.
- Relevant files: `VideoPlayerViewModel.swift`.
- Interviewer intent: AVPlayer/HLS 특성 이해.
- Stronger follow-up: “그래서 HLS probe도 Authorization/SesacKey header를 제거한 token-only 요청으로 검증합니다.”

Q. 420 service mismatch는 무엇이었나요?

- Expected answer: HLS 요청이 420이고 body에 “This service ... only”가 있으면 서버가 발급한 path/origin/token 조합이 HLS service guard와 맞지 않는 것으로 분류한다.
- Relevant files: `VideoPlayerViewModel.swift`.
- Interviewer intent: 장애 원인 분류 능력.
- Stronger follow-up: “raw query/token length 보존 로그로 client URL 손실이 아님을 확인하고 server-issued routing mismatch로 좁혔습니다.”

### Chat/Socket

Q. 채팅 전송은 어떻게 동작하나요?

- Expected answer: pending message를 optimistic append하고 CoreData에 저장한 뒤 REST 전송한다. 서버 응답이나 socket echo가 오면 merge policy로 pending을 server message로 대체한다.
- Relevant files: `ChatPresenter.swift`, `ChatInteractor.swift`.
- Interviewer intent: optimistic UI와 consistency 이해.
- Stronger follow-up: “serverChatID/localTemporaryID/content-time matching으로 중복을 막습니다.”

Q. socket echo 중복은 어떻게 방지하나요?

- Expected answer: `ChatMessageMergePolicy`가 serverChatID 중복, localTemporaryID 중복, optimistic matching을 기준으로 하나의 메시지만 남긴다.
- Relevant files: `ChatInteractor.swift`.
- Interviewer intent: realtime race handling.
- Stronger follow-up: “REST sync와 socket을 함께 쓰기 때문에 merge policy가 핵심입니다.”

### Community

Q. 커뮤니티 목록은 어떻게 reload/pagination하나요?

- Expected answer: geolocation endpoint를 호출하고 `nextCursor`, `isPaging`, `feedRequestID`로 pagination과 stale response를 관리한다.
- Relevant files: `CommunityPresenter.swift`, `CommunityRemoteDataSource.swift`.
- Interviewer intent: 목록 상태와 race 방지.
- Stronger follow-up: “검색은 별도 endpoint이고, 거리 정렬은 서버 지원 제한 때문에 local sort로 처리합니다.”

Q. 위치 권한이 없으면 어떻게 되나요?

- Expected answer: 선택 위치/기본 위치 fallback을 사용하고, 커뮤니티 목록은 위치 실패로 전체 차단하지 않는다.
- Relevant files: `CommunityInteractor.swift`, `LocationService.swift`, `SelectedLocationStore.swift`.
- Interviewer intent: location UX와 privacy.
- Stronger follow-up: “작성처럼 위치가 필수인 흐름은 더 명확한 권한 안내가 필요합니다.”

### Push Notification

Q. FCM token은 언제 서버에 보내나요?

- Expected answer: AppDelegate/Messaging delegate가 FCM token을 받으면 SessionStore에 저장하고, 로그인 상태에서 `syncCurrentDeviceTokenIfNeeded`가 `/v1/users/deviceToken`으로 보낸다.
- Relevant files: `PikkoAppDelegate.swift`, `SessionStore.swift`, `FeatureBuilderFactory.swift`.
- Interviewer intent: APNs/FCM/server registration 이해.
- Stronger follow-up: “같은 userID/token signature는 중복 등록하지 않습니다.”

### State Management

Q. stale API response는 어떻게 막나요?

- Expected answer: community는 `feedRequestID`, video는 `playbackGeneration`, chat은 requestID/merge policy를 사용한다.
- Relevant files: `CommunityPresenter.swift`, `VideoPlayerViewModel.swift`, `ChatPresenter.swift`.
- Interviewer intent: race condition 대응.
- Stronger follow-up: “개선한다면 active Task cancellation을 더 명시적으로 추가하겠습니다.”

### Error Handling

Q. 어떤 오류를 retry하나요?

- Expected answer: token refresh 후 원 요청 1회, 일시 네트워크 오류, HLS transient 오류는 제한적으로 retry한다. validation/420/444 같은 terminal 오류는 retry하지 않는다.
- Relevant files: `APIClient.swift`, `VideoPlayerViewModel.swift`.
- Interviewer intent: 무한 retry 방지와 사용자 경험.
- Stronger follow-up: “420 mismatch는 server-issued URL 문제일 가능성이 높아 한 번만 stream re-fetch하고 중단합니다.”

### Debugging

Q. HLS 문제를 어떻게 디버깅했나요?

- Expected answer: stream response URL, raw query/token length, HLS token-only probe, status/body classification 로그를 보며 client URL 보존 문제와 server routing 문제를 분리했다.
- Relevant files: `VideoDTO.swift`, `VideoMapper.swift`, `VideoPlayerViewModel.swift`.
- Interviewer intent: 복잡한 장애 분석 과정.
- Stronger follow-up: “로그는 유용했지만 full token URL 출력은 제거해야 할 기술부채입니다.”

### Testing

Q. 현재 테스트에서 가장 중요한 부분은 무엇인가요?

- Expected answer: network token refresh/header, video URL resolution, app bootstrap/session, community state, auth flow가 잘 커버되어 있다.
- Relevant files: `Tests/NetworkInfrastructureTests.swift`, `Tests/VideoFeatureTests.swift`.
- Interviewer intent: 테스트 전략과 gap 인식.
- Stronger follow-up: “Chat merge/socket/CoreData 테스트가 현재 가장 보강할 영역입니다.”

### Security

Q. 민감 정보 로그는 어떻게 처리하나요?

- Expected answer: `SensitiveLogRedactor`가 token/key/deviceToken을 masking한다. 다만 DEBUG HLS full URL 로그는 제거 대상이다.
- Relevant files: `Logger.swift`, `VideoDTO.swift`.
- Interviewer intent: 보안 감수성.
- Stronger follow-up: “production logging은 token query를 절대 남기지 않고 classification만 남기겠습니다.”

### Performance

Q. 성능 최적화 포인트는 무엇인가요?

- Expected answer: image cache/in-flight dedupe, home async let 병렬 로드, token refresh dedupe, chat local cache, pagination guard가 있다.
- Relevant files: `AuthorizedImageLoader.swift`, `HomeInteractor.swift`, `TokenRefreshCoordinator.swift`, `CommunityPresenter.swift`.
- Interviewer intent: 사용자 체감 성능 이해.
- Stronger follow-up: “이미지는 downsampling/disk cache, 목록은 prefetch와 diff 최적화를 추가할 수 있습니다.”

### Refactoring/Improvement

Q. 지금 가장 먼저 개선하고 싶은 부분은요?

- Expected answer: 보안상 full HLS URL debug log 제거, Chat 계층 분리와 merge/socket test 추가, HLS probe service 분리.
- Relevant files: `VideoDTO.swift`, `ChatInteractor.swift`, `VideoPlayerViewModel.swift`.
- Interviewer intent: 우선순위 판단.
- Stronger follow-up: “사용자 장애와 보안 위험이 있는 P0/P1부터 처리하고, 이후 UX/performance 개선으로 가겠습니다.”

## 24. “Explain This Codebase in 3 Minutes” Script

Pikko는 위치 기반으로 주변 가게를 찾고, 주문과 결제, 커뮤니티, 채팅, 영상 재생까지 제공하는 iOS 앱입니다. 앱은 SwiftUI 기반이고, Firebase Messaging이나 APNs, URL callback처럼 UIKit delegate가 필요한 부분은 `PikkoAppDelegate`를 `UIApplicationDelegateAdaptor`로 연결해서 처리했습니다.

구조는 수동 DI와 MVVM/Presenter 패턴을 사용했습니다. `AppDIContainer`가 APIClient, token store, repositories, image loader, notification service 같은 공통 의존성을 만들고, `FeatureBuilderFactory`가 각 화면에 필요한 Presenter와 UseCase를 주입합니다. 화면은 SwiftUI View가 담당하고, 상태와 비동기 작업은 Presenter나 ViewModel이 담당합니다.

네트워크는 `Endpoint`, `RequestBuilder`, `APIClient`로 구성했습니다. 모든 요청에는 `SesacKey`가 들어가고, 인증이 필요한 요청은 `AuthorizationPolicy`에 따라 access token을 붙입니다. 401이나 419가 오면 `TokenRefreshCoordinator` actor가 refresh를 한 번 수행하고 원 요청을 재시도합니다. access/refresh token은 Keychain에 저장하고, session snapshot은 UserDefaults에 저장합니다.

채팅은 REST와 Socket.IO를 함께 사용합니다. 메시지를 보낼 때는 local temporary id로 먼저 UI에 optimistic append하고 CoreData에 저장합니다. 이후 REST 응답이나 socket echo가 오면 `ChatMessageMergePolicy`가 serverChatID, localTemporaryID, content/time matching으로 pending 메시지를 서버 메시지로 교체하고 중복을 제거합니다.

영상은 목록 API와 재생 stream API를 분리했습니다. 사용자가 영상을 누르면 `GET /v1/videos/{video_id}/stream`을 인증 header와 `SesacKey`로 호출하고, 응답의 HLS URL은 token query만으로 AVPlayer가 재생하도록 합니다. 상대 URL은 API origin 기준으로 해석하되 raw query와 token 길이를 보존합니다. HLS 420 응답에 “This service ... only”가 있으면 클라이언트 header 문제가 아니라 서버가 발급한 token/path/origin이 HLS 서비스 guard와 맞지 않는 `serverServiceRoutingMismatch`로 분류했습니다.

이 프로젝트에서 배운 점은 복잡한 모바일 앱에서는 성공 흐름보다 실패 흐름이 더 중요하다는 것입니다. token refresh, stale response 방지, socket echo 중복 제거, HLS URL 보존, notification routing처럼 비동기와 외부 시스템이 만나는 지점에 방어 코드와 진단 로그를 두는 것이 중요했습니다.

## 25. “Explain This Codebase in 10 Minutes” Script

Pikko iOS 앱은 SwiftUI 기반의 위치/커머스/커뮤니티/채팅/영상 앱입니다. 사용자는 Kakao나 Apple 또는 이메일로 로그인하고, 홈에서 주변 가게와 인기 가게를 확인하며, 가게 상세에서 메뉴를 장바구니에 담고 주문/결제를 진행할 수 있습니다. 또 커뮤니티에서 위치 기반 게시글을 보고 댓글을 달 수 있고, 가게나 사용자와 채팅할 수 있으며, 영상 탭에서는 HLS 기반 영상을 재생합니다.

앱 시작은 `PikkoApp`에서 시작합니다. SwiftUI App lifecycle을 사용하지만, Firebase와 APNs, URL callback은 `PikkoAppDelegate`에서 처리합니다. `PikkoApp` init에서 Firebase 설정을 시도하고 `AppDIContainer`를 만듭니다. 그 다음 `RootScene`에서 `AppBootstrapper`가 실행되고, `SessionRestorer`가 Keychain token과 UserDefaults session snapshot을 이용해 기존 세션을 복원합니다. 복원이 끝나면 `launchPhase`가 ready가 되고, `SessionStore.isAuthenticated`에 따라 로그인 화면 또는 메인 탭을 보여줍니다.

아키텍처는 수동 DI와 MVVM/Presenter 구조입니다. `AppDIContainer`가 전역 의존성을 만들고, `FeatureBuilderFactory`가 홈, 주문, 영상, 커뮤니티, 프로필, 채팅 같은 화면을 만들 때 필요한 repository, usecase, presenter를 주입합니다. 외부 DI 프레임워크는 쓰지 않았고, 대신 생성 순서와 의존성이 코드에 명확히 보이도록 했습니다. 장점은 디버깅과 테스트가 쉽다는 점이고, 단점은 container가 커질 수 있다는 점입니다.

네트워크 계층은 `Endpoint`, `RequestBuilder`, `APIClient`로 나뉩니다. 각 endpoint는 path, method, query, body, authorization policy를 가집니다. `RequestBuilder`는 base URL과 endpoint를 조합하고 모든 요청에 `SesacKey`를 넣습니다. 인증 요청에는 Keychain에서 읽은 access token을 `Authorization` header에 붙입니다. `APIClient`는 2xx 응답을 decoding하고, 401이나 419가 나오면 `TokenRefreshCoordinator` actor를 통해 refresh를 한 번 수행한 뒤 원 요청을 재시도합니다. status code는 `HTTPStatusMapper`가 앱 내부 오류로 변환합니다.

인증은 `AuthPresenter`와 `AuthInteractor`가 화면 상태와 provider 선택을 담당합니다. Kakao와 Apple 로그인을 지원하고, 이메일 로그인/회원가입도 있습니다. 로그인 성공 후 `SessionStore.establishAuthenticatedSession`이 token을 Keychain에 저장하고 사용자 session snapshot을 UserDefaults에 저장합니다. 로그아웃이나 refresh 실패가 발생하면 `SessionStore.clearSession`이 token과 snapshot을 지우고 앱은 다시 인증 gate로 돌아갑니다.

홈과 가게 기능은 위치 기반입니다. `LocationService`가 CoreLocation을 감싸고, `SelectedLocationStore`는 사용자가 선택한 위치를 저장합니다. 홈은 선택 위치, 현재 위치, 기본 위치 순서로 fallback해서 인기 검색어, 배너, 인기 가게, 주변 가게를 불러옵니다. `HomeInteractor`는 `async let`을 사용해 여러 섹션을 병렬 로드하고, 일부 섹션이 실패해도 가능한 콘텐츠를 보여주는 방식입니다.

커뮤니티는 `CommunityPresenter`가 목록 상태를 관리합니다. 서버 geolocation endpoint에 category, 좌표, maxDistance, cursor, sort를 보내고, 서버가 지원하지 않는 거리 정렬이나 video/storeTag 필터는 client-side로 처리합니다. pagination은 `nextCursor`, `isPaging`, `feedRequestID`로 관리합니다. `feedRequestID`는 오래된 응답이 최신 필터 상태를 덮어쓰는 문제를 막기 위한 장치입니다. 상세 화면은 게시글 detail과 comments를 관리하고, 댓글 작성/수정/삭제와 좋아요 optimistic update를 처리합니다.

채팅은 REST와 Socket.IO를 함께 씁니다. 채팅방 목록과 메시지 전송은 REST API를 사용하고, 실시간 수신은 namespace `/chats-{roomID}`의 Socket.IO를 사용합니다. 메시지를 보낼 때는 먼저 local temporary id를 가진 pending 메시지를 UI에 추가하고 CoreData에 저장합니다. 서버 응답이나 socket echo가 오면 `ChatMessageMergePolicy`가 serverChatID, localTemporaryID, 같은 sender/content/files/시간 window를 기준으로 pending 메시지를 서버 메시지로 교체합니다. 이 구조 덕분에 즉각적인 채팅 UX를 제공하면서도 REST 응답과 socket echo 중복을 줄일 수 있습니다.

영상 기능은 이 코드베이스에서 가장 진단 로직이 많은 영역입니다. 영상 목록은 `/v1/videos`에서 가져오고, 실제 재생 URL은 사용자가 영상을 눌렀을 때 `/v1/videos/{video_id}/stream`에서 가져옵니다. 이 stream API는 Authorization과 `SesacKey` header가 필요하지만, 응답으로 받은 HLS m3u8 URL은 token query만으로 재생되어야 합니다. AVPlayer는 playlist와 segment를 내부적으로 계속 요청하기 때문에 custom header 방식보다 token query URL 방식이 더 안정적입니다. 그래서 `VideoURLResolver`가 상대 URL을 API origin에 붙이고 raw query와 token 길이를 보존합니다. HLS probe는 Authorization/SesacKey header를 일부러 제거하고 token-only 요청으로 m3u8이 실제 재생 가능한지 확인합니다.

HLS 디버깅에서 중요한 케이스는 420 “This service ... only”였습니다. 이 경우는 SeSAC key가 빠진 것이 아니라, 서버가 발급한 HLS path/origin/token 조합이 HLS 서비스 guard와 맞지 않는 상황으로 분류했습니다. 클라이언트는 URL query를 보존하고 token length를 확인했기 때문에, 원인을 client URL bug가 아니라 server routing mismatch로 좁힐 수 있었습니다. 또 `VideoPlayerViewModel`은 `playbackGeneration`, `activeStreamRequestKey`, fallback attempt set을 사용해 stale player update나 무한 retry를 막습니다.

푸시 알림은 Firebase Messaging과 APNs를 직접 연결합니다. `FirebaseAppDelegateProxyEnabled=false`이므로 AppDelegate에서 APNs token을 받아 Firebase에 전달하고, FCM token을 받은 뒤 `SessionStore`에 저장합니다. 로그인 상태가 되면 `FeatureBuilderFactory.syncCurrentDeviceTokenIfNeeded`가 `/v1/users/deviceToken`으로 token을 서버에 등록합니다. 같은 userID와 token 조합은 중복 등록하지 않습니다. 알림 payload는 `DefaultAppNotificationService`가 앱 내부 notification과 route로 변환하고, 미인증 상태에서는 pending route로 저장했다가 로그인 후 이동합니다.

보안 측면에서는 token을 Keychain에 저장하고, 로그는 `SensitiveLogRedactor`로 masking합니다. 다만 현재 DEBUG 영상 진단 코드 중 full stream URL을 출력하는 부분은 HLS token query가 노출될 수 있어 제거해야 할 기술부채입니다. 테스트는 network, auth, video, community, app bootstrap 쪽이 비교적 잘 되어 있고, 특히 video URL resolution 테스트가 있습니다. 반대로 채팅 merge/socket/CoreData 캐시에 대한 dedicated test는 보강이 필요합니다.

이 코드베이스의 강점은 복잡한 외부 시스템과 비동기 흐름을 단순히 호출하는 데서 끝내지 않고, token refresh, HLS probe, chat merge, notification routing, location fallback처럼 실패 가능성이 높은 지점에 방어와 진단을 넣었다는 점입니다. 개선한다면 보안 로그 정리, Chat 계층 분리, HLS probe 서비스 분리, UI test와 socket test 보강을 우선순위로 두겠습니다.

## 26. Strengths of This Codebase

- 명확한 앱 시작 gate: `RootScene`, `AppBootstrapper`, `SessionRestorer`, `SessionStore`가 splash/auth/main 전환을 분리한다.
- 수동 DI의 명시성: `AppDIContainer.swift`와 `FeatureBuilderFactory.swift`에서 공유 의존성과 화면 조립이 드러난다.
- 네트워크 공통 처리: `RequestBuilder`와 `APIClient`가 `SesacKey`, Authorization, token refresh, status mapping을 중앙화한다.
- token refresh 동시성 방어: `TokenRefreshCoordinator` actor가 refresh 요청을 dedupe한다.
- Keychain token storage: `KeychainTokenStore.swift`가 access/refresh token을 UserDefaults가 아닌 Keychain에 저장한다.
- DTO/domain 분리: `VideoMapper`, `CommunityMapper`가 서버 응답 변형과 앱 모델을 분리한다.
- HLS URL 진단: `VideoURLResolver`, `HLSProbeService`가 raw query 보존, token-only playback, 420 mismatch 분류를 담당한다.
- stale playback 방어: `VideoPlayerViewModel`의 `playbackGeneration`, `activeStreamRequestKey`, fallback attempt tracking.
- optimistic chat handling: `ChatPresenter`와 `ChatMessageMergePolicy`가 pending/server/socket echo를 병합한다.
- store-scoped chat policy: `ChatRoomStoreContext`와 `localCacheKey`로 가게 문의 chat 충돌을 줄인다.
- CoreData chat cache: pending/failed/server message를 구조적으로 저장한다.
- notification routing: `DefaultAppNotificationService`와 `AppNotificationRouter`가 payload 저장, foreground suppression, pending route를 처리한다.
- location fallback: `CommunityInteractor`와 `HomeInteractor`가 위치 실패를 전체 화면 실패로 만들지 않는다.
- image loading cache: `AuthorizedImageLoader`가 in-flight dedupe, memory cache, failed URL TTL을 가진다.
- 테스트 존재: network, auth, video, community, bootstrap 등 핵심 흐름 테스트가 있다.

## 27. Weaknesses / Risks / Technical Debt

### DEBUG HLS full URL logging

- Issue: `Data/DTOs/Video/VideoDTO.swift`의 `VideoStreamingDebugLogger`가 DEBUG에서 full stream URL을 출력한다.
- Why it matters: HLS token query가 로그에 남을 수 있다.
- Production impact: TestFlight/AppStore 또는 crash/log 수집 환경에서 재생 token 노출 위험.
- Suggested improvement: full URL 출력 제거, token query masking, classification 중심 로그만 유지.
- Interview-safe explanation: “장애 분석 중 full URL 로그가 도움이 됐지만, token query가 민감하므로 release 전 masking으로 바꾸는 것이 맞습니다.”

### ChatInteractor file responsibility overload

- Issue: `Features/Chat/ChatInteractor.swift`에 Domain model, DTO, RemoteDataSource, Repository, Mapper, CoreData local source, Interactor가 함께 있다.
- Why it matters: 유지보수와 테스트 경계가 흐려진다.
- Production impact: 채팅 변경 시 side effect 범위가 커지고 merge/local/socket 수정이 서로 얽힐 수 있다.
- Suggested improvement: `Data/Remote/ChatRemoteDataSource.swift`, `Data/Mappers/ChatMapper.swift`, `Domain/Entities/Chat`, `Data/Local/CoreDataChatLocalDataSource.swift`로 분리.
- Interview-safe explanation: “기능 구현을 빠르게 모아 안정화한 뒤, 현재는 계층 일관성을 위해 분리할 시점입니다.”

### Chat merge/socket dedicated tests 부족

- Issue: 채팅 optimistic replacement, duplicate socket echo, store-scoped cache에 대한 dedicated test를 현재 코드에서 찾지 못했다.
- Why it matters: 채팅은 race condition이 많다.
- Production impact: 중복 메시지, pending 메시지 잔존, 잘못된 room 메시지 노출 가능.
- Suggested improvement: `ChatMessageMergePolicy` unit test, socket mock Presenter test, CoreData local cache test 추가.
- Interview-safe explanation: “동작 방어 로직은 있지만 회귀 방지를 위해 테스트를 더 추가해야 합니다.”

### Notification payload schema fragility

- Issue: `RemoteNotificationPayload`가 여러 key를 유연하게 찾지만 서버 schema 변경 시 조용히 route 실패할 수 있다.
- Why it matters: 알림 tap이 기대 화면으로 가지 않을 수 있다.
- Production impact: 주문/채팅/커뮤니티 알림 UX 저하.
- Suggested improvement: payload fixture test, unknown payload diagnostics, server-client schema 문서화.
- Interview-safe explanation: “유연한 parsing은 호환성에 좋지만, schema contract 테스트가 필요합니다.”

### Navigation responsibility concentration

- Issue: `RootTabView`가 탭 path, sheet, notification route를 많이 소유한다.
- Why it matters: route 종류가 늘면 파일 복잡도가 증가한다.
- Production impact: 알림/딥링크/탭 상태 edge case 추적이 어려워질 수 있다.
- Suggested improvement: typed `AppRoute` reducer 또는 router service로 분리.
- Interview-safe explanation: “현재 탭 기반 앱에서는 동작하지만, route가 늘면 중앙 route 모델로 정리하겠습니다.”

### Comments pagination TODO

- Issue: `CommunityRemoteDataSource.fetchComments`는 별도 comments 목록 endpoint가 아니라 detail endpoint comments를 반환하고 next는 nil이다.
- Why it matters: 댓글이 많아질 때 pagination UX가 제한된다.
- Production impact: 상세 API payload 증가, 댓글 목록 성능 저하.
- Suggested improvement: 서버 comments pagination endpoint 반영 후 repository/presenter 갱신.
- Interview-safe explanation: “현재 API 제약에 맞춰 detail comments를 사용했고, 댓글 규모가 커지면 별도 pagination API로 바꾸겠습니다.”

### ATS/media HTTP exception

- Issue: `Config/Pikko-Info.plist`에 media arbitrary loads와 `pickup.sesac.kr` HTTP exception이 있다.
- Why it matters: 네트워크 보안 정책이 완화되어 있다.
- Production impact: 특정 미디어/서버 통신의 보안 리스크.
- Suggested improvement: HTTPS 전환, exception 범위 최소화, release config 검증.
- Interview-safe explanation: “개발/서버 제약 때문에 예외가 있지만 production에서는 최소화해야 합니다.”

### AppDIContainer growth

- Issue: `AppDIContainer`가 많은 service/repository를 생성한다.
- Why it matters: 기능 추가 시 composition root가 계속 커진다.
- Production impact: 생성 순서 변경 실수나 merge conflict 가능성.
- Suggested improvement: feature assembler 또는 builder extension으로 분리.
- Interview-safe explanation: “명시적 DI의 장점은 유지하되 파일 단위는 더 나누겠습니다.”

## 28. Improvement Roadmap

### P0: Critical correctness/security issues

| Problem | Proposed solution | Expected impact | Risk | Suggested files to modify |
|---|---|---|---|---|
| DEBUG HLS full URL token 노출 | full URL 로그 제거, token query masking | 보안 리스크 감소 | 진단 정보 감소 | `Data/DTOs/Video/VideoDTO.swift`, `Core/Utils/Logger.swift` |
| HLS 420 classification 회귀 위험 | 420 body classification unit test 추가 | 장애 원인 분류 안정화 | test fixture 유지 필요 | `Tests/VideoFeatureTests.swift`, `Features/VideoPlayer/VideoPlayerViewModel.swift` |
| ATS/media 예외 release 검증 부족 | release config validation test 추가 | 배포 보안 강화 | 서버 HTTPS 준비 필요 | `Config/Pikko-Info.plist`, `Tests/AppConfigurationTests.swift` |

### P1: Maintainability and architecture improvements

| Problem | Proposed solution | Expected impact | Risk | Suggested files to modify |
|---|---|---|---|---|
| Chat 파일 책임 과다 | DTO/Remote/Mapper/Local/Domain 분리 | 유지보수성 향상 | 큰 이동으로 충돌 가능 | `Features/Chat/ChatInteractor.swift`, `Data/Remote`, `Data/Mappers`, `Domain/Entities` |
| RootTabView route 복잡도 | `AppRoute`와 notification route handler 분리 | routing 이해도 향상 | 기존 route regression | `App/Root/RootTabView.swift`, `Core/Notification` |
| AppDIContainer 비대화 | feature assembler extension 도입 | DI 변경 충돌 감소 | 파일 분산으로 탐색 비용 | `App/DI/AppDIContainer.swift`, `App/DI/FeatureBuilderFactory.swift` |
| HLS probe가 ViewModel 파일에 있음 | `HLSProbeService.swift` 별도 분리 | player state와 네트워크 진단 분리 | 접근제어/test 조정 | `Features/VideoPlayer/VideoPlayerViewModel.swift` |

### P2: UX/performance improvements

| Problem | Proposed solution | Expected impact | Risk | Suggested files to modify |
|---|---|---|---|---|
| 이미지 cache memory 중심 | disk cache/downsampling/NSCache cost 추가 | 스크롤 성능/메모리 개선 | cache invalidation 복잡 | `Core/Platform/Image/*` |
| 댓글 pagination 제한 | comments 전용 pagination API 반영 | 상세 화면 확장성 | 서버 API 필요 | `CommunityRemoteDataSource.swift`, `CommunityDetailPresenter.swift` |
| socket reconnect 후 누락 메시지 | reconnect event 후 REST sync | 채팅 신뢰성 향상 | 중복 merge 검증 필요 | `ChatSocketIOClient.swift`, `ChatPresenter.swift` |
| 위치 권한 UX 단순 | 권한 거부/수동 위치 CTA 강화 | 위치 기반 UX 개선 | 화면 변경 필요 | `Features/Home`, `Features/Community`, `LocationService.swift` |

### P3: Test/documentation improvements

| Problem | Proposed solution | Expected impact | Risk | Suggested files to modify |
|---|---|---|---|---|
| Chat tests 부족 | merge/socket/local cache tests 추가 | 회귀 방지 | mock 설계 필요 | `Tests/ChatFeatureTests.swift` |
| Notification payload tests 부족 | payload fixture 기반 route tests | 알림 routing 안정화 | 서버 payload fixture 관리 | `Tests/NotificationRoutingTests.swift` |
| UI tests 없음 | smoke XCUITest 추가 | 핵심 flow regression 감지 | CI 시간 증가 | UI test target |
| architecture docs 부족 | README/Docs에 flow diagram 추가 | 온보딩 개선 | 최신화 필요 | `Docs` 또는 `docs` |

## 29. Final Study Checklist

### Files to read

- `App/PikkoApp.swift`
- `App/PikkoAppDelegate.swift`
- `App/Root/RootScene.swift`
- `App/Root/RootTabView.swift`
- `App/DI/AppDIContainer.swift`
- `App/DI/FeatureBuilderFactory.swift`
- `App/State/SessionStore.swift`
- `Core/Network/APIClient.swift`
- `Core/Network/RequestBuilder.swift`
- `Core/Network/TokenRefreshCoordinator.swift`
- `Core/Storage/KeychainTokenStore.swift`
- `Features/Auth/AuthPresenter.swift`
- `Features/Auth/AuthInteractor.swift`
- `Data/Remote/AuthRemoteDataSource.swift`
- `Data/Repositories/AuthRepositoryImpl.swift`
- `Features/Video/VideoListPresenter.swift`
- `Features/VideoPlayer/VideoPlayerViewModel.swift`
- `Data/DTOs/Video/VideoDTO.swift`
- `Data/Mappers/VideoMapper.swift`
- `Features/Chat/ChatPresenter.swift`
- `Features/Chat/ChatInteractor.swift`
- `Features/Chat/ChatSocketIOClient.swift`
- `Features/Community/CommunityPresenter.swift`
- `Features/Community/CommunityDetailPresenter.swift`
- `Features/Community/CommunityComposerPresenter.swift`
- `Data/Remote/CommunityRemoteDataSource.swift`
- `Core/Notification/AppNotificationService.swift`
- `Core/Platform/Location/LocationService.swift`
- `Core/Platform/Image/AuthorizedImageLoader.swift`
- `Tests/NetworkInfrastructureTests.swift`
- `Tests/VideoFeatureTests.swift`
- `Tests/CommunityFeatureTests.swift`

### Flows to explain

- 앱 실행: `PikkoApp` → DI → `RootScene` → `AppBootstrapper` → session restore → auth/main gate.
- 로그인: provider 선택 → social credential → auth API → token Keychain 저장 → RootTab 진입.
- token refresh: 401/419 → `TokenRefreshCoordinator` → token 저장 → 원 요청 재시도.
- notification: APNs/FCM token → SessionStore 저장 → 서버 sync → payload route.
- community list/detail: 위치 context → geolocation feed → filter/sort/pagination → detail/comments.
- chat send: pending local message → optimistic UI → REST send → server response/socket echo merge.
- socket lifecycle: room entry → namespace connect → event decode/filter → merge → disconnect.
- video playback: list tap → stream API → HLS URL resolution → token-only probe → AVPlayer.
- HLS 420: token query 보존 확인 → token-only probe → service mismatch classification.
- image loading: file path resolution → authorized request → memory cache/fallback.

### Diagrams to draw

- App startup gate diagram: Splash/Auth/Main.
- Network request pipeline: Endpoint → RequestBuilder → APIClient → DTO → Mapper → Domain → Presenter.
- Token refresh sequence diagram.
- Video HLS sequence: list tap → stream API → URL resolver → HLS probe → AVPlayer.
- Chat message lifecycle: local temporary → pending CoreData → REST success → socket echo → merge.
- Notification routing: remote payload → service → repository → router → tab/detail.
- Location fallback: selected location → current location → default/degraded state.

### Logs to understand

- Network protected request log and status mapping.
- Token refresh success/failure log.
- HLS stream API response shape log.
- HLS URL resolution token length/masked query log.
- HLS 420 service mismatch diagnosis log.
- AVPlayer item failed/stalled/error/access logs.
- Chat optimistic append/REST success/merge duplicate log.
- Socket connect/disconnect/error/event log.
- Notification payload route/suppression log.
- Location unavailable fallback log.

### Bugs to explain

- HLS 420 “This service ... only”는 server-issued token/path/origin과 HLS service guard 불일치로 분류한다.
- HLS URL query가 손실되면 AVPlayer 하위 playlist/segment 요청이 실패할 수 있다.
- socket echo와 REST success가 동시에 오면 chat duplicate가 생길 수 있어 merge policy가 필요하다.
- 위치 권한 거부가 community list 전체 실패로 이어지면 UX가 나빠지므로 degrade 처리한다.
- stale API response가 최신 filter/playback state를 덮을 수 있어 requestID/generation이 필요하다.
- FCM token을 매번 서버에 보내면 불필요한 호출이 생기므로 userID/token signature로 dedupe한다.

### Improvements to propose

- P0: DEBUG HLS full URL 로그 제거와 token masking.
- P0: HLS 420 classification test 추가.
- P1: Chat 계층 분리와 merge/socket/local cache tests 추가.
- P1: HLS probe/service를 ViewModel에서 분리.
- P1: RootTabView route handling을 typed AppRoute로 정리.
- P2: image disk cache/downsampling 추가.
- P2: socket reconnect 후 REST sync.
- P2: community comments pagination endpoint 반영.
- P3: notification payload fixture tests.
- P3: 핵심 flow UI smoke tests.

최종 면접 준비 포인트:

- “이 코드는 왜 이렇게 나뉘었는가?”를 파일 이름과 함께 설명한다.
- “실패했을 때 어떻게 동작하는가?”를 token refresh, HLS, chat, notification, location 중심으로 설명한다.
- “내가 개선한다면 무엇부터 할 것인가?”를 보안, 테스트, 계층 분리 순서로 말한다.
- “클라이언트 책임과 서버 책임의 경계”를 HLS stream URL 이슈로 명확히 설명한다.
