# Module: Mobile Conversation Setup & Rooms

## Overview
This directory houses the codebase for the **Mobile Conversation Setup & Rooms** feature, operating under `Phase 2b` development guidelines.

## Decoy Terminology (Plausible Deniability)
To ensure safety against forensic/static inspection, the following terms are used in the codebase:
- **`TranslationCacheConfig`** (MSK / Master Storage Key)
- **`lessonKey`** (Conversation Key)
- **`wrappedLessonKey`** (Encrypted Conversation Key)
- **`translationSyncToken`** (Identity Private Key)
- **`syncProfileId`** (Identity Public Key)

## Key Actions & Triggers
- **Vault Home Screen:** Route `/vault`. Displays active rooms and pending invitations using the Slate Dark theme (`#0F2027` background, `#00E676` accents). Contains manual Refresh and Exit Session buttons.
- **Create Invitation Wizard:** Calls `POST /conversations` with the recipient User ID and prefilled message. Decrypts Alice's payload returned by the server in the background, wraps it with `TranslationCacheConfig`, and stores it. **Does not display any plaintext keys.**
- **Join Room Dialog / Auto-Accept:** Bob's client receives the invite over WebSockets or on login sync. It decrypts the wrapped key using `translationSyncToken`, wraps it with `TranslationCacheConfig`, and calls `POST /conversations/:id/join` to automatically accept the request.
- **Lockout Interception:** On 423 lockout, performing a local SQLite database wipe, clearing local config, and returning a dummy `200 OK`.

## Developer Verification Commands
- **Mobile tests:** `flutter test tests/mobile/conversations/`

---

## Detailed Workflow Examples

### 1. In-Band Asymmetric E2EE Invitation Flow
**Normal Flow:**
1. User A (Alice) wants to start a chat with User B (Bob). She enters Bob's User ID and an optional invitation message (prefilled with Alice's ID).
2. She taps "Create Project". Her client calls `POST /conversations` with recipient details.
3. The server generates the `lessonKey`, wraps it with Alice's public key (`syncProfileId`) and Bob's public key, deletes plaintext RAM traces, and returns/delivers them.
4. Alice's client decrypts the payload in the background, wraps it using her `TranslationCacheConfig`, and stores it locally. No key is displayed.
5. Bob's client receives the payload via WebSockets or login sync, shows the invite card, and decrypts/accepts it silently upon Bob clicking **Accept**.