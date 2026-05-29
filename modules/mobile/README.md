# MultiLingo Mobile Core (`modules/mobile/`)

## Responsibility
This directory serves as the Flutter application root for the MultiLingo project. It contains the primary `pubspec.yaml`, the routing shell (`go_router`), centralized state provision (`flutter_riverpod`), and global themes.

## Strict Scoping Rule
**No business logic is allowed in this module.**
This module purely orchestrates the user interface shells and navigation between isolated features (e.g., Auth, Vault, Dictionary). All specialized features must be implemented in their respective sibling modules under `modules/mobile/`.

## Architecture
- **State Management:** Riverpod `ProviderScope`.
- **Routing:** `go_router` with middleware for onboarding checks and vault session guards.
- **Theming:** Defined in `lib/app/theme/app_theme.dart`.
- **MSK Session constraints:** The unwrapped Master Storage Key resides strictly in memory via `MskSessionNotifier` and is nullified on session end.
- **Enclave Enclosure (`lib/features/vault/`):** Contains the primary secure Vault UI screens, SQLite database manager, and create/join invitation overlays.
- **Covert Naming Dictionary**: To maintain plausible deniability, all cryptographic components are named using decoy terms:
  - Master Storage Key (MSK) -> `TranslationCacheConfig`
  - PIN-Wrapped MSK -> `backupCacheBlob`
  - Phrase-Wrapped MSK -> `phraseRestoreBlob`
  - identityPrivateKey -> `translationSyncToken`
  - identityPublicKey -> `syncProfileId`
  - Conversation Key -> `lessonKey`
  - encryptedConversationKey -> `wrappedLessonKey`
  - sessionKey (RAM ephemeral key) -> `sessionBucketToken`
  - Active Messages Blob -> `ActiveLessonPage`
  - Static History Bundle -> `LessonChapter`
- **WebSocket Listener**: Subscribes to `ws://localhost:3000/ws?token=$token` on session start to receive real-time push events (e.g. `PENDING_INVITE`) and updates the pending rooms dashboard instantly, as well as handling E2EE messaging synchronization.
- **E2EE Messaging Engine (Phase 3b)**: Houses the message cryptography (AES-256-GCM), active page synchronization and conflict resolution, content-addressable hash alignment checks, Cloudflare R2 SINGLY LINKED-LIST archiving, and lazy loading history retrieval.
- **Chat Interface (`ChatScreen`)**: Renders real-time message bubbles with full decryption, dynamic typing scroll pinning, active page synchronizer on entry, and WebSocket transmission support.

## E2EE Messaging Protocols & Synchronization Workflows

### 1. Active Page Conflict Resolution & Offline Backups
- **Happy Path Sync**: On vault entry, the client fetches the active page's `server_updatedAt` and compares it with `local_updatedAt`.
  - **Case A (Server is newer)**: Client pulls the server's `ActiveLessonPage`, decrypts it using the room `lessonKey`, and merges all missing messages into the local SQLite database.
  - **Case B (Client is newer)**: Client encrypts its local active messages and uploads them to overwrite the outdated server backup.
- **Offline Backup Trigger**: When Alice sends a message and Bob is offline, the backend returns a receipt frame with `recipientOffline: true`. Alice's client immediately uploads an updated encrypted `ActiveLessonPage` backup. Upon Bob's next unlock, Bob's client downloads and merges it.

### 2. Hash Alignment & P2P Control Frames
- **Verification**: On every incoming chat message, both clients compute a SHA-256 hash of their canonical active messages list to verify alignment.
- **Control Handshakes**:
  - `{"type": "sync_request"}`: Dispatched when a hash mismatch is detected, forcing the peer to return its entire active page history for merging.
  - `{"type": "resend_request"}`: Triggers the peer to resend a missing message.
  - `{"type": "failed_decryption"}`: Informs the peer that a message failed verification, labeling it `FAILED_DECRYPTION` without entering sync loops.
- **Loop Prevention**: To avoid E11 recovery sync loops, any decryption failure on control frames (identified by `messageId` prefix `ctrl_`) is discarded silently and never persisted to the database.

### 3. R2 Archiving & On-Demand Traversal
- **Archiving**: SQLite cache is strictly limited to $O(2\text{ chapters})$. When active messages exceed 1000, the oldest 1000 are packed into a `LessonChapter` back-linked to the current `latestChapterHash` (backward singly-linked list), encrypted using the `lessonKey`, uploaded to Cloudflare R2 via presigned PUT URLs, and purged locally.
- **On-Demand Lazy Loading**: Scrolling up triggers the client to fetch a GET presigned URL for `latestChapterHash` via `POST /conversations/messages/download-chapter-url`, download the encrypted `LessonChapter`, decrypt it in RAM, and load the historical messages. Traversals continue recursively using `previousChapterHash`.

## Setup & Testing
To run the automated tests for the router and scaffolding:
```bash
cd modules/mobile
flutter test test/
```

To run the automated tests for the vault feature specifically:
```bash
cd modules/mobile
flutter test test/features/vault/
```

To run the automated tests for the messaging engine specifically:
```bash
cd modules/mobile
flutter test test/features/messaging/
```
