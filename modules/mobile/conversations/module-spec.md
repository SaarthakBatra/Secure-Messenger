# Module Specification: Mobile Conversation Setup & Rooms

## 1. Overview
- **Path:** `modules/mobile/conversations/`
- **Module ID:** `mobile-conversations`
- **Implementation Phase:** Phase 2b (Mobile Client UI & Storage - Improvement Cycle)
- **Core Intent:** Conversation dashboard listing active rooms, invite displays, deep-link routing processors, in-band E2EE auto-join dialog overlays, and WebSocket notifications under a secure, plausible-deniability shell.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/mobile/vault-auth/`
- **Data Flow Contract:** Direct E2EE compliant integration using decoy terminology. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts & UI Screens

### Slate Dark Theme UI Rules
All vault screens must employ the **Slate Dark Theme** visual layout:
- **Primary Background:** `#0F2027` (solid or linear gradient to `#203A43`)
- **Accent Highlighting:** `#00E676` (Neon Green/Emerald)
- **Text Styling:** White / Light Grey (`#FFFFFF`, `#B0BEC5`)

### Screens and Sheets
- **Vault Home Screen (`VaultHomeScreen`):** Maps to `/vault` route. Displays nicknames, status indicators, pending requests list, and active connection status headers. Has exit and refresh buttons.
- **Create Invitation Sheet (`CreateConvoSheet`):** 
  - Requests conversation from server (`POST /conversations`).
  - Generates message prefilled with User ID: `"User <User_ID> wants to start a project..."`.
  - Server wraps key using Alice's and Bob's public keys, returns Alice's wrapped key.
  - Client decrypts wrapped key locally using `translationSyncToken`, encrypts with `TranslationCacheConfig`, and stores it.
  - **No plaintext key is shown to the user or copied to the clipboard.**
- **Join Invitation Sheet (`JoinConvoSheet`):**
  - Displays incoming invitations.
  - Decrypts invite key (`lessonKey`) using `translationSyncToken` in the background, encrypts with `TranslationCacheConfig` (`wrappedLessonKey`), and escrows it via `POST /conversations/:id/join`.

---

## 3. Data Architecture & Schemas

### Encrypted Local Storage (SQLCipher)
- SQLite database (`conversations.db`) is opened using `sqflite_sqlcipher`.
- The raw bytes of the Master Storage Key (`TranslationCacheConfig`) serve as the database encryption password.
- All local SQLite tables are encrypted at rest.

### Database Tables: `conversations`
- `conversation_id` (Text, Primary Key)
- `local_alias` (Text)
- `conversation_key` (Text, E2EE key encrypted with `TranslationCacheConfig`)
- `admin_user_id` (Text)
- `status` (Text, e.g. 'PENDING', 'ACTIVE')
- `partner_username` (Text)
- `created_at` (Integer)

---

## 4. Covert Naming Dictionary (Plausible Deniability)
To prevent reverse-engineering static analysis, the mobile codebase MUST use the decoy naming mappings:

| True Cryptographic Identifier | Covert Term (Mobile Codebase) | Decoy Rationale |
|---|---|---|
| Master Storage Key (MSK) | **`TranslationCacheConfig`** | Looks like translation caching config |
| PIN-Wrapped MSK | **`backupCacheBlob`** | Looks like local backup data |
| Phrase-Wrapped MSK | **`phraseRestoreBlob`** | Decoy learning phrase restorer |
| identityPrivateKey | **`translationSyncToken`** | Looks like API sync authentication |
| identityPublicKey | **`syncProfileId`** | Looks like user diagnostic profile ID |
| Conversation Key | **`lessonKey`** | Looks like a curriculum index key |
| encryptedConversationKey | **`wrappedLessonKey`** | Encrypted lesson metadata |
| sessionKey (RAM ephemeral key) | **`sessionBucketToken`** | Ephemeral memory allocation bucket |
| Active Messages Blob | **`ActiveLessonPage`** | Decoy active lesson tracking |
| Static History Bundle | **`LessonChapter`** | Decoy finished lesson chapter |

---

## 5. Security & Edge Case Handling
- **Wrong Key Lockout (3 Attempts):** Entering a wrong room key 3 times completely wipes that specific conversation from local SQLite tables.
- **PIN/MSK Rotations:** Changing Vault PIN or Duress PIN requires re-authentication (`POST /auth/reauth`) first.
- **Lockout Interception (HTTP 423):** `SessionInterceptor` catches status code `423` (account lockout). Wipes the local database (`conversations.db`), clears all `SharedPreferences` config keys, and resolves the request with a dummy `200 OK` response to prevent flashing error screens.
- **WebSocket Pending Notification:** WebSocket channels relay incoming invitations (`PENDING_INVITE`), keeping the list sync real-time without constant background polling.

---

## 6. Implementation Checklist & Phases

### Sub-Task Development Matrix
| Sub-Task | Description | Done |
|---|---|:---:|
| **T.1** | Add `sqflite_sqlcipher` in `pubspec.yaml` and update `VaultDbService` to use MSK. | [x] |
| **T.2** | Update `app_router.dart` and build `VaultHomeScreen` under the slate dark theme. | [x] |
| **T.3** | Implement exit button, refresh button, and WebSocket notification sync. | [x] |
| **T.4** | Update setup wizard to generate and save X25519 identity keypairs. | [x] |
| **T.5** | Implement background E2EE invite generation and auto-acceptance flows. | [x] |
| **T.6** | Add unit/widget tests for invite and exit flows, and verify the test suites pass. | [ ] |

### Manual Verification Checklist
- [x] Verify SQLCipher database encryption at rest using correct/incorrect passwords.
- [x] Tap Exit Vault on the screen and verify redirect and MSK erasure.
- [x] Create an invitation without displaying any plaintext keys on screen.
- [x] Automatically accept a pending invite, decrypting key in background and establishing session.
- [x] Simulate HTTP 423 lockout response from server, verify silent DB wipe, reset settings, and routing to `/home`.