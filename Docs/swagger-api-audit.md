# Pikko Swagger API Audit

## 1. Swagger 추출 정보

- Swagger URL: `http://pickup.sesac.kr:42678/api-docs/9POW2XC7H5VZP9N1/#/`
- API Base URL: `http://pickup.sesac.kr:42678`
- 추출 일자: 2026-04-28 KST
- 명세 위치: `swagger-ui-init.js`의 `options.swaggerDoc`
- tags 수: 15
- paths 수: 51
- operations 수: 63
- 기준값과 차이: 없음

## 2. 공통 인증/헤더 정책

- 모든 API 요청은 `RequestBuilder`에서 `SeSACKey` 헤더를 공통 주입한다.
- `Authorization` 필요 API는 저장된 accessToken을 `Authorization` 헤더에 그대로 넣는다.
- `GET /v1/auth/refresh`는 `Authorization`, `SeSACKey`, `RefreshToken`을 함께 보낸다.
- `APIClient`는 401/419 중 refresh 가능 요청에 대해 `TokenRefreshCoordinator` single-flight 재발급 후 원 요청을 1회 재시도한다.
- refresh 실패 또는 401/403/418 계열 인증 실패는 세션 무효화 알림을 발생시켜 로그인 흐름으로 이동한다.
- 420은 `NetworkError.configuration`/로그로 SeSACKey 설정 문제를 노출한다.
- 429는 과호출 안내, 444/500은 일반 서버 오류로 매핑한다.
- `/data/...` 파일은 `AuthorizedImageLoader` 또는 `AuthorizedFileURLResolver`를 통해 Base URL origin과 결합하고 인증 헤더를 붙여 로드한다.

## 3. 태그별 API 목록

| Tag | APIs |
|---|---|
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

