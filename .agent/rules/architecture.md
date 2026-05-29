# MultiLingo Unified Architecture Specification

## 1. Technical Stack Overview

### Mobile Client (Flutter & Dart)
- **State Management:** Riverpod (Providers, StateNotifier, AsyncNotifier)
- **Routing:** `go_router` for deep linking and programmatic navigation
- **Cryptography:** `flutter_sodium` (libsodium bindings) + `pointycastle` + `cryptography`
- **Local Storage:** `flutter_secure_storage` for credentials and keys; `sqflite` for offline message/notes database
- **Real-Time Client:** `web_socket_channel`
- **Location Services:** `geolocator` + `flutter_background_service` (background captures)
- **UI & Controls:** `flutter_windowmanager` (screenshot blocking), `qr_flutter` (IDs), `mobile_scanner` (QR reading)
- **HTTP Client:** `dio` for RESTful calls to backend

### Backend Server (Node.js & Express)
- **Runtime:** Node.js 20 LTS
- **Web API & Routing:** Express.js
- **Real-Time Engine:** `ws` (WebSocket) self-hosted
- **Queue & Async Workers:** `Bull` + `Redis` (Upstash) for background tasks (e.g. key rotation, auto-approvals, PENDING cleanup)
- **Crypto Support:** `libsodium-wrappers`
- **Database Driver:** `Mongoose` (MongoDB Atlas M0/M10)
- **Payload Validation:** `zod`
- **Logger:** `winston`
- **Push Services:** `firebase-admin` (Unified Firebase Cloud Messaging HTTP v1 API)

---

## 2. Directory Layout and Module Registry

The repository is structured as a mono-repo. The 18 pre-approved modules are categorized under `shared`, `backend`, and `mobile`.

```
multilingo/
├── .agent/                  ← Agent workflows, prompts, rules
├── modules/
│   ├── shared/              ← Global cryptoutils, shared constants, structures
│   ├── backend/
│   │   ├── dev/             ← Super-key shadow collection (dev-only)
│   │   ├── auth/            ← Registration, sessions, PIN KDF & login
│   │   ├── conversations/   ← Inbound invites, join room, Aliases
│   │   ├── messaging/       ← WebSocket hub, R2 presign, message storage
│   │   ├── notifications/   ← Unified FCM, disguised notification pooling
│   │   ├── notes/           ← CRUD, edit locks, snap version history
│   │   ├── location/        ← Discrete location ping routes
│   │   └── restoration/     ← Request routing, inactivity escape valve
│   └── mobile/
│       ├── cover/           ← Cover app UX, streaker, live translation
│       ├── vault-auth/      ← Setup screens, triggers, grace timer
│       ├── conversations/   ← Room joins, deep link, QR codes
│       ├── messaging/       ← Message bubbles, local decrypt, R2 upload
│       ├── security/        ← Screenshot blocks, PIN incorrect wipes, overlays
│       ├── notes/           ← Note lists, MD editor, lock status sync
│       ├── location/        ← Geo ping trigger, background geolocator
│       ├── restoration/     ← Request screens, recovery phrase login list
│       └── settings/        ← Cover, vault, and conversation controls
├── tests/                   ← Automated testing suites
├── Output/                  ← Quality guardian reports
└── Temp Resources/          ← Staged assets
```

### Allowed Dependency Matrix
Strict scoping prevents circular and unauthorized dependencies. Follow this matrix:

| Module | Allowed Imports / Dependencies |
|---|---|
| `shared` | None (pure library/constants) |
| `backend/dev` | `shared` |
| `backend/auth` | `shared`, `backend/dev` |
| `backend/conversations` | `shared`, `backend/auth` |
| `backend/messaging` | `shared`, `backend/auth`, `backend/conversations` |
| `backend/notifications` | `shared`, `backend/auth` |
| `backend/notes` | `shared`, `backend/auth`, `backend/conversations` |
| `backend/location` | `shared`, `backend/auth`, `backend/conversations` |
| `backend/restoration` | `shared`, `backend/auth`, `backend/conversations` |
| `mobile/cover` | `shared` |
| `mobile/vault-auth` | `shared`, `mobile/cover` |
| `mobile/conversations` | `shared`, `mobile/vault-auth` |
| `mobile/messaging` | `shared`, `mobile/vault-auth`, `mobile/conversations` |
| `mobile/security` | `shared`, `mobile/vault-auth`, `mobile/conversations` |
| `mobile/notes` | `shared`, `mobile/vault-auth`, `mobile/conversations` |
| `mobile/location` | `shared`, `mobile/vault-auth`, `mobile/conversations` |
| `mobile/restoration` | `shared`, `mobile/vault-auth`, `mobile/conversations` |
| `mobile/settings` | `shared`, `mobile/vault-auth`, `mobile/conversations`, `mobile/security` |

---

