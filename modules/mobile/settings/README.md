# Module: Mobile Unified Settings Controller

## Overview
This directory houses the isolated codebases for `Mobile Unified Settings Controller`, operating within `Phase 9` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/mobile-settings-agent.md`.

## Key Actions & Triggers
- **Unified Decoy Settings Panel:** Manages streaker daily timers and LibreTranslate profiles.
- **Vault General Settings Panel:** PIN changes (local MSK re-wrapping and `POST /auth/msk/update-pin` invocation), Duress PIN rotation (collision-checked `POST /auth/duress-pin/change` invocation), recovery phrase verification, active devices dashboard.
- **Admin Per-Conversation Panel:** Key rotation configurations, note edit lock timers, and member revocation triggers.

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/mobile/settings` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/mobile/settings`

---

## Detailed Workflow Examples

### 1. Vault PIN Rotation & MSK Re-wrapping
**Normal Flow:**
1. The user navigates to Vault settings and enters a new Vault PIN.
2. The client fetches the current raw MSK from `mskSessionProvider` (which is unlocked in memory).
3. The client derives a new key from the new Vault PIN using PBKDF2-SHA256.
4. The client re-encrypts the raw MSK using this new key to generate a new `pinWrappedMsk`.
5. The client submits `POST /auth/msk/update-pin` to update the escrowed payload on the server.
6. Once the server responds with 200 OK, the client updates the local clientKey hash on the server using the credentials change endpoint.