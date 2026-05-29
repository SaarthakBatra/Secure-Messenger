# Module Specification: Backend Conversation Architecture

## 1. Overview
- **Path:** `modules/backend/conversations/`
- **Module ID:** `backend-conversations`
- **Implementation Phase:** Phase 2
- **Core Intent:** Direct conversation setups, invitation codes, out-of-band security key generations, pending timeout cleanup crons, and custom local participant aliases.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/backend/auth/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- `POST /conversations` — create unique conversation room; returns Conversation ID and display-once Conversation Key
- `POST /conversations/:id/join` — accepts code and validates key hashes to enable the partner to join
- `DELETE /conversations/:id/pending` — cancels pending invitations, instantly purging records
- `GET /conversations` — fetches active rooms (IDs and local aliases only)
- `POST /conversations/:id/alias` — assigns a private local nickname to a conversation room
- `POST /conversations/escrow` — stores an encrypted conversation key mapping for the user (using their MSK)
- `GET /conversations/escrow` — retrieves all escrowed conversation keys for the user

---

## 3. Data Architecture & Schemas

### `conversations` Schema
- `conversationId` (String, unique, alphanumeric)
- `adminUserId` (String, creator)
- `participantUserIds` (Array of Strings)
- `status` (String: PENDING | ACTIVE | ROTATING)
- `keyValidationHash` (String, double SHA-256 hash of out-of-band key)
- `encryptedBlob` (String, server-side E2EE metadata details)
- `createdAt` (Date)
- `expiresAt` (Date, active on PENDING status)

### `user_conversation_keys` Schema
- `userId` (String, indexed)
- `conversationId` (String, indexed)
- `encryptedConversationKey` (String, Base64) - The conversation key encrypted with the user's MSK
- `localAlias` (String, Optional)
- `createdAt` (Date)
- *Compound unique index on `{ userId, conversationId }`.*

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:** 
  - **E1:** Auto-expires pending invitations exactly 24 hours after creation via Bull queues.
  - **E2:** Purges all trace elements of invitation transactions when a creator aborts a pending room.
  - **EC-15 (Cleartext Key Generation):** Safely generates the `conversationKey`, saves Argon2id hash, and returns cleartext exactly once.
  - **EC-17 (Pending Expiry):** Native Node.js `setInterval` sweeper automatically destroys unjoined `PENDING` conversations older than 24h.
  - **EC-14 (The Burn Race Condition):** Triggers an atomic cascading sequence of `deleteMany` operations eliminating all traces of a conversation to prevent orphaned artifacts.

---

## 6. Implementation Checklist & Phases

### Sub-Task Development Matrix
| Sub-Task | Description | Done |
|---|---|:---:|
| **T.1** | Scaffold schemas, interfaces, and providers. | [x] |
| **T.2** | Write core controller/handler business logic. | [x] |
| **T.3** | Implement edge case handlers (EC-14, EC-15, EC-17). | [x] |
| **T.4** | Add unit and integration test coverages. | [x] |

### Manual Verification Checklist
- [x] Post conversation creation and verify Conversation ID is returned with the out-of-band key.
- [x] Join the conversation with a wrong key and verify it is rejected with a validation error.
- [x] Wait 24 hours (or run mock test cron) and verify the pending conversation record is fully deleted from the database.