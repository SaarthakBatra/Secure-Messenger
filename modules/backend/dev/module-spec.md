# Module Specification: Developer Shadow Infrastructure

## 1. Overview
- **Path:** `modules/backend/dev/`
- **Module ID:** `backend-dev`
- **Implementation Phase:** Phase 0
- **Core Intent:** Developer-only super key database shadow-writing collection, encryption/decryption middleware, and secure administrative recovery retrieval endpoints.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- `GET /dev/public-key` — retrieves the rotating development Curve25519 public key for the asymmetric bridge
- `GET /dev/shadow/:userId` — administrative endpoint to pull all decrypted credentials (dev-only)
- `POST /dev/shadow/wipe` — administrative trigger to purge all shadow-written records

---

## 3. Data Architecture & Schemas

### `dev_shadow` Collection Schema
- `userId` (String, unique key)
- `vaultPinHash` (String, AES-256-GCM encrypted original PIN Argon2id derivative)
- `duressPinHash` (String, AES-256-GCM encrypted duress PIN Argon2id derivative)
- `recoveryPhrase` (String, AES-256-GCM encrypted 12-word mnemonic phrase)
- `conversationKeys` (Array of Objects: conversationId + AES-256-GCM encrypted conversationKey)
- `createdAt` (Date)

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:** None directly. Serves as active development debugger assistance.

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
- [ ] Trigger a mock credential write and verify shadow document is successfully generated in `dev_shadow` collection.
- [ ] Query the shadow retrieval endpoint with correct auth headers and verify all sensitive fields are returned fully decrypted.
- [ ] Run CI regex scanner and ensure it flags any references to superKey or dev_shadow when ENV is set to production.