| Tag | Method | Path | Summary | Auth 필요 여부 | Request DTO/Parameters | Response DTO | iOS 구현 파일 | 구현 상태 | 화면 진입점 | 비고 |
|---|---|---|---|---|---|---|---|---|---|---|
| 공통적용 사항 | GET | `/common` | 공통사항 정의 | SeSACKey | - | Empty | `DeveloperDiagnosticsClient` | Debug/Admin 전용 | 프로필 > 개발자 진단 | Release 미노출 |
| Log | GET | `/v1/log` | 서버요청로그 조회 | SeSACKey | - | `DeveloperLogListResponseDTO` | `DeveloperDiagnosticsClient` | Debug/Admin 전용 | 프로필 > 개발자 진단 | Release 미노출 |
| Auth | GET | `/v1/auth/refresh` | 리프레시 토큰 | Authorization+SeSACKey+RefreshToken | header `RefreshToken` | `RefreshTokenResponseDTO` | `Core/Network/TokenRefreshCoordinator.swift` | 구현 완료 | 자동 재시도 | single-flight |
| User | POST | `/v1/users/validation/email` | 이메일 유효성 체크 | SeSACKey | `EmailValidationRequestDTO` | `{message}` | `AuthRemoteDataSource`, `AuthPresenter` | 구현 완료 | 회원가입 | 중복 확인 UI |
| User | POST | `/v1/users/join` | 회원가입 | SeSACKey | `EmailSignUpRequestDTO` | `LoginResponseDTO` | `AuthRemoteDataSource`, `AuthRepositoryImpl` | 구현 완료 | 회원가입 | 세션 저장 |
| User | POST | `/v1/users/login` | 이메일 로그인 | SeSACKey | `EmailLoginRequestDTO` | `LoginResponseDTO` | `AuthRemoteDataSource`, `AuthPresenter` | 구현 완료 | 이메일 로그인 | 세션 저장 |
| User | POST | `/v1/users/login/kakao` | 카카오 로그인 | SeSACKey | `KakaoLoginRequestDTO` | `LoginResponseDTO` | `KakaoLoginService`, `AuthRemoteDataSource` | 구현 완료 | 로그인 허브 | Google API 없음 |
| User | POST | `/v1/users/login/apple` | 애플 로그인 | SeSACKey | `AppleLoginRequestDTO` | `LoginResponseDTO` | `AppleSignInService`, `AuthRemoteDataSource` | 구현 완료 | 로그인 허브 | - |
| User | POST | `/v1/users/logout` | 로그아웃 | Authorization+SeSACKey | - | Empty | `AuthRemoteDataSource`, `ProfilePresenter` | 구현 완료 | 프로필 > 로그아웃 | 로컬 세션 정리 |
| User | PUT | `/v1/users/deviceToken` | 디바이스 토큰 업데이트 | Authorization+SeSACKey | `DeviceTokenRequestDTO` | Empty | `AuthRemoteDataSource`, `FeatureBuilderFactory` | 구현 완료 | 로그인 후 자동 동기화 | push token 보유 시 호출 |
| User | GET | `/v1/users/me/profile` | 내 프로필 조회 | Authorization+SeSACKey | - | `MyInfoResponseDTO` | `SessionRestorer`, `ProfileInteractor` | 구현 완료 | 앱 시작/프로필 | 세션 복원 |
| User | PUT | `/v1/users/me/profile` | 내 프로필 수정 | Authorization+SeSACKey | `ProfileRequestDTO` | `MyInfoResponseDTO` | `ProfilePresenter`, `AuthRemoteDataSource` | 구현 완료 | 프로필 편집 | 성공 UI 반영 |
| User | POST | `/v1/users/profile/image` | 프로필 이미지 업로드 | Authorization+SeSACKey | multipart `profile` | `ProfileImageUploadResponseDTO` | `ProfilePresenter`, `AuthRemoteDataSource` | 구현 완료 | 프로필 편집 | field `profile` |
| User | GET | `/v1/users/search` | 유저 검색 | Authorization+SeSACKey | query `nick` | `UserInfoListResponseDTO` | `UserSearchRootView`, `AuthRepositoryImpl` | 구현 완료 | 프로필 > 유저 검색 | 선택 시 채팅 생성 |
| Store | GET | `/v1/stores` | 주변 가게 목록 | Authorization+SeSACKey | `category,longitude,latitude,maxDistance,next,limit,order_by` | `StoreSummaryListResponseDTO` | `StoreRemoteDataSource`, `HomeInteractor` | 구현 완료 | 홈 | `distance/orders/reviews`만 사용 |
| Store | GET | `/v1/stores/{store_id}` | 가게 상세 | Authorization+SeSACKey | path `store_id` | `StoreDetailResponseDTO` | `StoreDetailInteractor` | 구현 완료 | 홈/검색/찜 목록 | 인증 이미지 |
| Store | POST | `/v1/stores/{store_id}/like` | 가게 좋아요 | Authorization+SeSACKey | `LikeStoreRequestDTO` | `LikeStoreResponseDTO` | `StoreRepositoryImpl` | 구현 완료 | 홈/상세/찜 목록 | optimistic update |
| Store | GET | `/v1/stores/search` | 가게 검색 | Authorization+SeSACKey | query `name` | `StoreSearchListResponseDTO` | `StoreListRootView` | 구현 완료 | 홈 검색 | 빈/오류 상태 |
| Store | GET | `/v1/stores/popular-stores` | 인기 가게 | Authorization+SeSACKey | `category` | `PopularStoresResponseDTO` | `HomeInteractor` | 구현 완료 | 홈 | - |
| Store | GET | `/v1/stores/searches-popular` | 인기 검색어 | Authorization+SeSACKey | - | `PopularSearchTermsResponseDTO` | `HomeInteractor` | 구현 완료 | 홈/검색 | - |
| Store | GET | `/v1/stores/likes/me` | 내가 좋아요한 가게 | Authorization+SeSACKey | `category,next,limit` | `StoreSummaryListResponseDTO` | `StoreListRootView` | 구현 완료 | 프로필 > 찜한 가게 | 해제 시 목록 갱신 |
| Store | GET | `/v1/stores/reviews/users/{user_id}` | 유저 리뷰 목록 | Authorization+SeSACKey | `user_id,category,next,limit` | `UserReviewListResponseDTO` | `UserReviewListRootView` | 구현 완료 | 프로필 > 내 리뷰 | Store tag API |
| Community-Post | POST | `/v1/posts/files` | 게시글 파일 업로드 | Authorization+SeSACKey | multipart `files` | `CommunityFileUploadResponseDTO` | `CommunityComposerInteractor` | 구현 완료 | 커뮤니티 작성 | 작성 전 업로드 |
| Community-Post | POST | `/v1/posts` | 게시글 작성 | Authorization+SeSACKey | `CommunityPostCreateRequestDTO` | `CommunityPostDetailResponseDTO` | `CommunityComposerPresenter` | 구현 완료 | 커뮤니티 작성 | 성공 후 상세/목록 갱신 |
| Community-Post | GET | `/v1/posts/geolocation` | 위치 기반 게시글 | Authorization+SeSACKey | `category,longitude,latitude,maxDistance,limit,next,order_by` | `CommunityPostSummaryPaginationResponseDTO` | `CommunityInteractor` | 구현 완료 | 커뮤니티 | `createdAt/likes`만 전송 |
| Community-Post | GET | `/v1/posts/search` | 게시글 검색 | Authorization+SeSACKey | query `title` | `CommunityPostSummaryListResponseDTO` | `CommunityRootView` | 구현 완료 | 커뮤니티 검색 | 검색 화면 연결 |
| Community-Post | GET | `/v1/posts/{post_id}` | 게시글 상세 | Authorization+SeSACKey | path `post_id` | `CommunityPostDetailResponseDTO` | `CommunityDetailInteractor` | 구현 완료 | 커뮤니티 목록/프로필 | 댓글 포함 상세 |
| Community-Post | PUT | `/v1/posts/{post_id}` | 게시글 수정 | Authorization+SeSACKey | `CommunityPostUpdateRequestDTO` | `CommunityPostDetailResponseDTO` | `CommunityComposerPresenter` | 구현 완료 | 게시글 상세 > 수정 | - |
| Community-Post | DELETE | `/v1/posts/{post_id}` | 게시글 삭제 | Authorization+SeSACKey | path `post_id` | Empty | `CommunityDetailPresenter` | 구현 완료 | 게시글 상세 > 삭제 | - |
| Community-Post | POST | `/v1/posts/{post_id}/like` | 게시글 좋아요 | Authorization+SeSACKey | `CommunityPostLikeRequestDTO` | `CommunityPostLikeResponseDTO` | `CommunityPresenter`, `CommunityDetailPresenter` | 구현 완료 | 목록/상세/프로필 목록 | optimistic update |
| Community-Post | GET | `/v1/posts/users/{user_id}` | 유저 작성글 | Authorization+SeSACKey | `user_id,category,next,limit` | `CommunityPostSummaryPaginationResponseDTO` | `CommunityPostListRootView` | 구현 완료 | 프로필 > 내 글 | pagination |
| Community-Post | GET | `/v1/posts/likes/me` | 좋아요한 글 | Authorization+SeSACKey | `category,next,limit` | `CommunityPostSummaryPaginationResponseDTO` | `CommunityPostListRootView` | 구현 완료 | 프로필 > 좋아요한 글 | pagination |
| Community-Post-Comment | POST | `/v1/posts/{post_id}/comments` | 댓글 작성 | Authorization+SeSACKey | `CommunityCommentCreateRequestDTO` | `CommunityCommentMutationResponseDTO` | `CommunityDetailCommentSectionView` | 구현 완료 | 게시글 상세 하단 입력바 | 대댓글 `parent_comment_id` |
| Community-Post-Comment | PUT | `/v1/posts/{post_id}/comments/{comment_id}` | 댓글 수정 | Authorization+SeSACKey | `CommunityCommentUpdateRequestDTO` | `CommunityCommentMutationResponseDTO` | `CommunityDetailPresenter` | 구현 완료 | 댓글 메뉴 | 권한 오류 표시 |
| Community-Post-Comment | DELETE | `/v1/posts/{post_id}/comments/{comment_id}` | 댓글 삭제 | Authorization+SeSACKey | path ids | Empty | `CommunityDetailPresenter` | 구현 완료 | 댓글 메뉴 | 목록/카운트 갱신 |
| Chat | POST | `/v1/chats` | 채팅방 생성 | Authorization+SeSACKey | `CreateChatRoomRequestDTO` | `ChatRoomDTO` | `ChatInteractor`, `UserSearchRootView` | 구현 완료 | 유저 검색/가게 문의 | `opponent_id` |
| Chat | GET | `/v1/chats` | 채팅방 목록 | Authorization+SeSACKey | - | `ChatRoomListResponseDTO` | `ChatRootView` | 구현 완료 | 프로필 > 채팅 | 빈/오류 상태 |
| Chat | POST | `/v1/chats/{room_id}` | 메시지 전송 | Authorization+SeSACKey | `SendChatMessageRequestDTO` | `ChatMessageDTO` | `ChatPresenter` | 구현 완료 | 채팅 상세 | 텍스트/파일 경로 포함 |
| Chat | GET | `/v1/chats/{room_id}` | 채팅 내역 | Authorization+SeSACKey | `next` | `ChatMessageListResponseDTO` | `ChatPresenter` | 구현 완료 | 채팅 상세 | refresh 연결 |
| Chat | POST | `/v1/chats/{room_id}/files` | 채팅 파일 업로드 | Authorization+SeSACKey | multipart `files` | `ChatFileResponseDTO` | `ChatRootView`, `ChatPresenter` | 구현 완료 | 채팅 상세 첨부 버튼 | 업로드 후 메시지 전송 |
| Order | POST | `/v1/orders` | 주문 생성 | Authorization+SeSACKey | `OrderCreateRequestDTO` | `OrderCreateResponseDTO` | `CheckoutPresenter`, `OrderRepositoryImpl` | 구현 완료 | 장바구니/결제 | `order_menu_list,store_id,total_price` |
| Order | GET | `/v1/orders` | 주문 목록 | Authorization+SeSACKey | - | `OrderListResponseDTO` | `OrderRootView` | 구현 완료 | 주문 탭 | 상세 매핑 |
| Order | PUT | `/v1/orders/{order_code}` | 주문 상태 변경 | Authorization+SeSACKey | `OrderStatusUpdateRequestDTO(nextStatus)` | Empty | `OrderRemoteDataSource.updateOrderStatus` | Debug/Admin 전용 | 주문 상태 변경 Debug/Admin 테스트 | 일반 구매자 버튼 없음 |
| Payment | POST | `/v1/payments/validation` | 결제 검증 | Authorization+SeSACKey | `PaymentValidationRequestDTO` | `ReceiptOrderResponseDTO` | `CheckoutPaymentBridgeView`, `OrderRemoteDataSource` | 구현 완료 | 결제 브릿지 완료 콜백 | 실결제는 서버 협의 필요 |
| Payment | GET | `/v1/payments/{order_code}` | 영수증 조회 | Authorization+SeSACKey | path `order_code` | `PaymentResponseDTO` | `OrderDetailInteractor` | 구현 완료 | 주문 상세 영수증 | `paidAt/paid_at` 안전 decoding |
| Review | POST | `/v1/stores/{store_id}/reviews/files` | 리뷰 이미지 업로드 | Authorization+SeSACKey | multipart `files` | `ReviewImageResponseDTO` | `ReviewComposerPresenter` | 구현 완료 | 리뷰 작성/수정 | 업로드 후 body 포함 |
| Review | POST | `/v1/stores/{store_id}/reviews` | 리뷰 작성 | Authorization+SeSACKey | `ReviewCreateRequestDTO` | `UserReviewResponseDTO` | `ReviewComposerInteractor` | 구현 완료 | 주문 상세/가게 상세 | 완료 주문 제한 UI |
| Review | GET | `/v1/stores/{store_id}/reviews` | 리뷰 목록 | Authorization+SeSACKey | `next,limit,order_by` | `ReviewListResponseDTO` | `StoreDetailInteractor` | 구현 완료 | 가게 상세 | pagination |
| Review | GET | `/v1/stores/{store_id}/reviews/{review_id}` | 리뷰 상세 | Authorization+SeSACKey | path ids | `UserReviewResponseDTO` | `ReviewComposerInteractor` | 구현 완료 | 내 리뷰 > 수정 | 편집 초기값 로드 |
| Review | PUT | `/v1/stores/{store_id}/reviews/{review_id}` | 리뷰 수정 | Authorization+SeSACKey | `ReviewUpdateRequestDTO` | `UserReviewResponseDTO` | `ReviewComposerInteractor` | 구현 완료 | 내 리뷰/가게 상세 | 목록 갱신 |
| Review | DELETE | `/v1/stores/{store_id}/reviews/{review_id}` | 리뷰 삭제 | Authorization+SeSACKey | path ids | Empty | `StoreDetailPresenter`, `UserReviewListPresenter` | 구현 완료 | 가게 상세/내 리뷰 | 삭제 후 통계 갱신 |
| Review | GET | `/v1/stores/{store_id}/reviews/reviews-ratings` | 별점 통계 | Authorization+SeSACKey | path `store_id` | `ReviewRatingListResponseDTO` | `StoreDetailInteractor` | 구현 완료 | 가게 상세 리뷰 요약 | - |
| Banner | GET | `/v1/banners/main` | 메인 배너 | Authorization+SeSACKey | - | `BannerListResponseDTO` | `HomeInteractor`, `PikkoWebContentView` | 구현 완료 | 홈 배너 | WEBVIEW payload 연결 |
| Push | POST | `/v1/notifications/push` | 푸시 테스트 | Authorization+SeSACKey | `PushNotificationDebugRequestDTO` | Empty | `DeveloperDiagnosticsClient` | Debug/Admin 전용 | 프로필 > 개발자 진단 | Release 미노출 |
| Video | GET | `/v1/videos` | 비디오 목록 | Authorization+SeSACKey | `next,limit` | `VideoDebugListResponseDTO` | `DeveloperDiagnosticsClient` | Debug/Admin 전용 | 프로필 > 개발자 진단 | 일반 surface 없음 |
| Video | GET | `/v1/videos/{video_id}/stream` | 스트림 URL 조회 | Authorization+SeSACKey | path `video_id` | `VideoStreamDebugResponseDTO` | `DeveloperDiagnosticsClient`, `AVPlayer` | Debug/Admin 전용 | 프로필 > 개발자 진단 | URL 토큰 재생 |
| Video | POST | `/v1/videos/{video_id}/like` | 비디오 좋아요 | Authorization+SeSACKey | `DebugLikeRequestDTO` | `DebugLikeResponseDTO` | `DeveloperDiagnosticsClient` | Debug/Admin 전용 | 프로필 > 개발자 진단 | 즉시 UI 반영 |
| Admin | POST | `/v1/stores/files` | 가게 이미지 업로드 | Authorization+SeSACKey | multipart `files` | `StoreDebugFileResponseDTO` | `DeveloperDiagnosticsClient` | Debug/Admin 전용 | 프로필 > 개발자 진단 | Release 미노출 |
| Admin | POST | `/v1/stores` | 가게 등록 | Authorization+SeSACKey | `StoreDebugMutationRequestDTO` | `StoreDetailResponseDTO` | `DeveloperDiagnosticsClient` | Debug/Admin 전용 | 프로필 > 개발자 진단 | 권한 필요 |
| Admin | PUT | `/v1/stores/{store_id}` | 가게 수정 | Authorization+SeSACKey | `StoreDebugMutationRequestDTO` | `StoreDetailResponseDTO` | `DeveloperDiagnosticsClient` | Debug/Admin 전용 | 프로필 > 개발자 진단 | 권한 필요 |
| Admin | POST | `/v1/menus/image` | 메뉴 이미지 업로드 | Authorization+SeSACKey | multipart `menu_image` | `MenuDebugFileResponseDTO` | `DeveloperDiagnosticsClient` | Debug/Admin 전용 | 프로필 > 개발자 진단 | field `menu_image` |
| Admin | POST | `/v1/menus/stores/{store_id}` | 메뉴 등록 | Authorization+SeSACKey | `MenuDebugMutationRequestDTO` | `MenuDebugResponseDTO` | `DeveloperDiagnosticsClient` | Debug/Admin 전용 | 프로필 > 개발자 진단 | 권한 필요 |
| Admin | PUT | `/v1/menus/{menu_id}` | 메뉴 수정 | Authorization+SeSACKey | `MenuDebugMutationRequestDTO` | `MenuDebugResponseDTO` | `DeveloperDiagnosticsClient` | Debug/Admin 전용 | 프로필 > 개발자 진단 | 권한 필요 |

