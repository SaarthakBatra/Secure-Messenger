# Module: Mobile Recovery Phrase & Request UI

## Overview
This directory houses the isolated codebases for `Mobile Recovery Phrase & Request UI`, operating within `Phase 8` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/mobile-restoration-agent.md`.

## Key Actions & Triggers
- **Mnemonic Recovery Screen:** Form prompting for 12-word mnemonic phrase.
- **Restoration Wizard Screen:** Prompts for Conversation ID and request notes.
- **Admin Review Queue Screen:** Panel rendering outstanding partner requests.

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/mobile/restoration` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/mobile/restoration`