# Module Specification: Mobile Recovery Phrase & Request UI

## 1. Overview
- **Path:** `modules/mobile/restoration/`
- **Module ID:** `mobile-restoration`
- **Implementation Phase:** Phase 8
- **Core Intent:** On-screen recovery phrase wizards, restoration form decks, and administrative approval screens displaying requester descriptions.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/mobile/vault-auth/`, `modules/mobile/conversations/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- **Mnemonic Recovery Screen:** Form prompting for 12-word mnemonic phrase.
- **Restoration Wizard Screen:** Prompts for Conversation ID and request notes.
- **Admin Review Queue Screen:** Panel rendering outstanding partner requests.

---

## 3. Data Architecture & Schemas

### Local Database `restorations` (SQLite)
- `request_id` (Text, Primary Key)
- `conversation_id` (Text)
- `status` (Text)
- `reason_text` (Text)

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:** - **E3:** Blocks non-admins with informative dialogs until admin restorations are confirmed.
- **E4:** Guides users through restoring single conversations after recovery logins.
- **E5:** Informs users that request will auto-approve on inactivity thresholds if admin remains offline.
- **E10:** Handles admin self-restoration pipelines seamlessly.
- **E12:** Enforces proper administrative recovery ordering.

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
- [ ] Log in using the Recovery Phrase, verify all local rooms are wiped, and confirm the remote ID browser is active.
- [ ] Submit restoration request on Device B, open vault on Device A, and verify Approve/Deny buttons appear in event logs.
- [ ] Tap Approve on Device A, verify Device B displays PIN prompt, enters Key, and decrypts full conversation history.