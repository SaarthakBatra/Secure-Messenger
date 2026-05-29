# Module Specification: Mobile Notebook UI & Editor

## 1. Overview
- **Path:** `modules/mobile/notes/`
- **Module ID:** `mobile-notes`
- **Implementation Phase:** Phase 6
- **Core Intent:** Shared Markdown editor widgets with real-time observer socket broadcasts, edit lock visual blocks, and note snapshot browser decks.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/mobile/vault-auth/`, `modules/mobile/conversations/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- **Notebook Dashboard Screen:** Lists all shared notes in a conversation.
- **Markdown Editor Screen:** Renders edit interface with automatic Markdown rendering. Disables inputs if locked.

---

## 3. Data Architecture & Schemas

### Local Database `notes` (SQLite)
- `note_id` (Text, Primary Key)
- `conversation_id` (Text)
- `encrypted_title` (Text)
- `encrypted_content` (Text)
- `lock_owner` (Text)
- `lock_expiration` (Int)

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:** - **E15:** Automatically exits edit panels and saves progress immediately when local timeout alerts fire.
- **E16:** Displays explicit visual blocks preventing note restoration while partners edit notes.

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
- [ ] Open note on Device A, verify Device B immediately shows note as 'Locked by Partner' and disables editor button.
- [ ] Type on Device A and verify Device B shows beautiful real-time keystroke preview updates in read-only mode.
- [ ] Restore a note version as admin and verify a new history snapshot is generated rather than destroying history.