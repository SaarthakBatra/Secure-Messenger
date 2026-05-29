# Module: Mobile Vault Onboarding & Entry

## Overview
This directory houses the isolated codebases for `Mobile Vault Onboarding & Entry`, operating within `Phase 1` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/mobile-vault-auth-agent.md`.

## Key Actions & Triggers
- **Vault Setup Wizards:** 8 sequential pages (intro, User ID display, recovery phrase backup, Vault PIN selection, Duress PIN selection, grace period configuration, screenshot toggles, completion screen).
- **Vault PIN Entry Overlay:** Renders inside the Report Issue form or on long-press triggers. Disguised keypad input.

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/mobile/vault-auth` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/mobile/vault-auth`