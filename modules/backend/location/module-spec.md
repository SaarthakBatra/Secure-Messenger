# Module Specification: Backend Discrete Location Router

## 1. Overview
- **Path:** `modules/backend/location/`
- **Module ID:** `backend-location`
- **Implementation Phase:** Phase 7
- **Core Intent:** Discrete location request pings routing, target notifications dispatch, encrypted responses capture, and event logging.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/backend/auth/`, `modules/backend/conversations/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- `POST /location/request/:conversationId` — submits location request to target participant
- `POST /location/respond/:conversationId` — writes encrypted client coordinates response

---

## 3. Data Architecture & Schemas

Uses `events` collection to store transaction records:
- `encryptedPayloadBlob` (E2EE coordinates data inside the event log)

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:** - **E14:** Captures permission failure codes from mobile clients and registers error details inside conversation log events.

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
- [ ] Submit location request and verify a customized WebSocket ping is immediately received by the target partner.
- [ ] Submit location response and verify a coordinates packet is securely forwarded to the initial requester.
- [ ] Verify all location request events successfully write encrypted histories in the MongoDB database.