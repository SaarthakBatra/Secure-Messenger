# Module Specification: Mobile Vault Security & Wipers

## 1. Overview
- **Path:** `modules/mobile/security/`
- **Module ID:** `mobile-security`
- **Implementation Phase:** Phase 4
- **Core Intent:** Wiping mechanisms for 3 consecutive failed Vault PIN entries, screenshot lock managers, and duress PIN behaviors opening empty vaults and sending background coordinate payloads.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/mobile/vault-auth/`, `modules/mobile/conversations/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- **Vault Security Overlay:** System-wide dialog handling incorrect PIN tracking.
- **Duress Shell Screen:** Completely authentic, empty vault dashboard hiding background trackers.

---

## 3. Data Architecture & Schemas

### Local Security Settings (SQLite/SecureStorage)
- `wrong_pin_attempts` (Int)
- `duress_activated` (Boolean)
- `overlay_active` (Boolean)

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:** - **E7:** Blocks Vault PIN = Duress PIN setup operations during onboarding.
- **E8:** Silent coordinates upload and dispatch of push notifications to partners during a duress PIN entry.
- **E13:** Forces immediate reset to the cover app on old devices when new sessions are validated elsewhere.

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
- [ ] Enter incorrect Vault PIN 3 consecutive times and verify the entire SQLite database is wiped instantly.
- [ ] Enter the Duress PIN and verify a clean-shell empty vault loads with no errors or visual alert indicators.
- [ ] Verify that attempting screenshots inside the vault displays a blank screen or blocks capture, while cover app works normally.