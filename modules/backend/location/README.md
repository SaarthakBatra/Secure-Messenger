# Module: Backend Discrete Location Router

## Overview
This directory houses the isolated codebases for `Backend Discrete Location Router`, operating within `Phase 7` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/backend-location-agent.md`.

## Key Actions & Triggers
- `POST /location/request/:conversationId` — submits location request to target participant
- `POST /location/respond/:conversationId` — writes encrypted client coordinates response

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/backend/location` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/backend/location`