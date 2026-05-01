# HLS Streaming Failure - serverServiceMismatch

## 1. Symptoms

- Video list, thumbnails, and API authentication are working.
- `GET /v1/videos/{video_id}/stream` returns HTTP 200.
- The stream API response includes m3u8 URLs with a `token` query.
- Accessing the returned m3u8 URL returns a JSON error instead of an HLS manifest.

## 2. Reproduction Target

- `videoId=695b5b0eea9356dcee04dbfd`
- `stream path=/videos/stream/pickup_video_5/master.m3u8`
- qualities: `1080p`, `720p`, `480p`

## 3. Expected Result

```bash
curl -i "http://pickup.sesac.kr:42678/videos/stream/pickup_video_5/master.m3u8?token=<TOKEN>"
```

- HTTP 200
- `Content-Type: application/vnd.apple.mpegurl` or `application/x-mpegURL`
- Response body starts with `#EXTM3U`

## 4. Actual Result

- HTTP 420
- `Content-Type: application/json; charset=utf-8`
- Body:

```json
{"message":"This service sesac_memolease only"}
```

## 5. Additional Findings

- `tokenOnly` also returns 420.
- `noAuth` also returns 420.
- Adding `Authorization` and/or `SeSACKey` to the HLS URL returns 444.
- Therefore the HLS URL appears to use token query authentication, not API header authentication.
- However, the issued token or HLS resource binding does not match the PickUp service.

## 6. Server Checks Requested

- Confirm the HLS token issue-time `service`, `audience`, or `tenant` value is PickUp.
- Confirm the `pickup_video_5` HLS asset is registered for the PickUp service.
- Confirm `/videos/stream/pickup_video_5/master.m3u8` is not routed through `sesac_memolease`-only middleware.
- Confirm the PickUp `SeSACKey`/API key and HLS token service binding match.
- Confirm the HLS manifest and segment files are actually deployed.
- Confirm all quality URLs returned by the stream API should be accessible with only the `token` query.
- Confirm the token expiry is not too short and is not rejected immediately after issue.
- Confirm the server sees the same HTTP 420 when testing the same issued token with curl.

## 7. Client Checks Completed

- `baseURL` is `http://pickup.sesac.kr:42678`.
- The stream API request includes `Authorization` and `SeSACKey`.
- The m3u8 playback URL contains the `token` query.
- `rawQueryLength` and `percentEncodedQueryLength` are preserved identically.
- The AVPlayer playback URL uses `assetHeaders=false`.
- Raw token values are not exposed in logs.

## 8. Conclusion

This is not an issue the client can fix by adding extra query parameters or headers.

The server must return the PickUp HLS manifest by fixing HLS token issuance or the streaming resource service binding.

Do not include raw token, `Authorization`, or `SeSACKey` values in shared logs or reports.
