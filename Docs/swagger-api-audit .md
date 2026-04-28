# Swagger API Audit

## 1. 기준 정보
- Swagger UI URL: `http://pickup.sesac.kr:42678/api-docs/9POW2XC7H5VZP9N1/#/`
- API Base URL: `http://pickup.sesac.kr:42678`
- iOS baseURL 주의: Swagger UI URL을 API baseURL로 쓰지 않는다. `paths` 값만 API Base URL 뒤에 붙인다.
- 명세 추출 기준: `swagger-ui-init.js`의 `options.swaggerDoc` inline OpenAPI 3.0 명세
- 추출/검토 일자: 2026-04-28 KST
- 추출 결과: 15 tags, 51 paths, 63 operations

## 2. 공통 헤더/인증 정책
- 모든 API 요청은 `SeSACKey` 헤더가 필요하다.
- Authorization 필요 API는 `Authorization` 헤더에 저장된 accessToken을 그대로 넣는다.
- `GET /v1/auth/refresh`는 `Authorization` + `SeSACKey` + `RefreshToken` 헤더가 모두 필요하다.
- 파일 조회 URL(`/data/...`)은 `AuthorizedImageLoader`/`AuthorizedFileURLResolver` 경로를 통해 `Authorization` + `SeSACKey`를 붙여 로드한다.
- 419 응답은 refresh token으로 재발급 후 원 요청을 1회 재시도한다.
- refresh 실패 또는 401/403/418 계열 인증 실패는 세션 무효화 후 로그인 흐름으로 이동한다.
- 공통 에러 코드: 401 accessToken/refreshToken 유효하지 않음, 403 user_id 조회 불가 또는 권한 문제, 418 refreshToken 만료, 419 accessToken 만료, 420 SeSACKey 유효하지 않음, 429 과호출, 444 비정상 API 호출, 500 서버 에러.

## 3. 태그별 API 목록
태그: 공통적용 사항, Log, Auth, User, Store, Community-Post, Community-Post-Comment, Chat, Order, Payment, Review, Banner, Push, Video, Admin

| Tag | API |
| --- | --- |
| 공통적용 사항 | `GET /common` |
| Log | `GET /v1/log` |
| Auth | `GET /v1/auth/refresh` |
| User | `POST /v1/users/validation/email`, `POST /v1/users/join`, `POST /v1/users/login`, `POST /v1/users/login/kakao`, `POST /v1/users/login/apple`, `POST /v1/users/logout`, `PUT /v1/users/deviceToken`, `GET /v1/users/me/profile`, `PUT /v1/users/me/profile`, `POST /v1/users/profile/image`, `GET /v1/users/search` |
| Store | `GET /v1/stores`, `GET /v1/stores/{store_id}`, `POST /v1/stores/{store_id}/like`, `GET /v1/stores/search`, `GET /v1/stores/popular-stores`, `GET /v1/stores/searches-popular`, `GET /v1/stores/likes/me`, `GET /v1/stores/reviews/users/{user_id}` |
| Community-Post | `POST /v1/posts/files`, `POST /v1/posts`, `GET /v1/posts/geolocation`, `GET /v1/posts/search`, `GET /v1/posts/{post_id}`, `PUT /v1/posts/{post_id}`, `DELETE /v1/posts/{post_id}`, `POST /v1/posts/{post_id}/like`, `GET /v1/posts/users/{user_id}`, `GET /v1/posts/likes/me` |
| Community-Post-Comment | `POST /v1/posts/{post_id}/comments`, `PUT /v1/posts/{post_id}/comments/{comment_id}`, `DELETE /v1/posts/{post_id}/comments/{comment_id}` |
| Chat | `POST /v1/chats`, `GET /v1/chats`, `POST /v1/chats/{room_id}`, `GET /v1/chats/{room_id}`, `POST /v1/chats/{room_id}/files` |
| Order | `POST /v1/orders`, `GET /v1/orders`, `PUT /v1/orders/{order_code}` |
| Payment | `POST /v1/payments/validation`, `GET /v1/payments/{order_code}` |
| Review | `POST /v1/stores/{store_id}/reviews/files`, `POST /v1/stores/{store_id}/reviews`, `GET /v1/stores/{store_id}/reviews`, `GET /v1/stores/{store_id}/reviews/{review_id}`, `PUT /v1/stores/{store_id}/reviews/{review_id}`, `DELETE /v1/stores/{store_id}/reviews/{review_id}`, `GET /v1/stores/{store_id}/reviews/reviews-ratings` |
| Banner | `GET /v1/banners/main` |
| Push | `POST /v1/notifications/push` |
| Video | `GET /v1/videos`, `GET /v1/videos/{video_id}/stream`, `POST /v1/videos/{video_id}/like` |
| Admin | `POST /v1/stores/files`, `POST /v1/stores`, `PUT /v1/stores/{store_id}`, `POST /v1/menus/image`, `POST /v1/menus/stores/{store_id}`, `PUT /v1/menus/{menu_id}` |

