# Module: Backend WebSocket & Messaging Hub

## Overview
This directory houses the isolated codebases for `Backend WebSocket & Messaging Hub`, operating within `Phase 3` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/backend-messaging-agent.md`.

## Key Actions & Triggers
- `WebSocket /ws` — real-time subscription routing for all message events
- `POST /messages` — accepts encrypted message payloads to buffer to disk
- `POST /media/upload` — requests a pre-signed Cloudflare R2 upload path
- `GET /media/download/:mediaId` — retrieves pre-signed R2 media read URLs
- `PUT /messages/:id/hide` — adds active user ID to hidden lists for soft deletes

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/backend/messaging` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/backend/messaging`

---

## Detailed Workflow Examples

### 1. Idempotent Message Delivery (EC-09)
**Normal Flow:** 
A client on a flaky network sends an encrypted message via WebSocket. The network stutters, causing the client to re-send the identical payload (with the same `messageId`). The server attempts to save the second document. MongoDB instantly rejects the write due to a `11000 Duplicate Key` violation on the `messageId` index. The server catches the exception, avoids crashing, and instead proactively triggers a re-delivery push down the WebSocket to confirm receipt.

### 2. Socket Flood Storm Prevention (EC-11)
**Normal Flow:** 
If an adversary obtains a valid token and attempts to flood the database with junk encrypted blobs, a token-bucket algorithm intercepts the WebSocket frame stream. Once the threshold (`50 msgs/sec`) is crossed, the server actively terminates the socket with a `1008 Policy Violation` code. This prevents volumetric spam from artificially inflating the MongoDB storage footprint.