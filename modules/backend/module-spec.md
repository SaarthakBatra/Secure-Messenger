# MultiLingo Backend Module Specification

## 1. Overview
The `backend` module handles all server-side logic for the MultiLingo Secure Messenger. It adheres strictly to zero-knowledge policies, ensuring that no plaintext credentials, messages, or metadata are accessible to server administrators.

## 2. Dependencies
- **Crypto / Security**: `argon2` (hashing), `libsodium-wrappers` (asymmetric Dev Shadow bridge), `helmet`, `express-rate-limit`.
- **Database**: `mongoose` (MongoDB).
- **Core**: `express`, `ws` (WebSockets).

## 3. Endpoints

### 3.1 Authentication (`/auth`)
- **`POST /register`**: Registers a new user via Hash-then-Hash architecture.
  - **Payload**: `{ vaultClientKey, duressClientKey, recoveryClientKey, deviceFingerprint, pinWrappedMsk, phraseWrappedMsk, publicKey, encryptedIdentityPrivateKey, [sealedCredentials] }`
  - *Note*: `ClientKey`s are deterministic SHA256 hashes generated client-side. The server strictly performs asynchronous Argon2id hashing on these keys via the native `argon2` module to prevent event loop blocking. The `sealedCredentials` payload is an optional Libsodium `crypto_box_seal` Base64 string containing plaintext PINs (only utilized if the server is in Dev Shadow mode). This Base64 string is decoded via Node's native `Buffer` object to ensure leniency with Dart/Flutter padding and whitespace. Persists `publicKey` and `encryptedIdentityPrivateKey` (wrapped in MSK) to the database.
- **`POST /login`**: Unified login endpoint for all session types (Vault, Duress, Recovery).
  - **Payload**: `{ userId, clientKey, deviceFingerprint }`
  - **Response**: `{ sessionToken, refreshToken, sessionType, reauthGracePeriodSeconds, encryptedIdentityPrivateKey }`
  - **Constraints**: Strictly rate-limited to 5 attempts per minute per IP (configurable via `AUTH_LIMITER_MAX`). Enforces a strictly single active session per user policy (deletes any existing sessions in the DB for the user upon a successful new login). Returns the user's `encryptedIdentityPrivateKey` to restore keys.
- **`GET /users/:userId/public-key`**: Returns `{ publicKey }` containing the public identity key (Curve25519) of the specified user.
- **`POST /refresh`**: Refreshes short-lived JWT tokens.
  - **Payload**: `{ sessionToken, refreshToken }`
  - **Response**: `{ sessionToken, refreshToken }`
  - **Constraints**: Uses `reauthLimiter` (100 req/15min). The `refreshToken` is a signed JWT containing `createdAt` and `expiresAt` and is **not** tracked in the DB to avoid pollution.
  - **Hack Detection Trigger**: If a request is made with a refresh token that is older than 3 lifecycles (15 minutes or older) or if there is a session mismatch, it triggers an immediate `403 HACK_DETECTED`. All active sessions for the user are immediately dropped.
- **`POST /reauth`**: Handles Vault PIN re-authentication overlay.
  - **Payload**: `{ sessionToken, clientKey }`
  - **Response**: `{ sessionToken, refreshToken, sessionType }`
  - **Constraints**: Uses `reauthLimiter`. Triggers `401 Unauthorized` on failure. After 3 failed PIN attempts, it locks the user (sets `lockedUntil` and `wrongPinAttempts`) and triggers a `423 LOCKED_OUT` while terminating the active session.
- **`GET /msk`**: Fetch user's Master Storage Key wrappers.
  - **Authentication**: Valid Session Token required.
  - **Response**: `{ pinWrappedMsk, phraseWrappedMsk }`
- **`POST /msk/update-pin`**: Update the PIN-wrapped MSK.
  - **Authentication**: Valid Session Token required.
  - **Payload**: `{ newPinWrappedMsk }`
- **`POST /duress-pin/change`**: Change the Duress PIN.
  - **Authentication**: Valid Session Token required.
  - **Payload**: `{ currentClientKey, newDuressClientKey }`

### 3.2 Dev Shadow (`/dev`)
*Available only when `SUPER_KEY_ENABLED=true`.*
- **`GET /public-key`**: Returns the server's dynamically generated X25519 public key (Base64) used to decrypt `sealedCredentials`.
- **`GET /shadow/:userId`**: Query endpoint for the mobile app to verify existence of a `user_id` during a Covert Identity Restoration attempt.

### 3.3 Conversations & Messaging (`/conversations`)
- **`POST /`**: Creates a pending conversation with asymmetric invites.
  - **Payload**: `{ recipientUserId, invitationMessage }`
  - **Response**: `{ "conversationId": "...", "aliceInvite": "<aliceInvitePayload>" }`
  - **Behavior**: Generates a 256-bit symmetric `lessonKey` (conversation key), encrypts it twice (sealed boxes for Alice and Bob using their public keys), saves the pending conversation with `aliceInvitePayload` and `bobInvitePayload` (standard base64 encoded using `sodium.base64_variants.ORIGINAL` for both participants), and notifies Bob's websocket if online.
- **`GET /pending`**: Retrieves all pending conversations for the authenticated user where they are a participant but not the admin.
  - **Response**: `[{ conversationId, message, bobInvite, senderUserId }]`
- **`POST /:id/join`**: Joins a pending conversation using the plaintext key.
  - **Payload**: `{ conversationKey }`
  - **Constraints**: Validates key against Argon2id hash stored in `encryptedBlob`, promotes status to `ACTIVE`, adds the recipient to `participantUserIds`, and nullifies `bobInvitePayload`.
