# Module: Mobile Vault Onboarding & Entry

## Overview
This directory houses the documentation and specifications for `Mobile Vault Onboarding & Entry`. 
To comply with Dart compiler rules, the executable source code resides in `modules/mobile/lib/features/vault_auth/` and `modules/mobile/lib/features/security/`. 

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/mobile-vault-auth-agent.md`.

## Key Actions & Triggers
- **Vault Setup Wizards:** 8 sequential pages (intro, User ID display, recovery phrase backup, Vault PIN selection, Duress PIN selection, grace period configuration, screenshot toggles, completion screen). Managed by `SetupWizardNotifier`.
- **Vault PIN Entry Overlay:** Renders inside the Report Issue form or on long-press triggers. Disguised keypad input.
- **Routing & Session Authentication:** Future modules grant access and make authenticated network requests by reading `vaultSessionNotifierProvider` to retrieve the session type and secure in-memory session token.
- **MSK Session Lifecycle:** The 256-bit MSK state is housed within a dedicated `mskSessionProvider` (StateNotifierProvider). It reacts immediately to `vaultSessionNotifierProvider` and aggressively nullifies the MSK from local RAM whenever the vault session terminates or the app is pushed to the background beyond the grace period.

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/mobile/vault-auth` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/mobile/vault-auth`
- **Linux Setup:** If testing on Fedora-based instances, ensure you run `sudo ln -s /usr/lib64/libsodium.so.26 /usr/local/lib/` to enable `flutter_sodium` bindings.

---

## Detailed Workflow Examples

### 1. First-Time Vault Initialization (Scenario A)
**Normal Flow:**
The user installs the app, completes the Decoy Onboarding, and reaches the Decoy Home screen (`/home`). They perform a strict 3-second Long Press on the Cover Logo. The `coverLogoLongPressCallbackProvider` fires. The stealth orchestrator reads `vault_is_configured == false` from `SharedPreferences` and seamlessly routes the user directly to `/vault/setup`. The user completes the 8-screen setup, setting `vault_is_configured = true`, and is routed to the Vault Home (`/vault`).

### 2. Standard Vault Entry (Phase 1.4 Unified Login & MSK Recovery)
**Normal Flow:**
The user is already set up. They Long Press the Cover Logo, routing them to `/home/report-issue`. They enter exactly 6 digits into the Reference Code field and leave the Description empty, then tap Submit. The `issueReportProvider` triggers the `main.dart` stealth listener. The interceptor uses `Sodium.cryptoHashSha256` to compute a deterministic `Client_Key` from the PIN and `deviceFingerprint`. It sends this to the unified `POST /auth/login` endpoint. Upon receiving a 200 OK with `sessionType: "vault"` and a `sessionToken`, the client calls `GET /auth/msk` to fetch the wrapped MSK blobs. Using the derived PIN KDF key, the client decrypts `pinWrappedMsk` to obtain the raw 256-bit MSK in memory, storing it in `mskSessionProvider`. GoRouter then silently redirects the user to `/vault`.

### 3. Keyboard Dismissal vs. Background Ejection (Edge Case 1)
**Edge Case:**
The user taps "Submit" on the Report Issue form. This action drops the software keyboard, which momentarily triggers the `AppLifecycleState.inactive` OS event. A naive listener would treat this as the app backgrounding and immediately eject the user from the vault.
**Resolution:**
The AppLifecycleState observer respects the user-defined `grace_period_duration`. Additionally, if running on Desktop environments (Linux/macOS/Windows), a 0-second grace period is automatically padded to 5 seconds to prevent immediate lockouts when a developer switches focus to view terminal logs, while maintaining the strict 800ms debounce for Mobile targets. If the grace period expires, both the session token and the raw MSK are purged from memory, and the app redirects to `/home`.

### 4. Vault Setup Wizard & Cryptographic Registration (Phase 1.3/1.4 / Phase 2 MSK Escrow)
**Normal Flow:**
During the 8-screen setup wizard, the user generates a BIP-39 recovery phrase, sets a Vault PIN, and sets a Duress PIN. Upon completion, the app fetches a Curve25519 public key from `GET /dev/public-key`. The app locally hashes the PINs and Recovery Phrase deterministically using `Sodium.cryptoHashSha256` to generate `Client_Key`s. It also seals the true plaintext Vault PIN, Duress PIN, and Recovery Phrase in a `crypto_box_seal`. Simultaneously, the app generates a random 256-bit symmetric MSK and encrypts it twice: once with a key derived from the Vault PIN, and once with a key derived from the Recovery Phrase. This hybrid payload (containing `vaultClientKey`, `duressClientKey`, `recoveryClientKey`, `deviceFingerprint`, `sealedCredentials`, `pinWrappedMsk`, and `phraseWrappedMsk`) is sent to `POST /auth/register`. Upon a `201 Created`, the app presents the newly generated `userId`. Once copied, the user taps "Exit to Decoy App", which drops them onto the Decoy Home screen.
*Note: Tapping the back button on the wizard's AppBar immediately aborts setup and explicitly routes to `/home`, permanently preventing unauthenticated leaks into the `/vault` stack.*

### 5. Duress PIN Conflict Validation (Edge Case E7)
**Edge Case:**
During the Vault Setup Wizard (Phase 1.3), the user attempts to set their Duress PIN to be exactly the same as their Vault PIN.
**Resolution:**
The local UI validation securely hashes the input and compares it against the Vault PIN state. If they match, the UI rejects the input and requires a unique Duress PIN to proceed, ensuring the plausible deniability wipe mechanism cannot be accidentally triggered during normal login.

### 6. Phase 1.4: Vault Decrypt & Entry Handoff
**Next Step Workflow:**
Once Phase 1.3 is complete, Phase 1.4 implemented the actual login flow utilizing the Hash-then-Hash architecture and unified API endpoint.

### 7. Permanent Stealth Lockout (Burn Protocol)
**Edge Case / Coercion Attack:**
An adversary forces the user to enter a PIN, but the user repeatedly enters an incorrect PIN (or an attacker uses an automated tool).
**Resolution:**
The stealth interceptor calls `POST /auth/login` and receives a `401 Unauthorized`. It increments a local `wrong_pin_attempts` counter. Once this hits 3, the app executes the **Burn Protocol**: it deletes `vault_is_configured`, `user_id`, and `recovery_phrase_words` from local storage and writes a permanent `vault_burned = true` flag. The UI shows a generic network error. Forever after, all stealth triggers (long presses, dummy pins) instantly abort. The app becomes a permanently benign decoy, forcing a full uninstall/reinstall to recover via phrase.

### 8. Covert Identity Restoration (Device Migration)
**Normal Flow:**
When migrating to a new device, a user avoids the Setup Wizard entirely to preserve operational security. Instead, they navigate to the Decoy App's Settings screen and type their existing 9-11 digit numeric `user_id` into the "System Diagnostics & Codes" text field. The app silently queries `GET /dev/shadow/:userId`. Upon a 200 OK, the app writes the ID to `SharedPreferences`, flags the vault as configured in memory, and displays a decoy "Diagnostic profile applied successfully." SnackBar. The user can then immediately log in via the Report Issue stealth form using their original PIN.

### 9. Active ID Covert Query
**Normal Flow:**
To view their current `user_id` without exposing themselves to shoulder-surfing in the Vault UI, a user can enter `#*ID*#` into the Decoy Settings Diagnostic field. This triggers a premium overlay Dialog displaying the ID with a copy-to-clipboard button. For security, the dialog auto-dismisses after precisely 3 seconds if not closed manually.