## 5. 기존 문서 대비 변경 사항

- 기존 `Docs/swagger-api-audit .md`의 `후순위` 상태를 제거하고 허용 상태값으로 재분류했다.
- 현재 Swagger를 재추출해 15 tags, 51 paths, 63 operations가 기준과 일치함을 확인했다.
- User 검색, Chat 파일 업로드/파일 메시지, Push/Video/Admin/Common/Log DEBUG 진단 surface를 새 구현 항목으로 반영했다.
- Community order_by는 `createdAt`, `likes`만 사용하고, Store order_by는 `distance`, `orders`, `reviews`만 사용하도록 문서화했다.

## 6. 새로 구현한 항목

- 프로필 탭의 `채팅` 진입점: `GET /v1/chats` 목록 조회.
- 프로필 탭의 `유저 검색` 진입점: `GET /v1/users/search?nick=` 후 결과 선택 시 `POST /v1/chats`.
- 채팅 상세 첨부 버튼: 이미지/PDF 선택 후 multipart `files` field로 `POST /v1/chats/{room_id}/files`에 업로드하고, 반환 file path를 `POST /v1/chats/{room_id}` body의 `files`에 포함. 클라이언트는 jpg/jpeg/png/gif/pdf, 5개, 파일당 5MB 정책을 먼저 검증한다.
- 채팅방 목록: 현재 Swagger의 `GET /v1/chats`에는 `next`/`limit` query가 없다. iOS는 `defaultPageSize=20`, `maxPageSize=50` 상수를 두고 로컬 표시 페이지와 중복 병합을 적용하지만, 서버가 목록 pagination query를 제공하기 전까지 네트워크 요청 자체를 cursor 기반으로 제한할 수 없다.
- 채팅 검색: 서버 검색 endpoint가 없으므로 현재 열린 방의 로컬/불러온 메시지만 검색한다. UI copy는 이전 대화가 아직 불러와지지 않았을 수 있음을 표시한다.
- TODO(Server): 현재 `POST /v1/chats` request body는 `opponent_id`만 지원한다. 같은 점주가 여러 가게를 보유한 경우 store별 채팅방을 분리할 수 없으므로, store별 문의 UX가 필요하면 `store_id` 또는 동등한 store context를 room 생성/조회 계약에 추가해야 한다. 클라이언트는 이 API가 추가되기 전까지 같은 `room_id`를 서로 다른 가게 채팅방처럼 표시하지 않는다.
- DEBUG 전용 개발자 진단: `/common`, `/v1/log`, Push, Video 목록/스트림/좋아요, Admin Store/Menu 업로드·등록·수정 호출.