## 4. API별 구현 상태 표
| Tag | Method | Path | Summary | Auth 필요 여부 | Request DTO/Parameters | Response DTO | iOS 구현 파일 | 구현 상태 | 비고 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 공통적용 사항 | GET | `/common` | 공통사항 정의 | SeSACKey | - | Empty | - | 앱 범위 제외 | 문서/공통 정책 확인용 |
| Log | GET | `/v1/log` | SeSACKey별 서버요청로그 조회 | SeSACKey | - | `LogListResponseDTO` | - | 후순위 | 개발자 진단용 |
| Auth | GET | `/v1/auth/refresh` | 리프레시 토큰 | Authorization+SeSACKey+RefreshToken | header `RefreshToken` | `RefreshTokenResponseDTO` | `Core/Network/TokenRefreshCoordinator.swift` | 구현 완료 | single-flight refresh |
| User | POST | `/v1/users/validation/email` | 이메일 유효성 체크 | SeSACKey | `email` | `{message}` | `Data/Remote/AuthRemoteDataSource.swift`, `Features/Auth/AuthPresenter.swift` | 구현 완료 | 회원가입 UI에서 호출 |
| User | POST | `/v1/users/join` | 회원가입 | SeSACKey | `email,password,nick,phoneNum,deviceToken` | `JoinResponseDTO` | `Data/Remote/AuthRemoteDataSource.swift` | 구현 완료 | 토큰/세션 저장 |
| User | POST | `/v1/users/login` | 이메일 로그인 | SeSACKey | `email,password,deviceToken` | `LoginDTO` | `Data/Remote/AuthRemoteDataSource.swift` | 구현 완료 | 토큰/사용자 정보 저장 |
| User | POST | `/v1/users/login/kakao` | 카카오 로그인 | SeSACKey | `oauthToken,deviceToken` | `LoginDTO` | `Core/Platform/Auth/KakaoLoginService.swift`, `Data/Remote/AuthRemoteDataSource.swift` | 구현 완료 | Google endpoint 없음 |
| User | POST | `/v1/users/login/apple` | 애플 로그인 | SeSACKey | `idToken,deviceToken` | `LoginDTO` | `Core/Platform/Auth/AppleSignInService.swift`, `Data/Remote/AuthRemoteDataSource.swift` | 구현 완료 | - |
| User | POST | `/v1/users/logout` | 로그아웃 | Authorization+SeSACKey | - | Empty | `Data/Remote/AuthRemoteDataSource.swift`, `App/State/SessionStore.swift` | 구현 완료 | 실패해도 로컬 세션 정리 |
| User | PUT | `/v1/users/deviceToken` | 디바이스 토큰 업데이트 | Authorization+SeSACKey | `deviceToken` | Empty | `AuthRemoteDataSource.swift`, `FeatureBuilderFactory.swift` | 구현 완료 | push 등록 흐름에서 호출 가능 |
| User | GET | `/v1/users/me/profile` | 내 프로필 조회 | Authorization+SeSACKey | - | `MyInfoResponseDTO` | `SessionRestorer.swift`, `AuthRemoteDataSource.swift` | 구현 완료 | optional field 안전 decoding |
| User | PUT | `/v1/users/me/profile` | 내 프로필 수정 | Authorization+SeSACKey | `nick,phoneNum,profileImage` | `MyInfoResponseDTO` | `ProfileInteractor.swift`, `AuthRemoteDataSource.swift` | 구현 완료 | 프로필 화면 연결 |
| User | POST | `/v1/users/profile/image` | 내 프로필 이미지 업로드 | Authorization+SeSACKey | multipart `profile` | `{profileImage}` | `ProfilePresenter.swift`, `AuthRemoteDataSource.swift` | 구현 완료 | field name `profile` |
| User | GET | `/v1/users/search` | 유저 검색 | Authorization+SeSACKey | query `nick` | `UserInfoListResponseDTO` | `AuthRepository.swift`, `AuthRemoteDataSource.swift` | 일부 구현 | 전용 화면 없음 |
| Banner | GET | `/v1/banners/main` | 배너 목록 조회 | Authorization+SeSACKey | - | `BannerListResponseDTO` | `BannerRemoteDataSource.swift`, `BannerMapper.swift`, `HomeInteractor 2.swift` | 구현 완료 | WEBVIEW payload 웹뷰 연결 |
| Store | GET | `/v1/stores` | 위치 기반 주변 가게 목록 | Authorization+SeSACKey | `category,longitude,latitude,maxDistance,next,limit,order_by` | `StoreSummaryListResponseDTO` | `StoreRemoteDataSource.swift`, `HomeInteractor 2.swift` | 구현 완료 | `distance/orders/reviews` 매핑 |
| Store | GET | `/v1/stores/{store_id}` | 가게 상세 | Authorization+SeSACKey | path `store_id` | `StoreDetailResponseDTO` | `StoreRemoteDataSource.swift`, `StoreDetailInteractor.swift` | 구현 완료 | `menu_list` 매핑 |
| Store | POST | `/v1/stores/{store_id}/like` | 가게 좋아요/취소 | Authorization+SeSACKey | path `store_id`, body `like_status` | `LikeStoreResponseDTO` | `StoreRemoteDataSource.swift` | 구현 완료 | optimistic update |
| Store | GET | `/v1/stores/search` | 가게 이름 검색 | Authorization+SeSACKey | query `name` | `StoreSearchListResponseDTO` | `StoreRemoteDataSource.swift` | 일부 구현 | 검색 화면 연결 제한 |
| Store | GET | `/v1/stores/popular-stores` | 인기 가게 | Authorization+SeSACKey | query `category` | `[StoreSummaryDTO]` | `StoreRemoteDataSource.swift`, `HomeInteractor 2.swift` | 구현 완료 | - |
| Store | GET | `/v1/stores/searches-popular` | 인기 검색어 | Authorization+SeSACKey | - | `{data}` | `StoreRemoteDataSource.swift`, `HomeInteractor 2.swift` | 구현 완료 | - |
| Store | GET | `/v1/stores/likes/me` | 내가 좋아요한 가게 | Authorization+SeSACKey | `category,next,limit` | `StoreSummaryListResponseDTO` | `StoreRemoteDataSource.swift` | 일부 구현 | 전용 목록 화면 제한 |
| Store | GET | `/v1/stores/reviews/users/{user_id}` | 유저 리뷰 목록 | Authorization+SeSACKey | `user_id,category,next,limit` | `UserReviewListResponseDTO` | `ReviewRemoteDataSource.swift`, `ProfileRootView.swift` | 구현 완료 | Swagger tag는 Store |
| Community-Post | POST | `/v1/posts/files` | 게시글 파일 업로드 | Authorization+SeSACKey | multipart `files` | `FileResponseDTO` | `CommunityRemoteDataSource.swift`, `CommunityComposerInteractor.swift` | 구현 완료 | 글 작성 전 업로드 |
| Community-Post | POST | `/v1/posts` | 게시글 작성 | Authorization+SeSACKey | `category,title,content,latitude,longitude,store_id?,files?` | `PostResponseDTO` | `CommunityRemoteDataSource.swift` | 구현 완료 | - |
| Community-Post | GET | `/v1/posts/geolocation` | 위치 기반 게시글 | Authorization+SeSACKey | `category,longitude,latitude,maxDistance,limit,next,order_by` | `PostSummaryPaginationResponseDTO` | `CommunityRemoteDataSource.swift`, `CommunityInteractor.swift` | 구현 완료 | `createdAt/likes`만 사용 |
| Community-Post | GET | `/v1/posts/search` | 게시글 제목 검색 | Authorization+SeSACKey | query `title` | `PostSummaryListResponseDTO` | `CommunityRemoteDataSource.swift` | 구현 완료 | - |
| Community-Post | GET | `/v1/posts/{post_id}` | 게시글 상세 | Authorization+SeSACKey | path `post_id` | `PostResponseDTO` | `CommunityDetailInteractor.swift` | 구현 완료 | comments 포함 |
| Community-Post | PUT | `/v1/posts/{post_id}` | 게시글 수정 | Authorization+SeSACKey | `PostUpdateRequestDTO` | `PostResponseDTO` | `CommunityComposerInteractor.swift` | 구현 완료 | - |
| Community-Post | DELETE | `/v1/posts/{post_id}` | 게시글 삭제 | Authorization+SeSACKey | path `post_id` | Empty | `CommunityDetailInteractor.swift` | 구현 완료 | 소유자 권한 필요 |
| Community-Post | POST | `/v1/posts/{post_id}/like` | 게시글 좋아요/취소 | Authorization+SeSACKey | body `like_status` | `PostLikeResponseDTO` | `CommunityRemoteDataSource.swift` | 구현 완료 | - |
| Community-Post | GET | `/v1/posts/users/{user_id}` | 유저 작성 게시글 | Authorization+SeSACKey | `user_id,category,limit,next` | `PostSummaryPaginationResponseDTO` | `CommunityRemoteDataSource.swift`, `ProfileRootView.swift` | 구현 완료 | 프로필 목록 |
| Community-Post | GET | `/v1/posts/likes/me` | 내가 좋아요한 게시글 | Authorization+SeSACKey | `category,next,limit` | `PostSummaryPaginationResponseDTO` | `CommunityRemoteDataSource.swift`, `ProfileRootView.swift` | 구현 완료 | - |
| Community-Post-Comment | POST | `/v1/posts/{post_id}/comments` | 댓글/대댓글 작성 | Authorization+SeSACKey | `content,parent_comment_id?` | `CommentResponseDTO` | `CommunityDetailInteractor.swift` | 구현 완료 | 1-depth 정책 |
| Community-Post-Comment | PUT | `/v1/posts/{post_id}/comments/{comment_id}` | 댓글 수정 | Authorization+SeSACKey | `content` | `CommentResponseDTO` | `CommunityDetailInteractor.swift` | 구현 완료 | - |
| Community-Post-Comment | DELETE | `/v1/posts/{post_id}/comments/{comment_id}` | 댓글 삭제 | Authorization+SeSACKey | path ids | Empty | `CommunityDetailInteractor.swift` | 구현 완료 | - |
| Chat | POST | `/v1/chats` | 채팅방 생성/조회 | Authorization+SeSACKey | `opponent_id` | `ChatRoomResponseDTO` | `ChatInteractor.swift` | 구현 완료 | 가게 owner 대상 문의 |
| Chat | GET | `/v1/chats` | 채팅방 목록 | Authorization+SeSACKey | - | `ChatRoomListResponseDTO` | `ChatInteractor.swift` | 구현 완료 | - |
| Chat | POST | `/v1/chats/{room_id}` | 채팅 보내기 | Authorization+SeSACKey | `content,files` | `ChatResponseDTO` | `ChatInteractor.swift` | 구현 완료 | 텍스트 UI 연결 |
| Chat | GET | `/v1/chats/{room_id}` | 채팅 내역 | Authorization+SeSACKey | `next` | `ChatListResponseDTO` | `ChatInteractor.swift` | 구현 완료 | next UI pagination은 제한 |
| Chat | POST | `/v1/chats/{room_id}/files` | 채팅 파일 업로드 | Authorization+SeSACKey | multipart `files` | `ChatFileResponseDTO` | `ChatInteractor.swift` | 일부 구현 | data layer만 추가, 첨부 UI 없음 |
| Order | POST | `/v1/orders` | 주문 생성 | Authorization+SeSACKey | `store_id,order_menu_list,total_price` | `OrderCreateResponseDTO` | `OrderRemoteDataSource.swift`, `CheckoutInteractor.swift` | 구현 완료 | `order_code`를 merchant_uid로 사용 |
| Order | GET | `/v1/orders` | 주문 내역 | Authorization+SeSACKey | - | `{data}` | `OrderRemoteDataSource.swift`, `OrderPresenter.swift` | 구현 완료 | Swagger상 query 없음 |
| Order | PUT | `/v1/orders/{order_code}` | 주문 상태 변경 | Authorization+SeSACKey | `nextStatus` | Empty | `OrderRemoteDataSource.swift` | 서버 협의 필요 | 사용자 취소로 사용 금지 |
| Payment | POST | `/v1/payments/validation` | 결제 영수증 검증 | Authorization+SeSACKey | `imp_uid` | `ReceiptOrderResponseDTO` | `OrderRemoteDataSource.swift`, `CheckoutPresenter.swift` | 일부 구현 | PortOne 실결제 콜백 검증은 추가 확인 필요 |
| Payment | GET | `/v1/payments/{order_code}` | 결제 영수증 조회 | Authorization+SeSACKey | path `order_code` | `PaymentResponseDTO` | `OrderRemoteDataSource.swift` | 구현 완료 | `paidAt`/`paid_at` dual decode |
| Review | POST | `/v1/stores/{store_id}/reviews/files` | 리뷰 파일 업로드 | Authorization+SeSACKey | multipart `files` | `ReviewImageResponseDTO` | `ReviewRemoteDataSource.swift`, `ProfileRootView.swift` | 구현 완료 | - |
| Review | POST | `/v1/stores/{store_id}/reviews` | 리뷰 작성 | Authorization+SeSACKey | `content,rating,order_code,review_image_urls?` | `UserReviewResponseDTO` | `ReviewRepositoryImpl.swift`, `ProfileRootView.swift` | 구현 완료 | 주문 기반 작성 |
| Review | GET | `/v1/stores/{store_id}/reviews` | 리뷰 목록 | Authorization+SeSACKey | `next,limit,order_by` | `ReviewListResponseDTO` | `ReviewRemoteDataSource.swift`, `StoreDetailInteractor.swift` | 구현 완료 | `latest/rating_high/rating_low` |
| Review | GET | `/v1/stores/{store_id}/reviews/{review_id}` | 리뷰 상세 | Authorization+SeSACKey | path ids | `UserReviewResponseDTO` | `ReviewRepositoryImpl.swift`, `ProfileRootView.swift` | 구현 완료 | - |
| Review | PUT | `/v1/stores/{store_id}/reviews/{review_id}` | 리뷰 수정 | Authorization+SeSACKey | `content,rating,review_image_urls` | `UserReviewResponseDTO` | `ReviewRepositoryImpl.swift`, `ProfileRootView.swift` | 구현 완료 | - |
| Review | DELETE | `/v1/stores/{store_id}/reviews/{review_id}` | 리뷰 삭제 | Authorization+SeSACKey | path ids | Empty | `ReviewRepositoryImpl.swift`, `ProfileRootView.swift` | 구현 완료 | - |
| Review | GET | `/v1/stores/{store_id}/reviews/reviews-ratings` | 별점별 리뷰 개수 | Authorization+SeSACKey | path `store_id` | `ReviewRatingListResponseDTO` | `ReviewRemoteDataSource.swift`, `StoreDetailInteractor.swift` | 구현 완료 | - |
| Push | POST | `/v1/notifications/push` | 푸시알림 전송 테스트 | Authorization+SeSACKey | `user_id,title,subtitle,body` | Empty | - | 후순위 | 일반 사용자 앱 직접 호출 제외 |
| Video | GET | `/v1/videos` | 비디오 목록 | Authorization+SeSACKey | `next,limit` | `VideoListResponseDTO` | - | 후순위 | Video surface 없음 |
| Video | GET | `/v1/videos/{video_id}/stream` | 스트리밍 URL | Authorization+SeSACKey | path `video_id` | `StreamUrlResponseDTO` | - | 후순위 | HLS/AVPlayer 추후 |
| Video | POST | `/v1/videos/{video_id}/like` | 비디오 좋아요/취소 | Authorization+SeSACKey | `like_status` | `{like_status}` | - | 후순위 | Video surface 없음 |
| Admin | POST | `/v1/stores/files` | 가게 이미지 업로드 | Authorization+SeSACKey | multipart `files` | `StoreFileResponseDTO` | - | 관리자/콘텐츠 등록용 | 앱 구현 제외 |
| Admin | POST | `/v1/stores` | 가게 등록 | Authorization+SeSACKey | `StoreCreateRequestDTO` | `StoreDetailResponseDTO` | - | 관리자/콘텐츠 등록용 | 앱 구현 제외 |
| Admin | PUT | `/v1/stores/{store_id}` | 가게 수정 | Authorization+SeSACKey | `StoreCreateRequestDTO` | `StoreDetailResponseDTO` | - | 관리자/콘텐츠 등록용 | 앱 구현 제외 |
| Admin | POST | `/v1/menus/image` | 메뉴 이미지 업로드 | Authorization+SeSACKey | multipart `menu_image` | `MenuFileResponseDTO` | - | 관리자/콘텐츠 등록용 | 앱 구현 제외 |
| Admin | POST | `/v1/menus/stores/{store_id}` | 메뉴 등록 | Authorization+SeSACKey | `MenuCreateRequestDTO` | `MenuResponseDTO` | - | 관리자/콘텐츠 등록용 | 앱 구현 제외 |
| Admin | PUT | `/v1/menus/{menu_id}` | 메뉴 수정 | Authorization+SeSACKey | `MenuUpdateRequestDTO` | `MenuResponseDTO` | - | 관리자/콘텐츠 등록용 | 앱 구현 제외 |

