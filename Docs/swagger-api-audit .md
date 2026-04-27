# Swagger API Audit

## 0. Executive Summary
- Swagger 기준 전체 endpoint 수: **63**
- tag별 endpoint 수:
  - 공통적용 사항: 1
  - Log: 1
  - Auth: 1
  - User: 11
  - Store: 8
  - Community-Post: 10
  - Community-Post-Comment: 3
  - Chat: 5
  - Order: 3
  - Payment: 2
  - Review: 7
  - Banner: 1
  - Push: 1
  - Video: 3
  - Admin: 6
- public endpoint 목록: 없음 (Swagger security 기준 모든 endpoint에 최소 SeSACKey가 필요)
- Authorization required endpoint 목록: `GET /v1/auth/refresh`, `GET /v1/banners/main`, `POST /v1/users/logout`, `PUT /v1/users/deviceToken`, `GET /v1/users/me/profile`, `PUT /v1/users/me/profile`, `POST /v1/users/profile/image`, `GET /v1/users/search`, `POST /v1/payments/validation`, `GET /v1/payments/{order_code}`, `POST /v1/notifications/push`, `POST /v1/chats`, `GET /v1/chats`, `POST /v1/chats/{room_id}`, `GET /v1/chats/{room_id}`, `POST /v1/chats/{room_id}/files`, `POST /v1/stores/files`, `POST /v1/stores`, `GET /v1/stores`, `GET /v1/stores/{store_id}`, `PUT /v1/stores/{store_id}`, `POST /v1/stores/{store_id}/like`, `POST /v1/menus/image`, `POST /v1/menus/stores/{store_id}`, `PUT /v1/menus/{menu_id}`, `GET /v1/stores/search`, `GET /v1/stores/popular-stores`, `GET /v1/stores/searches-popular`, `GET /v1/stores/likes/me`, `POST /v1/posts/files`, `POST /v1/posts`, `GET /v1/posts/geolocation`, `GET /v1/posts/search`, `GET /v1/posts/{post_id}`, `PUT /v1/posts/{post_id}`, `DELETE /v1/posts/{post_id}`, `POST /v1/posts/{post_id}/like`, `GET /v1/posts/users/{user_id}`, `GET /v1/posts/likes/me`, `POST /v1/posts/{post_id}/comments`, `PUT /v1/posts/{post_id}/comments/{comment_id}`, `DELETE /v1/posts/{post_id}/comments/{comment_id}`, `POST /v1/orders`, `GET /v1/orders`, `PUT /v1/orders/{order_code}`, `POST /v1/stores/{store_id}/reviews/files`, `POST /v1/stores/{store_id}/reviews`, `GET /v1/stores/{store_id}/reviews`, `GET /v1/stores/{store_id}/reviews/{review_id}`, `PUT /v1/stores/{store_id}/reviews/{review_id}`, `DELETE /v1/stores/{store_id}/reviews/{review_id}`, `GET /v1/stores/{store_id}/reviews/reviews-ratings`, `GET /v1/stores/reviews/users/{user_id}`, `GET /v1/videos`, `GET /v1/videos/{video_id}/stream`, `POST /v1/videos/{video_id}/like`
- SeSACKey only endpoint 목록: `GET /common`, `GET /v1/log`, `POST /v1/users/validation/email`, `POST /v1/users/join`, `POST /v1/users/login`, `POST /v1/users/login/kakao`, `POST /v1/users/login/apple`
- RefreshToken required endpoint 목록: `GET /v1/auth/refresh`
- iOS MVP 필수 endpoint 목록: `POST /v1/users/join`, `POST /v1/users/login`, `POST /v1/users/login/kakao`, `POST /v1/users/login/apple`, `POST /v1/users/logout`, `GET /v1/users/me/profile`, `GET /v1/auth/refresh`, `GET /v1/banners/main`, `GET /v1/stores`, `GET /v1/stores/popular-stores`, `GET /v1/stores/searches-popular`, `GET /v1/stores/search`, `GET /v1/stores/{store_id}`, `POST /v1/stores/{store_id}/like`, `GET /v1/stores/likes/me`, `POST /v1/orders`, `GET /v1/orders`, `POST /v1/payments/validation`, `GET /v1/payments/{order_code}`
- 현재 구현 완료/부분 구현/미구현/앱 범위 외 요약:
  - 구현 완료: 26
  - 부분 구현: 4
  - 미구현: 21
  - 앱 범위 외: 12
- 가장 위험한 mismatch 요약:
  - StoreSummaryDTO.store_image_urls 설명은 “첫 번째 이미지만 포함”인데, 실응답은 현재 2장 케이스가 많다. Home 카드가 3장 고정 슬롯을 기대하면 placeholder가 노출된다. 이번 턴에 0/1/2/3장 분기로 수정했다.
  - BannerResponseDTO.imageUrl, payload.value는 상대경로다. 이미지/웹뷰 URL을 baseURL과 결합하지 않으면 빈 화면 또는 잘못된 링크가 된다.
  - PaymentResponseDTO는 Swagger required에 paid_at이 적혀 있지만 실제 properties에는 paidAt도 공존한다. dual-key decoding이 필요하다.
  - ReceiptOrderResponseDTO 스키마는 required에 store를 적어두고 properties에는 store가 없다. 실응답 확인 전까지 안전 decoding과 로그가 필요하다.
  - Swagger에는 Google 로그인 endpoint가 없다. 앱에서 backend endpoint를 임의 생성하면 444/401 오류가 난다. 현재 코드는 unsupported로 처리한다.

## 1. Security & Common Policy
- SeSACKey
  - 모든 요청 기본 헤더
  - header name: `SeSACKey`
- Authorization
  - 로그인 이후 주요 서비스 API에 필요
  - header name: `Authorization`
- RefreshToken
  - `GET /v1/auth/refresh`의 required header parameter
  - securitySchemes에는 없지만 header parameter로 존재
- 공통 에러 정책
  - 400: 필수값 누락/유효하지 않은 값 타입/잘못된 요청
  - 401: accessToken 또는 refreshToken 인증 불가
  - 403: user_id 조회 실패/탈퇴 회원 등
  - 418: refreshToken 만료
  - 419: accessToken 만료
  - 420: SeSACKey 오류
  - 429: 과호출
  - 444: 비정상 API 호출
  - 445: 권한/소유자 불일치 계열
  - 500: 서버 오류
- iOS 처리 정책
  - 419 발생 시 refresh 시도
  - refresh 성공 시 원 요청 재시도
  - refresh 401/418/403 계열 실패 시 세션 정리 후 Auth root 이동
  - 420은 개발 설정 오류로 명확한 로그 출력
  - 445는 권한 없음 메시지로 사용자 안내

