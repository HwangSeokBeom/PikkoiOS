# PortOne Payment QA Checklist

## Configuration

- [ ] Debug/Staging uses the intended `PORTONE_USER_CODE`, `PORTONE_PG`, `PORTONE_PG_ID`, `PORTONE_PAY_METHOD`, and `PORTONE_APP_SCHEME`.
- [ ] `PAYMENT_TEST_MODE=YES` shows this warning in Checkout: "테스트 결제에서도 실제 금액이 결제될 수 있으며, PG 정책에 따라 자동 환불될 수 있습니다."
- [ ] Release build blocks payment start when `PAYMENT_TEST_MODE=YES`.
- [ ] Release build blocks payment start when `PORTONE_PG_ID` contains a test PG value such as `INIpayTest`.
- [ ] `PORTONE_USER_CODE`, PortOne API secret, access token, refresh token, and card/payment-sensitive data are not printed in logs.

## Payment Flow

- [ ] Tap Checkout payment once and confirm duplicate taps do not create duplicate orders or payment sheets.
- [ ] Card payment succeeds in PortOne and returns to Pikko.
- [ ] External card app opens and returns to Pikko through `PORTONE_APP_SCHEME`.
- [ ] Kakao/other 간편결제 app opens and returns to Pikko without breaking Kakao login URL handling.
- [ ] Closing the PortOne payment sheet is treated as cancellation.
- [ ] Cancellation does not call `/v1/payments/validation`.
- [ ] Cancellation keeps the cart and allows payment retry.
- [ ] Failure without `imp_uid` does not call `/v1/payments/validation`.
- [ ] Failure keeps the cart and shows a friendly retry message.
- [ ] PortOne success callback does not clear the cart before server validation succeeds.
- [ ] PortOne success with `imp_uid` calls `POST /v1/payments/validation`.
- [ ] Validation success clears the cart and shows the order completion screen.
- [ ] Validation failure keeps the cart and shows the safe message that payment may have completed.
- [ ] Validation failure allows "결제 확인 재시도" using the same `imp_uid` and `order_code`.

## Order List And Detail

- [ ] After validation success, entering order history triggers the latest `GET /v1/orders`.
- [ ] If the paid order is present, the order list highlights or routes to that order.
- [ ] If the paid order is not present yet, the user sees "주문이 접수되었습니다. 목록 반영까지 잠시 걸릴 수 있습니다."
- [ ] Order detail shows `PENDING_APPROVAL` as 승인대기.
- [ ] `APPROVED`, `IN_PROGRESS`, and `READY_FOR_PICKUP` show progress states without review CTA.
- [ ] `PICKED_UP` enables review creation when no review exists.
- [ ] Failed/canceled/unvalidated payment states do not expose order detail or review CTA from Checkout.

## App Lifecycle And Network

- [ ] Put the app in background during PortOne payment, return, and confirm callback handling still reaches validation.
- [ ] Turn off network before validation and confirm cart is kept with "결제 확인 재시도".
- [ ] Retry validation after restoring network.
- [ ] Kill and relaunch after payment app return edge cases; confirm order history can still be refreshed manually.

## Refund Boundary

- [ ] Paid order cancellation is not exposed as a normal buyer cancel action.
- [ ] Any visible cancel affordance says: "결제 완료 주문 취소는 환불 처리가 필요합니다. 현재 앱에서는 지원 준비 중입니다."
- [ ] `PUT /v1/orders/{order_code}` is not used for buyer cancellation.
- [ ] Debug/admin order status mutation remains DEBUG-only and is not visible in Release.
- [ ] Refund API integration is tracked as a separate server contract before enabling paid order cancellation.
