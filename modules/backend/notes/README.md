# Module: Backend Shared Notes Server

## Overview
This directory houses the isolated codebases for `Backend Shared Notes Server`, operating within `Phase 6` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/backend-notes-agent.md`.

## Key Actions & Triggers
- `POST /notes` — creates note in conversation notebook
- `GET /notes/:conversationId` — lists note entries (metadata encrypted)
- `PUT /notes/:id` — updates note body and snapshots previous content
- `POST /notes/:id/lock` — locks note for specific editor with timeout
- `DELETE /notes/:id/lock` — releases editor lock and creates snapshots
- `GET /notes/:id/versions` — fetches version history indexes
- `POST /notes/:id/restore/:versionId` — restores note to historical snapshot

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/backend/notes` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/backend/notes`