# Module Specification: Mobile Messaging UI & Encrypter

## 1. Overview
- **Path:** `modules/mobile/messaging/`
- **Module ID:** `mobile-messaging`
- **Implementation Phase:** Phase 3
- **Core Intent:** On-device E2EE message processors (AES-256-GCM), real-time chat bubbles, tick indicator widgets, media selectors, and local swipe-to-hide actions.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/mobile/vault-auth/`, `modules/mobile/conversations/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- **Active Chat Screen:** Infinite list rendering message bubbles, media attachments, and local action buttons.
- **Attachment Panel:** Integrated image selectors and document browsers before cryptographic uploads.

---

## 3. Data Architecture & Schemas

### Local Database `messages` (SQLite)
- `message_id` (Text, Primary Key)
- `conversation_id` (Text)
- `sender_user_id` (Text)
- `plaintext_body` (Text, decrypted locally)
- `media_local_path` (Text)
- `tick_status` (Text)
- `is_hidden` (Int, 0 or 1)
- `timestamp` (Int)

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:** - **E11:** Executes immediate local database wipes on a specific room if wrong keys are inputted 3 consecutive times.

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
- [ ] Send a text message and confirm 1 tick (sent) changes to 2 ticks (delivered) immediately when recipient joins.
- [ ] Swipe a message and verify it disappears locally, but remains perfectly visible on the partner's screen.
- [ ] Verify that images are fully encrypted locally on-device before being transmitted to Cloudflare R2 buckets.