# Module: Backend Restoration Requests Admin

## Overview
This directory houses the isolated codebases for `Backend Restoration Requests Admin`, operating within `Phase 8` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/backend-restoration-agent.md`.

## Key Actions & Triggers
- `POST /restoration/request` — files a conversation recovery request
- `GET /restoration/pending` — fetches active recovery requests for admin review
- `POST /restoration/approve/:requestId` — admin approves recovery; enables key syncs
- `POST /restoration/deny/:requestId` — admin denies restoration request
- `GET /restoration/recovery-list` — fetches encrypted conversation lists matching PBKDF2 recovery tokens

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/backend/restoration` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/backend/restoration`