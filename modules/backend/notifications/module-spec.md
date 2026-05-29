# Module Specification: Backend Disguised Push Engine

## 1. Overview
- **Path:** `modules/backend/notifications/`
- **Module ID:** `backend-notifications`
- **Implementation Phase:** Phase 5
- **Core Intent:** Unified Firebase Cloud Messaging endpoints disguised as randomized language-learning reminders, notification receipts, and secure E2EE in-app event log writes.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/backend/auth/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- `POST /notifications/acknowledge/:messageId` — registers notification interactions (fires 3-grey tick status updates)
- `GET /events/:conversationId` — retrieves the encrypted, in-app audit log records

---

## 3. Data Architecture & Schemas

### `events` Schema
- `eventId` (String, unique)
- `conversationId` (String, indexed)
- `type` (String, e.g. WRONG_PIN, WIPE, SESSION_PURGE, DURESS, restoration)
- `encryptedPayloadBlob` (String, E2EE JSON payload details)
- `timestamp` (Date)

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:** - **E8:** Coordinates concurrent FCM alerts to all active room partners during duress events using decoy templates.
- **E14:** Graceful logging of failures inside conversation event lists if location permissions are denied.

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
- [ ] Send a push notification and confirm the outbound Firebase payload strictly contains decoy language-learning headers.
- [ ] Tap a notification on Device B and verify Device A's message tick status upgrades to 3 grey ticks (acknowledged).
- [ ] Verify all 12 operational security alerts successfully generate encrypted documents in the `events` collection.