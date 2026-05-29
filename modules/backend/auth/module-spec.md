# Module Specification: Backend Anonymous Identity & Auth

## 1. Overview
- **Path:** `modules/backend/auth/`
- **Module ID:** `backend-auth`
- **Implementation Phase:** Phase 1
- **Core Intent:** Anonymous user accounts creation, PIN logins, duress login hooks, mnemonic recovery logins, and single-session validation middleware.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/backend/dev/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- `POST /auth/register` — anonymous registration generating 9-10 digit User ID. Accepts client-side Argon2id hashes (`vaultPinHash`, `duressPinHash`), optional `sealedCredentials` for dev shadow, and MSK escrow blobs (`pinWrappedMsk`, `phraseWrappedMsk`).
- `POST /auth/login` — standard vault PIN login; purges all previous sessions.
- `POST /auth/login/duress` — duress PIN login; grants clean-shell token and sets trigger state.
- `POST /auth/login/recovery` — 12-word recovery mnemonic login; invalidates PIN and returns convo ID lists.
- `POST /auth/pin/change` — resets the vault PIN given correct previous credentials.
- `GET /auth/msk` — fetches the `pinWrappedMsk` and `phraseWrappedMsk` blobs for the active user.
- `POST /auth/msk/update-pin` — updates the user's `pinWrappedMsk` blob upon Vault PIN rotation.
- `POST /auth/duress-pin/change` — resets the user's duress PIN hash after verifying current Vault PIN credentials and asserting non-collision.
- `DELETE /auth/session` — terminates active session and issues logged notifications to partners.

---

## 3. Data Architecture & Schemas

### `users` Schema
- `userId` (String, unique)
- `pinHash` (String, Argon2id derivative of Vault PIN)
- `duressPinHash` (String, Argon2id derivative of Duress PIN)
- `recoveryPhraseHash` (String, PBKDF2 hash of 12-word mnemonic)
- `pinWrappedMsk` (String, Base64 representation of MSK encrypted with Vault PIN key)
- `phraseWrappedMsk` (String, Base64 representation of MSK encrypted with Recovery Phrase key)
- `createdAt` (Date)

### `sessions` Schema
- `userId` (String)
- `token` (String, indexed)
- `deviceFingerprint` (String)
- `createdAt` (Date)
- `invalidatedAt` (Date, null if active)

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:** 
  - **E7:** Blocks Duress PIN = Vault PIN matching during credential creation via hash comparisons.
  - **E9:** Session timeout and state handling during client-side phone call interruptions.
  - **E13:** Wipes active sessions immediately when a new device successfully logs in with the user's credentials.
  - **EC-05 (Timing Attacks):** Uses `dummyVerify()` for invalid User IDs to ensure uniform response times.
  - **EC-07 (Brute Force):** 15-minute lockout upon 3 failed attempts, augmented with rate limiting.
  - **Duress PIN Rotation Collision Prevention:** The `POST /auth/duress-pin/change` endpoint asserts that the proposed new Duress PIN derivative does not match the active Vault PIN hash, preventing coercion leaks.

---

## 6. Implementation Checklist & Phases

### Sub-Task Development Matrix
| Sub-Task | Description | Done |
|---|---|:---:|
| **T.1** | Scaffold schemas, interfaces, and providers. | [x] |
| **T.2** | Write core controller/handler business logic. | [x] |
| **T.3** | Implement edge case handlers. | [x] |
| **T.4** | Add unit and integration test coverages. | [x] |

### Manual Verification Checklist
- [x] Attempt registration and verify a random 9-10 digit User ID is successfully returned.
- [x] Attempt registration with identical Vault PIN and Duress PIN; verify the server blocks with a validation error.
- [x] Log in on Device B and verify Device A's active session is instantly invalidated and returned with a 401 Unauthorized.