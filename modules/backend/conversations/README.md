# Module: Backend Conversation Architecture

## Overview
This directory houses the isolated codebases for `Backend Conversation Architecture`, operating within `Phase 2` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/backend-conversations-agent.md`.

## Key Actions & Triggers
- `POST /conversations` — create unique conversation room; returns Conversation ID and display-once Conversation Key.
- `POST /conversations/:id/join` — accepts code and validates key hashes to enable the partner to join.
- `DELETE /conversations/:id/pending` — cancels pending invitations, instantly purging records.
- `GET /conversations` — fetches active rooms (IDs and local aliases only).
- `POST /conversations/:id/alias` — assigns a private local nickname to a conversation room.
- `POST /conversations/escrow` — stores an encrypted conversation key mapping for the user (using their MSK).
- `GET /conversations/escrow` — retrieves all escrowed conversation keys for the user.

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/backend/conversations` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/backend/conversations`

---

## Detailed Workflow Examples

### 1. Cleartext Key Generation (EC-15)
**Normal Flow:** 
When `POST /conversations` is called, the server dynamically generates a 256-bit high-entropy key. It performs an Argon2id hash on the key and saves the hash. The cleartext key is then dispatched back to the creator **exactly once** in the HTTP response. The server retains zero knowledge of the cleartext going forward.

### 2. The Burn Protocol (EC-14)
**Normal Flow:** 
When a conversation must be destroyed (`DELETE /conversations/:id/burn`), a naive deletion could leave orphaned messages or media blobs if an exception occurs mid-flight. The Burn Protocol solves this by executing a synchronized, sequential set of `deleteMany` operations (Messages → MediaRefs → Notes → Events → Conversation), ensuring atomic consistency and absolute data eradication.

### 3. Conversation Escrow Sync Flow
**Normal Flow:**
1. Upon successfully starting or joining a conversation, the client encrypts the 256-bit symmetric conversation key using the Master Storage Key (MSK).
2. The client posts the encrypted key to `POST /conversations/escrow`.
3. The server validates the session and saves the escrow record.
4. During future logins or on database recovery, the client calls `GET /conversations/escrow` to download all conversation keys and restores their local chat database decrypting the keys using their MSK.