## 2. Full API Catalog by Tag
### 공통적용 사항
#### GET /common
- Tag: 공통적용 사항
- Summary: 공통사항 정의
- Method: `GET`
- Path: `/common`
- OperationId: `get-api-v1-common`
- Authorization 필요 여부: 아니오
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> EmptyResponse
- 주요 성공 응답: 200
- 주요 에러 응답: 401, 403, 419, 420, 429, 444, 500
- iOS 현재 구현 여부: 앱 범위 외
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: Out of scope
- 비고: 공통 점검용 endpoint로 보이며 현재 사용자 앱 기능에서는 사용하지 않는다.

### Log
#### GET /v1/log
- Tag: Log
- Summary: SeSACKey별 서버요청로그 조회
- Method: `GET`
- Path: `/v1/log`
- OperationId: `get-v1-log`
- Authorization 필요 여부: 아니오
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> application/json: LogListResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: -
- iOS 현재 구현 여부: 앱 범위 외
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: Out of scope
- 비고: 운영/로깅 확인용 endpoint. 사용자 앱에서 직접 호출하지 않는다.

### Auth
#### GET /v1/auth/refresh
- Tag: Auth
- Summary: 리프레시 토큰
- Method: `GET`
- Path: `/v1/auth/refresh`
- OperationId: `get-v1-auth-refreshToken`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: RefreshToken
- Path Parameter: -
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> application/json: RefreshTokenResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 401, 418
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Core/Network/RequestBuilder.swift`, `Core/Network/APIClient.swift`, `Core/Network/TokenRefreshCoordinator.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P0
- 비고: Authorization + RefreshToken + SeSACKey 헤더를 모두 넣고 single-flight refresh 후 원 요청 1회 재시도한다.

### User
#### POST /v1/users/validation/email
- Tag: User
- Summary: 이메일 유효성 체크
- Method: `POST`
- Path: `/v1/users/validation/email`
- OperationId: `get-v1-users-validation/email`
- Authorization 필요 여부: 아니오
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: application/json: EmailValidationRequestDTO (inline object {email})
- Response DTO: 200 -> application/json: inline object {message}
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 409
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: `Features/Auth/AuthRootView.swift`, `Data/Remote/AuthRemoteDataSource.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: 회원가입은 가능하지만 이메일 중복 확인 API를 별도 호출하는 UI는 아직 없다.

#### POST /v1/users/join
- Tag: User
- Summary: 회원가입
- Method: `POST`
- Path: `/v1/users/join`
- OperationId: `get-v1-users-join`
- Authorization 필요 여부: 아니오
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: application/json: JoinRequestDTO (inline object {email, password, nick, phoneNum, deviceToken})
- Response DTO: 200 -> application/json: JoinResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 409
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/AuthRemoteDataSource.swift`, `Data/Repositories/AuthRepositoryImpl.swift`, `Features/Auth/AuthInteractor.swift`, `Features/Auth/AuthPresenter.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P0
- 비고: deviceToken optional body까지 Swagger와 동일하게 전송한다.

#### POST /v1/users/login
- Tag: User
- Summary: 이메일 로그인
- Method: `POST`
- Path: `/v1/users/login`
- OperationId: `get-users-login`
- Authorization 필요 여부: 아니오
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: application/json: LoginRequestDTO (inline object {email, password, deviceToken})
- Response DTO: 200 -> application/json: LoginDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 401
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/AuthRemoteDataSource.swift`, `Data/Repositories/AuthRepositoryImpl.swift`, `Features/Auth/AuthInteractor.swift`, `Features/Auth/AuthPresenter.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P0
- 비고: -

#### POST /v1/users/login/kakao
- Tag: User
- Summary: 카카오 로그인
- Method: `POST`
- Path: `/v1/users/login/kakao`
- OperationId: `get-v1-users-login-kakao`
- Authorization 필요 여부: 아니오
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: application/json: KaKaoLoginRequestDTO (inline object {oauthToken, deviceToken})
- Response DTO: 200 -> application/json: LoginDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 401, 409
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Core/Platform/Auth/KakaoAuthService.swift`, `Data/Remote/AuthRemoteDataSource.swift`, `Features/Auth/AuthInteractor.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P0
- 비고: -

#### POST /v1/users/login/apple
- Tag: User
- Summary: 애플 로그인
- Method: `POST`
- Path: `/v1/users/login/apple`
- OperationId: `get-api-v1-users-login-apple`
- Authorization 필요 여부: 아니오
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: application/json: AppleLoginRequestDTO (inline object {idToken, deviceToken})
- Response DTO: 200 -> application/json: LoginDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 401, 409
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Core/Platform/Auth/AppleSignInService.swift`, `Data/Remote/AuthRemoteDataSource.swift`, `Features/Auth/AuthInteractor.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P0
- 비고: -

#### POST /v1/users/logout
- Tag: User
- Summary: 로그아웃
- Method: `POST`
- Path: `/v1/users/logout`
- OperationId: `post-v1-users-logout`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> 로그아웃 성공
- 주요 성공 응답: 200
- 주요 에러 응답: -
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/AuthRemoteDataSource.swift`, `Data/Repositories/AuthRepositoryImpl.swift`, `App/State/SessionStore.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P0
- 비고: 서버 응답 성공/실패와 무관하게 세션 정리 흐름을 유지한다.

#### PUT /v1/users/deviceToken
- Tag: User
- Summary: 디바이스 토큰 업데이트
- Method: `PUT`
- Path: `/v1/users/deviceToken`
- OperationId: `get-v1-users-deviceToken`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: application/json: DeviceTokenRequestDTO (inline object {deviceToken})
- Response DTO: 200 -> EmptyResponse
- 주요 성공 응답: 200
- 주요 에러 응답: -
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: `App/State/SessionStore.swift`
- Swagger와 mismatch 여부: 로컬에 deviceToken을 저장하지만 서버 동기화 API는 아직 호출하지 않는다.
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: -

#### GET /v1/users/me/profile
- Tag: User
- Summary: 내 프로필 조회
- Method: `GET`
- Path: `/v1/users/me/profile`
- OperationId: `get-v1-users-me-profile`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> application/json: MyInfoResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: -
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/AuthRemoteDataSource.swift`, `Data/Repositories/AuthRepositoryImpl.swift`, `App/Bootstrap/SessionRestorer.swift`
- Swagger와 mismatch 여부: 실응답에서는 optional 필드가 종종 생략된다. 현재 DTO는 optional decoding으로 처리한다.
- 수정 필요 여부: 아니오
- 구현 우선순위: P0
- 비고: -

#### PUT /v1/users/me/profile
- Tag: User
- Summary: 내 프로필 수정
- Method: `PUT`
- Path: `/v1/users/me/profile`
- OperationId: `put-v1-users-me-profile`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: application/json: ProfileRequestDTO (inline object {nick, phoneNum, profileImage})
- Response DTO: 200 -> application/json: MyInfoResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: `Features/Profile/ProfileRootView.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: 프로필 조회 화면은 있으나 수정 API는 아직 연결되지 않았다.

#### POST /v1/users/profile/image
- Tag: User
- Summary: 내 프로필 이미지 업로드
- Method: `POST`
- Path: `/v1/users/profile/image`
- OperationId: `post-v1-users-me-profile-image`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: multipart/form-data: inline object {profile}
- Response DTO: 200 -> application/json: inline object {profileImage}
- 주요 성공 응답: 200
- 주요 에러 응답: 400
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: `Features/Profile/ProfileRootView.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: -

