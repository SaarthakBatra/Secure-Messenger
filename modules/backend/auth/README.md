# Module: Backend Anonymous Identity & Auth

## Overview
This directory houses the isolated codebases for `Backend Anonymous Identity & Auth`, operating within `Phase 1` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/backend-auth-agent.md`.

## Key Actions & Triggers
- `POST /auth/register` — anonymous registration generating 9-10 digit User ID; accepts MSK escrow payloads.
- `POST /auth/login` — standard vault PIN login; purges all previous sessions.
- `POST /auth/login/duress` — duress PIN login; grants clean-shell token and sets trigger state.
- `POST /auth/login/recovery` — 12-word recovery mnemonic login; invalidates PIN and returns convo ID lists.
- `POST /auth/pin/change` — resets the vault PIN given correct previous credentials.
- `GET /auth/msk` — returns the encrypted MSK payloads (`pinWrappedMsk` & `phraseWrappedMsk`).
- `POST /auth/msk/update-pin` — updates the user's PIN-wrapped MSK.
- `POST /auth/duress-pin/change` — updates the user's duress PIN hash after verifying current Vault PIN credentials and asserting non-collision.
- `DELETE /auth/session` — terminates active session and issues logged notifications to partners.

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/backend/auth` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/backend/auth`

---

## Detailed Workflow Examples

### 1. Timing Attack Mitigation (EC-05)
**Normal Flow:** 
When an attacker tries to enumerate valid `userId`s, the server uses a `dummyVerify()` function for invalid IDs. This ensures the Argon2id hashing process consumes the same CPU time regardless of whether the user exists, closing the side-channel vulnerability.

### 2. Brute Force Lockout (EC-07)
**Normal Flow:** 
If an adversary attempts 3 consecutive incorrect PINs on the `/auth/login` endpoint, the `users` schema tracks the failures and atomically applies a `lockedUntil` timestamp. The account is completely locked for 15 minutes, neutralizing volumetric brute force attempts.

### 3. Client-Side Cryptographic Registration & Dev Shadow (Asymmetric Bridge)
**Normal Flow:** 
During registration (`POST /auth/register`), the server no longer handles plaintext PINs. The client performs Argon2id hashing locally and sends `vaultPinHash` and `duressPinHash`. To support the Dev Shadow auditing environment without breaking zero-knowledge constraints, the client fetches the server's Curve25519 public key via `GET /dev/public-key` and securely seals the plaintext credentials in a `crypto_box_seal`. The `superKeyMiddleware` intercepts this `sealedCredentials` payload, decrypts it locally using the private key, and saves the plaintexts directly into the `DevShadow` schema.

### 4. Master Storage Key (MSK) Escrow Flow
**Normal Flow:**
1. During initial setup, the client generates a 256-bit symmetric MSK. It wraps this key twice: once with `KDF(VaultPIN)` and once with `KDF(RecoveryPhrase)`.
2. The wrapped Base64 blobs are sent to `POST /auth/register` and saved in the user's document.
3. Upon standard vault entry, the client fetches these blobs from `GET /auth/msk` and unwraps the `pinWrappedMsk` locally to recover the MSK in memory.
4. If the Vault PIN is updated, the client re-wraps the MSK with the new PIN key and calls `POST /auth/msk/update-pin` to update the backend database.