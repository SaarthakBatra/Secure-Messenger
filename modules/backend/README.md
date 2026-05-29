# MultiLingo Backend Service

This is the Node.js / Express backend module for the MultiLingo Secure Messenger.

## Quick Start
1. Ensure MongoDB is running locally or configure `MONGO_URI` in `.env` to point to MongoDB Atlas.
2. `npm install`
3. `npm run dev` (starts on port 3000)

## Features
- **Zero-Knowledge Architecture:** The server never stores or sees plaintext credentials (except exclusively in the `DevShadow` collection when `SUPER_KEY_ENABLED=true` for testing).
- **Master Storage Key Escrow:** Encrypted conversation keys are escrowed in a zero-knowledge fashion via `pinWrappedMsk` and `phraseWrappedMsk`.
- **Hash-then-Hash Cryptography:** Mobile clients compute deterministic SHA-256 `Client_Key`s, which the backend subsequently hashes using `Argon2id` (via the native `argon2` npm package utilizing `libuv` C++ worker threads to completely protect the Node event loop).
- **Short-Lived Sessions & Hack Detection:** Sessions expire rapidly (default 30 mins access token) with a 5-minute JWT `refreshToken` rotation window. The `refreshToken` is a signed JWT storing `createdAt` and `expiresAt`, requiring zero DB tracking. Replaying rotated tokens or tokens older than 15 minutes triggers an immediate `403 HACK_DETECTED` block, dropping all active user sessions and wiping the local mobile state to protect accounts.
- **Progressive Brute Force Mitigation:** The system tracks `wrongPinAttempts` and establishes a `lockedUntil` epoch after 3 failed login/re-auth attempts, rejecting further requests with `423 LOCKED_OUT`.
- **Single Active Session:** The system enforces a strict one-session-per-user policy. Upon any successful new login, all pre-existing sessions for that user are immediately destroyed.
- **Unified Authentication:** All login flows (Vault, Duress, Recovery) are indistinguishable and routed through a single `/auth/login` endpoint, completely neutralizing traffic analysis and endpoint sniffing attacks.
- **Dev Shadow Bridge:** Uses `libsodium-wrappers` to dynamically generate an X25519 keypair for the mobile app to securely pass sealed plaintext credentials during development. To guarantee cross-platform compatibility, Node's native `Buffer` is used for all Base64 payload decoding, ensuring absolute leniency with Dart/Flutter's whitespace and padding formatting.
- **R2 Media Uploads:** Offloads heavy bandwidth by issuing presigned URLs.
- **Active Page Syncing & R2 Cold-Storage Archiving:** Supports client active-page backup in MongoDB and cold-storage linked-list message archiving in Cloudflare R2 to maintain O(1) MongoDB storage per conversation.
- **Asymmetric Key Invite Flow & WebSocket Push:** Supports zero-knowledge room initialization by encrypting generated room keys under Alice's and Bob's Curve25519 identity public keys (Sealed Boxes) and pushing invites via a thread-safe WebSocket connection pool.


## Specs
See `module-spec.md` for API contracts and edge case mitigations.

## Detailed Workflow Examples

### 1. E2EE Active Page Backup & Sync Flow
This flow synchronizes the hot active chat window messages (up to `MESSAGE_BUNDLE_SIZE`) in a zero-knowledge manner.

#### Normal Flow (Active Page Backup)
1. The user sends a message to an offline peer, navigates away from a conversation, or remains inactive for `INACTIVE_TIMEOUT_SEC` (default 60 seconds).
2. The client compiles the active messages list, encrypts it using the Conversation Key (`lessonKey`) via `AES-256-GCM` to produce `ActiveLessonPage` (`encryptedActivePage`).
3. The client POSTs the encrypted blob and a plaintext `updatedAt` timestamp to `/conversations/:id/active-page`.
4. The server validates that the requesting user is a participant of the conversation and performs an `upsert` on the `ActivePage` document, replacing the old version.

#### Edge Case (Conflict Resolution on Login / Unlock)
When a user unlocks their vault, the client fetches the active page's `server_updatedAt`. It compares this with its local `local_updatedAt` timestamp:
*   **Case A (Server is newer):** The server has a more recent backup (e.g. sent by the offline partner). The client downloads the server's encrypted active page, decrypts it using the `lessonKey`, and merges the messages into its local SQLite database (matching on unique message ID). It then computes a merged active page, uploads it, and updates timestamps to match.
*   **Case B (Client is newer):** The client has newer local offline messages. The client encrypts its local active page and POSTs it to the server to overwrite the outdated backup.
*   **Case C (Timestamps are equal):** The databases are fully aligned. No network action is taken.

