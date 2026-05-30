# Mobile Application Specification (Phase 2.1 & 9.1)

## Overview
This module (`modules/mobile/`) serves as the root for the MultiLingo Flutter mobile application. It acts purely as a routing and state management shell for integrating the other modular features of the app. It adheres to strict isolation principles—containing ZERO business logic of its own.

## Architecture

### 1. State Management
- **Provider:** `flutter_riverpod` (^2.5.0)
- **Scope:** The entire application is wrapped in a `ProviderScope` at the root (`main.dart`).

### 2. Routing (`app_router.dart`)
- **Router:** `go_router` (^14.0.0)
- **Initial Route Logic:**
  - Reads `has_completed_onboarding` from `SharedPreferences`.
  - If `true` -> redirects to `/home`.
  - If `false` (or null) -> redirects to `/onboarding`.
- **Vault Guarding:**
  - Routes like `/vault`, `/vault/settings`, or `/vault/setup` are protected by a middleware/guard.
  - If no vault session is active, the router redirects the request back to `/home` (except for `/vault/setup`).
- **Newly Added Routes:**
  - `/vault`: Maps to `VaultHomeScreen`, the main enclave landing page.
  - `/vault/settings`: Maps to `VaultSettingsScreen`, containing duress PIN configurations, session logs, and grace period controls.
  - `/vault/chat/:id`: Maps to `ChatScreen`, providing real-time secure E2EE messaging, active history rendering, and dynamic text/input capabilities.

### 3. Theming (`app_theme.dart`)
- Centralized theme definitions including `AppColors`, `AppDimensions`, and `AppTextStyles`.
- Provides a consistent visual language across all isolated modules.
- Vault screens employ a dark slate gradient (`#0F2027` to `#203A43`) with neon green (`#00E676`) highlights and white/white70 text.

### 4. Persistence
- **Preferences:** `shared_preferences` (for flags like onboarding status, grace period duration, screenshot protection, `user_id`, and `encrypted_identity_private_key` which stores the MSK-wrapped `translationSyncToken`).
- **Secure Storage:** `flutter_secure_storage`.
- **Local Database `conversations.db` (SQLite with SQLCipher):**
  - Table: **`conversations`**
    - `conversation_id` (Text, Primary Key)
    - `local_alias` (Text)
    - `conversation_key` (Text, E2EE key decrypted/wrapped by MSK/`TranslationCacheConfig`)
    - `admin_user_id` (Text)
    - `status` (Text, e.g., 'PENDING', 'ACTIVE')
    - `partner_username` (Text)
    - `created_at` (Integer)
  - Table: **`messages`**
    - `message_id` (Text, Primary Key)
    - `conversation_id` (Text, Index)
    - `sender_id` (Text)
    - `encrypted_payload` (Text, AES-GCM envelope using the `lessonKey`)
    - `timestamp` (Integer)
    - `delivery_status` (Text, e.g. 'PENDING', 'SENT', 'DELIVERED', 'READ', 'FAILED_DECRYPTION')
    - `chapter_hash` (Text, Nullable, Index) - references `cached_chapters(chapter_hash)`
  - Table: **`active_page_metadata`**
    - `conversation_id` (Text, Primary Key)
    - `local_updated_at` (Integer)
    - `last_sync_hash` (Text)
  - Table: **`cached_chapters`** (NEW)
    - `chapter_hash` (Text, Primary Key)
    - `conversation_id` (Text, Index)
    - `previous_chapter_hash` (Text)
    - `created_at` (Integer)

### 5. Cryptography & Network
- **Networking:** `dio` (configured with authorization headers pointing to current session token).
- **Cryptography:** `flutter_sodium`, `pointycastle`.
  - **MSK (Master Storage Key):** 256-bit symmetric key, resides strictly in-memory during an active session (covert term: `TranslationCacheConfig`).
  - **KDF:** `crypto_pwhash` (Argon2id) derives keys from PIN and Recovery Phrase.
  - **MSK Escrow:** MSK is wrapped using `crypto_aead_xchacha20poly1305_ietf` with the KDF keys and escrowed to the backend.
  - **AES-256-GCM:** Used for message-level and payload-level E2EE on mobile client.

## Core Messaging Engine Services (NEW)

### 1. Cryptography Service (`message_crypto_service.dart`)
- AES-256-GCM encryption/decryption using `PointyCastle`.
- Derives `SubKeyContext.messages` subkeys from `lessonKey`.
- Formats: `Base64(nonce || ciphertext || tag)`. AAD matches context.

### 2. Live WebSocket Service (`websocket_service.dart`)
- Establishes/maintains WS to `ws://localhost:3000/ws?token=$token`.
- Dispatches and listens to `chat` and `receipt` frames.
- Reconnects on network loss, handles overwrites (`1008`).