#### GET /v1/users/search
- Tag: User
- Summary: 유저 검색
- Method: `GET`
- Path: `/v1/users/search`
- OperationId: `get-v1-users-search`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: nick (string, optional)
- Request Body: -
- Response DTO: 200 -> application/json: UserInfoListResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: -
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: 유저 검색 기능을 사용하는 화면/Repository가 아직 없다.

### Store
#### GET /v1/stores
- Tag: Store
- Summary: 위치 기반 주변 가게 목록 조회
- Method: `GET`
- Path: `/v1/stores`
- OperationId: `get-v1-stores-nearby`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: category (string, optional), longitude (number/float, optional), latitude (number/float, optional), maxDistance (number/float, optional), next (string, optional), limit (integer, optional), order_by (string, optional)
- Request Body: -
- Response DTO: 200 -> application/json: StoreSummaryListResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/StoreRemoteDataSource.swift`, `Data/Repositories/StoreRepositoryImpl.swift`, `Data/Mappers/StoreMapper.swift`, `Features/Home/HomeInteractor 2.swift`, `Shared/Component/StoreCard.swift`
- Swagger와 mismatch 여부: Swagger 설명은 첫 번째 이미지만 포함될 수 있다고 적혀 있고 실응답은 현재 2장 케이스가 많다. Home 카드는 이미지 개수별 분기로 보강했다.
- 수정 필요 여부: 아니오
- 구현 우선순위: P1
- 비고: 0/1/2/3장 이상 이미지 레이아웃을 모두 안전하게 처리한다.

#### GET /v1/stores/{store_id}
- Tag: Store
- Summary: 가게 상세 정보 조회
- Method: `GET`
- Path: `/v1/stores/{store_id}`
- OperationId: `get-v1-stores-store_id`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: store_id (string, required)
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> application/json: StoreDetailResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 404
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/StoreRemoteDataSource.swift`, `Data/Repositories/StoreRepositoryImpl.swift`, `Features/StoreDetail/StoreDetailInteractor.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P1
- 비고: -

#### POST /v1/stores/{store_id}/like
- Tag: Store
- Summary: 가게 좋아요 / 좋아요 취소
- Method: `POST`
- Path: `/v1/stores/{store_id}/like`
- OperationId: `post-v1-stores-store_id-like`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: store_id (string, required)
- Query Parameter: -
- Request Body: application/json: LikeStoreRequestDTO (inline object {like_status})
- Response DTO: 200 -> application/json: LikeStoreResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/StoreRemoteDataSource.swift`, `Data/Repositories/StoreRepositoryImpl.swift`, `Features/Home/HomePresenter 2.swift`, `Features/StoreDetail/StoreDetailPresenter.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P1
- 비고: Home/StoreDetail 모두 optimistic update 후 실패 시 rollback 패턴을 사용한다.

#### GET /v1/stores/search
- Tag: Store
- Summary: 가게 이름 검색
- Method: `GET`
- Path: `/v1/stores/search`
- OperationId: `get-v1-stores-search-by-name`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: name (string, optional)
- Request Body: -
- Response DTO: 200 -> application/json: StoreSearchListResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: -
- iOS 현재 구현 여부: 부분 구현
- 현재 구현 파일: `Data/Remote/StoreRemoteDataSource.swift`, `Data/Repositories/StoreRepositoryImpl.swift`, `Features/Home/HomeRouter.swift`
- Swagger와 mismatch 여부: DataSource/Repository는 준비됐지만 Home search route가 아직 TODO라서 실제 화면 호출이 없다.
- 수정 필요 여부: 예
- 구현 우선순위: P1
- 비고: -

#### GET /v1/stores/popular-stores
- Tag: Store
- Summary: 실시간 인기 가게 조회
- Method: `GET`
- Path: `/v1/stores/popular-stores`
- OperationId: `get-v1-stores-popular-stores`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: category (string, optional)
- Request Body: -
- Response DTO: 200 -> application/json: Array<StoreSummaryDTO>
- 주요 성공 응답: 200
- 주요 에러 응답: -
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/StoreRemoteDataSource.swift`, `Data/Repositories/StoreRepositoryImpl.swift`, `Features/Home/HomeInteractor 2.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P1
- 비고: -

#### GET /v1/stores/searches-popular
- Tag: Store
- Summary: 인기 검색어 목록 조회
- Method: `GET`
- Path: `/v1/stores/searches-popular`
- OperationId: `get-v1-stores-searches-popular`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> application/json: inline object {data}
- 주요 성공 응답: 200
- 주요 에러 응답: -
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/StoreRemoteDataSource.swift`, `Data/Repositories/StoreRepositoryImpl.swift`, `Features/Home/HomeInteractor 2.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P1
- 비고: -

#### GET /v1/stores/likes/me
- Tag: Store
- Summary: 내가 좋아요한 가게 조회
- Method: `GET`
- Path: `/v1/stores/likes/me`
- OperationId: `get-v1-stores-likes-me`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: category (string, optional), next (string, optional), limit (string, optional)
- Request Body: -
- Response DTO: 200 -> application/json: StoreSummaryListResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400
- iOS 현재 구현 여부: 부분 구현
- 현재 구현 파일: `Data/Remote/StoreRemoteDataSource.swift`, `Data/Repositories/StoreRepositoryImpl.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P1
- 비고: 이번 턴에 DataSource/Repository는 연결했지만 좋아요 목록 화면은 아직 없다.

#### GET /v1/stores/reviews/users/{user_id}
- Tag: Store
- Summary: 유저가 작성한 리뷰 목록 조회
- Method: `GET`
- Path: `/v1/stores/reviews/users/{user_id}`
- OperationId: `get-v1-stores-reviews-users-user_id`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: user_id (string, required)
- Query Parameter: category (string, optional), next (string, optional), limit (integer, optional)
- Request Body: -
- Response DTO: 200 -> application/json: UserReviewListResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: 유저별 리뷰 목록 기능이 아직 없다.

### Community-Post
#### POST /v1/posts/files
- Tag: Community-Post
- Summary: 파일 업로드
- Method: `POST`
- Path: `/v1/posts/files`
- OperationId: `post-v1-posts-files`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: multipart/form-data: FileRequestDTO (inline object {files})
- Response DTO: 200 -> application/json: FileResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: 커뮤니티 글 파일 업로드 multipart API가 아직 없다.

