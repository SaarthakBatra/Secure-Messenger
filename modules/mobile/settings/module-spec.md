# Module Specification: Mobile Unified Settings Controller

## 1. Overview
- **Path:** `modules/mobile/settings/`
- **Module ID:** `mobile-settings`
- **Implementation Phase:** Phase 9
- **Core Intent:** Cover configuration sliders, Vault-level controls (PIN edits, sessions logouts), and admin conversation setups (key rotation wizards, revocations).

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/mobile/vault-auth/`, `modules/mobile/conversations/`, `modules/mobile/security/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- **Unified Decoy Settings Panel:** Manages streaker daily timers and LibreTranslate profiles.
- **Vault General Settings Panel:** PIN changes (re-wraps MSK, calls `POST /auth/msk/update-pin` and updates client key hash), Duress PIN changes (calls `POST /auth/duress-pin/change`), recovery phrase verification, active devices dashboard.
- **Admin Per-Conversation Panel:** Key rotation configurations, note edit lock timers, and member revocation triggers.

---

## 3. Data Architecture & Schemas

None.

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:**
  - **E6:** Locks chat access screens for participants during background administrative key re-encryptions.
  - **E11:** Wipes local room indices on client if wrong keys are entered 3 times post-rotation.
  - **E13:** Terminates and wipes local vault if remote sessions are revoked.
  - **Duress PIN Rotation Collision Prevention:** Setting a new Duress PIN checks locally and rejects the action if the proposed Duress PIN hash matches the active Vault PIN.

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
- [x] Change Vault PIN and verify old PIN fails to unlock the Report Issue vault door.
- [x] Change Duress PIN and verify it logs in with a clean shell vault, and old Duress PIN fails.
- [ ] Trigger Key Rotation as admin, verify partner screen locks, copy new key out-of-band, and verify partner unlocks on entry.
- [ ] Tap Revoke User as admin and verify the revoked partner's local database room tables are instantly purged.