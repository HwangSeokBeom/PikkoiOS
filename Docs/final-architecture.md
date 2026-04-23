# Pikko iOS 최종 설계 문서

작성 기준: 2026년 4월 23일  
기준 소스: [Swagger](http://pickup.sesac.kr:42678/api-docs/9POW2XC7H5VZP9N1/)

이 문서는 2026년 4월 23일 기준으로 Swagger와 UI 시안 [Main View.png](../도봉3기%20LSLP%20픽업/Main%20View.png), [Community View.png](../도봉3기%20LSLP%20픽업/Community%20View.png), [Order View.png](../도봉3기%20LSLP%20픽업/Order%20View.png), [Detail View_Timeout.png](../도봉3기%20LSLP%20픽업/Detail%20View_Timeout.png)를 기준으로 정리한 최종 설계 문서다.

표기 기준은 다음 4개로 통일한다.

- `즉시 가능`: Swagger 기준 서버 연동 가능
- `서버 협의 필요`: 스펙은 있으나 계약이 불완전하거나 실제 서비스용 의미가 부족
- `추가 서버 구현 필요`: Swagger에 없음
- `클라이언트 선구현 가능`: 서버 없이 로컬 상태/목업으로 먼저 가능

## 목차

1. [프로젝트 개요](#1-프로젝트-개요)
2. [최종 아키텍처 선택 이유](#2-최종-아키텍처-선택-이유)
3. [전체 레이어 구조](#3-전체-레이어-구조)
4. [실제 프로젝트 폴더 구조 최종안](#4-실제-프로젝트-폴더-구조-최종안)
5. [VIPER 모듈 구성 원칙](#5-viper-모듈-구성-원칙)
6. [Feature 분리 최종안](#6-feature-분리-최종안)
7. [객체 생성 / 조립 구조](#7-객체-생성--조립-구조)
8. [DI 전략 최종안](#8-di-전략-최종안)
9. [상태 관리 전략](#9-상태-관리-전략)
10. [네비게이션 전략](#10-네비게이션-전략)
11. [네트워크 레이어 최종안](#11-네트워크-레이어-최종안)
12. [Swift Concurrency / Combine 사용 기준](#12-swift-concurrency--combine-사용-기준)
13. [Swagger 반영 API 분석](#13-swagger-반영-api-분석)
14. [Feature별 API 매핑](#14-feature별-api-매핑)
15. [DTO / Entity / Mapper 전략](#15-dto--entity--mapper-전략)
16. [디자인 시스템 / 공통 컴포넌트 전략](#16-디자인-시스템--공통-컴포넌트-전략)
17. [구현 우선순위 / Phase 제안](#17-구현-우선순위--phase-제안)
18. [파일 비대화 방지 규칙](#18-파일-비대화-방지-규칙)
19. [포트폴리오 설명 포인트](#19-포트폴리오-설명-포인트)
20. [최종 추천안 요약](#20-최종-추천안-요약)

---

## 1. 프로젝트 개요

- 앱 컨셉: 배달보다 `픽업` 경험에 집중한 로컬 주문 iOS 앱이다. 사용자는 현재 위치 기준으로 가게를 탐색하고, 메뉴를 담고, 결제 후 픽업 상태를 추적한다.
- 핵심 사용자 경험: `빠른 탐색 -> 부드러운 상세 진입 -> 단일 가게 장바구니 -> 결제 검증 -> 픽업 상태 확인`의 흐름을 가장 짧게 만든다.
- 화면 구성 요약: 홈, 커뮤니티, 가게 상세, 장바구니/결제, 주문, 프로필/마이, 채팅.
- 이번 설계의 목표: SwiftUI + VIPER + 직접 DI + async/await + URLSession으로 `대형 루트 파일 없이`, `Feature 단위 책임이 분리된`, `테스트 가능하고 AI 협업 친화적인` 구조를 만든다.
- 서버 전제: 현재 Swagger상 대부분의 핵심 API가 인증 전제다. 따라서 서버 연동 기준 메인 탭은 `로그인 이후 진입`을 기본값으로 설계한다.

## 2. 최종 아키텍처 선택 이유

- 왜 SwiftUI인가: 카드형 리스트, 하단 탭, sticky CTA, 검색/필터 칩, pull-to-refresh, skeleton, sheet/fullScreen 전환을 빠르게 구현하고 시안 반영 속도를 높일 수 있다.
- 왜 VIPER인가: 화면 책임을 `View/Presenter/Interactor/Router/Builder`로 강제 분리해 화면 조립, 상태, 비즈니스 로직, 라우팅이 한 파일에 몰리지 않는다.
- 왜 TCA 대신 VIPER인가: 이전 TCA 프로젝트에서 루트 조립 지점이 비대해졌고, 전역 상태/화면 조립/라우팅이 집중됐다. 이번 프로젝트는 루트 집중을 피하는 것이 우선순위이므로 feature-local assembly가 쉬운 VIPER가 더 맞다.
- 왜 Swift Concurrency 중심인가: 이 앱의 중심은 HTTP 호출, 토큰 재발급, 업로드, 결제 검증, 페이지네이션이다. async/await가 URLSession과 가장 자연스럽고, Combine보다 호출 흐름과 에러 전파가 단순하다.
- 왜 URLSession 직접 사용인가: SeSACKey, AccessToken, RefreshToken, 419/418/445 같은 비표준 상태 코드, multipart, 상대경로 파일 URL 처리까지 직접 설계 포인트가 많다. 포트폴리오 설명력도 높다.
- 왜 Combine은 제한적으로만 사용하는가: debounce, 앱 이벤트 스트림, 실시간 수신 보조처럼 연속 스트림 문제에만 쓴다. 일반 API 호출까지 Combine으로 끌고 가면 상태 흐름이 불필요하게 복잡해진다.
- 왜 DI 라이브러리 없이 직접 DI인가: 현재 규모에서는 `AppDIContainer + Feature Builder + init 주입`이 가장 명확하다. 의존성 생성 경로가 코드에 그대로 드러나고, 테스트 더블 주입도 단순하다.
- 왜 이 구조가 포트폴리오/유지보수/AI 협업에 유리한가: 수정 단위가 `한 Feature의 Presenter/Interactor/View`로 좁혀지고, Builder가 조립 책임을 흡수하므로 AI가 안전하게 고칠 수 있다. “왜 이렇게 나눴는가”를 면접에서 설명하기도 쉽다.

## 3. 전체 레이어 구조

| 레이어 | 책임 | 허용 의존 | 금지 |
|---|---|---|---|
| App | 앱 엔트리, 부트스트랩, DI, 루트 탭, 로그인 게이트, 딥링크 | 모든 레이어 | 비즈니스 로직 직접 구현 |
| Core | 네트워크, 저장소, 플랫폼 서비스, 유틸 | 외부 프레임워크 | Feature 지식 포함 |
| Domain | Entity, Repository protocol, UseCase | 없음 또는 Core 추상 타입 최소 | UIKit/SwiftUI, DTO |
| Data | DTO, Mapper, Repository 구현, Remote DataSource | Core, Domain | ViewState, UI 표현 로직 |
| DesignSystem | 색상, 타이포, 간격, 기본 버튼/칩/로딩 등 순수 UI 토큰/프리미티브 | Core 최소 | API, Feature 의존 |
| Shared | 공통 복합 컴포넌트, 공통 포맷터, 공통 상태/헬퍼 | DesignSystem, Core | 특정 Feature 비즈니스 로직 |
| Features | 각 화면의 VIPER 모듈 | Domain, Shared, DesignSystem, Core 일부 | Data 직접 참조, 다른 Feature 내부 구현 직접 참조 |

의존 방향은 `App -> Features -> Domain`, `App -> Data -> Domain`, `Features -> Shared/DesignSystem/Core`, `Data -> Core/Domain`으로 고정한다.  
금지 규칙은 `Features -> Data 직접 import`, `Shared -> Features`, `Domain -> DTO/SwiftUI`다.

## 4. 실제 프로젝트 폴더 구조 최종안

```text
Pikko/
├── App/
│   ├── PikkoApp.swift
│   ├── Bootstrap/
│   │   ├── AppBootstrapper.swift
│   │   ├── LaunchPhase.swift
│   │   └── SessionRestorer.swift
│   ├── DI/
│   │   ├── AppDIContainer.swift
│   │   ├── RepositoryFactory.swift
│   │   ├── UseCaseFactory.swift
│   │   └── FeatureBuilderFactory.swift
│   ├── Routing/
│   │   ├── AppCoordinator.swift
│   │   ├── AppRoute.swift
│   │   ├── AppDeeplinkParser.swift
│   │   └── PendingRouteStore.swift
│   ├── State/
│   │   ├── AppState.swift
│   │   ├── SessionStore.swift
│   │   ├── CartStore.swift
│   │   └── AppToastCenter.swift
│   └── Root/
│       ├── RootScene.swift
│       ├── RootTabView.swift
│       ├── RootTab.swift
│       ├── AuthGateView.swift
│       └── FloatingQuickActionView.swift
├── Config/
│   ├── Debug.xcconfig
│   ├── Release.xcconfig
│   ├── Secrets.xcconfig.sample
│   └── AppConfiguration.swift
├── Core/
│   ├── Network/
│   │   ├── APIClient.swift
│   │   ├── APIClientProtocol.swift
│   │   ├── Endpoint.swift
│   │   ├── HTTPMethod.swift
│   │   ├── NetworkError.swift
│   │   ├── RequestBuilder.swift
│   │   ├── TokenRefreshCoordinator.swift
│   │   ├── AuthorizationPolicy.swift
│   │   ├── MultipartFormDataBuilder.swift
│   │   └── URLSessionConfigurationFactory.swift
│   ├── Storage/
│   │   ├── KeychainTokenStore.swift
│   │   ├── TokenStore.swift
│   │   ├── UserDefaultsStore.swift
│   │   └── RecentSearchStore.swift
│   ├── Platform/
│   │   ├── Auth/
│   │   │   ├── AppleSignInService.swift
│   │   │   └── KakaoLoginService.swift
│   │   ├── Location/
│   │   │   ├── LocationService.swift
│   │   │   ├── LocationServiceProtocol.swift
│   │   │   └── ReverseGeocoder.swift
│   │   ├── Map/
│   │   │   ├── MapLauncher.swift
│   │   │   └── MapLauncherProtocol.swift
│   │   └── Image/
│   │       ├── AuthorizedImageLoader.swift
│   │       ├── AuthorizedFileURLResolver.swift
│   │       └── ImageCache.swift
│   ├── Utils/
│   │   ├── Logger.swift
│   │   ├── DateParser.swift
│   │   ├── CurrencyFormatter.swift
│   │   ├── DistanceFormatter.swift
│   │   └── MediaTypeResolver.swift
│   └── Extensions/
│       ├── URLRequest+.swift
│       ├── View+.swift
│       └── Color+.swift
├── Domain/
│   ├── Entities/
│   │   ├── AuthSession.swift
│   │   ├── User.swift
│   │   ├── Store.swift
│   │   ├── Menu.swift
│   │   ├── Order.swift
│   │   ├── OrderStatus.swift
│   │   ├── Review.swift
│   │   ├── CommunityPost.swift
│   │   ├── Comment.swift
│   │   ├── ChatRoom.swift
│   │   ├── ChatMessage.swift
│   │   ├── Banner.swift
│   │   ├── CursorPage.swift
│   │   └── MediaAsset.swift
│   ├── Repositories/
│   │   ├── AuthRepository.swift
│   │   ├── UserRepository.swift
│   │   ├── StoreRepository.swift
│   │   ├── CommunityRepository.swift
│   │   ├── OrderRepository.swift
│   │   ├── ReviewRepository.swift
│   │   ├── ChatRepository.swift
│   │   ├── BannerRepository.swift
│   │   └── VideoRepository.swift
│   └── UseCases/
│       ├── Auth/
│       ├── Home/
│       ├── Store/
│       ├── Community/
│       ├── Order/
│       ├── Review/
│       ├── Profile/
│       └── Chat/
├── Data/
│   ├── DTOs/
│   │   ├── Auth/
│   │   ├── User/
│   │   ├── Store/
│   │   ├── Community/
│   │   ├── Order/
│   │   ├── Review/
│   │   ├── Chat/
│   │   ├── Banner/
│   │   └── Video/
│   ├── Mappers/
│   │   ├── AuthMapper.swift
│   │   ├── UserMapper.swift
│   │   ├── StoreMapper.swift
│   │   ├── CommunityMapper.swift
│   │   ├── OrderMapper.swift
│   │   ├── ReviewMapper.swift
│   │   ├── ChatMapper.swift
│   │   ├── BannerMapper.swift
│   │   └── VideoMapper.swift
│   ├── Repositories/
│   │   ├── AuthRepositoryImpl.swift
│   │   ├── UserRepositoryImpl.swift
│   │   ├── StoreRepositoryImpl.swift
│   │   ├── CommunityRepositoryImpl.swift
│   │   ├── OrderRepositoryImpl.swift
│   │   ├── ReviewRepositoryImpl.swift
│   │   ├── ChatRepositoryImpl.swift
│   │   ├── BannerRepositoryImpl.swift
│   │   └── VideoRepositoryImpl.swift
│   └── Remote/
│       ├── AuthRemoteDataSource.swift
│       ├── UserRemoteDataSource.swift
│       ├── StoreRemoteDataSource.swift
│       ├── CommunityRemoteDataSource.swift
│       ├── OrderRemoteDataSource.swift
│       ├── ReviewRemoteDataSource.swift
│       ├── ChatRemoteDataSource.swift
│       └── BannerRemoteDataSource.swift
├── DesignSystem/
│   ├── Color/
│   ├── Typography/
│   ├── Spacing/
│   ├── Radius/
│   ├── Shadow/
│   ├── Component/
│   │   ├── PrimaryButton.swift
│   │   ├── SecondaryButton.swift
│   │   ├── TagChip.swift
│   │   ├── SearchBar.swift
│   │   ├── SectionHeader.swift
│   │   ├── EmptyStateView.swift
│   │   ├── LoadingView.swift
│   │   ├── SkeletonView.swift
│   │   ├── ToastView.swift
│   │   └── SnackbarView.swift
│   └── Modifier/
├── Shared/
│   ├── Component/
│   │   ├── StoreCard.swift
│   │   ├── CommunityCard.swift
│   │   ├── OrderStatusTimelineView.swift
│   │   ├── AuthorizedAsyncImage.swift
│   │   ├── RatingSummaryView.swift
│   │   └── DistanceChipBar.swift
│   ├── Navigation/
│   │   ├── FeatureFactory.swift
│   │   ├── RoutePresentable.swift
│   │   └── ExternalRoute.swift
│   ├── Formatter/
│   └── Support/
│       ├── SearchDebouncer.swift
│       └── PaginationTrigger.swift
├── Features/
│   ├── Auth/
│   │   ├── Builder/AuthBuilder.swift
│   │   ├── Entity/AuthAction.swift
│   │   ├── Entity/AuthViewState.swift
│   │   ├── Interactor/AuthInteractor.swift
│   │   ├── Presenter/AuthPresenter.swift
│   │   ├── Router/AuthRouter.swift
│   │   └── View/
│   │       ├── AuthView.swift
│   │       └── SocialLoginSection.swift
│   ├── Home/
│   │   ├── Builder/HomeBuilder.swift
│   │   ├── Entity/HomeAction.swift
│   │   ├── Entity/HomeViewState.swift
│   │   ├── Interactor/HomeInteractor.swift
│   │   ├── Presenter/HomePresenter.swift
│   │   ├── Router/HomeRouter.swift
│   │   └── View/
│   │       ├── HomeView.swift
│   │       └── Sections/
│   ├── Community/
│   │   ├── Builder/CommunityBuilder.swift
│   │   ├── Entity/CommunityAction.swift
│   │   ├── Entity/CommunityViewState.swift
│   │   ├── Interactor/CommunityInteractor.swift
│   │   ├── Presenter/CommunityPresenter.swift
│   │   ├── Router/CommunityRouter.swift
│   │   └── View/
│   │       ├── CommunityView.swift
│   │       ├── CommunityDetailView.swift
│   │       └── CommunityComposerView.swift
│   ├── StoreDetail/
│   │   ├── Builder/StoreDetailBuilder.swift
│   │   ├── Entity/StoreDetailAction.swift
│   │   ├── Entity/StoreDetailViewState.swift
│   │   ├── Entity/MenuFilter.swift
│   │   ├── Interactor/StoreDetailInteractor.swift
│   │   ├── Presenter/StoreDetailPresenter.swift
│   │   ├── Router/StoreDetailRouter.swift
│   │   └── View/
│   │       ├── StoreDetailView.swift
│   │       ├── ReviewListView.swift
│   │       └── MenuSearchView.swift
│   ├── Cart/
│   │   ├── Builder/CartBuilder.swift
│   │   ├── Entity/CartViewState.swift
│   │   ├── Interactor/CartInteractor.swift
│   │   ├── Presenter/CartPresenter.swift
│   │   ├── Router/CartRouter.swift
│   │   └── View/CartView.swift
│   ├── Checkout/
│   │   ├── Builder/CheckoutBuilder.swift
│   │   ├── Entity/CheckoutViewState.swift
│   │   ├── Interactor/CheckoutInteractor.swift
│   │   ├── Presenter/CheckoutPresenter.swift
│   │   ├── Router/CheckoutRouter.swift
│   │   ├── Bridge/PaymentWebViewBridge.swift
│   │   ├── Bridge/PaymentGatewayProtocol.swift
│   │   └── View/
│   │       ├── CheckoutView.swift
│   │       ├── PaymentWebView.swift
│   │       └── OrderCompleteView.swift
│   ├── Order/
│   │   ├── Builder/OrderBuilder.swift
│   │   ├── Entity/OrderViewState.swift
│   │   ├── Interactor/OrderInteractor.swift
│   │   ├── Presenter/OrderPresenter.swift
│   │   ├── Router/OrderRouter.swift
│   │   └── View/
│   │       ├── OrderView.swift
│   │       ├── OrderDetailView.swift
│   │       └── ReviewComposerView.swift
│   ├── Profile/
│   │   ├── Builder/ProfileBuilder.swift
│   │   ├── Entity/ProfileViewState.swift
│   │   ├── Interactor/ProfileInteractor.swift
│   │   ├── Presenter/ProfilePresenter.swift
│   │   ├── Router/ProfileRouter.swift
│   │   └── View/
│   │       ├── ProfileView.swift
│   │       ├── EditProfileView.swift
│   │       └── PickedStoresView.swift
│   ├── Chat/
│   │   ├── Builder/ChatBuilder.swift
│   │   ├── Entity/ChatViewState.swift
│   │   ├── Interactor/ChatInteractor.swift
│   │   ├── Presenter/ChatPresenter.swift
│   │   ├── Router/ChatRouter.swift
│   │   ├── Realtime/
│   │   │   ├── ChatRealtimeService.swift
│   │   │   ├── PollingChatRealtimeService.swift
│   │   │   └── SocketIOChatRealtimeService.swift
│   │   └── View/
│   │       ├── ChatRoomListView.swift
│   │       └── ChatRoomView.swift
│   └── Video/            // Phase 3
├── Resources/
│   ├── Assets.xcassets
│   ├── Localizable.strings
│   └── Info.plist
└── Tests/
    ├── CoreTests/
    ├── DataTests/
    ├── DomainTests/
    └── FeatureTests/
        ├── AuthTests/
        ├── HomeTests/
        ├── StoreDetailTests/
        ├── CheckoutTests/
        ├── OrderTests/
        ├── CommunityTests/
        └── ChatTests/
```

## 5. VIPER 모듈 구성 원칙

- View: SwiftUI `struct View`다. 렌더링, 바인딩, `onAppear`, `refreshable`, 입력 이벤트 전달만 맡는다. API 호출과 라우팅 판단을 직접 하지 않는다.
- Presenter: `@MainActor final class ...Presenter: ObservableObject`로 둔다. `@Published private(set) var state: ViewState`를 단일 진실원으로 관리한다.
- ViewState 관리 위치: Presenter가 가진다. View는 상태를 소유하지 않고 읽기만 한다. 다만 포커스, 텍스트 입력 임시값, 시트 토글 같은 일시 UI 상태는 View의 `@State`로 둔다.
- Interactor: use case orchestration, repository 호출, 세션/장바구니/업로드/결제 같은 비즈니스 사이드이펙트를 담당한다. `거리 문자열`, `칩 텍스트`, `카드 섹션 배열` 같은 표현 로직은 하지 않는다.
- Router: `NavigationPath`, `sheet`, `fullScreenCover`, 외부 맵/웹뷰 오픈만 담당한다. 비즈니스 로직과 데이터 가공은 금지한다.
- Entity: 이번 구조에서 VIPER Entity는 `Feature-local model`이다. 예: `HomeAction`, `HomeSection`, `StoreDetailMenuFilter`. 순수 비즈니스 Entity는 `Domain/Entities`에 둔다.
- Builder: Feature별 composition root다. Router/Interactor/Presenter/View 생성, cross-feature destination factory 주입, 공통 서비스 연결을 담당한다. Builder가 있어야 App 루트에서 객체 생성이 폭증하지 않는다.

## 6. Feature 분리 최종안

| 모듈 | 핵심 책임 | 주요 화면 | 연관 API |
|---|---|---|---|
| Auth | 로그인, 세션 복구, 로그아웃 | 로그인 게이트, 소셜 로그인 | User, Auth |
| Home | 위치 기반 가게 탐색, 배너, 인기 검색어, 찜 | 홈 메인 | Store, Banner |
| Community | 위치 기반 피드, 좋아요, 댓글, 글 작성/수정 | 커뮤니티 리스트/상세/작성 | Community-Post, Community-Post-Comment |
| StoreDetail | 가게 상세, 메뉴 필터, 리뷰, 찜, 길찾기, 채팅 진입 | 가게 상세, 리뷰 리스트 | Store, Review, Chat |
| Cart | 단일 가게 장바구니 상태 | 장바구니 | API 없음, Checkout과 연동 |
| Checkout | 주문 생성, PG 브릿지, 영수증 검증 | 결제 요약, 결제 웹뷰, 완료 | Order, Payment |
| Order | 현재 주문/이전 주문, 상태 타임라인, 영수증, 리뷰 작성 | 주문 탭, 주문 상세 | Order, Payment, Review |
| Profile | 내 정보, 찜 가게, 내 리뷰, 설정, 로그아웃 | 프로필/마이, 수정 | User, Store, Review |
| Chat | 채팅방 목록, 메시지, 파일 첨부, 실시간 수신 | 채팅방 목록, 채팅방 | Chat |
| Shared / DesignSystem | 공통 UI, 레이아웃, 인증 이미지 로더 | 모든 화면 | API 없음 |

## 7. 객체 생성 / 조립 구조

- AppDIContainer가 소유하는 전역 의존성:
  - `AppConfiguration`
  - `URLSession`, `APIClient`, `RequestBuilder`
  - `TokenRefreshCoordinator`
  - `KeychainTokenStore`, `UserDefaultsStore`, `RecentSearchStore`
  - `SessionStore`, `CartStore`
  - `LocationService`, `MapLauncher`
  - `AuthorizedImageLoader`
  - 모든 Repository 구현체와 UseCase
- Feature Builder가 생성하는 모듈 전용 객체:
  - Feature Router
  - Feature Interactor
  - Feature Presenter
  - Feature Root View
  - 필요 시 feature 전용 bridge 객체(`PaymentWebViewBridge`, `PollingChatRealtimeService`)
- 앱 전체 공유 의존성:
  - 세션, 토큰, 장바구니, APIClient, 이미지 로더, 위치 서비스
- Feature별 생성 의존성:
  - Presenter, Router, Interactor, feature-local formatter, screen-specific realtime/polling object
- 조립 분산 방식:
  1. `PikkoApp`는 `AppDIContainer`만 만든다.
  2. `RootScene`은 `SessionStore.authState`에 따라 `AuthBuilder` 또는 `FeatureBuilderFactory`만 호출한다.
  3. 각 탭은 자기 Builder로만 루트 뷰를 만든다.
  4. 다른 Feature로 이동할 때는 Builder 간 직접 참조 대신 `factory closure` 또는 `Buildable protocol`을 주입한다.
- 핵심 흐름:
  - `PikkoApp -> AppBootstrapper -> SessionRestorer -> RootScene`
  - `RootScene -> HomeBuilder / OrderBuilder / CommunityBuilder / ProfileBuilder`
  - `HomeBuilder -> HomeRouter + HomeInteractor + HomePresenter + HomeView`

## 8. DI 전략 최종안

- 구현 방식: 직접 DI다. `init` 주입이 기본이고, property injection은 금지한다.
- protocol을 두는 기준:
  - 둔다: Repository, APIClient, TokenStore, LocationService, PaymentGateway, RealtimeService
  - 안 둔다: 단순 Router, Formatter, Mapper, 작은 helper
- Repository 추상화 기준: 서버/저장소 구현이 바뀔 가능성이 있는 모든 데이터 접근 경계는 Repository protocol로 감싼다.
- Service 추상화 기준: OS/외부 SDK/실시간 연결/지도/결제처럼 인프라 성격이 강한 것은 Service protocol로 둔다.
- Storage 추상화 기준: Keychain/UserDefaults는 protocol로 둔다. 토큰/최근 검색어/플래그 테스트가 쉬워진다.
- APIClient 추상화 기준: `execute(endpoint:) async throws -> Response` 한 개의 제네릭 경계를 둔다.
- Router를 무조건 protocol로 만들 필요는 없다. 대부분 concrete class로 두고, cross-feature handoff가 필요한 경우에만 factory protocol을 둔다.
- 테스트용 Mock 전략:
  - Presenter 테스트: MockInteractor
  - Interactor 테스트: MockRepository / InMemoryTokenStore
  - APIClient 테스트: `URLProtocol` stub
  - SwiftUI Preview: `PreviewDIContainer`
- 역할 구분:
  - `AppDIContainer`: 싱글톤 성격의 shared dependency 보유
  - `Builder`: 화면 단위 조립
  - `Factory`: low-level 객체 생성 또는 cross-feature destination 제공

## 9. 상태 관리 전략

- 전역 상태: `AppState`
  - `launchPhase`
  - `selectedTab`
  - `pendingDeepLink`
  - `globalToast`
- 세션 상태: `SessionStore`
  - `accessToken`
  - `refreshToken`
  - `currentUserID`
  - `nick`
  - `profileImagePath`
  - `isAuthenticated`
  - `deviceToken`
- 화면 상태: 각 Feature Presenter의 `ViewState`
  - 예시 `HomeViewState`: `locationLabel`, `selectedCategory`, `searchText`, `popularKeywords`, `banners`, `popularStores`, `nearbyStores`, `nextCursor`, `isLoading`, `isRefreshing`, `errorMessage`
- 일시 UI 상태: View 내부 `@State`
  - 키보드 포커스
  - 검색창 활성화
  - 바텀시트 열림 여부
  - 탭 스크롤 위치
- 사용 기준:
  - `@StateObject`: Feature root view가 소유하는 Presenter/Router
  - `@ObservedObject`: 상위에서 전달받은 Presenter/Router
  - `@EnvironmentObject`: `SessionStore` 1개만 허용
- 상태 공유 최소화 원칙:
  - Home와 StoreDetail는 `CartStore`를 공유하지만, ViewState는 공유하지 않는다.
  - Order와 Checkout은 `orderCode`로만 연결하고 상태 객체는 재사용하지 않는다.
  - Community와 Home는 서로의 presenter를 절대 참조하지 않는다.

## 10. 네비게이션 전략

- 하단 탭 구조: `Home / Order / Community / Profile` 4탭 + 중앙 플로팅 CTA는 shell overlay로 둔다.
- 탭별 `NavigationStack`을 분리한다. 각 탭은 자기 `Router.path`를 가진다.
- Router와 SwiftUI 연결:
  - Router가 `path`, `sheet`, `fullScreen`을 publish
  - Root Feature View가 `navigationDestination`, `sheet`, `fullScreenCover`를 바인딩
- 분리 기준:
  - `push`: 상세 drill-down, 주문 상세, 커뮤니티 상세, 채팅방
  - `sheet`: 필터, 검색, 리뷰 작성, 퀵 액션, 이미지 선택
  - `fullScreenCover`: 로그인, 결제 웹뷰, 온보딩
- 딥링크 처리 흐름:
  - `AppDeeplinkParser -> AppCoordinator -> pending route 저장 -> 로그인 상태 확인 -> 해당 Feature Builder 호출`
  - 지원 우선순위: 배너 웹뷰, 가게 상세, 주문 상세, 채팅방
- 로그인 게이트:
  - 서버 연동 화면은 로그인 이후 진입이 기본
  - 비로그인 상태에서 딥링크 유입 시 `pendingDeepLink` 저장 후 Auth success 시 재실행
  - 비로그인 홈 탐색은 `추가 서버 구현 필요` 또는 별도 public token 정책 `서버 협의 필요`
- 주문 완료 후 이동:
  - `Checkout -> Payment 검증 성공 -> OrderCompleteView -> selectedTab = .order -> OrderRouter.push(orderCode)`

## 11. 네트워크 레이어 최종안

- APIClient 구조:
  - `Endpoint<ResponseDTO>`
  - `RequestBuilder`
  - `APIClient.execute`
  - `TokenRefreshCoordinator(actor)`
- Endpoint 설계 필드:
  - `path`, `method`, `query`, `headers`, `body`, `timeout`, `authorizationPolicy`
- Authorization 정책:
  - `.none`
  - `.accessToken`
  - `.refreshToken`
  - `.fileAuthorized`
- 공통 헤더:
  - `SeSACKey`는 전 요청에 주입
  - `Authorization`은 access token이 필요한 요청에만 주입
  - `RefreshToken`은 refresh 요청에만 주입
- 중요한 판단:
  - Swagger security array는 OR 형태로 모델링되어 있지만 `/common` 설명상 SeSACKey는 항상 필요하다.
  - `Authorization`은 Swagger상 apiKey header라서 `Bearer` 접두사를 임의 확정하지 않는다. `raw token` 기본값으로 설계하고, 필요 시 formatter로 바꾼다.
- Refresh 흐름:
  1. 일반 요청이 419 반환
  2. `TokenRefreshCoordinator`가 single-flight로 `/v1/auth/refresh` 호출
  3. 성공 시 토큰 저장 후 원요청 1회 재시도
  4. 418/401이면 세션 초기화 후 로그인 게이트 이동
- status code 처리 규칙:
  - `400`: validation/business error
  - `401`: invalid auth
  - `403`: forbidden
  - `404`: resource not found
  - `409`: conflict
  - `418`: refresh expired -> 강제 로그아웃
  - `419`: access expired -> refresh 시도
  - `420`: invalid SeSACKey -> 환경설정 오류
  - `429`: rate limit
  - `444`: invalid endpoint/business reject
  - `445`: permission mismatch/business authorization error
  - `500`: server error
- `NetworkError`는 최소 다음 case를 가진다:
  - `invalidRequest`
  - `unauthorized`
  - `accessTokenExpired`
  - `refreshTokenExpired`
  - `forbidden`
  - `notFound(message)`
  - `conflict(message)`
  - `rateLimited`
  - `serviceKeyInvalid`
  - `businessAuthorization(message)`
  - `server(message)`
  - `decoding`
  - `transport`
- JSONDecoder/Encoder 설정:
  - `keyDecodingStrategy`는 전역 자동 변환보다 `useDefaultKeys + DTO별 CodingKeys`를 권장한다.
  - 이유: `store_id`, `id`, `createdAt`, `paid_at`, `is_picchelin`처럼 키 규칙이 섞여 있다.
  - date는 ISO8601 fractional seconds 파서를 쓴다.
- multipart upload 위치:
  - 공통 생성은 `Core/Network/MultipartFormDataBuilder`
  - 도메인별 field name은 Data/Remote에서 관리한다.
  - 현재 서버 field name:
    - 프로필 이미지: `profile`
    - 게시글/채팅/리뷰 파일: `files`
- Retry/Timeout 정책:
  - GET은 transport error에 한해 1회 재시도
  - POST/PUT/DELETE는 일반 재시도 금지
  - 단, 419 후 refresh 성공 시 원요청 1회 재시도 허용
  - 기본 timeout 15초, 업로드 60초, 결제 검증 30초
- 추가 중요 사항:
  - 현재 Swagger 접근 URL은 `http`다. 실제 API도 HTTP-only면 iOS ATS 예외가 필요하고, 프로덕션 출시 전 `HTTPS 전환은 서버 협의 필요`다.
  - 업로드 파일 조회도 인증 헤더가 필요하므로 기본 `AsyncImage`만으로는 충분하지 않다.

## 12. Swift Concurrency / Combine 사용 기준

- `async/await`로 처리:
  - 일반 API 호출
  - pull-to-refresh
  - 커서 페이지네이션
  - 주문 생성
  - 결제 검증
  - 프로필 수정/업로드
  - 리뷰 작성/업로드
  - 홈/커뮤니티/주문 초기 로드
- Combine을 제한적으로 사용하는 항목:
  - 검색 debounce
  - 앱 내부 간단 이벤트 스트림
  - 실시간 채팅 수신 브릿지
- 권장 패턴:
  - 일반 API: `Task { await presenter.load() }`
  - pull-to-refresh: `.refreshable { await presenter.refresh() }`
  - 페이지네이션: `CursorPager` + `loadNextIfNeeded(item:)`
  - 검색 debounce: `@Published rawQuery -> debounce(300ms) -> Task { await search(query) }`
  - 앱 이벤트: `NotificationCenter publisher`를 `AsyncStream`으로 감싸서 Presenter에서 소비
  - 채팅 수신:
    - Phase 1: `PollingChatRealtimeService`로 `GET /v1/chats/{room_id}?next=lastCreatedAt`
    - Phase 2: `SocketIOChatRealtimeService`
  - 푸시 반영: APNs/FCM 수신 후 `AppCoordinator`에서 딥링크 route로 변환
- 결론: HTTP는 Concurrency, 연속 스트림은 `AsyncStream 우선 / Combine 보조`가 최종 기준이다.

## 13. Swagger 반영 API 분석

- 전체 확인 결과: 15개 태그, 51개 path operation이 있다.

### Auth

- 존재: refresh 1개
- iOS 사용: 세션 복구, access token 재발급
- 상태: `즉시 가능`
- 특이점: `RefreshToken` header 사용

### User

- 존재: 이메일/카카오/애플 로그인, 회원가입, 로그아웃, 내 프로필 조회/수정, 프로필 이미지 업로드, 디바이스 토큰 업데이트, 유저 검색, 이메일 유효성 체크
- iOS 사용: Auth, Profile, Push token 등록
- 상태: `즉시 가능`
- 누락: 회원 탈퇴 API 없음 -> `추가 서버 구현 필요`

### Store / Menu / Search

- 존재: 위치 기반 가게 목록, 상세, 좋아요, 좋아요한 가게, 인기 가게, 가게 이름 검색, 인기 검색어, 유저 리뷰 목록
- iOS 사용: Home, StoreDetail, Profile
- 상태: `즉시 가능`
- 특이점:
  - 가게 목록은 `category/longitude/latitude/maxDistance/next/limit/order_by`
  - `order_by`는 `distance/orders/reviews`
  - 인기 검색어 제공
  - 가게 상세 응답에 `menu_list` 포함
- 누락:
  - 카테고리 enum endpoint 없음 -> `서버 협의 필요`
  - 메뉴 전용 검색/정렬 endpoint 없음 -> `클라이언트 선구현 가능(상세 내 local filter)`

### Order / Payment

- 존재: 주문 생성, 주문 내역 조회, 주문 상태 변경, 결제 검증, 결제 영수증 조회
- iOS 사용: Checkout, Order
- 상태: `즉시 가능`
- 특이점:
  - 주문 생성 후 `order_code`를 PortOne `merchant_uid`로 사용
  - 결제 검증 성공 후 주문 상태는 `PENDING_APPROVAL`
  - 주문 조회는 `결제 완료된 주문만` 반환
- 주의:
  - `PUT /v1/orders/{order_code}`는 주문자 계정 기준으로 상태 변경이 열려 있어 소비자 앱 UX와 맞지 않는다. 실제 매장 운영 플로우로 쓰려면 `서버 협의 필요`
  - 결제 취소/환불 endpoint 없음 -> `추가 서버 구현 필요`

### Community-Post / Community-Post-Comment

- 존재: 게시글 작성/수정/삭제, 상세, 위치 기반 목록, 검색, 좋아요, 내가 좋아요한 글, 유저 글, 댓글/대댓글 작성/수정/삭제
- iOS 사용: Community
- 상태: `즉시 가능`
- 특이점:
  - 피드는 `longitude/latitude/maxDistance/limit/next/order_by`
  - 정렬은 `createdAt/likes`
  - 게시글에 `store`가 optional로 연결됨
  - 댓글은 1 depth reply까지 지원
- 누락:
  - 거리순 정렬 endpoint 없음 -> `추가 서버 구현 필요`
  - 댓글 pagination 없음 -> `서버 협의 필요`

### Upload

- 존재:
  - 게시글 파일 업로드
  - 리뷰 이미지 업로드
  - 채팅 파일 업로드
  - 프로필 이미지 업로드
- iOS 사용: Community, Review, Chat, Profile
- 상태: `즉시 가능`
- 특이점:
  - 업로드 후 path 배열/문자열을 다시 create API body에 넣는 2단계 구조
  - 조회 시 인증 헤더 필요

### Chat

- 존재: 채팅방 생성/조회, 채팅방 목록, 채팅내역 조회, 메시지 전송, 파일 업로드
- iOS 사용: Chat, StoreDetail의 상담 진입
- 상태:
  - REST inbox/send/history: `즉시 가능`
  - 진짜 실시간 수신: `서버 협의 필요`
- 특이점:
  - 태그 설명에 Socket.IO room namespace가 명시됨
  - `GET /v1/chats/{room_id}?next=`는 과거 페이지가 아니라 `이 시각 이후의 새 메시지 조회`
  - 파일만 보내는 메시지는 Swagger상 불가능(`content` required) -> `서버 협의 필요`

### Pagination

- 존재:
  - Stores / Posts / Reviews / Videos: cursor 기반
  - Chat: timestamp 기반 incremental sync
- iOS 사용: Home, Community, Review, Chat
- 상태: `즉시 가능`
- 주의:
  - `next_cursor` 종료값이 `"0"` 또는 누락으로 섞여 있다.
  - `limit` 타입이 string/integer로 섞여 있다.
  - Orders, search APIs, chat room list는 pagination이 없다.

### Banner

- 존재: 메인 배너 목록
- iOS 사용: Home
- 상태: `즉시 가능`
- 주의: `payload.type/value` 예시는 `WEBVIEW`뿐이다. 추가 payload type은 `서버 협의 필요`

### Push

- 존재: 디바이스 토큰 업데이트, 푸시 전송 테스트
- iOS 사용: 토큰 등록
- 상태:
  - 토큰 등록: `즉시 가능`
  - 실제 서비스용 푸시 이벤트 설계: `서버 협의 필요`

### Video

- 존재: 비디오 목록, 좋아요, HLS 스트리밍 URL
- iOS 사용: 현재 5탭 범위 밖, Phase 3
- 상태: `즉시 가능`
- 판단: 별도 `VideoFeature`로 분리하는 것이 맞다.

### Admin / Log

- 존재: 가게/메뉴 등록/수정/업로드, 서버 요청 로그
- 소비자 iOS 앱 사용 여부: 없음
- 판단: 소비자 앱 범위에서 제외

### Swagger 방어 포인트

- `Authorization/SeSACKey` 모델링이 OpenAPI 의미상 OR지만 설명은 AND에 가깝다.
- `store_id`와 `id`, `menu_id`와 `id`가 응답마다 다르다.
- `ReceiptOrderResponseDTO`, `PaymentResponseDTO`의 required/property가 일부 불일치한다.
- 파일/배너/이미지 URL은 상대경로이며 인증이 필요하다.

## 14. Feature별 API 매핑

### Auth

- API: `/v1/users/login`, `/login/kakao`, `/login/apple`, `/join`, `/logout`, `/v1/auth/refresh`
- request/response: 로그인 요청 DTO -> `LoginDTO`, refresh -> `RefreshTokenResponseDTO`
- DTO 필요 여부: 필요
- 인증 필요 여부: 로그인/회원가입 제외
- 서버 지원 여부: `즉시 가능`
- 추가 작업: Kakao SDK, Apple Sign In client integration 필요

### Home

- API: `/v1/stores`, `/v1/stores/popular-stores`, `/v1/stores/search`, `/v1/stores/searches-popular`, `/v1/banners/main`, `/v1/stores/{store_id}/like`
- request/response: cursor page + summary DTO + banner DTO
- DTO 필요 여부: 필요
- 인증 필요 여부: 필요
- 서버 지원 여부: `즉시 가능`
- 추가 작업: 지역 선택은 reverse geocoding 기반 `클라이언트 선구현 가능`; 카테고리 raw value 정규화는 `서버 협의 필요`

### Community

- API: `/v1/posts/geolocation`, `/v1/posts/{id}`, `/v1/posts/search`, `/v1/posts/{id}/like`, `/v1/posts/{id}/comments`, `/v1/posts/files`, `/v1/posts`
- request/response: `PostSummaryPaginationResponseDTO`, `PostResponseDTO`, comment DTO, file DTO
- DTO 필요 여부: 필요
- 인증 필요 여부: 필요
- 서버 지원 여부: 읽기/좋아요/작성/댓글 `즉시 가능`
- 추가 작업: 거리순 정렬 `추가 서버 구현 필요`; 동영상 첨부 본격 재생은 인증 URL 정책상 `서버 협의 필요`

### StoreDetail

- API: `/v1/stores/{store_id}`, `/v1/stores/{store_id}/reviews`, `/reviews/reviews-ratings`, `/stores/{store_id}/like`, `/v1/chats`
- request/response: detail DTO, review list DTO, rating histogram DTO, like DTO
- DTO 필요 여부: 필요
- 인증 필요 여부: 필요
- 서버 지원 여부: `즉시 가능`
- 추가 작업: 메뉴 검색/탭은 `클라이언트 선구현 가능`; 인기메뉴 의미 확정은 `서버 협의 필요`

### Cart

- API: 직접 사용 없음
- request/response: 로컬 상태만 관리
- DTO 필요 여부: 없음
- 인증 필요 여부: 없음
- 서버 지원 여부: `클라이언트 선구현 가능`
- 추가 작업: `한 장바구니 = 한 store_id` 규칙을 강제

### Checkout

- API: `/v1/orders`, `/v1/payments/validation`, `/v1/payments/{order_code}`
- request/response: `OrderCreateRequestDTO`, `OrderCreateResponseDTO`, `ReceiptOrderResponseDTO`, `PaymentResponseDTO`
- DTO 필요 여부: 필요
- 인증 필요 여부: 필요
- 서버 지원 여부: `즉시 가능`
- 추가 작업: PG 설정값, 실패/취소 처리 규칙, WebView bridge는 `서버 협의 필요`

### Order

- API: `/v1/orders`, `/v1/payments/{order_code}`, `/v1/stores/{store_id}/reviews`, `/reviews/{review_id}`
- request/response: 주문 배열(inline), 영수증 DTO, 리뷰 DTO
- DTO 필요 여부: 필요
- 인증 필요 여부: 필요
- 서버 지원 여부: 조회/리뷰 `즉시 가능`
- 추가 작업: 주문 상태 변경 PUT은 소비자 앱에서 노출하지 않음. 매장용 상태 변경은 `서버 협의 필요`

### Profile

- API: `/v1/users/me/profile`, `/v1/users/profile/image`, `/v1/users/deviceToken`, `/v1/stores/likes/me`, `/v1/stores/reviews/users/{user_id}`, `/v1/users/logout`
- request/response: 프로필 DTO, image upload response, picked store cursor page, user review list
- DTO 필요 여부: 필요
- 인증 필요 여부: 필요
- 서버 지원 여부: `즉시 가능`
- 추가 작업: 회원 탈퇴 `추가 서버 구현 필요`

### Chat

- API: `/v1/chats`, `/v1/chats/{room_id}`, `/v1/chats/{room_id}/files`
- request/response: room list DTO, room DTO, chat list DTO, file DTO
- DTO 필요 여부: 필요
- 인증 필요 여부: 필요
- 서버 지원 여부: REST는 `즉시 가능`
- 추가 작업: Socket.IO event contract, file-only message, 긴 히스토리 backward pagination은 `서버 협의 필요`

## 15. DTO / Entity / Mapper 전략

- Swagger 응답 DTO를 View에 바로 쓰면 안 되는 이유:
  - 키 naming이 일관되지 않다(`store_id` vs `id`)
  - 상대경로 파일 URL을 절대 URL로 해석해야 한다
  - `"0"` cursor, missing field, optional/required mismatch가 있다
  - 날짜/거리/금액/상태 라벨은 View 친화적으로 다시 만들어야 한다
  - 게시글 파일은 확장자로 media type을 판별해야 한다
- DTO 위치: `Data/DTOs`
- Entity 위치: `Domain/Entities`
- Mapper 위치: `Data/Mappers`
- ViewState 생성 위치: `Feature Presenter`
- 권장 흐름: `ResponseDTO -> Domain Entity -> ViewState`
- 요청 DTO와 응답 DTO는 분리한다.
  - 이유: 서버 요청 키는 snake/camel이 섞여 있고, 응답과 재사용할 수 없다.
- 추가 정규화 규칙:
  - `next_cursor == "0"`이면 `nil`
  - `store_id/id`, `menu_id/id`, `review.id/review_id`는 Entity에서 통일
  - 파일 path는 `AuthorizedFileURLResolver`로 절대 URL 변환
  - `MediaAsset`는 확장자로 `image/video/gif/pdf` 판단

## 16. 디자인 시스템 / 공통 컴포넌트 전략

- 디자인 방향:
  - 배경은 warm white
  - 브랜드는 sage/mint 계열
  - 강조는 warm yellow(좋아요/별점)
  - 무드는 부드럽지만 정보 밀도는 낮추지 않는다
- 토큰:
  - Color: `Sage50`, `Sage100`, `Sage300`, `Sage500`, `Olive700`, `WarmYellow`, `Ink900`, `Gray100~600`
  - Typography: `Pretendard + SF Pro fallback`, Title 28/22, CardTitle 18, Body 15, Caption 12
  - Spacing: 4/8/12/16/20/24/32
  - Radius: 기본 카드 8, 칩 16~18, 플로팅 CTA 28+, hero 예외 16
  - Shadow: y=4 blur=12 alpha=0.08 수준의 얕은 그림자
- 컴포넌트 배치:
  - `PrimaryButton`: sage fill, 흰 텍스트, 52pt
  - `SecondaryButton`: white fill + sage stroke
  - `TagChip`: 카테고리/거리/정렬
  - `StoreCard`: 상단 이미지, heart overlay, hashTag, 거리/리뷰/주문수
  - `CommunityCard`: 작성자, 미디어 mosaic, 좋아요/거리, optional store snippet
  - `SectionHeader`: 좌측 타이틀, 우측 정렬/더보기 액션
  - `EmptyState`: 아이콘 + 짧은 액션 문구
  - `Loading/Skeleton`: 카드형 리스트 전용 skeleton
  - `AsyncImage Wrapper`: `AuthorizedAsyncImage`로 구현
  - `Toast/Snackbar`: like, 업로드, 결제 실패, 네트워크 오류에 사용
- 중요한 구현 판단:
  - 배너/가게/메뉴/프로필/게시글 이미지가 인증 헤더를 요구하므로 `SwiftUI.AsyncImage` 기본 구현은 메인 전략이 아니다.
  - `StoreCard`, `CommunityCard`, `OrderStatusTimelineView`는 DesignSystem이 아니라 Shared의 product-specific composite다.

## 17. 구현 우선순위 / Phase 제안

### Phase 1: MVP

- Auth(카카오/애플, 세션 복구)
- Home(가게 목록, 인기 가게, 배너, 찜)
- StoreDetail(메뉴, 리뷰 읽기, 길찾기)
- Cart(로컬)
- Checkout(주문 생성, PG 브릿지, 영수증 검증)
- Order(현재 주문/이전 주문, 상태 타임라인)
- Profile basic(내 정보, 찜 가게, 로그아웃)
- Community read-only + like

### Phase 2: 서비스 확장

- Community 작성/수정/댓글
- 리뷰 작성/수정/삭제
- Profile 수정/프로필 이미지
- Chat REST + polling
- banner payload 라우팅 고도화
- push token 등록과 foreground 반영

### Phase 3: 고도화

- Socket.IO 실시간 채팅
- push 기반 주문 상태 갱신
- Video/HLS 탭
- order history pagination
- seller/admin 별도 앱 또는 운영툴 분리

### 지금 바로 구현 가능한 기능

- 홈 탐색, 가게 상세, 찜, 주문 생성/검증, 주문 조회, 리뷰, 프로필, 커뮤니티, 업로드, 채팅 REST

### 서버 협의 후 구현할 기능

- 비로그인 탐색
- 매장 측 주문 상태 변경 주체
- Socket.IO event contract
- payment failure/cancel/refund 정책
- category enum contract
- banner payload type 확장
- HTTPS 전환

### 나중에 붙일 기능

- HLS 비디오 피드
- 커뮤니티 동영상 전용 스트리밍
- push inbox
- 주문 취소/환불
- 회원 탈퇴

## 18. 파일 비대화 방지 규칙

```text
- AppScreens 같은 거대 루트 파일 금지
- PikkoApp.swift는 app entry와 container 생성만 둔다
- 모든 Feature는 Builder / View / Presenter / Interactor / Router / Entity 분리를 유지한다
- View가 200줄을 넘으면 Sections/로 분리한다
- Presenter가 250줄을 넘으면 Load, Action, Mapper extension으로 쪼갠다
- Router에 비즈니스 로직 금지
- Presenter에 네트워크 구현 상세 금지
- Interactor에 화면 전용 표현 로직 금지
- Shared UI는 2개 이상 Feature에서 재사용될 때만 올린다
- DTO는 Data 밖으로 내보내지 않는다
- cross-feature import 대신 builder closure/factory를 사용한다
- 한 PR은 가능하면 한 Feature + 한 shared component까지만 건드린다
- AI 협업 시 수정 단위를 Presenter 1개 + View Section 1개 + Interactor 1개로 좁힌다
```

## 19. 포트폴리오 설명 포인트

- “이전 TCA 프로젝트에서 루트 조립 파일이 비대해진 경험이 있어서, 이번에는 VIPER + Builder로 조립 책임을 feature별로 분산했습니다.”
- “SwiftUI를 선택한 이유는 감성형 카드 UI를 빠르게 구현하면서도 NavigationStack, refreshable, sticky CTA 같은 패턴을 자연스럽게 가져가기 위해서입니다.”
- “DI 프레임워크 대신 수동 DI를 쓴 이유는 객체 생성 경로를 코드에 명시적으로 남기고, 테스트와 AI 수정 범위를 줄이기 위해서입니다.”
- “HTTP는 URLSession + async/await로 직접 설계해서 토큰 재발급, multipart, 비표준 상태 코드 매핑까지 설명 가능한 구조로 만들었습니다.”
- “Builder 중심 조립을 택한 이유는 App 루트에서 모든 화면을 조립하지 않게 만들고, Feature 단위로 독립적인 수정과 테스트가 가능하게 하기 위해서입니다.”
- “이 구조는 화면 추가가 생겨도 기존 루트 파일을 키우지 않고 Builder 하나만 추가하면 되기 때문에 협업과 유지보수에 유리합니다.”

## 20. 최종 추천안 요약

- 최종 기술 스택: `SwiftUI`, `VIPER`, `Swift Concurrency`, `URLSession`, `Keychain`, `CoreLocation`, `AuthenticationServices`, `Kakao SDK`, `WKWebView bridge`
- 최종 아키텍처: `Layered + Feature-based VIPER`
- 최종 DI 방식: `AppDIContainer + Feature Builder + init 주입`
- 최종 상태 관리 방식: `SessionStore 최소 전역 + Feature Presenter ViewState + View local state`
- 최종 네트워크 방식: `URLSession APIClient + SeSACKey 주입 + raw token header + 419 single-flight refresh + multipart builder`
- 지금 바로 시작할 폴더 구조: `App / Core / Domain / Data / DesignSystem / Shared / Features / Tests`
- 가장 먼저 구현할 모듈 순서:
  1. Auth
  2. Home
  3. StoreDetail
  4. Cart
  5. Checkout
  6. Order
  7. Profile
  8. Community
  9. Chat

---

## 참고 소스

- [Swagger](http://pickup.sesac.kr:42678/api-docs/9POW2XC7H5VZP9N1/)
- [Main View.png](../도봉3기%20LSLP%20픽업/Main%20View.png)
- [Community View.png](../도봉3기%20LSLP%20픽업/Community%20View.png)
- [Order View.png](../도봉3기%20LSLP%20픽업/Order%20View.png)
- [Detail View_Timeout.png](../도봉3기%20LSLP%20픽업/Detail%20View_Timeout.png)
