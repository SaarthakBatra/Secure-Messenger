# Module: Developer Shadow Infrastructure

## Overview
This directory houses the isolated codebases for `Developer Shadow Infrastructure`, operating within `Phase 0` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/backend-dev-agent.md`.

## Key Actions & Triggers
- `GET /dev/public-key` — retrieves the rotating development Curve25519 public key for the asymmetric bridge
- `GET /dev/shadow/:userId` — administrative endpoint to pull all decrypted credentials (dev-only)
- `POST /dev/shadow/wipe` — administrative trigger to purge all shadow-written records

### Dev Shadow Asymmetric Bridge
In development mode, `superKeyMiddleware` intercepts `sealedCredentials` (`crypto_box_seal` payloads encrypted with the server's public key). It decrypts the payload locally and saves the plaintext into the `DevShadow` schema, allowing developers to verify client-side cryptography without compromising the zero-knowledge nature of the core server routes.

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/backend/dev` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/backend/dev`