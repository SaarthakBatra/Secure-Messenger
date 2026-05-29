# Module: Backend Disguised Push Engine

## Overview
This directory houses the isolated codebases for `Backend Disguised Push Engine`, operating within `Phase 5` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/backend-notifications-agent.md`.

## Key Actions & Triggers
- `POST /notifications/acknowledge/:messageId` — registers notification interactions (fires 3-grey tick status updates)
- `GET /events/:conversationId` — retrieves the encrypted, in-app audit log records

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/backend/notifications` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/backend/notifications`