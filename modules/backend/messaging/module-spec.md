# Module Specification: Backend WebSocket & Messaging Hub

## 1. Overview
- **Path:** `modules/backend/messaging/`
- **Module ID:** `backend-messaging`
- **Implementation Phase:** Phase 3
- **Core Intent:** WebSocket servers holding direct authenticated streams, offline packet caching, pre-signed R2 storage URL generators, soft deletes, and delivery tick cascades.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/backend/auth/`, `modules/backend/conversations/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- `WebSocket /ws` — real-time subscription routing for all message events
- `POST /messages` — accepts encrypted message payloads to buffer to disk
- `POST /media/upload` — requests a pre-signed Cloudflare R2 upload path
- `GET /media/download/:mediaId` — retrieves pre-signed R2 media read URLs
- `PUT /messages/:id/hide` — adds active user ID to hidden lists for soft deletes

---

## 3. Data Architecture & Schemas

### `messages` Schema
- `messageId` (String, unique)
- `conversationId` (String, indexed)
- `senderUserId` (String)
- `encryptedBlob` (String, GCM encrypted message metadata and contents)
- `tickStatus` (String: SENT | DELIVERED | ACKNOWLEDGED | READ)
- `timestamps` (Object: sentAt, deliveredAt, acknowledgedAt, readAt)
- `hiddenFlags` (Array of Strings)

### `media_refs` Schema
- `mediaId` (String, unique)
- `conversationId` (String)
- `r2Key` (String, `/conversationId/mediaId` path)
- `encryptedMetaBlob` (String)

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:** - **E11:** Blocks media and message sync actions on devices whose keys are wiped from consecutive rotational failures.

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
- [ ] Send an encrypted message over WebSockets and verify the packet returns with a SENT status code.
- [ ] Request R2 pre-sign links and confirm the key layout strictly follows `/conversationId/mediaId` format.
- [ ] Call the local hide endpoint and verify the target user's ID is appended to `hiddenFlags` list.