## 5. Swagger와 기존 문서 불일치 수정 내역
- 실제 operation 수는 63개, path 수는 51개로 재확인했다.
- `GET /v1/stores/reviews/users/{user_id}`는 Swagger tag가 Review가 아니라 Store로 내려온다. 문서 표에 Store로 정리했다.
- Chat REST는 현재 코드에 구현되어 있으므로 기존 문서의 미구현 표기를 수정했다.
- Community 파일 업로드, 게시글 삭제, 유저 작성/좋아요 게시글 조회는 현재 구현되어 있으므로 기존 미구현 표기를 수정했다.
- Review 파일 업로드/작성/상세/수정/삭제/유저 리뷰 조회는 현재 구현되어 있으므로 기존 미구현 표기를 수정했다.
- `PUT /v1/orders/{order_code}`는 사용자 취소가 아니라 주문 상태 변경 API다. 취소 API로 쓰지 않도록 문서와 코드 모두 수정했다.

## 6. Swagger에는 있으나 기존 문서에 없던 API
- Payment: `POST /v1/payments/validation`, `GET /v1/payments/{order_code}`
- Push: `POST /v1/notifications/push`
- Video: `GET /v1/videos`, `GET /v1/videos/{video_id}/stream`, `POST /v1/videos/{video_id}/like`
- Admin: stores/menus 콘텐츠 등록용 6개 API
- 위 항목은 이번 재검증 문서에 모두 포함했다.

