# Pikko iOS HLS 스트리밍 실패 케이스 정리 및 서버 확인 요청

## 1. 문의 목적

Pikko iOS 클라이언트에서 영상 목록 API, Stream URL 발급 API, 썸네일 이미지 요청은 정상 동작합니다. 그러나 Stream API가 반환한 실제 HLS `.m3u8` URL에 접근하면 모든 테스트된 인증 조합에서 HLS playlist가 아닌 JSON 오류 응답이 반환되어 영상 재생이 실패합니다.

본 문서는 클라이언트에서 검증한 요청 형태, 헤더, 응답, 현재 결론을 정리하여 서버/API 측에서 HLS URL, 토큰, 리소스 배포, 라우팅, 인증 정책을 확인할 수 있도록 전달하기 위한 자료입니다.

## 2. 테스트 대상 정보

| 항목 | 값 |
| --- | --- |
| `video_id` | `695b5b0eea9356dcee04dbfd` |
| 비디오 리소스/path | `pickup_video_5` |
| API origin | `http://pickup.sesac.kr:42678` |
| Stream API path | `GET /v1/videos/695b5b0eea9356dcee04dbfd/stream` |

Stream API 요청 헤더:

```http
Authorization: Bearer <redacted>
SesacKey: <redacted>
```

Stream API 결과:

```text
status=200
response keys include: qualities, stream_url, subtitles, video_id
```

Stream API에서 반환된 HLS URL path:

```text
/videos/stream/pickup_video_5/master.m3u8?token=<redacted>
/videos/stream/pickup_video_5/1080p/index.m3u8?token=<redacted>
/videos/stream/pickup_video_5/720p/index.m3u8?token=<redacted>
/videos/stream/pickup_video_5/480p/index.m3u8?token=<redacted>
```

클라이언트에서 해석한 HLS URL 구조:

```text
scheme=http
host=pickup.sesac.kr
port=42678
path=/videos/stream/pickup_video_5/master.m3u8
queryKeys=token
tokenLengthPreserved=true
strategy=originPlusRawPathAndQuery
```

해석된 전체 URL 형태:

```text
http://pickup.sesac.kr:42678/videos/stream/pickup_video_5/master.m3u8?token=<redacted>
```

## 3. 클라이언트에서 확인 완료된 사항

아래 항목은 iOS 클라이언트에서 확인 완료했습니다.

| 확인 항목 | 결과 |
| --- | --- |
| HLS URL에 `token` query 존재 | 확인됨 |
| URL 해석 후 token 길이 보존 | 확인됨 |
| raw path 보존 | 확인됨 |
| raw query 보존 | 확인됨 |
| 상대 HLS URL을 API origin 기준으로 해석 | 확인됨 |
| HLS GET 요청에 `Content-Type` 추가 여부 | 추가하지 않음 |
| HLS probe 세션 | `URLSession` ephemeral 사용 |
| 보호 이미지 요청과 HLS 요청의 보호 리소스 헤더 이름 비교 | 일치 |
| 보호 이미지/HLS 헤더 이름 | `Authorization`, `SesacKey` |
| `apiKeyLengthMatches` | `true` |
| `authorizationExistsMatches` | `true` |

헤더 비교 로그:

```text
DEBUG [HLSAuthDebug] compare image/protected-resource headers vs HLS headers imageAuthHasAuthorization=true imageAuthHasSeSACKey=true imageAuthHeaderNames=Authorization,SesacKey hlsAuthHasAuthorization=true hlsAuthHasSeSACKey=true hlsAuthHeaderNames=Authorization,SesacKey apiKeyLengthMatches=true authorizationExistsMatches=true
```

보호 이미지 요청은 동일 origin에서 `Authorization + SesacKey` 조합으로 성공합니다.

```text
DEBUG Image request completed. url=http://pickup.sesac.kr:42678/v1/data/videos/pickup_video_5.jpg status=200 hasAuthorization=true hasSesacKey=true
```

따라서 현재 관찰 기준으로는 access token 또는 `SesacKey` 값이 전체적으로 잘못되었거나 만료된 상태라고 보기 어렵습니다.

## 4. 정상 동작하는 요청

