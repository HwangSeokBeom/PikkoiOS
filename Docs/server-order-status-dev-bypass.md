# Order Status Dev Bypass

## Server Policy

- production: 결제가 완료된 주문만 `PUT /v1/orders/{order_code}` 상태 변경을 허용한다.
- development/staging/local/test: `ALLOW_UNPAID_ORDER_STATUS_UPDATE=true`일 때만 미결제 주문 상태 변경을 허용한다.
- production에서는 `ALLOW_UNPAID_ORDER_STATUS_UPDATE=true`가 들어가도 최종 우회값을 `false`로 강제해야 한다.

## Required Env Values

```dotenv
# .env.development, .env.staging, .env.local, .env.test
ALLOW_UNPAID_ORDER_STATUS_UPDATE=true

# .env.production
ALLOW_UNPAID_ORDER_STATUS_UPDATE=false
```

## Expected Server Guard

```ts
const isProduction =
  process.env.NODE_ENV === "production" ||
  process.env.APP_ENV === "production";

const allowUnpaidOrderStatusUpdate =
  process.env.ALLOW_UNPAID_ORDER_STATUS_UPDATE === "true" && !isProduction;

if (!order.isPaid && !allowUnpaidOrderStatusUpdate) {
  throw new BadRequestError(
    isProduction
      ? "결제가 완료된 주문만 상태 변경이 가능합니다."
      : "결제가 완료된 주문만 상태 변경이 가능합니다. 개발 테스트에서 미결제 주문 상태 변경을 허용하려면 ALLOW_UNPAID_ORDER_STATUS_UPDATE=true를 설정하세요."
  );
}
```

## Swagger Note

`PUT /v1/orders/{order_code}` should document:

- production: 결제 완료 주문만 상태 변경 가능
- development/staging/test: `ALLOW_UNPAID_ORDER_STATUS_UPDATE=true`일 때 미결제 주문도 상태 변경 가능
- request body: `{"nextStatus":"APPROVED"}`
- status enum currently used by iOS: `PENDING_APPROVAL`, `APPROVED`, `IN_PROGRESS`, `READY_FOR_PICKUP`, `PICKED_UP`

## Restart Checklist

```sh
cd ~/프로젝트서버경로
grep -n "ALLOW_UNPAID_ORDER_STATUS_UPDATE" .env .env.development .env.staging .env.production
echo "ALLOW_UNPAID_ORDER_STATUS_UPDATE=true" >> .env.development
npm run build
pm2 restart <process-name> --update-env
pm2 logs <process-name> --lines 100
```

## Verification

1. 미결제 주문을 생성한다.
2. iOS 주문 내역에서 승인대기 주문의 `주문승인`을 선택한다.
3. development/staging 서버는 200을 반환하고 체크마크가 `주문승인`으로 이동해야 한다.
4. `/v1/orders` refresh 이후에도 상태가 유지되어야 한다.
5. production 서버는 동일 요청을 400으로 차단하고 아래 로그를 남겨야 한다.

```text
WARN [OrderStatusUpdate] blocked unpaid order status update in production orderCode=... paymentStatus=...
```
