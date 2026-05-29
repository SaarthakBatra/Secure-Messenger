# Module: Mobile Notebook UI & Editor

## Overview
This directory houses the isolated codebases for `Mobile Notebook UI & Editor`, operating within `Phase 6` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/mobile-notes-agent.md`.

## Key Actions & Triggers
- **Notebook Dashboard Screen:** Lists all shared notes in a conversation.
- **Markdown Editor Screen:** Renders edit interface with automatic Markdown rendering. Disables inputs if locked.

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/mobile/notes` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/mobile/notes`