### 4-1. 영상 목록 API

Request:

```http
GET /v1/videos?limit=20
Host: pickup.sesac.kr:42678
```

Headers:

```http
Authorization: Bearer <redacted>
SesacKey: <redacted>
```

Result:

```text
status=200
list count=5
```

Meaning:

```text
영상 목록 API는 정상 응답합니다. 기본 API origin 접근과 API 인증 흐름은 동작합니다.
```

### 4-2. Stream URL 발급 API

Request:

```http
GET /v1/videos/695b5b0eea9356dcee04dbfd/stream
Host: pickup.sesac.kr:42678
```

Headers:

```http
Authorization: Bearer <redacted>
SesacKey: <redacted>
```

Result:

```text
status=200
response keys include: qualities, stream_url, subtitles, video_id
stream_url and qualities returned
```

Meaning:

```text
Stream API는 정상적으로 token query가 포함된 HLS URL을 발급합니다.
발급 API 자체의 Authorization/SesacKey 인증은 통과합니다.
```

### 4-3. 썸네일 이미지 요청

Request:

```http
GET /v1/data/videos/pickup_video_5.jpg
Host: pickup.sesac.kr:42678
```

Headers:

```http
Authorization: Bearer <redacted>
SesacKey: <redacted>
```

Result:

```text
status=200
```

실제 확인 로그:

```text
DEBUG Image request completed. url=http://pickup.sesac.kr:42678/v1/data/videos/pickup_video_5.jpg status=200 hasAuthorization=true hasSesacKey=true
```

Meaning:

```text
동일 서버/origin의 보호 이미지 리소스는 Authorization + SesacKey 조합을 정상 수락합니다.
따라서 해당 Authorization 또는 SesacKey가 보호 이미지 리소스 기준으로는 유효합니다.
```

## 5. 실패하는 HLS 요청 케이스

### 5-1. 케이스 A: HLS token only, no headers → 420

Request:

```http
GET /videos/stream/pickup_video_5/master.m3u8?token=<redacted>
Host: pickup.sesac.kr:42678
```

Headers:

```text
Authorization: none
SesacKey: none
Content-Type: none
```

Result:

```text
status=420
contentType=application/json; charset=utf-8
bodyType=json
classification=hlsRequiresServiceHeader
```

Actual observed message:

```text
message=This service sesac_memolease only
```

Interpretation:

```text
HLS token query만으로는 HLS master playlist에 접근할 수 없습니다.
서버가 서비스/테넌트/API key 계열의 추가 조건을 요구하거나, 해당 HLS 라우트가 다른 서비스 정책으로 처리되는 것으로 보입니다.
```

### 5-2. 케이스 B: HLS token + SesacKey → 444

Request:

```http
GET /videos/stream/pickup_video_5/master.m3u8?token=<redacted>
Host: pickup.sesac.kr:42678
```

Headers:

```http
Authorization: none
SesacKey: <redacted>
Content-Type: none
```

Result:

```text
status=444
contentType=application/json; charset=utf-8
bodyType=json
classification=hlsUnauthorizedWithPartialHeaders
```

Actual observed message:

```text
message=돌아가 여긴 자네가 올 곳이 아니야.
```

Interpretation:

```text
SesacKey를 추가하면 420 서비스 헤더 요구 응답은 사라지지만, 서버는 여전히 HLS 요청을 444로 거부합니다.
이는 token + SesacKey 조합만으로는 현재 HLS endpoint 인증 조건을 만족하지 못한다는 의미입니다.
```

### 5-3. 케이스 C: HLS token + Authorization + SesacKey → 444

Request:

```http
GET /videos/stream/pickup_video_5/master.m3u8?token=<redacted>
Host: pickup.sesac.kr:42678
```

Headers:

```http
Authorization: Bearer <redacted>
SesacKey: <redacted>
Content-Type: none
```

Result:

```text
status=444
contentType=application/json; charset=utf-8
bodyType=json
classification=hlsUnauthorizedEvenWithProtectedHeaders
```

Actual observed message:

```text
message=돌아가 여긴 자네가 올 곳이 아니야.
```

Interpretation:

