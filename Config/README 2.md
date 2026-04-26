Pikko local auth setup

1. Copy `Config/AuthSecrets.example.xcconfig` to `Config/AuthSecrets.xcconfig` or `Config/LocalSecrets.xcconfig`.
2. Fill in these values locally:
   - `KAKAO_NATIVE_APP_KEY`
   - `GOOGLE_IOS_CLIENT_ID`
   - `GOOGLE_REVERSED_CLIENT_ID`
   - `PIKKO_BASE_URL`
   - `PIKKO_SESAC_KEY`
   - For `PIKKO_BASE_URL`, do not write `http://...` directly in xcconfig.
   - Use:
     `PIKKO_URL_SLASH = /`
     `PIKKO_BASE_URL = http:$(PIKKO_URL_SLASH)$(PIKKO_URL_SLASH)pickup.sesac.kr:42678/`
   - `http://pickup.sesac.kr:42678` and `http://pickup.sesac.kr:42678/` both work at runtime.
3. Keep `Config/AuthSecrets.xcconfig` and `Config/LocalSecrets.xcconfig` out of git. `.gitignore` already excludes them.
4. `Config/GoogleService-Info.plist` is optional for the current client-ID based Google Sign-In flow.
   - If another SDK flow requires it later, place the real file at `Config/GoogleService-Info.plist`.
   - Do not commit the real plist.
5. Regenerate the Xcode project after config changes:
   - `xcodegen generate`
6. Apple Sign In still requires local developer portal validation:
   - Verify the app bundle identifier.
   - Verify the `Sign in with Apple` capability is enabled for the app ID.
   - Verify provisioning and release signing settings outside this repository.
7. Release/CI secret injection is still a TODO. The current repository only documents local development setup.
8. Runtime guardrails:
   - Missing or invalid `PIKKO_BASE_URL` stops request creation and surfaces a configuration error instead of falling back to `http://v1/...`.
   - Missing `PIKKO_SESAC_KEY` stops protected API calls before the request is sent.
   - `$(PIKKO_BASE_URL)`, `<base_url>`, `v1`, `/v1`, and `http://v1` are treated as invalid.
9. Info.plist exposure:
   - The app keeps the existing `PIKKO_BASE_URL` / `PIKKO_SESAC_KEY` keys and also exposes camel-case aliases:
     `PIKKOBaseURL`, `PIKKOSeSACKey`, `KakaoNativeAppKey`, `GoogleIOSClientID`, `GoogleReversedClientID`.
   - `AppConfiguration` reads both forms, so xcconfig -> Build Settings -> Info.plist -> runtime stays aligned.
10. ATS exception policy:
   - `Config/Pikko-Info.plist` allows insecure HTTP loads only for `pickup.sesac.kr`.
   - This is limited to the current training server that responds on `http://pickup.sesac.kr:42678/`.
   - Do not widen this to `NSAllowsArbitraryLoads`.
   - Replace this exception with HTTPS before production release if the backend supports TLS.
11. App Review notes:
   - If review requires authenticated flows, prepare review notes with a test account or keep guest browsing available.
   - `Sign in with Apple` capability is already declared in `Config/Pikko.entitlements`, but the App ID and signing assets still need to be verified in the Apple Developer portal.
12. Remaining TODOs:
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
