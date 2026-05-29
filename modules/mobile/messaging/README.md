# Module: Mobile Messaging UI & Encrypter

## Overview
This directory houses the isolated codebases for `Mobile Messaging UI & Encrypter`, operating within `Phase 3` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/mobile-messaging-agent.md`.

## Key Actions & Triggers
- **Active Chat Screen:** Infinite list rendering message bubbles, media attachments, and local action buttons.
- **Attachment Panel:** Integrated image selectors and document browsers before cryptographic uploads.

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/mobile/messaging` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/mobile/messaging`