```text
Stream API 및 보호 이미지 요청에 사용한 Authorization + SesacKey를 HLS 요청에 함께 전달해도 HLS endpoint는 444로 거부합니다.
따라서 현재 실패는 단순히 Authorization 또는 SesacKey 헤더 누락 때문으로 보기 어렵습니다.
```

### 5-4. 케이스 D: HLS token + image-equivalent protected resource headers → 444

Request:

```http
GET /videos/stream/pickup_video_5/master.m3u8?token=<redacted>
Host: pickup.sesac.kr:42678
```

Headers:

```http
Authorization: Bearer <redacted>
SesacKey: <redacted>
Content-Type: none
```

Result:

```text
status=444
contentType=application/json; charset=utf-8
bodyType=json
classification=hlsRejectedByServerEvenWithImageEquivalentHeaders
classification alternate=hlsUnauthorizedEvenWithProtectedHeaders
```

Actual observed message:

```text
message=돌아가 여긴 자네가 올 곳이 아니야.
```

Interpretation:

```text
보호 이미지 요청과 동일한 헤더 이름 및 Authorization 존재 여부를 맞춘 상태에서도 HLS endpoint가 444를 반환합니다.
서버 측 HLS 라우트, 토큰 검증, 리소스 정책 또는 서비스 설정이 보호 이미지 라우트와 다르게 적용되는지 확인이 필요합니다.
```

## 6. 썸네일은 보이지만 영상이 재생되지 않는 이유에 대한 현재 해석

썸네일과 HLS는 같은 origin을 사용하지만 서로 다른 path와 서버 라우팅을 사용합니다.

| 리소스 | 요청 path | 현재 결과 |
| --- | --- | --- |
| 썸네일 이미지 | `/v1/data/videos/pickup_video_5.jpg` | `200` |
| HLS master playlist | `/videos/stream/pickup_video_5/master.m3u8` | `444` 또는 조건에 따라 `420` |

현재 해석:

```text
썸네일 요청은 /v1/data/videos/pickup_video_5.jpg 보호 이미지 라우트를 사용합니다.
HLS 요청은 /videos/stream/pickup_video_5/master.m3u8 스트리밍 라우트를 사용합니다.
두 요청은 서로 다른 서버 라우팅, 인증 미들웨어, 리소스 매핑, 서비스 정책을 통과할 가능성이 있습니다.

따라서 썸네일 성공은 Authorization/SesacKey가 이미지 리소스에 대해 유효하다는 점은 증명하지만,
HLS URL, HLS token, HLS 리소스 매핑, HLS 라우팅 정책까지 유효하다는 점을 증명하지는 않습니다.
```

## 7. 현재 클라이언트 측 결론

현재까지의 검증 결과 기준 결론은 다음과 같습니다.

- 더 이상 URL construction 문제로 보기 어렵습니다.
- 더 이상 token query 보존 실패 문제로 보기 어렵습니다.
- 더 이상 raw path 또는 raw query 손실 문제로 보기 어렵습니다.
- 더 이상 `Authorization`/`SesacKey` 헤더 누락 문제로 보기 어렵습니다.
- HLS endpoint는 보호 이미지 요청과 동등한 인증 헤더를 포함해도 요청을 거부합니다.
- Stream URL을 한 번 refresh하여 새 tokenized HLS URL을 받아도, `Authorization + SesacKey` 조합에서 동일하게 444가 재현됩니다.
- 따라서 단순 token 만료 문제로 보기 어렵습니다.
- 클라이언트는 반복 실패 요청을 피하기 위해 추가 자동 retry를 억제합니다.

서버 측에서 HLS URL, token, resource deployment, route, auth policy를 확인해 주시기 바랍니다.

## 8. 서버에서 확인 요청드리는 항목

1. `/videos/stream/pickup_video_5/master.m3u8`가 올바른 HLS path인지 확인 부탁드립니다.
2. HLS path가 `/v1/videos/stream/...` 또는 다른 prefix를 사용해야 하는지 확인 부탁드립니다.
3. `pickup_video_5`의 `master.m3u8` 파일이 서버에 실제 존재하는지 확인 부탁드립니다.
4. 아래 variant playlist가 실제 존재하는지 확인 부탁드립니다.
   - `/videos/stream/pickup_video_5/1080p/index.m3u8`
   - `/videos/stream/pickup_video_5/720p/index.m3u8`
   - `/videos/stream/pickup_video_5/480p/index.m3u8`