### 10. Vault PIN Rotation & MSK Re-wrapping
**Normal Flow:**
1. The user navigates to Vault Settings and submits a new Vault PIN.
2. The client fetches the current raw MSK from `mskSessionProvider` (which is unlocked in memory).
3. The client derives a new key from the new Vault PIN using PBKDF2-SHA256.
4. The client re-encrypts the raw MSK using this new key to generate a new `pinWrappedMsk`.
5. The client submits `POST /auth/msk/update-pin` to update the escrowed payload on the server.
6. Once the server responds with 200 OK, the client updates the local clientKey hash on the server using the existing credentials change endpoint.

### 11. Duress PIN Rotation
**Normal Flow:**
1. The user navigates to Vault Settings and enters a new Duress PIN.
2. The client derives the new duress client key hash and compares it against the active Vault PIN hash to ensure there is no collision.
3. The client submits `POST /auth/duress-pin/change` sending the current active Vault client key as verification and the new Duress client key.
4. The server validates the Vault client key and updates the stored duress PIN hash.

### 12. Token Refresh & Re-Authentication Interceptor
**Normal Flow:**
1. A background request returns `401 Unauthorized` with `code: 'REFRESH_EXPIRED'`.
2. The custom Dio `SessionInterceptor` halts all outgoing requests and silently hits `/auth/refresh` using a separate clean instance.
3. Upon success, it patches `VaultSessionNotifier` with the new refresh token, injects the new token into the original queued requests, and seamlessly resumes operation.
4. If the server returns `401 SESSION_EXPIRED`, the interceptor triggers the global Re-Authentication Overlay. A premium UI prompts the user to enter their Vault PIN within a countdown timer (e.g., 10 seconds). Successful PIN entry resumes the queued requests.
5. If the server detects intrusion (`403 HACK_DETECTED`) or rate-limit lockouts (`423 LOCKED_OUT`), the interceptor immediately invokes the Active Burn Protocol, wiping the SQLite database and all shared preferences, rendering the app a permanent decoy. It then swallows the HTTP error and returns a dummy `200 OK` so the decoy app doesn't flash a vault-related network error, preserving plausible deniability.