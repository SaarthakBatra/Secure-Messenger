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
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention using `flutter_windowmanager` (Android `FLAG_SECURE`) and `screen_protector` (iOS), and zero server plaintext.
- **Edge Cases Handled:** 
  - **E7:** Blocks Vault PIN = Duress PIN setup operations during onboarding.
  - **E8:** Silent coordinates upload and dispatch of push notifications to partners during a duress PIN entry.
  - **E13:** Forces immediate reset to the cover app on old devices when new sessions are validated elsewhere.
  - **Edge Case 2 (App Switcher Leak):** Ignoring `inactive` lifecycle states leaves the Vault UI fully visible in the OS App Switcher carousel. Android blocks this entirely via `FLAG_SECURE`, while iOS utilizes `screen_protector` to draw a `#0F2027` block over the screen the millisecond the home bar is touched.

---

## 6. Implementation Checklist & Phases

### Sub-Task Development Matrix (Phase 1.1)
| Sub-Task | Description | Done |
|---|---|:---:|
| **T.1** | Native Security Integrations (`flutter_windowmanager`, `screen_protector`). | [x] |
| **T.2** | Write core stealth controllers inside `main.dart` for lifecycle routing. | [x] |
| **T.3** | Implement edge case handlers (Keyboard dismissal debounce). | [x] |
| **T.4** | Configure Duress Wipe protocol hooks (Phase 4 deferred). | [x] |

### Manual Verification Checklist
- [x] Verify that attempting screenshots inside the vault displays a blank screen or blocks capture on Android, while the cover app works normally.
- [x] Verify iOS app switcher overlays the screen with `#0F2027` color when swiping up.