## 7. 기존 iOS 구현과 Swagger 불일치 내역
- 주문 취소: Swagger에 취소 endpoint가 없는데 기존 repository가 `PUT /v1/orders/{order_code}` + `nextStatus=CANCELLED`를 호출했다. 이번 작업에서 호출 차단 및 취소 버튼 비노출 정책으로 수정했다.
- Community 가까운순: Swagger `order_by`는 `createdAt`, `likes`만 허용한다. `distance`를 보내지 않는다.
- Store 정렬: Swagger `order_by`는 `distance`, `orders`, `reviews` 기준이다. UI 문구는 이 세 값에 맞춰 매핑한다.
- Google 로그인: Swagger에 Google endpoint가 없다. 현재 Google backend login은 unsupported stub로 남겨야 하며 서버 API를 상상해 호출하지 않는다.
- 파일/웹뷰 상대경로: `/data/...`, `/event-application` 등은 baseURL origin과 결합하고 인증 헤더가 필요한 경로에는 RequestBuilder를 통과한다.

## 8. 이번 작업에서 수정/추가 구현한 항목
- `Domain/Entities/OrderSummary.swift`: 사용자 주문 취소가 노출되지 않도록 `isCancellable`을 false로 고정했다.
- `Data/Repositories/OrderRepositoryImpl.swift`: 주문 취소 요청이 `PUT /v1/orders/{order_code}`로 나가지 않도록 차단하고 서버 협의 필요 메시지를 반환한다.
- `Features/Chat/ChatInteractor.swift`: `POST /v1/chats/{room_id}/files`용 `ChatFileResponseDTO`, `ChatUploadFile`, remote/repository upload 메서드를 추가했다.
- `Docs/swagger-api-audit .md`: 실제 Swagger 기준으로 12개 섹션 구조와 63개 API 상태 표를 갱신했다.

