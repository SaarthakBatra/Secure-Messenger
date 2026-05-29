# Module Specification: Mobile Vault Onboarding & Entry

## 1. Overview
- **Path:** `modules/mobile/vault-auth/`
- **Module ID:** `mobile-vault-auth`
- **Implementation Phase:** Phase 1
- **Core Intent:** Vault access triggers, 8-screen initial vault setup flow, PIN inputs, grace period lockouts, and recent apps screenshot obscuring overlays.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/mobile/cover/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- **Vault Setup Wizards:** 8 sequential pages (intro, User ID display, recovery phrase backup, Vault PIN selection, Duress PIN selection, grace period configuration, screenshot toggles, completion screen).
- **Vault PIN Entry Overlay:** Renders inside the Report Issue form or on long-press triggers. Disguised keypad input.

---

## 3. Data Architecture & Schemas

### Secured Local Prefs (SecureStorage)
- `vault_setup_completed` (Boolean)
- `grace_period_duration` (Int, seconds)
- `screenshot_protection_enabled` (Boolean)
- `user_id` (String)
- `recovery_phrase_words` (List of Strings)

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:** - **E7:** Intercepts and rejects matching Vault and Duress PINs during the setup wizard.
- **E9:** Automatically starts a grace period timer during telephone interruptions, enforcing PIN prompt on lock release.

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
- [ ] Trigger vault onboarding via 'Enable Premium Features' and complete all 8 setup screens.
- [ ] Trigger vault input by entering Vault PIN in the 'Error Code' field of the feedback form and verify it unlocks.
- [ ] Background the app, wait longer than the configured grace period, foreground, and verify the Vault PIN keypad is shown.