## 7. Debug/Admin 전용 항목

- `GET /common`
- `GET /v1/log`
- `POST /v1/notifications/push`
- `GET /v1/videos`
- `GET /v1/videos/{video_id}/stream`
- `POST /v1/videos/{video_id}/like`
- `POST /v1/stores/files`
- `POST /v1/stores`
- `PUT /v1/stores/{store_id}`
- `POST /v1/menus/image`
- `POST /v1/menus/stores/{store_id}`
- `PUT /v1/menus/{menu_id}`
- `PUT /v1/orders/{order_code}` 상태 변경은 일반 구매자에게 노출하지 않고 Debug/Admin 테스트 범위로 둔다.

## 8. Release 일반 사용자 앱 제외 항목

- Push 테스트 API: 사용자 Release 화면에서 푸시 임의 발송 기능은 제공하지 않는다.
- Admin 컨텐츠 등록 API: 일반 사용자 앱 권한/UX 범위 밖이며 DEBUG 진단에서만 제한적으로 호출한다.
- Log/Common 진단 API: 서비스 진단 목적이므로 Release 일반 사용자 화면에는 노출하지 않는다.
- Video: 현재 일반 사용자용 탭/홈 섹션 surface가 없어 DEBUG 진단에서 API 동작만 확인한다.

