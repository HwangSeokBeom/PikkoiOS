# Server TODO: store-scoped chat rooms

The iOS client now sends `POST /v1/chats` with both `opponent_id` and `store_id` for store inquiry entry points and logs collisions when the same `room_id` is returned for different stores.

Required server behavior:

- General 1:1 chat rooms should remain unique by participants.
- Store inquiry chat rooms should be unique by participants and `store_id`.
- If the same user asks the same owner about different stores, the server must return different `room_id` values.
- When `POST /v1/chats` receives `store_id`, the find-or-create condition must include `store_id`.
- Add or update DB uniqueness constraints so user/opponent/store combinations do not collapse into a participant-only room.

Client limitation until server changes:

- Socket namespaces are still `/chats-{room_id}`, so the iOS app cannot fully separate real-time or server history for different stores if the backend returns the same `room_id`.
- The iOS app keeps local message cache keys store-scoped and avoids merging server history during detected collisions to prevent showing another store's cached messages as if they belonged to the current store.