### 3. Active Page Synchronization (`active_page_sync_service.dart`)
- Executes conflict resolution: compares server/client timestamps and merges/uploads accordingly.
- Automatically pushes backups on exits/backgrounding.

### 4. Hash Alignment Verification (`hashing_alignment_service.dart`)
- Formulates canonical representation of active messages and computes SHA-256.
- Compares hashes on message arrival and triggers P2P sync on mismatch.

### 5. R2 History Archiver (`archiver_service.dart`)
- Offloads old SQLite history (>1000 messages) into encrypted `LessonChapter` backward singly-linked list on R2.
- Updates tail pointer on MongoDB, then purges local active SQLite records.

### 6. Lazy Loading History (`lazy_loading_service.dart`)
- Loads historical `LessonChapter` records from R2 on scroll-up.
- Restricts local cached chapters count to $O(2\text{ chapters})$.

## P2P Control Frames & E11 Recovery Protocols (NEW)
To maintain synchronized states and handle decryption or network dropouts, clients exchange out-of-band P2P control frames.

### 1. Control Frame Specification
- **Identifier**: Any frame with a `messageId` starting with `ctrl_` (e.g., `ctrl_sync_123`).
- **Decryption Rules**:
  - If a control frame fails decryption, it is **discarded silently** and does NOT trigger the E11 recovery flow, avoiding infinite loop triggers.
  - If it decrypts successfully, the control instruction is routed, and the function exits early.
  - Control frames are **never** persisted to the SQLite `messages` table.

### 2. Control Messages Payload Schemas
- **P2P Sync Request**:
  - Payload: `{"type": "sync_request"}`
  - Action: The recipient client immediately compiles and encrypts its entire active page history list and transmits it to the peer to force alignment.
- **Resend Request**:
  - Payload: `{"type": "resend_request", "targetMessageId": "<id>"}`
  - Action: The peer checks its local database for the target message and re-transmits its encrypted payload.
- **Failed Decryption Notification**:
  - Payload: `{"type": "failed_decryption", "targetMessageId": "<id>"}`
  - Action: Inform the peer client that a specific message failed verification, prompting the peer UI to label that message locally as `FAILED_DECRYPTION`.

## Initialization Flow (`main.dart`)
1. Ensure Flutter binding is initialized (`WidgetsFlutterBinding.ensureInitialized()`).
2. Initialize `SharedPreferences` asynchronously.
3. Inject the initialized preferences into Riverpod providers (via `ProviderScope` overrides).
4. Mount the `MultiLingoApp` routing shell.

## Stealth Hook and Native Security Specification (Phase 2.1 & 9.1 Updates)

### 1. Stealth Hook Entrance
- **Trigger:** Tapping the main logo on the decoy home screen (`decoy_home_screen.dart`) 5 times rapidly.
- **Constraints:** The interval between consecutive taps must be less than 2 seconds. If a tap occurs after more than 2 seconds, the counter resets.
- **Action:** Triggers `coverLogoLongPressCallbackProvider`, routing the user to `/vault/setup` (if not configured) or `/home/report-issue` (if configured).

### 2. Network Safety and Error Handling
- **Production Endpoints:** Production environments omit dev shadow endpoints `/dev/*`.
- **Fault-Tolerant Setup:** `completeRegistration` in `SetupWizardProvider` executes public key fetch (`fetchPublicKey`) optionally. If it fails (e.g. 404), the error is caught, and registration proceeds with `sealedCredentials` set to an empty string.
- **Robust Error Interceptor:** `SessionInterceptor` must perform a type check on `err.response?.data` to ensure it is a `Map` before indexing key values like `['code']`. This prevents crashes on HTML 404 error pages returned by CDN/servers.

### 3. Screen Lock / Native App Termination
- **Android BroadcastReceiver:** `MainActivity` registers a receiver for `Intent.ACTION_SCREEN_OFF`.
- **Termination Action:** If `isVaultActive` is set to `true`, the activity invokes `finishAndRemoveTask()` on screen-off to close the app and remove it from the recent apps list.
- **Platform MethodChannel:** Communication of vault status uses the MethodChannel `com.example.mobile/security` with method `setVaultActive` (invoked only on Android).

### 4. Dynamic Screen Protection (App Switcher)
- **Decoy Visibility:** The app switcher preview for decoy screen is fully visible and not protected.
- **Vault Protection:** App switcher preview is protected/blacked out (Android `FLAG_SECURE` / iOS `ScreenProtector.protectDataLeakageWithColor`) only when a vault session is active (`isVaultActive` is true).