## 9. 앱 범위 제외/후순위 항목
- `GET /common`: 공통 정책 문서/점검용
- `GET /v1/log`: 개발자 진단용
- `POST /v1/notifications/push`: 푸시 테스트/관리성 API
- Video 3개 API: 현재 앱에 Video 화면 없음
- Admin 6개 API: 컨텐츠 등록용 라우터로 일반 사용자 앱 구현 제외
- Socket.IO 실시간 채팅: REST 우선 구현, 실시간은 후순위
- Chat 파일 첨부 UI: data layer만 추가, 화면 연결은 후순위

## 10. 서버 협의 필요 항목
- 주문 취소 API가 Swagger에 없다. `PUT /v1/orders/{order_code}`를 취소로 오용하지 않는다.
- Community 가까운순 정렬용 `order_by=distance`가 없다. 기본 위치 기반 결과로 처리하거나 서버에 정렬 옵션 추가를 협의한다.
- Payment validation은 PortOne 완료 콜백의 `imp_uid` 전달까지 실기기/실계정 흐름 확인이 필요하다.
- `ReceiptOrderResponseDTO`는 required에 `store`가 있으나 properties에는 `store`가 없다. 현재는 안전 decoding이 필요하다.
- Video stream URL의 상대경로/토큰 만료 정책은 실제 화면 구현 전에 확인이 필요하다.

