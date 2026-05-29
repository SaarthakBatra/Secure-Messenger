# Module Specification: Backend Shared Notes Server

## 1. Overview
- **Path:** `modules/backend/notes/`
- **Module ID:** `backend-notes`
- **Implementation Phase:** Phase 6
- **Core Intent:** Continuous CRUD operations for conversation notebook items, WebSocket edit lock brokers, note version snapshots, and auto-save timers.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/backend/auth/`, `modules/backend/conversations/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- `POST /notes` — creates note in conversation notebook
- `GET /notes/:conversationId` — lists note entries (metadata encrypted)
- `PUT /notes/:id` — updates note body and snapshots previous content
- `POST /notes/:id/lock` — locks note for specific editor with timeout
- `DELETE /notes/:id/lock` — releases editor lock and creates snapshots
- `GET /notes/:id/versions` — fetches version history indexes
- `POST /notes/:id/restore/:versionId` — restores note to historical snapshot

---

## 3. Data Architecture & Schemas

### `notes` Schema
- `noteId` (String, unique)
- `conversationId` (String)
- `title` (String, encrypted)
- `encryptedContentBlob` (String)
- `editLock` (Object: heldByUserId, expiresAt)
- `versions` (Array of Objects: versionId, encryptedContentBlob, snapshotByUserId, snapshotAt)

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:** - **E15:** Automatically saves and releases notes edit locks if editor remains inactive for 30 seconds.
- **E16:** Rejects restoration operations on notes if an active edit lock is held by another user.

---

## 6. Implementation Checklist & Phases

### Sub-Task Development Matrix
| Sub-Task | Description | Done |
|---|---|:---:|
| **T.1** | Scaffold schemas, interfaces, and providers. | [ ] |
| **T.2** | Write core controller/handler business logic. | [ ] |
| **T.3** | Implement edge case handlers. | [ ] |
| **T.4** | Add unit and integration test coverages. | [ ] |

### Manual Verification Checklist
- [ ] Create a note and confirm it is saved as an encrypted document.
- [ ] Lock a note for User A, attempt edits by User B, and confirm the server blocks User B with a 423 Locked status.
- [ ] Let the edit lock timeout expire and verify note contents are automatically snapshot and lock is released.