#### POST /v1/posts
- Tag: Community-Post
- Summary: 게시글 작성
- Method: `POST`
- Path: `/v1/posts`
- OperationId: `post-v1-post`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: application/json: PostRequestDTO (inline object {category, title, content, store_id, latitude, longitude, ...})
- Response DTO: 200 -> application/json: PostResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/CommunityRemoteDataSource.swift`, `Data/Repositories/CommunityRepositoryImpl.swift`, `Features/Community/CommunityComposerInteractor.swift`
- Swagger와 mismatch 여부: files path를 선행 업로드로 채우는 Swagger 플로우는 아직 미구현이다.
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: -

#### GET /v1/posts/geolocation
- Tag: Community-Post
- Summary: 위치 기반 게시글 조회
- Method: `GET`
- Path: `/v1/posts/geolocation`
- OperationId: `setSwitchTimer`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: category (string, optional), longitude (string, optional), latitude (string, optional), maxDistance (string, optional), limit (integer, optional), next (string, optional), order_by (string, optional)
- Request Body: -
- Response DTO: 200 -> application/json: PostSummaryPaginationResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/CommunityRemoteDataSource.swift`, `Data/Repositories/CommunityRepositoryImpl.swift`, `Features/Community/CommunityInteractor.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P2
- 비고: -

#### GET /v1/posts/search
- Tag: Community-Post
- Summary: 게시글 타이틀 검색
- Method: `GET`
- Path: `/v1/posts/search`
- OperationId: `search-pickup-community-posts`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: title (string, optional)
- Request Body: -
- Response DTO: 200 -> application/json: PostSummaryListResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: -
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/CommunityRemoteDataSource.swift`, `Data/Repositories/CommunityRepositoryImpl.swift`, `Features/Community/CommunityInteractor.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P2
- 비고: -

#### GET /v1/posts/{post_id}
- Tag: Community-Post
- Summary: 게시글 상세 조회
- Method: `GET`
- Path: `/v1/posts/{post_id}`
- OperationId: `get-v1-posts-post_id`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: post_id (string, required)
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> application/json: PostResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 404
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/CommunityRemoteDataSource.swift`, `Data/Repositories/CommunityRepositoryImpl.swift`, `Features/Community/CommunityDetailInteractor.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P2
- 비고: -

#### PUT /v1/posts/{post_id}
- Tag: Community-Post
- Summary: 게시글 수정
- Method: `PUT`
- Path: `/v1/posts/{post_id}`
- OperationId: `put-v1-post`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: post_id (string, required)
- Query Parameter: -
- Request Body: application/json: PostUpdateRequestDTO (inline object {category, title, content, store_id, latitude, longitude, ...})
- Response DTO: 200 -> application/json: PostResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404, 445
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/CommunityRemoteDataSource.swift`, `Data/Repositories/CommunityRepositoryImpl.swift`, `Features/Community/CommunityComposerInteractor.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P2
- 비고: -

#### DELETE /v1/posts/{post_id}
- Tag: Community-Post
- Summary: 게시글 삭제
- Method: `DELETE`
- Path: `/v1/posts/{post_id}`
- OperationId: `delete-v1-post`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: post_id (string, required)
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> EmptyResponse
- 주요 성공 응답: 200
- 주요 에러 응답: 404, 445
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: -

#### POST /v1/posts/{post_id}/like
- Tag: Community-Post
- Summary: 게시글 좋아요/좋아요 취소
- Method: `POST`
- Path: `/v1/posts/{post_id}/like`
- OperationId: `post-v1-posts-post_id-like`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: post_id (string, required)
- Query Parameter: -
- Request Body: application/json: PostLikeRequestDTO (inline object {like_status})
- Response DTO: 200 -> application/json: PostLikeResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/CommunityRemoteDataSource.swift`, `Data/Repositories/CommunityRepositoryImpl.swift`, `Features/Community/CommunityPresenter.swift`, `Features/Community/CommunityDetailPresenter.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P2
- 비고: -

#### GET /v1/posts/users/{user_id}
- Tag: Community-Post
- Summary: 유저가 작성한 게시글 조회
- Method: `GET`
- Path: `/v1/posts/users/{user_id}`
- OperationId: `get-v1-posts-users-user_id`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: user_id (string, required)
- Query Parameter: category (string, optional), limit (integer, optional), next (string, optional)
- Request Body: -
- Response DTO: 200 -> application/json: PostSummaryPaginationResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: -

#### GET /v1/posts/likes/me
- Tag: Community-Post
- Summary: 내가 좋아요한 게시글 조회
- Method: `GET`
- Path: `/v1/posts/likes/me`
- OperationId: `get-v1-posts-likes-me`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: category (string, optional), next (string, optional), limit (string, optional)
- Request Body: -
- Response DTO: 200 -> application/json: PostSummaryPaginationResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: -

### Community-Post-Comment
#### POST /v1/posts/{post_id}/comments
- Tag: Community-Post-Comment
- Summary: 댓글 또는 대댓글 작성
- Method: `POST`
- Path: `/v1/posts/{post_id}/comments`
- OperationId: `post-v1-post-comment`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: post_id (string, required)
- Query Parameter: -
- Request Body: application/json: CommentRequestDTO (inline object {parent_comment_id, content})
- Response DTO: 200 -> application/json: CommentResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/CommunityRemoteDataSource.swift`, `Data/Repositories/CommunityRepositoryImpl.swift`, `Features/Community/CommunityDetailInteractor.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P2
- 비고: -

#### PUT /v1/posts/{post_id}/comments/{comment_id}
- Tag: Community-Post-Comment
- Summary: 댓글 또는 대댓글 수정
- Method: `PUT`
- Path: `/v1/posts/{post_id}/comments/{comment_id}`
- OperationId: `put-v1-posts-post_id-comments-comment_id`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: post_id (string, required), comment_id (string, required)
- Query Parameter: -
- Request Body: application/json: CommentUpdateRequestDTO (inline object {content})
- Response DTO: 200 -> application/json: CommentResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404, 445
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/CommunityRemoteDataSource.swift`, `Data/Repositories/CommunityRepositoryImpl.swift`, `Features/Community/CommunityDetailInteractor.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P2
- 비고: -

#### DELETE /v1/posts/{post_id}/comments/{comment_id}
- Tag: Community-Post-Comment
- Summary: 댓글 또는 대댓글 삭제
- Method: `DELETE`
- Path: `/v1/posts/{post_id}/comments/{comment_id}`
- OperationId: `delete-v1-posts-post_id-comments-comment_id`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: post_id (string, required), comment_id (string, required)
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> EmptyResponse
- 주요 성공 응답: 200
- 주요 에러 응답: 404, 445
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/CommunityRemoteDataSource.swift`, `Data/Repositories/CommunityRepositoryImpl.swift`, `Features/Community/CommunityDetailInteractor.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P2
- 비고: 댓글 replies는 detail 응답 기준 1-depth만 다룬다.

### Chat
#### POST /v1/chats
- Tag: Chat
- Summary: 채팅방 생성(조회)
- Method: `POST`
- Path: `/v1/chats`
- OperationId: `post-v1-chats`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: application/json: inline object {opponent_id}
- Response DTO: 200 -> application/json: ChatRoomResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: `Features/Chat/ChatRootView.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P3
- 비고: Chat 화면은 placeholder 수준이며 RemoteDataSource/Repository가 없다.

