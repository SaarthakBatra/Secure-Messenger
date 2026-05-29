# Module Specification: Backend Restoration Requests Admin

## 1. Overview
- **Path:** `modules/backend/restoration/`
- **Module ID:** `backend-restoration`
- **Implementation Phase:** Phase 8
- **Core Intent:** Security restoration queues, admin review dashboards, automatic approval crons (escape valve), and recovery phrase conversation indexes.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/backend/auth/`, `modules/backend/conversations/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- `POST /restoration/request` — files a conversation recovery request
- `GET /restoration/pending` — fetches active recovery requests for admin review
- `POST /restoration/approve/:requestId` — admin approves recovery; enables key syncs
- `POST /restoration/deny/:requestId` — admin denies restoration request
- `GET /restoration/recovery-list` — fetches encrypted conversation lists matching PBKDF2 recovery tokens

---

## 3. Data Architecture & Schemas

### `restoration_requests` Schema
- `requestId` (String, unique)
- `conversationId` (String)
- `requestingUserId` (String)
- `reasonBlob` (String, encrypted explanation)
- `status` (String: PENDING | APPROVED | DENIED)
- `createdAt` (Date)
- `resolvedAt` (Date)

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:** - **E3:** Rejects requests from non-admins if the admin has not restored the conversation first.
- **E4:** Re-indexes matches across encrypted database lists using recovery hashes.
- **E5:** Auto-approves requests if the admin does not log in for the configured escape valve duration (30-365 days).
- **E10:** Auto-approves admin self-restoration requests directly.
- **E12:** Manages simultaneous data recovery sequences cleanly.

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
- [ ] Trigger recovery request and verify conversation admin receives a notification badge in their review tab.
- [ ] Verify a non-admin attempting recovery receives a blocked warning until the admin has completed restoration.
- [ ] Set the admin inactivity threshold to 1 minute, wait, and verify the Bull job auto-approves pending request tickets.