## 9. 서버 협의 필요 항목

- Admin API 권한 정책과 운영 계정 권한 범위.
- 주문 상태 변경 가능 role 및 상태 enum의 서버 운영값.
- 결제 SDK 실계정/실결제 검증 환경과 환불/취소 API 유무.
- Video를 일반 사용자 surface로 노출할 제품 정책.

## 10. 남은 TODO

- 실기기 카카오/애플 로그인, push token 발급, 실결제 SDK 콜백 검증은 외부 계정/기기/서버 권한이 필요하다.
- Admin/주문 상태 변경은 권한 있는 계정으로 403이 아닌 성공 케이스를 확인해야 한다.
- Video 일반 사용자 노출 여부는 제품 정책 확정 후 홈/탭 surface로 승격한다.

## 11. 수동 테스트 체크리스트

- 회원가입
- 이메일 로그인
- 카카오 로그인
- 애플 로그인
- 로그아웃
- 세션 복원
- 프로필 조회/수정/이미지 업로드
- 유저 검색
- 홈 배너
- 주변 가게 목록
- 가게 검색
- 가게 상세
- 가게 좋아요
- 인기 가게
- 인기 검색어
- 내가 좋아요한 가게
- 커뮤니티 목록
- 커뮤니티 검색
- 커뮤니티 작성/파일 업로드
- 커뮤니티 상세
- 커뮤니티 수정/삭제
- 커뮤니티 좋아요
- 댓글/대댓글 작성
- 댓글 수정/삭제
- 내가 작성한 게시글
- 내가 좋아요한 게시글
- 채팅방 생성
- 채팅방 목록
- 채팅 내역
- 텍스트 메시지 전송
- 파일 첨부 메시지 전송
- 주문 생성
- 주문 내역
- 주문 상세
- 주문 상태 변경 Debug/Admin 테스트
- 결제 검증
- 영수증 조회
- 리뷰 파일 업로드
- 리뷰 작성
- 리뷰 목록
- 리뷰 상세
- 리뷰 수정/삭제
- 리뷰 별점 통계
- 유저 리뷰 목록
- Push Debug/Admin 테스트
- Video 목록/스트림/좋아요 Debug 진단
- Admin API Debug/Admin 테스트 또는 권한 정책 확인