#### GET /v1/chats
- Tag: Chat
- Summary: 채팅방 목록 조회
- Method: `GET`
- Path: `/v1/chats`
- OperationId: `get-v1-chats`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> application/json: ChatRoomListResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: -
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: `Features/Chat/ChatRootView.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P3
- 비고: -

#### POST /v1/chats/{room_id}
- Tag: Chat
- Summary: 채팅 보내기
- Method: `POST`
- Path: `/v1/chats/{room_id}`
- OperationId: `post-v1-chats-room_id`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: room_id (string, required)
- Query Parameter: -
- Request Body: application/json: inline object {content, files}
- Response DTO: 200 -> application/json: ChatResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404, 445
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: `Features/Chat/ChatRootView.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P3
- 비고: -

#### GET /v1/chats/{room_id}
- Tag: Chat
- Summary: 채팅내역 목록 조회
- Method: `GET`
- Path: `/v1/chats/{room_id}`
- OperationId: `get-v1-chats-room_id`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: room_id (string, required)
- Query Parameter: next (string, optional)
- Request Body: -
- Response DTO: 200 -> application/json: ChatListResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404, 445
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: `Features/Chat/ChatRootView.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P3
- 비고: -

#### POST /v1/chats/{room_id}/files
- Tag: Chat
- Summary: 채팅방 파일 업로드
- Method: `POST`
- Path: `/v1/chats/{room_id}/files`
- OperationId: `post-v1-chats-room_id-files`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: room_id (string, required)
- Query Parameter: -
- Request Body: multipart/form-data: FileRequestDTO (inline object {files})
- Response DTO: 200 -> application/json: ChatFileResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404, 445
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: `Features/Chat/ChatRootView.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P3
- 비고: Socket.IO URL은 Swagger 규칙대로 별도 구성해야 한다: http://{baseURL}:{port}/chats-{room_id}

### Order
#### POST /v1/orders
- Tag: Order
- Summary: 주문 생성
- Method: `POST`
- Path: `/v1/orders`
- OperationId: `create-order`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: application/json: OrderCreateRequestDTO (-)
- Response DTO: 200 -> application/json: OrderCreateResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/OrderRemoteDataSource.swift`, `Data/Repositories/OrderRepositoryImpl.swift`, `Features/Checkout/CheckoutInteractor.swift`, `Features/Checkout/CheckoutPresenter.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P1
- 비고: order_code를 CreatedOrder에 그대로 보존한다.

#### GET /v1/orders
- Tag: Order
- Summary: 주문 내역 조회
- Method: `GET`
- Path: `/v1/orders`
- OperationId: `get-v1-orders`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> application/json: inline object {data}
- 주요 성공 응답: 200
- 주요 에러 응답: -
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/OrderRemoteDataSource.swift`, `Data/Repositories/OrderRepositoryImpl.swift`, `Features/Order/OrderInteractor.swift`, `Features/Order/OrderPresenter.swift`
- Swagger와 mismatch 여부: Repository 인터페이스는 cursor/filter를 받지만 Swagger는 query 없는 GET /v1/orders만 정의한다. RemoteDataSource는 Swagger대로 query를 보내지 않는다.
- 수정 필요 여부: 아니오
- 구현 우선순위: P1
- 비고: -

#### PUT /v1/orders/{order_code}
- Tag: Order
- Summary: 주문 상태 변경
- Method: `PUT`
- Path: `/v1/orders/{order_code}`
- OperationId: `update-order-status`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: order_code (string, required)
- Query Parameter: -
- Request Body: application/json: inline object {nextStatus}
- Response DTO: 200 -> 주문 상태 변경 성공
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404, 445
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: 일반 사용자 앱에서 직접 호출할 화면 정책이 아직 없다.

### Payment
#### POST /v1/payments/validation
- Tag: Payment
- Summary: 결제 영수증 검증
- Method: `POST`
- Path: `/v1/payments/validation`
- OperationId: `post-v1-payments-validation`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: application/json: inline object {imp_uid}
- Response DTO: 200 -> application/json: ReceiptOrderResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404, 409, 445
- iOS 현재 구현 여부: 부분 구현
- 현재 구현 파일: `Data/DTOs/Order/PaymentReceiptResponseDTO.swift`, `Data/Remote/OrderRemoteDataSource.swift`, `Data/Repositories/OrderRepositoryImpl.swift`, `Domain/Repositories/OrderRepository.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P1
- 비고: Swagger body(imp_uid)와 DTO/Repository는 연결했지만 실제 PortOne 성공 후 호출하는 UI bridge는 아직 남아 있다.