5. media segment 파일들이 존재하며 master/variant playlist와 동일한 인증 정책을 사용하는지 확인 부탁드립니다.
6. Stream API가 생성한 token이 HLS server에서 유효한 token인지 확인 부탁드립니다.
7. HLS server가 Stream API와 동일한 JWT/token secret/service config를 사용하는지 확인 부탁드립니다.
8. token only 요청에서 `"This service sesac_memolease only"`가 반환되는 이유를 확인 부탁드립니다.
9. `Authorization + SesacKey + token` 요청에서 444가 반환되는 이유를 확인 부탁드립니다.
10. `"돌아가 여긴 자네가 올 곳이 아니야."` 메시지가 발생하는 정확한 서버 조건을 확인 부탁드립니다.
11. HLS 요청이 `Authorization + SesacKey + token query` 조합을 사용해야 하는지, 또는 다른 인증 조합을 사용해야 하는지 확인 부탁드립니다.
12. 서버에서 기대하는 API key 헤더 이름이 정확히 `SesacKey`인지 확인 부탁드립니다.
13. HLS master playlist, variant playlist, media segment 요청이 모두 동일한 헤더를 포함해야 하는지 확인 부탁드립니다.
14. `video_id=695b5b0eea9356dcee04dbfd` / `pickup_video_5`가 현재 재생 가능한 유효 샘플인지 확인 부탁드립니다.
15. 서버 측에서 동일 요청을 curl로 재현해 확인 부탁드립니다.

## 9. 서버 확인용 curl 형태

### 9-1. Stream API success example

```sh
curl -i "http://pickup.sesac.kr:42678/v1/videos/695b5b0eea9356dcee04dbfd/stream" \
  -H "Authorization: Bearer <redacted>" \
  -H "SesacKey: <redacted>"
```

Expected:

```text
200
stream_url and qualities returned
```

### 9-2. Thumbnail success example

```sh
curl -i "http://pickup.sesac.kr:42678/v1/data/videos/pickup_video_5.jpg" \
  -H "Authorization: Bearer <redacted>" \
  -H "SesacKey: <redacted>"
```

Expected:

```text
200 image response
```

### 9-3. HLS failing example

```sh
curl -i "http://pickup.sesac.kr:42678/videos/stream/pickup_video_5/master.m3u8?token=<redacted>" \
  -H "Authorization: Bearer <redacted>" \
  -H "SesacKey: <redacted>"
```

Actual:

```text
444
message=돌아가 여긴 자네가 올 곳이 아니야.
```

Expected if server is correctly configured:

```text
200
Content-Type: application/vnd.apple.mpegurl or equivalent
Body starts with #EXTM3U
```

## 10. 기대되는 정상 HLS 응답

정상 HLS master playlist 응답은 아래 조건을 만족해야 합니다.

- HTTP `200`
- HLS playlist content type
  - 예: `application/vnd.apple.mpegurl`
  - 또는 서버에서 사용하는 동등한 HLS playlist MIME type
- Body가 `#EXTM3U`로 시작
- master playlist인 경우 `#EXT-X-STREAM-INF` 포함
- variant playlist인 경우 media segment reference 포함

예상 응답 형태:

```text
HTTP/1.1 200 OK
Content-Type: application/vnd.apple.mpegurl

#EXTM3U
#EXT-X-STREAM-INF:...
...
```

## 11. 서버에 전달할 짧은 요약