---

### 2. Singly Linked-List R2 Cold-Storage Archiving
This flow archives historical messages to Cloudflare R2 once the active window threshold is exceeded, maintaining a strict O(1) MongoDB footprint.

#### Normal Flow (Archiving)
1. The client-side database reaches `MESSAGE_BUNDLE_SIZE` (default 1000 messages).
2. The client queries `/conversations/:id/latest-chapter` to retrieve the current tail pointer (`latestChapterHash`).
3. The client packages the oldest 1000 messages into a `LessonChapter` object. It includes the old `latestChapterHash` as `previousChapterHash` in the metadata, forming a backward-pointing singly linked list.
4. The client encrypts the bundle via `AES-256-GCM` using the `lessonKey` and computes the new chapter's SHA-256 hash.
5. The client POSTs the hash to `/messages/upload-chapter-url` to obtain a Cloudflare R2 presigned PUT URL for bucket path `convo_{conversationId}/chapter_{new_chapter_hash}`.
6. The client PUTs the encrypted payload directly to R2 using the presigned URL.
7. The client finalizes the step by POSTing to `/messages/archive-chapter`, which updates the tail pointer (`latestChapterHash`) to the new hash in MongoDB and deletes the active page document.
8. The client purges the 1000 archived messages from its local active SQLite database.
9. To retrieve and decrypt historical chapters, the client requests a presigned GET read URL via `POST /conversations/messages/download-chapter-url` (expiring in 15 minutes) to download the encrypted chapter directly from Cloudflare R2, then decrypts it using the local `lessonKey`.


#### Edge Cases
*   **R2 Put Fails:** If R2 is offline or the upload fails, the client halts the operation. It does NOT call `/messages/archive-chapter` and does NOT delete local SQLite messages. It will retry the archive operation later.
*   **Pointer Update Fails:** If the R2 upload succeeds but the subsequent call to `/messages/archive-chapter` fails (e.g., due to network drop), the server's tail pointer remains pointing to the old chapter. The next time the client runs the archive job, it detects that the tail pointer has not advanced. It generates a new chapter pointing to the same old tail, uploads it, and retries the pointer update, ensuring no link is broken or orphaned.

---
 
 ### 3. Session Soft-Deletion
 *   **Normal Flow:** When a user logs out (`DELETE /auth/session`), the server sets `invalidatedAt = new Date()`.
 *   **Intrusion Detection (Edge Case):** If a session replay or token mismatch occurs during refresh, the server flags a hack and terminates all user sessions by updating their `invalidatedAt` timestamp, blocking subsequent requests with `401 Unauthorized` or `403 HACK_DETECTED`.

---

### 4. Zero-Knowledge Asymmetric Invitation & Verification Flow
This flow establishes end-to-end encrypted rooms between two independent clients utilizing asymmetric Curve25519 sealed boxes, escrow backup, and WebSocket push notifications.

#### Normal Flow (Create & Join)
1. **Identity Registration**: During vault setup, each user generates a Curve25519 public key (`publicKey` / `syncProfileId`) and an MSK-wrapped private key (`encryptedIdentityPrivateKey` / `translationSyncToken`). The keys are sent via `/auth/register` and saved to the Database.
2. **Conversation Initiation (Alice)**: Alice initiates a conversation with Bob by calling `POST /conversations` with `{ recipientUserId, invitationMessage }`.
3. **Sealed Box Key Exchange**:
   - The backend resolves both Alice's and Bob's public keys.
   - The backend generates a 256-bit symmetric conversation key (`lessonKey`).
   - The backend encrypts this key for both participants using Libsodium sealed boxes (`crypto_box_seal`) using the `sodium.base64_variants.ORIGINAL` variant to handle standard base64 formats.
   - The raw keys in server memory are securely wiped.
   - The pending conversation is stored in MongoDB with `aliceInvitePayload` and `bobInvitePayload`.
