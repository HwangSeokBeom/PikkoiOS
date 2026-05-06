# Video Streaming Debug Notes

## Client behavior

`GET /v1/videos/{video_id}/stream` is an API request and must keep the normal API authentication headers: `Authorization` and `SeSACKey`.

Swagger previously implied token-only HLS playback, but the server requires SeSACKey header for HLS .m3u8 requests. Playback must use token query + SeSACKey header.

HLS playback uses the `stream_url` and `qualities[].url` values returned by the stream API for manifest playback, preserving the original query string token. The app injects only `SeSACKey` through `AVURLAssetHTTPHeaderFieldsKey` and does not add `Authorization` or `Content-Type` to HLS GET requests.

If the manifest probe receives JSON instead of an HLS playlist, the client classifies the response before creating the `AVPlayerItem`:

- `HTTP 200` with `application/vnd.apple.mpegurl`, `application/x-mpegURL`, `audio/mpegurl`, or a body containing `#EXTM3U`: valid HLS
- `HTTP 200` with `application/json`, or a body starting with `{`: invalid JSON response
- `HTTP 420` without `SeSACKey` and a later token + `SeSACKey` success: `hlsRequiresSeSACKeyHeader`
- `HTTP 420` with token + `SeSACKey`: `hlsServiceMismatchEvenWithSeSACKey`
- `HTTP 444`: `forbiddenByStreamServer`

When the probe classifies the token + `SeSACKey` response as `hlsServiceMismatchEvenWithSeSACKey` or `forbiddenByStreamServer`, the client stops quality fallback and shows:

> 영상 스트리밍 주소가 만료되었거나 서버 설정이 올바르지 않습니다. 다시 시도해 주세요.

Retrying the player calls `GET /v1/videos/{video_id}/stream` again to receive a fresh URL and token. It does not reuse the previous HLS URL.

## Server/API checks

If token + `SeSACKey` still returns JSON from the m3u8 URL, please verify:

1. `GET /v1/videos/{video_id}/stream` returns a `stream_url` token whose audience/service is for PickUp.
2. `/videos/stream/pickup_video_5/master.m3u8` returns `This service sesac_memolease only`.
3. The PickUp `SeSACKey`/API key and the HLS token validation service name are aligned.
4. `videoId=695b5b0eea9356dcee04dbfd` is actually mapped to `pickup_video_5`.
5. The video list thumbnail/title and stream asset mapping point to the same video asset.
6. The m3u8 manifests and ts segment files are deployed.
7. `stream_url` is accessible with the `token` query and the `SeSACKey` header, without `Authorization`.

## Curl check

Use a placeholder token in shared logs and tickets.

```sh
curl -i -H "SeSACKey: <SESAC_KEY>" "http://pickup.sesac.kr:42678/videos/stream/pickup_video_5/master.m3u8?token=<TOKEN>"
```

Expected:

```text
HTTP 200
Content-Type: application/vnd.apple.mpegurl

#EXTM3U
```

or:

```text
HTTP 200
Content-Type: application/x-mpegURL

#EXTM3U
```

Token-only diagnostic failure:

```text
HTTP 420
Content-Type: application/json

{"message":"This service sesac_memolease only"}
```