```text
Pikko iOS에서 video_id=695b5b0eea9356dcee04dbfd / pickup_video_5 재생을 확인했습니다.

- Stream API: GET /v1/videos/695b5b0eea9356dcee04dbfd/stream → 200
- Thumbnail: GET /v1/data/videos/pickup_video_5.jpg + Authorization + SesacKey → 200
- HLS token only: GET /videos/stream/pickup_video_5/master.m3u8?token=<redacted> → 420, "This service sesac_memolease only"
- HLS token + SesacKey → 444, "돌아가 여긴 자네가 올 곳이 아니야."
- HLS token + Authorization + SesacKey → 444, "돌아가 여긴 자네가 올 곳이 아니야."
- 보호 이미지 요청과 HLS 요청의 인증 헤더 이름은 Authorization,SesacKey로 일치합니다.
- token query는 존재하고 URL 해석 후에도 길이/path/query가 보존됩니다.

클라이언트 측 URL 구성, token query 보존, Authorization/SesacKey 헤더 누락 문제는 아닌 것으로 확인했습니다.
서버 측 HLS path, token 검증, 리소스 배포, 라우팅, 서비스/auth policy 확인 부탁드립니다.
```

## 12. 부록: 원본 로그 발췌

아래는 공유 가능한 범위로 민감값을 제거한 핵심 로그 발췌입니다.

Stream API 200:

```text
DEBUG Stream API request. method=GET url=http://pickup.sesac.kr:42678/v1/videos/695b5b0eea9356dcee04dbfd/stream hasAuthorization=true hasSesacKey=true
DEBUG Stream API response. status=200 keys=qualities,stream_url,subtitles,video_id
```

VideoStreamDTO token preserved:

```text
DEBUG VideoStreamDTO decoded. video_id=695b5b0eea9356dcee04dbfd stream_url=/videos/stream/pickup_video_5/master.m3u8?token=<redacted> tokenQueryExists=true tokenLengthPreserved=true qualities=1080p,720p,480p
```

VideoURLResolve tokenLengthPreserved:

```text
DEBUG VideoURLResolve resolved HLS URL. scheme=http host=pickup.sesac.kr port=42678 path=/videos/stream/pickup_video_5/master.m3u8 queryKeys=token tokenLengthPreserved=true strategy=originPlusRawPathAndQuery
```

Image request 200:

```text
DEBUG Image request completed. url=http://pickup.sesac.kr:42678/v1/data/videos/pickup_video_5.jpg status=200 hasAuthorization=true hasSesacKey=true
```

HLS tokenOnly 420:

```text
DEBUG [HLSProbe] tokenOnly request. url=http://pickup.sesac.kr:42678/videos/stream/pickup_video_5/master.m3u8?token=<redacted> hasAuthorization=false hasSesacKey=false hasContentType=false
DEBUG [HLSProbe] tokenOnly response. status=420 contentType=application/json; charset=utf-8 bodyType=json message="This service sesac_memolease only" classification=hlsRequiresServiceHeader
```

HLS tokenPlusSeSACKey 444:

```text
DEBUG [HLSProbe] tokenPlusSeSACKey request. url=http://pickup.sesac.kr:42678/videos/stream/pickup_video_5/master.m3u8?token=<redacted> hasAuthorization=false hasSesacKey=true hasContentType=false
DEBUG [HLSProbe] tokenPlusSeSACKey response. status=444 contentType=application/json; charset=utf-8 bodyType=json message="돌아가 여긴 자네가 올 곳이 아니야." classification=hlsUnauthorizedWithPartialHeaders
```

HLS protected headers comparison:

```text
DEBUG [HLSAuthDebug] compare image/protected-resource headers vs HLS headers imageAuthHasAuthorization=true imageAuthHasSeSACKey=true imageAuthHeaderNames=Authorization,SesacKey hlsAuthHasAuthorization=true hlsAuthHasSeSACKey=true hlsAuthHeaderNames=Authorization,SesacKey apiKeyLengthMatches=true authorizationExistsMatches=true
```

HLS protected headers 444:

```text
DEBUG [HLSProbe] protectedHeaders request. url=http://pickup.sesac.kr:42678/videos/stream/pickup_video_5/master.m3u8?token=<redacted> hasAuthorization=true hasSesacKey=true hasContentType=false
DEBUG [HLSProbe] protectedHeaders response. status=444 contentType=application/json; charset=utf-8 bodyType=json message="돌아가 여긴 자네가 올 곳이 아니야." classification=hlsUnauthorizedEvenWithProtectedHeaders
```
