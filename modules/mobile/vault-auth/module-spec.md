# Module Specification: Mobile Vault Onboarding & Entry

## 1. Overview
- **Path:** `modules/mobile/vault-auth/` (Documentation)
- **Executable Source:** `modules/mobile/lib/features/vault_auth/` & `modules/mobile/lib/features/security/`
- **Module ID:** `mobile-vault-auth`
- **Implementation Phase:** Phase 1
- **Core Intent:** Vault access triggers, 8-screen initial vault setup flow, PIN inputs, grace period lockouts, and recent apps screenshot obscuring overlays.

### Structural Rule Enforcement
To comply with the Flutter Dart compiler's strict package-boundary restrictions, all executable source code resides within the `lib/` tree. The `modules/mobile/vault-auth/` directory strictly houses the specifications, READMEs, and graph files. Future agents must maintain this separation of documentation and code.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/mobile/cover/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- **Vault Setup Wizards:** 8 sequential pages (intro, User ID display, recovery phrase backup, Vault PIN selection, Duress PIN selection, grace period configuration, screenshot toggles, completion screen). State managed by `SetupWizardNotifier`. Sleek dark UI (#0F2027, #00E676 accents).
- **Vault PIN Entry Overlay:** Renders inside the Report Issue form or on long-press triggers. Disguised keypad input.

### API Integration Contract (Phase 1.3 / Phase 2 MSK Escrow)
- **GET `/dev/public-key`:** Fetches rotating development Curve25519 public key.
  - *Critical Note:* The frontend `AuthApiService` actively normalizes the backend's base64url response prior to decoding to prevent Dart `FormatException` errors.
- **POST `/auth/register`:** 
  - Hits the endpoint via `dio` and expects a `201 Created` containing the `userId`.
  - Generates deterministic `Client_Key`s using SHA-256 locally via `SodiumCryptoService`. `vaultClientKey` and `duressClientKey` use `SHA256(PIN + deviceFingerprint)`. `recoveryClientKey` uses `SHA256(recoveryPhrase)`.
  - Generates sealed box (`crypto_box_seal`) containing plaintext Vault PIN, Duress PIN, and Recovery Phrase using the fetched public key.
  - Generates a 256-bit symmetric MSK and encrypts it using `XChaCha20-Poly1305` and `PBKDF2-SHA256` keys derived from the user's PIN and Recovery Phrase.
  - **Payload schema:**
    ```json
    {
      "vaultClientKey": "<SHA-256 Hash>",
      "duressClientKey": "<SHA-256 Hash>",
      "recoveryClientKey": "<SHA-256 Hash>",
      "deviceFingerprint": "dev-fingerprint-mobile",
      "sealedCredentials": "<Base64 Encoded Curve25519 Sealed Box>",
      "pinWrappedMsk": "<Base64 String>",
      "phraseWrappedMsk": "<Base64 String>"
    }
    ```
- **POST `/auth/login` (Phase 1.4):**
  - Sends `{ "userId": "...", "clientKey": "<SHA256(PIN + deviceFingerprint)>", "deviceFingerprint": "..." }`.
  - Returns `sessionToken` and `sessionType` (`vault`, `duress`, or `recovery`).
  - **In-Memory Token Flow:** The `sessionToken` is stored strictly in memory within `VaultSessionNotifier` (`_token`) and is never persisted to `SharedPreferences` or disk.
  - **Token Lifetime:** The `sessionToken` is cleared automatically upon background/inactivity ejection or explicit logout, preventing memory-dump leaks.
  - Catches 401 Unauthorized (increments `wrong_pin_attempts`).
  - Handles 429 Too Many Requests (rate limiting max 5 attempts/min) gracefully.
- **GET `/auth/msk` (Phase 2):**
  - Returns the encrypted MSK payloads `{ pinWrappedMsk, phraseWrappedMsk }`.
- **POST `/auth/msk/update-pin` (Phase 2):**
  - Sends `{ "newPinWrappedMsk": "..." }` when the user updates their Vault PIN.
- **POST `/auth/duress-pin/change` (Phase 2):**
  - Sends `{ "currentClientKey": "...", "newDuressClientKey": "..." }` to rotate the duress PIN.

---

## 3. Data Architecture & Schemas