- **`DELETE /:id/burn`**: Atomically wipes all messages, media, notes, and the conversation (EC-14).
- **`POST /escrow`**: Escrows an encrypted conversation key.
  - **Payload**: `{ conversationId, encryptedConversationKey, localAlias }`
- **`GET /escrow`**: Retrieves all escrowed conversation keys for the user.
- **`POST /:id/active-page`**: Accepts `{ encryptedActivePage, updatedAt }` in body. Validates that the request user is a participant. Upserts the `ActivePage` document.
- **`GET /:id/active-page`**: Returns `{ encryptedActivePage, updatedAt }` for the conversation (checks participant permissions).
- **`GET /:id/latest-chapter`**: Returns the `latestChapterHash` of the conversation (checks participant permissions).
- **WebSockets**: Mounted on HTTP upgrade with `Authorization: Bearer <token>` or path `ws://localhost:3000/ws?token=...` for real-time idempotent chat routing. Pushes `PENDING_INVITE` events to online recipients.
  - **Message Lifecycle Status Tracking (Ticks)**:
    - **Sent Status (`sent`)**: Default state when message is stored. If the recipient is offline (not in `activeConnections` or socket connection not ready), the server immediately returns a receipt status frame:
      ```json
      {
        "type": "receipt",
        "payload": {
          "messageId": "<messageId>",
          "tickStatus": "sent",
          "recipientOffline": true
        }
      }
      ```
    - **Delivered Status (`delivered`)**: Broadcasted to recipient if online, and a `type: 'receipt'` with `tickStatus: 'delivered'` frame is sent back to the sender.
    - **Acknowledged (`acknowledged`)** & **Read (`read`)**: Upon receiving a `type: 'receipt'` frame from the client with `tickStatus: 'acknowledged'` or `'read'`:
      1. Update the message record in the database using `Message.findOneAndUpdate` (setting `tickStatus` and updating `timestamps.acknowledged` or `timestamps.read` respectively).
      2. Forward the status update frame directly to the original sender's active WebSocket connection:
         ```json
         {
           "type": "receipt",
           "payload": {
             "messageId": "<messageId>",
             "tickStatus": "acknowledged" | "read"
           }
         }
         ```

### 3.4 Media, Notes & Messaging Storage (`/media`, `/notes`, `/conversations/messages`)
- **`/media/upload-url`**: Generates a Cloudflare R2 presigned URL.
- **`/notes/:id/lock`**: Acquires a 60-second concurrency lock for editing.
- **`POST /conversations/messages/upload-chapter-url`**: Accepts `{ conversationId, new_chapter_hash }` in body. Uses `@aws-sdk/client-s3` and `@aws-sdk/s3-request-presigner` configured with environment credentials (endpoint, bucket, keys) to generate a presigned PUT URL for bucket path `convo_${conversationId}/chapter_${new_chapter_hash}`. (Checks participant permissions).
- **`POST /conversations/messages/download-chapter-url`**: Accepts `{ conversationId, chapter_hash }` in body. Uses `@aws-sdk/client-s3` and `@aws-sdk/s3-request-presigner` configured with environment credentials to generate a presigned GET read URL for bucket path `convo_${conversationId}/chapter_${chapter_hash}` (expires in 15 minutes). Returns a mock URL (`https://mock-r2.local/download/...`) for testing/development environments when credentials are absent. (Checks participant permissions).
- **`POST /conversations/messages/archive-chapter`**: Accepts `{ conversationId, new_chapter_hash }`. Updates the `latestChapterHash = new_chapter_hash` on the conversation document and resets/deletes the `ActivePage` document for that conversation. (Checks participant permissions).

## 4. Edge Case Mitigations
- **EC-05 (Timing Attacks):** Handled via `dummyVerify()` on login failures.
- **EC-09 (Idempotent WS):** Handled via MongoDB `11000` duplicate key interception.
- **EC-11 (WS Floods):** Handled via 50 msg/sec token-bucket limiter.
- **EC-13 (Note Concurrency):** Handled via `NOTE_LOCK_TIMEOUT_MS`.
- **Hack Detection (Token Age/Replay):** Checked on `/auth/refresh`. Immediate termination and `403` returned on rotated token reuse (>15 min old). The mobile client wipes itself upon receiving this.
- **Session Expiration:** MongoDB TTL index leaves a 1-hour active buffer to gracefully return `401 SESSION_EXPIRED` to clients. The session access token expires in 30 minutes, while refresh tokens have a 5-minute lifecycle.
- **Progressive Brute Force Mitigation:** Tracked via `wrongPinAttempts` on the User document. Hitting the 3-attempt limit drops active sessions, sets `lockedUntil`, and triggers a `423` response.
## 5. Telemetry & Debugging
To assist frontend integration without compromising production security, the backend employs **Universal Inline Granular Logging**.
- **Implementation:** All core controllers MUST use semantic, inline loggers (e.g., `if (process.env.DEBUG === 'true') winston.info(...)`). Global generic HTTP logging middlewares are strictly prohibited.
- **Semantic Tracing:** Logs must explicitly document cryptographic state transitions, payload unpacking, and logic branching (e.g., matching Vault vs. Duress).
- **Security Constraints:** The logger must NEVER dump raw HTTP headers, plaintext user messages, or the `sealedCredentials` Dev Shadow payload. Only deterministic `ClientKey`s, resulting Argon2id hashes, and state transitions are permitted to be logged.