## 11. 남은 TODO
- Xcode 빌드 실패 항목이 있으면 우선 수정한다.
- Chat 파일 첨부 UI와 업로드 후 `files` 배열 전송을 연결한다.
- Store 검색 결과 화면 및 내가 좋아요한 가게 목록 화면을 완성한다.
- User search 전용 UI가 필요하면 `/v1/users/search`와 연결한다.
- Socket.IO 실시간 채팅을 도입할지 제품 범위를 확정한다.
- Push 테스트 전송, Video, Admin은 앱 범위 확정 전까지 구현하지 않는다.

## 12. 테스트 체크리스트
- Xcode build: 완료. `xcodebuild -project Pikko.xcodeproj -scheme Pikko -configuration Debug -destination 'generic/platform=iOS' build` 성공.
- Swift compile check: 완료. 위 Xcode build에서 Swift compile/link 성공.
- 기존 테스트: 완료. `xcodebuild -project Pikko.xcodeproj -scheme Pikko -configuration Debug -destination 'id=5FA039E2-D173-43D5-9108-D469C1665BA0' test` 160 tests, 0 failures.
- 로그인 성공/accessToken 저장: 코드 경로 확인, 실계정 수동 확인 필요
- 419 refresh 재시도/418 세션 만료: `APIClient`/`TokenRefreshCoordinator` 코드 확인, 서버 재현 테스트 필요
- 홈 배너/가게 목록/상세/좋아요: 코드 경로 확인, 수동 API 확인 필요
- 커뮤니티 목록/상세/작성/좋아요/댓글: 코드 경로 확인, 수동 API 확인 필요
- 채팅방 생성/목록/내역/전송: 코드 경로 확인, 수동 API 확인 필요
- 주문 생성/주문 내역/결제 검증: 코드 경로 확인, 실결제 콜백 확인 필요
- 리뷰 작성/목록/상세/수정/삭제: 코드 경로 확인, 주문 상태 조건 수동 확인 필요
- 이미지 URL 로딩: `AuthorizedImageLoader` 경로 확인, 인증 필요 파일 수동 확인 필요
- 주요 화면 safe area: 커뮤니티/채팅 입력창은 `safeAreaInset` 사용 확인, 실기기 수동 확인 필요