### Secured Local Prefs (SecureStorage)
- `vault_setup_completed` (Boolean)
- `grace_period_duration` (Int, seconds)
- `screenshot_protection_enabled` (Boolean)
- `user_id` (String)
- `recovery_phrase_words` (List of Strings)
- `wrong_pin_attempts` (Int)
- `vault_burned` (Boolean)

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:** 
  - **E7:** Intercepts and rejects matching Vault and Duress PINs during the setup wizard.
  - **E9:** Automatically starts a grace period timer during telephone interruptions, enforcing PIN prompt on lock release.
  - **Edge Case 1 (Keyboard Dismissal vs. Ejection):** Tapping "Submit" drops the software keyboard, triggering a brief `AppLifecycleState.inactive`. The AppLifecycleState observer now correctly respects the user-defined `grace_period_duration` (offering 10-second increments up to 5 minutes). Additionally, if running on Desktop environments (Linux/macOS/Windows), a 0-second grace period is automatically padded to 5 seconds to prevent immediate lockouts when a developer switches focus to view terminal logs, while maintaining the strict 800ms debounce for Mobile targets.
  - **Edge Case 3 (Router Annihilation):** Decoupled GoRouter rebuilds from authentication state via a `VaultSessionNotifier` attached to `refreshListenable`, preserving the navigation stack.
  - **Setup Routing Leak (Phase 1.4.3):** The `VaultSetupWrapper` AppBar strictly binds the back button to `context.go('/home')`. This entirely eliminates the possibility of `Navigator.pop()` dropping a user into the unauthenticated `/vault` stack upon aborting setup.
  - **Covert Identity Restoration (Phase 1.4.4):** Migrating users bypass the Setup Wizard entirely by entering a 9-11 digit ID into the Decoy Settings Diagnostic field. The client validates existence via `GET /dev/shadow/:userId`. On `200 OK`, it imports the ID to `SharedPreferences` and enables the vault stealth hooks cleanly.
  - **Active ID Covert Query (Phase 1.4.4):** The Decoy Settings Diagnostic field acts as a stealth trigger for `#*ID*#`, launching an auto-dismissing (3-second timer) premium popup that displays the active User ID for secure copy-to-clipboard functionality without entering the actual vault.
  - **Linux Native Dependency:** Requires the `/usr/lib64/libsodium.so.26` symlink injected into `/usr/local/lib/` for Fedora-based developer instances to successfully bind `flutter_sodium`.
  - **Permanent Stealth Lockout (Burn Protocol):** If `wrong_pin_attempts >= 3`, the vault is wiped (keys deleted) and `vault_burned` is set to true. All stealth triggers are permanently ignored to maintain plausible deniability.
  - **Covert Entry Stealth Delays:** Displays native loading spinners upon detecting a 6-digit stealth PIN. A 10-second auto-timeout is implemented to lock the submit button; if the stealth vault network authentication fails, the UI organically times out and displays a mock failure message (e.g., "Failed to upload diagnostic package"), perfectly preserving the decoy illusion.
  - **MSK Session Lifecycle:** The 256-bit MSK state is housed within a dedicated `mskSessionProvider` (StateNotifierProvider). It reacts immediately to `vaultSessionNotifierProvider` and aggressively nullifies the MSK from local RAM whenever the vault session terminates or the app is pushed to the background beyond the grace period.
  - **Token Refresh Interceptor:** A `SessionInterceptor` (Dio) transparently catches `401 REFRESH_EXPIRED` errors. It halts the queue, performs a silent `/auth/refresh` request using a clean Dio instance, updates the `VaultSessionNotifier` with the new refresh token, and retries the original request.
  - **Re-Authentication Overlay:** If the interceptor catches a `401 SESSION_EXPIRED`, it triggers a global premium Re-Authentication Overlay. The queue is halted while a countdown timer dictates the `reauthGracePeriodSeconds`. If the user successfully enters their PIN before the timeout, the new token is injected and original requests retry.
  - **Active Burn Protocol (HACK_DETECTED / LOCKED_OUT):** If refresh/reauth or any request returns `403 HACK_DETECTED` or `423 LOCKED_OUT`, the custom `SessionInterceptor` actively wipes the local `VaultDbService` SQLite database (`conversations.db`), clears all `SharedPreferences` keys (`vault_is_configured`, `user_id`, `recovery_phrase_words`), sets `vault_burned` to `true`, and ejects the user to the decoy app. Crucially, to maintain plausible deniability, the interceptor swallows the HTTP error and resolves the failed Dio request with a dummy `200 OK` payload so the decoy UI never displays vault-related technical network errors.

---

## 6. Implementation Checklist & Phases

### Sub-Task Development Matrix (Phase 1.1)
| Sub-Task | Description | Done |
|---|---|:---:|
| **T.1** | Scaffold Stealth Hooks (`coverLogoLongPressCallbackProvider`, `issueReportProvider`). | [x] |
| **T.2** | Reactive Routing Architecture (`VaultSessionNotifier` + `refreshListenable`). | [x] |
| **T.3** | Implement edge case handlers (800ms debounce timer for keyboard drops). | [x] |
| **T.4** | State Synchronization (Bridge `SharedPreferences` to `StateProvider`). | [x] |

### Manual Verification Checklist
- [x] Trigger vault onboarding via strict 3-second Long Press on Cover Logo.
- [x] Trigger vault input by entering exactly 6 digits in the 'Error Code' field of the feedback form with an empty description and verify it unlocks.
- [x] Background the app completely and verify immediate ejection to `/home` due to lifecycle observer.
- [x] Tap submit (dropping keyboard) and verify the 800ms debounce timer prevents accidental ejection.