#### GET /v1/payments/{order_code}
- Tag: Payment
- Summary: 결제 영수증 조회
- Method: `GET`
- Path: `/v1/payments/{order_code}`
- OperationId: `get-v1-payments-order_code`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: order_code (string, required)
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> application/json: PaymentResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 404, 445
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/DTOs/Order/PaymentReceiptResponseDTO.swift`, `Data/Remote/OrderRemoteDataSource.swift`, `Data/Repositories/OrderRepositoryImpl.swift`, `Data/Mappers/OrderMapper.swift`
- Swagger와 mismatch 여부: Swagger는 paid_at required로 적혀 있으나 실제 payload에는 paidAt도 존재할 수 있어 dual-key decoding을 적용했다.
- 수정 필요 여부: 아니오
- 구현 우선순위: P1
- 비고: -

### Review
#### POST /v1/stores/{store_id}/reviews/files
- Tag: Review
- Summary: 파일 업로드
- Method: `POST`
- Path: `/v1/stores/{store_id}/reviews/files`
- OperationId: `post-v1-store-store_id-reviews-files`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: store_id (string, required)
- Query Parameter: -
- Request Body: multipart/form-data: inline object {files}
- Response DTO: 200 -> application/json: ReviewImageResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: -

#### POST /v1/stores/{store_id}/reviews
- Tag: Review
- Summary: 리뷰 작성
- Method: `POST`
- Path: `/v1/stores/{store_id}/reviews`
- OperationId: `post-v1-store-store_id-reviews`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: store_id (string, required)
- Query Parameter: -
- Request Body: application/json: ReviewCreateRequestDTO (inline object {content, rating, review_image_urls, order_code})
- Response DTO: 200 -> application/json: UserReviewResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404, 409, 445
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: 리뷰 작성 화면/Repository가 아직 없다.

#### GET /v1/stores/{store_id}/reviews
- Tag: Review
- Summary: 리뷰 목록 조회
- Method: `GET`
- Path: `/v1/stores/{store_id}/reviews`
- OperationId: `get-v1-store-store_id-reviews`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: store_id (string, required)
- Query Parameter: next (string, optional), limit (integer, optional), order_by (string, optional)
- Request Body: -
- Response DTO: 200 -> application/json: ReviewListResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/ReviewRemoteDataSource.swift`, `Data/Repositories/ReviewRepositoryImpl.swift`, `Features/StoreDetail/StoreDetailInteractor.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P2
- 비고: -

#### GET /v1/stores/{store_id}/reviews/{review_id}
- Tag: Review
- Summary: 리뷰 상세 조회
- Method: `GET`
- Path: `/v1/stores/{store_id}/reviews/{review_id}`
- OperationId: `get-v1-store-store_id-reviews-review_id`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: store_id (string, required), review_id (string, required)
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> application/json: UserReviewResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 404
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: -

#### PUT /v1/stores/{store_id}/reviews/{review_id}
- Tag: Review
- Summary: 리뷰 수정
- Method: `PUT`
- Path: `/v1/stores/{store_id}/reviews/{review_id}`
- OperationId: `put-v1-store-store_id-reviews-review_id`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: store_id (string, required), review_id (string, required)
- Query Parameter: -
- Request Body: application/json: ReviewUpdateRequestDTO (inline object {content, rating, review_image_urls})
- Response DTO: 200 -> application/json: UserReviewResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404, 445
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: -

#### DELETE /v1/stores/{store_id}/reviews/{review_id}
- Tag: Review
- Summary: 리뷰 삭제
- Method: `DELETE`
- Path: `/v1/stores/{store_id}/reviews/{review_id}`
- OperationId: `delete-v1-store-store_id-reviews-review_id`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: store_id (string, required), review_id (string, required)
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> 리뷰 삭제 성공
- 주요 성공 응답: 200
- 주요 에러 응답: 404, 445
- iOS 현재 구현 여부: 미구현
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 예
- 구현 우선순위: P2
- 비고: Swagger 설명대로 삭제 후 주문 내역 rating이 0으로 보일 수 있다는 정책을 UI에 반영해야 한다.

#### GET /v1/stores/{store_id}/reviews/reviews-ratings
- Tag: Review
- Summary: 별점별 리뷰 개수 조회
- Method: `GET`
- Path: `/v1/stores/{store_id}/reviews/reviews-ratings`
- OperationId: `get-v1-store-store_id-reviews-ratings`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: store_id (string, required)
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> application/json: ReviewRatingListResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 404
- iOS 현재 구현 여부: 구현 완료
- 현재 구현 파일: `Data/Remote/ReviewRemoteDataSource.swift`, `Data/Repositories/ReviewRepositoryImpl.swift`, `Features/StoreDetail/StoreDetailInteractor.swift`
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: P2
- 비고: -

### Banner
#### GET /v1/banners/main
- Tag: Banner
- Summary: 배너 목록 조회
- Method: `GET`
- Path: `/v1/banners/main`
- OperationId: `get-v1-banner-main`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> application/json: BannerListResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: -
- iOS 현재 구현 여부: 부분 구현
- 현재 구현 파일: `Data/Remote/BannerRemoteDataSource.swift`, `Data/Repositories/BannerRepositoryImpl.swift`, `Data/Mappers/BannerMapper.swift`, `Features/Home/HomeInteractor 2.swift`, `Features/Home/HomeRouter.swift`
- Swagger와 mismatch 여부: 배너 데이터 로딩과 상대경로 해석은 구현됐지만, 탭 시 웹뷰 라우팅과 출석 브리지는 아직 TODO다.
- 수정 필요 여부: 예
- 구현 우선순위: P1
- 비고: imageUrl, payload.value 상대경로는 BannerMapper에서 절대 URL로 정규화한다.

### Push
#### POST /v1/notifications/push
- Tag: Push
- Summary: 푸시알림 전송 테스트
- Method: `POST`
- Path: `/v1/notifications/push`
- OperationId: `post-v1-push-opponents`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: application/json: inline object {user_id, title, subtitle, body}
- Response DTO: 200 -> 푸시알림 전송성공
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404
- iOS 현재 구현 여부: 앱 범위 외
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: Out of scope
- 비고: 일반 사용자 앱에서 노출하지 않는다. deviceToken 업데이트만 우선 대상이다.

### Video
#### GET /v1/videos
- Tag: Video
- Summary: 비디오 목록 조회
- Method: `GET`
- Path: `/v1/videos`
- OperationId: `get-v1-videos`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: next (string, optional), limit (integer, optional)
- Request Body: -
- Response DTO: 200 -> application/json: VideoListResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: -
- iOS 현재 구현 여부: 앱 범위 외
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: Out of scope
- 비고: 현재 앱에 video surface가 없어 문서화만 한다.

#### GET /v1/videos/{video_id}/stream
- Tag: Video
- Summary: 스트리밍 URL 조회
- Method: `GET`
- Path: `/v1/videos/{video_id}/stream`
- OperationId: `get-v1-videos-video_id-stream`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: video_id (string, required)
- Query Parameter: -
- Request Body: -
- Response DTO: 200 -> application/json: StreamUrlResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 404
- iOS 현재 구현 여부: 앱 범위 외
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: Out of scope
- 비고: HLS stream_url/qualities URL은 추후 AVPlayer 연결 시 baseURL resolver를 재사용해야 한다.

#### POST /v1/videos/{video_id}/like
- Tag: Video
- Summary: 비디오 좋아요/좋아요 취소
- Method: `POST`
- Path: `/v1/videos/{video_id}/like`
- OperationId: `post-v1-videos-video_id-like`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: video_id (string, required)
- Query Parameter: -
- Request Body: application/json: inline object {like_status}
- Response DTO: 200 -> application/json: inline object {like_status}
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404
- iOS 현재 구현 여부: 앱 범위 외
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: Out of scope
- 비고: Video 화면 부재로 현재 MVP에서는 제외한다.

### Admin
#### POST /v1/stores/files
- Tag: Admin
- Summary: 가게 이미지 업로드
- Method: `POST`
- Path: `/v1/stores/files`
- OperationId: `post-v1-stores-files`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: multipart/form-data: inline object {files}
- Response DTO: 200 -> application/json: StoreFileResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400
- iOS 현재 구현 여부: 앱 범위 외
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: Out of scope
- 비고: Swagger 설명대로 컨텐츠 등록용 Admin 라우터. 일반 사용자 앱에 노출하지 않는다.

#### POST /v1/stores
- Tag: Admin
- Summary: 가게 등록
- Method: `POST`
- Path: `/v1/stores`
- OperationId: `post-v1-stores`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: application/json: StoreCreateRequestDTO (inline object {name, category, description, address, longitude, latitude, ...})
- Response DTO: 200 -> application/json: StoreDetailResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404
- iOS 현재 구현 여부: 앱 범위 외
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: Out of scope
- 비고: Admin 라우터.

#### PUT /v1/stores/{store_id}
- Tag: Admin
- Summary: 가게 정보 수정
- Method: `PUT`
- Path: `/v1/stores/{store_id}`
- OperationId: `-`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: store_id (string, required)
- Query Parameter: -
- Request Body: application/json: StoreCreateRequestDTO (inline object {name, category, description, address, longitude, latitude, ...})
- Response DTO: 200 -> application/json: StoreDetailResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404, 445
- iOS 현재 구현 여부: 앱 범위 외
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: Out of scope
- 비고: Admin 라우터.

#### POST /v1/menus/image
- Tag: Admin
- Summary: 메뉴 이미지 업로드
- Method: `POST`
- Path: `/v1/menus/image`
- OperationId: `post-v1-menus-files`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: -
- Query Parameter: -
- Request Body: multipart/form-data: MenuFileRequestDTO (inline object {menu_image})
- Response DTO: 200 -> application/json: MenuFileResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400
- iOS 현재 구현 여부: 앱 범위 외
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: Out of scope
- 비고: Admin 라우터.

#### POST /v1/menus/stores/{store_id}
- Tag: Admin
- Summary: 메뉴 등록
- Method: `POST`
- Path: `/v1/menus/stores/{store_id}`
- OperationId: `post-v1-create-menu-for-store`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: store_id (string, required)
- Query Parameter: -
- Request Body: application/json: MenuCreateRequestDTO (MenuCreateRequestDTO)
- Response DTO: 200 -> application/json: MenuResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404
- iOS 현재 구현 여부: 앱 범위 외
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: Out of scope
- 비고: Admin 라우터.

#### PUT /v1/menus/{menu_id}
- Tag: Admin
- Summary: 메뉴 정보 수정
- Method: `PUT`
- Path: `/v1/menus/{menu_id}`
- OperationId: `put-v1-update-menu`
- Authorization 필요 여부: 예
- SeSACKey 필요 여부: 예
- 추가 Header: -
- Path Parameter: menu_id (string, required)
- Query Parameter: -
- Request Body: application/json: MenuUpdateRequestDTO (MenuUpdateRequestDTO)
- Response DTO: 200 -> application/json: MenuResponseDTO
- 주요 성공 응답: 200
- 주요 에러 응답: 400, 404, 445
- iOS 현재 구현 여부: 앱 범위 외
- 현재 구현 파일: -
- Swagger와 mismatch 여부: 없음
- 수정 필요 여부: 아니오
- 구현 우선순위: Out of scope
- 비고: Admin 라우터.

## 3. DTO Mapping Notes
### Auth/User
- LoginDTO: `user_id`, `email`, `nick`, `profileImage?`, `accessToken`, `refreshToken`
- JoinResponseDTO: `user_id`, `email`, `nick`, `accessToken`, `refreshToken`
- RefreshTokenResponseDTO: `accessToken`, `refreshToken`
- MyInfoResponseDTO: `user_id`, `email`, `nick`, `profileImage?`, `phoneNum?`
### Store
- StoreSummaryDTO.store_image_urls 설명에는 “첫 번째 이미지만 포함”이라고 되어 있다.
- 따라서 홈/목록 카드에서 3장 이미지가 항상 온다고 가정하면 안 된다.
- 목록 카드 UI는 이미지 0/1/2/3개 이상에 따라 안전하게 분기해야 한다.
- StoreDetailResponseDTO.store_image_urls는 가게 대표 이미지 배열이므로 상세 화면에서 여러 장 표시 가능성이 있다.
- 상대경로 예: `/data/stores/...` 는 baseURL과 결합해야 한다.
### Banner
- BannerResponseDTO.imageUrl은 상대경로 가능.
- payload.type은 현재 `WEBVIEW`.
- payload.value가 `/event-application` 같은 상대경로일 수 있으므로 web baseURL과 결합해야 한다.
- 웹뷰 로드 시 `SeSACKey` 필요.
- 출석 이벤트 bridge: `click_attendance_button`, `complete_attendance`, `requestAttendance(accessToken)`
### Community
- PostSummaryPaginationResponseDTO: `data`, `next_cursor`
- PostSummaryResponseDTO: `post_id`, `category`, `title`, `content`, `store?`, `geolocation`, `creator`, `files`, `is_like`, `like_count`, `createdAt`, `updatedAt`
- PostResponseDTO: `comments` 포함
- 댓글 replies는 1-depth까지만 허용.
### Order
- OrderCreateRequestDTO: `store_id`, `order_menu_list[{menu_id, quantity}]`, `total_price`
- OrderCreateResponseDTO: `order_id`, `order_code`, `total_price`
- order_code는 PortOne/아임포트 결제 `merchant_uid`로 사용한다.
- GET /v1/orders 응답은 `{ data: [OrderWithStatusResponseDTO] }`.
- order_status_timeline 매핑을 정확히 해야 한다.
### Payment
- POST /v1/payments/validation body는 `imp_uid`만 필요하다.
- 이 API 성공 후 주문 상태가 `PENDING_APPROVAL`로 변경된다.
- GET /v1/payments/{order_code}는 PaymentResponseDTO를 따른다.
- PaymentResponseDTO required에는 `paid_at`이 있으나 properties에는 `paidAt`도 존재한다. 현재 코드는 두 키를 모두 decode 하도록 보강했다.
### Review
- 리뷰 작성은 결제가 완료된 주문만 가능.
- ReviewCreateRequestDTO: `content`, `rating`, `review_image_urls?`, `order_code`
- 리뷰 이미지 업로드는 multipart files 선행 후 path 배열을 `review_image_urls`로 전달한다.
- 리뷰 삭제 시 주문 내역에서 rating이 0으로 표시된다는 설명을 문서에 남긴다.
### Chat
- REST API와 Socket.IO URL을 분리 정리해야 한다.
- 채팅 파일 업로드 후 files path 배열을 채팅 전송 body에 넣는다.
### Video
- HLS 기반.
- GET /v1/videos/{video_id}/stream 응답의 `stream_url` 또는 `qualities[].url`을 AVPlayer에 전달한다.
- stream_url, qualities, subtitles는 상대경로/토큰 포함 URL일 수 있으므로 baseURL 결합 규칙을 명확히 해야 한다.
- 스트리밍 파일은 URL token으로 접근하며, 그 외 API/썸네일/자막은 Authorization + SeSACKey 필요하다는 설명을 문서화한다.
### Admin
- Swagger 설명상 “Admin에 등록된 라우터는 구현 라우터가 아닌 컨텐츠 등록용 라우터”다.
- 일반 사용자 앱에 직접 노출하지 않는다.
- 문서에는 정리하되 iOS MVP 구현 우선순위는 Out of scope 또는 P3로 둔다.

## 4. iOS Implementation Audit
### 감사 범위
#### Network/Core
- `Core/Network/RequestBuilder.swift`: SeSACKey 기본 주입, access token / refresh token header 중앙화.
- `Core/Network/APIClient.swift`: 419/401 refresh 후 1회 재시도, decode 실패 payload 로그 추가.
- `Core/Network/TokenRefreshCoordinator.swift`: single-flight refresh, 실패 시 세션 무효화.
- `Core/Platform/Image/AuthorizedFileURLResolver.swift`: `/data/...`, `/videos/...`, `/event-application` 상대경로를 안전하게 절대 URL로 변환.

#### RemoteDataSource / Repository
- `Data/Remote/AuthRemoteDataSource.swift`: 로그인/회원가입/프로필 조회/로그아웃 구현.
- `Data/Remote/BannerRemoteDataSource.swift`: 메인 배너 조회 구현.
- `Data/Remote/StoreRemoteDataSource.swift`: 홈/상세/좋아요/검색/좋아요 목록까지 커버. likes/me는 이번 턴에 추가.
- `Data/Remote/CommunityRemoteDataSource.swift`: 글/댓글/좋아요/목록/검색 구현. 파일 업로드/삭제/내 글/내 좋아요는 미구현.
- `Data/Remote/OrderRemoteDataSource.swift`: 주문 생성/목록/영수증 조회 + imp_uid 결제 검증까지 보강.
- `Data/Remote/ReviewRemoteDataSource.swift`: 리뷰 목록/별점 분포만 구현.
- `ChatRemoteDataSource`, `VideoRemoteDataSource`는 아직 없다.

#### Feature 연결
- `App/Root/RootScene.swift`, `App/Bootstrap/SessionRestorer.swift`: 비로그인 시 AuthGateView, 로그인 세션 복원 시 프로필 조회.
- `Features/Home/HomeInteractor 2.swift`: 주변 가게/인기 가게/인기 검색어/배너를 병렬 로드.
- `Features/Home/HomeRouter.swift`: 배너/검색 라우트가 아직 TODO라 배너 API는 부분 구현 상태.
- `Features/Checkout/CheckoutInteractor.swift`: 주문 생성 호출은 연결돼 있지만 결제 검증 API 호출 트리거는 TODO.
- `Features/Chat/ChatRootView.swift`: placeholder 수준이라 Chat API는 전부 미구현.
- `Shared/Component/StoreCard.swift`: 주변 가게 카드 이미지 0/1/2/3장 이상 레이아웃 안정화.

### 실응답 확인 결과
- Runtime /v1/users/login, /v1/users/join 응답은 Swagger의 LoginDTO/JoinResponseDTO와 동일하게 user_id, email, nick, accessToken, refreshToken을 내려준다.
- Runtime /v1/users/me/profile 응답은 profileImage, phoneNum 같은 optional 필드를 값이 없으면 생략한다.
- Runtime /v1/banners/main 응답은 imageUrl, payload.value 모두 상대경로를 포함하며 payload.type은 현재 WEBVIEW다.
- Runtime /v1/stores 응답은 store_image_urls가 현재 2개인 케이스가 많다. Swagger 설명처럼 첫 번째 이미지만 온다고 가정하면 안 되고, 3장 고정 렌더링도 금지다.
- Runtime /v1/orders 응답은 현재 { data: [] } 형태였다. order list는 next_cursor 없이 data 배열만 오는 케이스를 처리해야 한다.
- Runtime /v1/auth/refresh 응답은 accessToken, refreshToken을 모두 내려준다.

#### 2026-04-26 P1/P2 추가 실서버 확인
- `POST /v1/posts/files`: multipart field name `files`로 200 성공. 응답 field는 `files`, 값은 `/data/posts/...` 상대경로 배열이다.
- `POST /v1/stores/{store_id}/reviews/files`: multipart field name `files`로 200 성공. 응답 field는 Swagger와 동일한 `review_image_urls`, 값은 `/data/reviews/...` 상대경로 배열이며 리뷰 작성/수정 body에는 이 path 배열을 그대로 넣는다.
- `GET /v1/posts/users/{user_id}`: 응답은 `{ data, next_cursor }`. 마지막 페이지 종료값은 `"0"`으로 확인됐다. `next` field는 내려오지 않았다.
- `GET /v1/posts/likes/me`: 빈 목록 응답은 `{ "data": [], "next_cursor": "0" }`.
- `GET /v1/stores/reviews/users/{user_id}`: 빈 목록 응답은 `{ "data": [], "next_cursor": "0" }`. sampled runtime에서는 실제 리뷰가 있는 사용자 케이스를 확보하지 못해 `rating`/`review_image_urls` 비어 있지 않은 응답은 추가 확인이 필요하다.
- `POST /v1/stores/{store_id}/reviews`: 존재하지 않는 `order_code`는 404 `{ "message": "주문번호를 다시 확인해주세요." }`.
- `GET/PUT/DELETE /v1/stores/{store_id}/reviews/{review_id}`: 유효한 ObjectId 형식이지만 존재하지 않는 review_id는 404 `{ "message": "리뷰를 찾을 수 없습니다." }`. ObjectId 형식이 아닌 review_id는 서버가 500 `{ "message": "ServerError" }`를 반환하므로 클라이언트는 서버 메시지를 그대로 노출하지 않는 편이 안전하다.
- `POST /v1/payments/validation`: 존재하지 않는 `imp_uid`는 400 `{ "message": "유효하지 않은 결제건입니다." }`. 400 응답 message 보존을 위해 HTTPStatusMapper는 400/422를 `.abnormalRequest(message:)`로 매핑한다.
- Community 삭제/댓글 수정/삭제: 성공 응답은 body 없는 200. 비소유자 요청은 445와 `{ "message": "게시글 삭제 권한이 없습니다." }`, `{ "message": "댓글 수정 권한이 없습니다." }`, `{ "message": "댓글 삭제 권한이 없습니다." }`를 반환한다. 없는 게시글/댓글 계열은 404와 `{ "message": "게시글을 찾을 수 없습니다." }`를 반환한다.

### 구현 상태 집계
- 구현 완료: 26
- 부분 구현: 4
- 미구현: 21
- 앱 범위 외: 12

### 기능별 판정 메모
- Auth는 로그인/회원가입/소셜 로그인/세션 복원/refresh/logout까지 P0 범위가 연결돼 있다. Google backend endpoint는 Swagger에 없어 unsupported로 처리한다.
- Home/Store는 배너/주변 가게/인기 가게/인기 검색어/상세/좋아요까지 연결됐고, store image count mismatch는 UI 분기로 보강했다.
- Order/Payment는 주문 생성/목록/영수증 조회와 결제 성공 callback의 `imp_uid` 검증 호출까지 연결돼 있다.
- Community는 파일 업로드, 삭제, 내 글/내 좋아요 조회, 댓글 수정/삭제까지 P2 범위가 연결돼 있다.
- Review는 목록/별점 분포와 작성/수정/삭제/파일 업로드/내 리뷰 목록까지 P2 범위가 연결돼 있다. 단, 리뷰 작성 성공/409/445는 결제 완료 주문 데이터가 필요해 실서버에서 추가 확인이 필요하다.
- Chat/Video/Admin/Push는 현재 MVP 범위 밖이거나 placeholder 수준이다.