4. **WebSocket Push**: If Bob is currently online, the backend pushes a `PENDING_INVITE` message over Bob's active WebSocket connection.
5. **Decryption and Join (Bob)**:
   - Bob retrieves invitations (via the real-time WebSocket push or by polling `GET /conversations/pending`).
   - Bob decrypts his invitation payload using his private identity key.
   - Bob joins the room by calling `POST /conversations/:id/join`, providing the decrypted plaintext conversation key. The backend verifies the key against the Argon2id hash stored in the conversation's `encryptedBlob`.
   - On success, the room status is updated to `ACTIVE`, and the `bobInvitePayload` is purged.
6. **Key Escrow Backup**: Both Alice and Bob encrypt the symmetric conversation key with their local Master Storage Keys (MSK) and upload the resulting cipher via `POST /conversations/escrow`, ensuring cloud key recovery.

### 5. WebSocket Message Lifecycle Status Tracking (Ticking System)
This system tracks message delivery and read status transitions in real-time.

#### Normal Flow (Online Recipient)
1. **Sent**: Alice sends a chat message. The server stores it in the database with status `sent`.
2. **Delivered**: If Bob is online, the server forwards the message to Bob's active WebSocket connection, updates the database status to `delivered`, and returns a receipt frame to Alice: `{ type: "receipt", payload: { messageId, tickStatus: "delivered" } }`.
3. **Acknowledged**: When Bob's client successfully writes the message to SQLite and matches the database hash, it sends back a receipt: `{ type: "receipt", payload: { messageId, tickStatus: "acknowledged" } }`. The server updates the database and forwards this to Alice's active WebSocket.
4. **Read**: When Bob opens the chat UI, his client sends a receipt: `{ type: "receipt", payload: { messageId, tickStatus: "read" } }`. The server updates the database and forwards this to Alice.

#### Offline Flow (Bob Offline)
1. Alice sends a chat message.
2. The server detects Bob is not present in `activeConnections` or has a closed socket connection.
3. The server immediately returns an offline receipt frame to Alice:
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
4. This receipt frame triggers Alice's client to upload the `ActiveLessonPage` backup immediately, ensuring offline synchronization.

### 6. R2 Cold-Storage Chapter Download & On-Demand Lazy Loading
This workflow allows clients to lazy-load historical messages from R2 cold-storage on-demand as the user scrolls up past the local SQLite message limit.

#### Normal Flow (Lazy Loading)
1. **Trigger**: The user scrolls to the top of the chat history, and the client detects that `latestChapterHash` (retrieved from the conversation document) is not null and points to older messages.
2. **Download URL Request**: The client requests a presigned GET read URL from the backend via `POST /conversations/messages/download-chapter-url` with `{ conversationId, chapter_hash }`.
3. **Authorization & Dispatch**: The server authenticates the user, checks that they are a participant in the conversation, generates the R2 path `convo_${conversationId}/chapter_${chapter_hash}`, and returns a presigned GET URL (expiring in 15 minutes).
4. **Binary Retrieval**: The client downloads the encrypted binary payload directly from Cloudflare R2 using the presigned URL.
5. **Decryption & Render**: The client decrypts the chapter in RAM using the local `lessonKey` and AES-256-GCM. It parses the JSON array and prepends the historical messages to the UI.
6. **Traversal**: The client reads the `previousChapterHash` field in the decrypted chapter's metadata, updating its local pointer for the next scroll-up trigger.

#### Edge Cases
*   **Presigned URL Expiry**: If the client attempts to use the presigned GET URL after 15 minutes, R2 returns `403 Forbidden`. The client must request a new presigned URL from the backend.
*   **Network Failure during Download**: If the download is interrupted, the client caches the current chapter hash pointer and retries the GET request upon subsequent scrolls.
*   **Decryption Failure (Corrupt Chapter)**: If the chapter data is corrupt or fails integrity checks, the client discards the binary and displays a placeholder without updating the pagination pointer, preventing infinite scroll triggers.

## Development & Debugging
The backend features a **Universal Inline Granular Debug Logger**.
- To enable deep semantic tracing of authentication workflows, cryptographic generation, and database interactions, set `DEBUG=true` in your `.env` file.
- The logs will explicitly trace payload evaluations (e.g., the step-by-step matching logic for Vault vs Duress vs Recovery entries) using `winston` loggers.
- **Note:** For strict zero-knowledge compliance, the logger will *never* print raw HTTP headers or `sealedCredentials`.


