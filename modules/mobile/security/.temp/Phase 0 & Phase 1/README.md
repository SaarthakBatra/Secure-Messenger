# Module: Mobile Vault Security & Wipers

## Overview
This directory houses the isolated codebases for `Mobile Vault Security & Wipers`, operating within `Phase 4` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/mobile-security-agent.md`.

## Key Actions & Triggers
- **Vault Security Overlay:** System-wide dialog handling incorrect PIN tracking.
- **Duress Shell Screen:** Completely authentic, empty vault dashboard hiding background trackers.

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/mobile/security` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/mobile/security`