## 3. End-to-End Encryption & Data Flow Contract
The server operates as an opaque data vault. Plaintext MUST NOT be sent or stored on the server under production configurations.

```
+--------------------+               +--------------------+               +--------------------+
|  Client A (Sender) |               |       Server       |               | Client B (Rcvr)    |
+--------------------+               +--------------------+               +--------------------+
          |                                    |                                    |
          |  1. Generate Message               |                                    |
          |  2. Encrypt locally                |                                    |
          |     (AES-256-GCM / ChaCha)         |                                    |
          |  3. JSON Ciphertext Blob           |                                    |
          |----------------------------------->|                                    |
          |                                    |  4. Store Opaque Ciphertext        |
          |                                    |  5. Forward Ciphertext             |
          |                                    |     (WS or Push Notification)      |
          |                                    |----------------------------------->|
          |                                    |                                    |  6. Download Ciphertext
          |                                    |                                    |  7. Decrypt locally
          |                                    |                                    |     (Argon2id + Key)
          v                                    v                                    v
```

### Structural Rules:
- **Zero Server Plaintext:** Timestamps, read states, and text payloads are packaged inside the encrypted conversation blob before transport. The server only sees `encryptedBlob`.
- **Display-Once Key:** The Conversation Encryption Key is generated server-side during room setup and returned exactly ONCE to the creator. It must be shared out-of-band. The server stores only a high-entropy hash of this key to validate correctness (key correctness checks).

---

## 4. MongoDB Collection Schemas

The following Mongoose models dictate MongoDB data architecture:

### `users`
- `userId` (String, unique, 9-10 numeric digits)
- `pinHash` (String, Argon2id derivative of Vault PIN)
- `duressPinHash` (String, Argon2id derivative of Duress PIN)
- `recoveryPhraseHash` (String, PBKDF2 hash of 12-word mnemonic)
- `sessionToken` (String, active session identifier)
- `deviceFingerprint` (String, SHA-256 of device metrics)
- `createdAt` (Date)

### `sessions`
- `userId` (String)
- `token` (String, indexed)
- `deviceFingerprint` (String)
- `createdAt` (Date)
- `invalidatedAt` (Date, null if active)

### `conversations`
- `conversationId` (String, unique, random alphanumeric)
- `adminUserId` (String)
- `participantUserIds` (Array of Strings)
- `status` (String: PENDING | ACTIVE | ROTATING)
- `keyValidationHash` (String, hash of Conversation Key to verify joiners)
- `encryptedBlob` (String, opaque payload of conversation metadata)
- `createdAt` (Date)

### `messages`
- `messageId` (String, unique)
- `conversationId` (String, indexed)
- `senderUserId` (String)
- `encryptedBlob` (String, E2EE message details, text, metadata)
- `tickStatus` (String: SENT | DELIVERED | ACKNOWLEDGED | READ)
- `timestamps` (Object: sentAt, deliveredAt, acknowledgedAt, readAt)
- `hiddenFlags` (Array of Strings, stores UserIDs for whom the message is locally hidden)

### `media_refs`
- `mediaId` (String, unique)
- `conversationId` (String)
- `r2Key` (String, path format: `/{conversationId}/{mediaId}`)
- `encryptedMetaBlob` (String, E2EE metadata like filename, size, mime)

### `notes`
- `noteId` (String, unique)
- `conversationId` (String)
- `title` (String, encrypted blob)
- `encryptedContentBlob` (String, encrypted note contents)
- `editLock` (Object: heldByUserId, expiresAt)
- `versions` (Array of Objects: versionId, encryptedContentBlob, snapshotByUserId, snapshotAt)

### `events`
- `eventId` (String, unique)
- `conversationId` (String)
- `type` (String, e.g. WRONG_KEY, WIPE, DURESS, SESSION_PURGE, KEY_ROTATION)
- `encryptedPayloadBlob` (String, event details)
- `timestamp` (Date)

### `restoration_requests`
- `requestId` (String, unique)
- `conversationId` (String)
- `requestingUserId` (String)
- `reasonBlob` (String, encrypted explanation text)
- `status` (String: PENDING | APPROVED | DENIED)
- `createdAt` (Date)
- `resolvedAt` (Date)

---

## 5. Storage Conventions & Cloudflare R2
- **Path Isolation:** Media files uploaded to Cloudflare R2 are saved at exactly `/{conversationId}/{mediaId}`.
- **Header Encryption:** Pre-signed URLs for upload/download are issued on demand. No plaintext metadata (e.g. original filename) is allowed in R2 metadata tags.

---

## 6. WebSockets and Connection Protocols
- **Handshake Verification:** WebSocket connections require `sessionToken` inside the query parameters. Subscriptions are verified against the user's conversation list.
- **Event Channels:** Client subscribes to the channel of active conversation IDs. Standard WebSocket messages enforce discrete JSON packets:
  - `type`: message | tick | note_preview | edit_lock
  - `payload`: encrypted blob payload
