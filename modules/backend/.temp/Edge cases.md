# Phase 0 Backend Foundation & Dev-Shadow Orchestrator
**Module:** `modules/backend/` | **Status:** Awaiting Approval | **Version:** 2.0

Brief: This plan covers the initial scaffolding of the Express server (Phase 0.1), the `SUPER_KEY_ENABLED` dev-shadow infrastructure (Phase 0.2), and Mongoose schema definitions (Phase 0.3). It also resolves both open questions from v1.0 and catalogues all discovered backend edge cases to be handled from Phase 0 onward.

---

## Resolved Questions

### Q1 — `dev_shadow` Document Structure: **Single Document Per User** ✅

Per your direction: a single `DevShadow` document per `userId`. The encrypted blob is a JSON payload of all sensitive cleartext fields (userId, pinHash, duressPinHash, recoveryPhraseHash, conversationKeys, etc.) encrypted atomically under the `SUPER_KEY` using AES-256-GCM.

**Rationale:** Simpler querying for `GET /dev/shadow/:userId`, no join logic, and a single upsert is more atomic than per-collection shadow writes, which could produce a partial shadow state if one write fails mid-request.

---

### Q2 — `superKeyMiddleware` Interception Strategy: Detailed Analysis

The middleware must intercept and capture plaintext credentials **before** they are hashed and written to the main collections. There are three viable patterns:

#### Option A: Global `app.use()` Middleware
The middleware is registered on every route before business logic executes.

```
app.use(superKeyMiddleware);
app.use('/auth', authRouter);
app.use('/conversations', conversationsRouter);
```

| Pros | Cons |
|---|---|
| Zero risk of forgetting to attach to a new route | Runs on every request (health checks, static routes, etc.) — unnecessary overhead |
| Single, centralised interception point | Requires internal `req.path` checks to determine if it is a credential-mutating route |
| Harder to miss a future credential endpoint | `req.body` may not be parsed yet if body-parser is ordered incorrectly — order-sensitive |
| Can capture all mutations uniformly | Hard to reason about; business logic and dev code are tightly coupled |

**Use case:** Only sensible if the entire server is private (no public endpoints). Still requires explicit path-list filtering inside the middleware.

---

#### Option B: Router-Level Middleware (Recommended ✅)
The middleware is attached to specific **routers** that handle credential-mutating endpoints. The `superKeyMiddleware` is a no-op bypass function if `SUPER_KEY_ENABLED !== 'true'`.

```
// auth/router.js
authRouter.post('/register', superKeyMiddleware, registerController);
authRouter.post('/auth/pin/change', superKeyMiddleware, pinChangeController);
```

| Pros | Cons |
|---|---|
| Surgical precision: only fires on defined credential endpoints | Developer must remember to add it to future credential routes (mitigated by code review) |
| Zero performance cost on unrelated routes | Slightly more verbose route definitions |
| Clean separation: public vs. credential-mutating routes are explicit | |
| Body is guaranteed to be parsed when the middleware runs (consistent order) | |
| Easy to unit-test in isolation — inject a spy on these exact routes | |
| Completely removed by deleting the `dev/` import before prod build | |

**Use case:** Preferred for production-safety. The middleware is attached **inline** to exactly: `POST /auth/register`, `POST /auth/pin/change`, `POST /conversations` (captures Conversation Key), and `POST /auth/login/recovery` (captures recovery phrase usage). These are the only four endpoints where plaintext credentials exist server-side simultaneously.

---

#### Option C: Mongoose Post-Save Hook
A Mongoose `post('save')` hook on specified models writes to `dev_shadow` after every document write.

| Pros | Cons |
|---|---|
| Captures every persistence event, even internal ones | Fires **after** hash derivation — plaintext is already lost; cannot capture pre-hash cleartext |
| No Express coupling | Cannot capture transient credentials (e.g., Conversation Key that is returned once and never persisted) |
| | Mongoose hooks are harder to remove cleanly before prod build |
| | Tightly couples the Model (permanent contract) with dev tooling (ephemeral concern) |

**Use case:** Unsuitable for this project because the primary goal is capturing **cleartext** credentials for verification, not post-hash documents.

---

**Decision: Option B (Router-Level Middleware)** for the four identified credential-mutating routes.

---

## Proposed File Structure

```
modules/backend/
├── index.js                    # [NEW] Express entry point, DB bootstrap
├── .env                        # [NEW] MONGO_URI, SUPER_KEY_ENABLED, SUPER_KEY
├── models/
│   ├── User.js                 # [NEW]
│   ├── Session.js              # [NEW]
│   ├── Conversation.js         # [NEW]
│   ├── Message.js              # [NEW]
│   ├── MediaRef.js             # [NEW]
│   ├── Note.js                 # [NEW]
│   ├── Event.js                # [NEW]
│   ├── RestorationRequest.js   # [NEW]
│   └── DevShadow.js            # [NEW] dev-only
└── dev/
    ├── superKey.js             # [NEW] encrypt/decrypt + superKeyMiddleware
    └── routes.js               # [NEW] GET /dev/shadow/:userId
```

---

## Phase 0.1 — Express Scaffold: `modules/backend/index.js`

**Responsibilities (entry point only, no business logic per workflow-protocol.md):**
- Load `.env` via `dotenv`.
- Bootstrap `mongoose.connect()`.
- Register global middleware: `express.json()`, `helmet()`, CORS.
- Apply global rate limiter (see Edge Case EC-01).
- Conditionally `require('./dev/routes')` only if `SUPER_KEY_ENABLED === 'true'`.
- Mount routers: `/auth`, `/conversations`, `/messages`, `/media`, `/notes`, `/events`, `/restoration`, `/location`, `/notifications`.
- Start HTTP server + attach `ws` WebSocket server.

---

## Phase 0.2 — Super Key Infrastructure

### `modules/backend/dev/superKey.js`

**`encrypt(plaintext: string | object) → { iv, authTag, ciphertext }`**
- Generate a 12-byte random IV per invocation (never reuse IVs with AES-GCM).
- Derive key from `process.env.SUPER_KEY` (must be exactly 32 bytes / 64 hex chars; server startup fails fast if malformed).
- Return Base64-encoded `iv`, `authTag`, and `ciphertext` as a structured string `iv:authTag:ciphertext`.

**`decrypt(payload: string) → string`**
- Parse `iv:authTag:ciphertext` from the payload string.
- Decipher with stored `SUPER_KEY`.
- Return original plaintext JSON string.

**`superKeyMiddleware(req, res, next)`**
- Guard: `if (process.env.SUPER_KEY_ENABLED !== 'true') return next()` — hard bypass; zero overhead in prod.
- Extract the credential fields from `req.body` relevant to the specific route (route-aware via `req.path`).
- Bundle as a plaintext JSON object.
- Call `encrypt()` to produce the cipher blob.
- Call `DevShadow.findOneAndUpdate({ userId }, { $set: { encryptedBlob } }, { upsert: true })`.
- Call `next()` — never block the real request.
- On any error inside the middleware: **log and call `next()`** — dev tooling must never crash the server.

### `modules/backend/dev/routes.js`

**`GET /dev/shadow/:userId`**
- Guard: if `SUPER_KEY_ENABLED !== 'true'` → `404 Not Found` (endpoint does not exist in prod).
- Query `DevShadow.findOne({ userId })`.
- Call `decrypt()` on the blob.
- Return parsed JSON payload.
- Never expose raw ciphertext in the response.

---

## Phase 0.3 — Mongoose Schema Definitions

All schemas use `timestamps: false` on content collections (timestamps are tracked in application fields for precision). Indexes defined at schema level to ensure they are applied on collection creation.

### `models/User.js`
```js
{
  userId:              { type: String, required: true, unique: true, index: true },
  pinHash:             { type: String, required: true },          // Argon2id output
  duressPinHash:       { type: String, required: true },          // Argon2id output
  recoveryPhraseHash:  { type: String, required: true },          // Argon2id output
  sessionToken:        { type: String, default: null },           // opaque token
  deviceFingerprint:   { type: String, required: true },          // SHA-256 of device attrs
  wrongPinAttempts:    { type: Number, default: 0 },              // EC-07 counter
  lockedUntil:         { type: Date, default: null },             // EC-07 lockout
  createdAt:           { type: Date, default: Date.now }
}
```

### `models/Session.js`
```js
{
  userId:            { type: String, required: true, index: true },
  token:             { type: String, required: true, unique: true },
  deviceFingerprint: { type: String, required: true },
  createdAt:         { type: Date, default: Date.now },
  invalidatedAt:     { type: Date, default: null }
}
```

### `models/Conversation.js`
```js
{
  conversationId:     { type: String, required: true, unique: true, index: true },
  adminUserId:        { type: String, required: true },
  participantUserIds: [{ type: String }],
  status:             { type: String, enum: ['PENDING','ACTIVE','ROTATING'], default: 'PENDING' },
  encryptedBlob:      { type: String, required: true },   // opaque ciphertext
  createdAt:          { type: Date, default: Date.now }
}
```

### `models/Message.js`
```js
{
  messageId:      { type: String, required: true, unique: true, index: true },
  conversationId: { type: String, required: true, index: true },
  senderUserId:   { type: String, required: true },
  encryptedBlob:  { type: String, required: true },
  tickStatus:     { type: String, enum: ['sent','delivered','read','acknowledged'], default: 'sent' },
  timestamps: {
    sent:         { type: Date },
    delivered:    { type: Date },
    read:         { type: Date },
    acknowledged: { type: Date }
  },
  hidden_flags:   [{ type: String }]   // array of userIds who soft-deleted
}
```

### `models/MediaRef.js`
```js
{
  mediaId:            { type: String, required: true, unique: true, index: true },
  conversationId:     { type: String, required: true, index: true },
  r2Key:              { type: String, required: true },
  encryptedMetaBlob:  { type: String, required: true }
}
```

### `models/Note.js`
```js
{
  noteId:              { type: String, required: true, unique: true, index: true },
  conversationId:      { type: String, required: true, index: true },
  title:               { type: String, required: true },
  encryptedContentBlob:{ type: String, required: true },
  versions: [{
    versionId:           { type: String },
    timestamp:           { type: Date },
    encryptedContentBlob:{ type: String }
  }],
  editLock: {
    userId:    { type: String, default: null },
    expiresAt: { type: Date, default: null }
  }
}
```

### `models/Event.js`
```js
{
  eventId:             { type: String, required: true, unique: true, index: true },
  conversationId:      { type: String, required: true, index: true },
  type:                { type: String, required: true },    // enum enforced at app layer
  encryptedPayloadBlob:{ type: String, required: true },
  timestamp:           { type: Date, default: Date.now }
}
```

### `models/RestorationRequest.js`
```js
{
  requestId:         { type: String, required: true, unique: true, index: true },
  conversationId:    { type: String, required: true, index: true },
  requestingUserId:  { type: String, required: true },
  reasonBlob:        { type: String, required: true },     // opaque ciphertext
  status:            { type: String, enum: ['PENDING','APPROVED','DENIED'], default: 'PENDING' },
  timestamps: {
    requestedAt:     { type: Date, default: Date.now },
    decidedAt:       { type: Date, default: null }
  }
}
```

### `models/DevShadow.js` *(dev-only)*
```js
{
  userId:         { type: String, required: true, unique: true, index: true },
  encryptedBlob:  { type: String, required: true },    // AES-256-GCM of plaintext JSON
  updatedAt:      { type: Date, default: Date.now }
}
```

---

## Backend Edge Case Register

This is the exhaustive catalogue of edge cases the backend must handle. Each entry has an ID for cross-reference in future phases.

### Category 1 — Authentication & Session Race Conditions

#### EC-01 · Parallel Registration with the Same User ID
**Scenario:** Two concurrent `POST /auth/register` requests arrive in the same millisecond with a collision on the generated `userId`.  
**Risk:** Non-atomic check-then-insert creates a duplicate user.  
**Mitigation:** Rely on the MongoDB unique index on `userId`. The second insert will throw `E11000 (duplicate key)`. The handler must catch this specific error code and retry ID generation — not return a generic 500. Return `409 Conflict` to the client after N retries.

#### EC-02 · Concurrent Login + Session Purge Race
**Scenario:** Two login requests arrive for the same `userId` simultaneously (e.g., client double-tap). Both read the old session token as valid, both attempt to purge and create a new token — one write wins, the other creates an orphaned session.  
**Risk:** Two valid session tokens coexist, violating single-session enforcement.  
**Mitigation:** Use a MongoDB transaction spanning the `Session` invalidation and new `Session` insert. Use `findOneAndUpdate` with `{ userId }` filter and the new token to make the upsert atomic. Alternatively, apply a Redis distributed lock keyed on `userId` for the duration of the login transaction.

#### EC-03 · Session Token Replay After Logout
**Scenario:** A token is intercepted (man-in-the-middle, memory dump) and reused after the legitimate user has logged out and the token is in `invalidatedAt` state.  
**Risk:** Authenticated access post-logout.  
**Mitigation:** Session middleware must check `invalidatedAt === null` on every request — not just token signature validity. Use short-lived tokens (15-min JWT expiry) with a Redis-backed `jti` denylist for immediate invalidation. Check Redis first, DB second.

#### EC-04 · Wrong PIN Attempt Counter Race
**Scenario:** Three concurrent requests all fail PIN verification. Each reads `wrongPinAttempts = 2` before any can write `3`. All three increment to 3 and trigger three simultaneous wipe events.  
**Risk:** Duplicate wipe events logged; non-atomic counter.  
**Mitigation:** Use MongoDB `$inc` operator atomically: `User.findOneAndUpdate({ userId }, { $inc: { wrongPinAttempts: 1 } }, { new: true })`. The returned document reflects the post-increment value — only the request that sees `wrongPinAttempts === 3` triggers the wipe.

#### EC-05 · Timing Attack on PIN / Recovery Phrase Verification
**Scenario:** Attacker measures response time differences between "User ID not found" (fast) vs. "PIN wrong" (slow, Argon2id comparison) to enumerate valid user IDs.  
**Risk:** User ID enumeration via timing side-channel.  
**Mitigation:** If `userId` is not found, still execute a dummy Argon2id verification against a stored dummy hash (constant-time). Both code paths must take the same wall-clock time. Always return the generic error `"Invalid credentials"` for all failure reasons.

#### EC-06 · Session Fixation
**Scenario:** Attacker pre-sets a known session token in a shared environment; victim logs in and the same token is promoted.  
**Risk:** Session hijacking.  
**Mitigation:** Always issue a **brand-new** cryptographically random session token on every successful login. Never promote or reuse a pre-existing token.

---

### Category 2 — IP & Network Security

#### EC-07 · Brute-Force Login / PIN Attack
**Scenario:** Attacker issues thousands of `POST /auth/login` requests from the same or rotating IPs.  
**Mitigation (layered):**
1. **IP-rate limiter** (`express-rate-limit` + Redis store): max 10 requests / 15 min to `/auth/*` per IP.
2. **Account-level lockout** (independent of IP): after 3 failed attempts, set `User.lockedUntil = Date.now() + 15min`. Return `423 Locked` regardless of IP rotation.
3. **Progressive delay**: each failed attempt adds a 500ms artificial delay on the response using `setTimeout`, making parallel attacks impractical.
4. **Argon2id cost**: the KDF itself is rate-limiting by design — ensure `memoryCost` and `timeCost` are tuned to ≥200ms per verification.

#### EC-08 · IP Spoofing / Proxy Headers
**Scenario:** Attacker sets `X-Forwarded-For` to a trusted IP to bypass IP-based rate limits.  
**Risk:** Rate limiter sees a fake IP.  
**Mitigation:** Configure `express-rate-limit` with `trustProxy: false` (or explicitly whitelist known proxy IPs). Use `req.socket.remoteAddress` as the canonical IP in all security-sensitive contexts. Never trust `X-Forwarded-For` headers without strict proxy trust configuration.

#### EC-09 · IP Metadata Leakage
**Scenario:** Server logs contain `req.ip`, tying requests to real-world IP addresses, creating a metadata graph linkable to user identity.  
**Risk:** Violates privacy-by-design; log subpoena risk.  
**Mitigation:**
- Winston logger must **never log `req.ip`** in any production-mode log entry.
- Do not store originating IP in any MongoDB collection.
- Apply traffic-aware error messages: never reveal whether a User ID exists.

#### EC-10 · DDoS / Connection Exhaustion on REST API
**Scenario:** Flood of HTTP requests overwhelms Node.js event loop before auth middleware can reject them.  
**Mitigation:**
- Nginx reverse proxy upstream enforces connection limits before reaching Node.js.
- `helmet()` sets security headers including `X-Content-Type-Options`, `X-Frame-Options` to block trivial attacks.
- Set `server.maxHeadersCount = 30` and `server.headersTimeout = 10000ms` to kill malformed/slow HTTP attacks.

---

### Category 3 — WebSocket Security

#### EC-11 · Unauthenticated WebSocket Upgrade
**Scenario:** Client sends a WebSocket upgrade request without a valid session token.  
**Risk:** Open WebSocket connection without identity binding.  
**Mitigation:** Use `ws`'s `verifyClient` hook to validate the session token **before** the connection is upgraded. Reject the upgrade with `401` immediately if the token is missing or invalid. Never complete the handshake for unauthenticated clients.

#### EC-12 · WebSocket Connection Flooding
**Scenario:** Attacker opens thousands of WebSocket connections per second to exhaust file descriptors and memory.  
**Mitigation:**
- Track concurrent connections per `userId` in Redis; cap at N (e.g., 2 — one active, one overlap during reconnect).
- Track connections per IP in Redis; cap at M (e.g., 5) to block single-IP flooding.
- Implement an idle connection timeout: close connections with no ping/message for 60s.
- Set maximum message size on the `ws` server (`maxPayload: 100 * 1024` — 100 KB).

#### EC-13 · WebSocket Message Replay / Out-of-Order Delivery
**Scenario:** Duplicate WebSocket message frames delivered by unreliable network; messages rendered out of order on client.  
**Mitigation:**
- Each message in the `messages` collection has a server-assigned `timestamps.sent` — client must sort by this value.
- Use Redis to cache recently seen `messageId`s (TTL 60s) and reject duplicates within the window.

#### EC-14 · Cross-Site WebSocket Hijacking (CSWSH)
**Scenario:** A third-party page initiates a WebSocket connection to the backend using the victim's session cookies.  
**Risk:** Authenticated messages sent on behalf of victim.  
**Mitigation:** Validate the `Origin` header in `verifyClient`. Only accept connections from the app's trusted origin. Since this is a mobile app (not browser-based), reject all non-null `Origin` values that are not explicitly whitelisted.

---

### Category 4 — Data Integrity & MongoDB Race Conditions

#### EC-15 · Conversation Key Display-Once Race
**Scenario:** Two simultaneous `GET /conversations/:id` requests arrive in the display-once window; both receive the Conversation Key before it can be invalidated.  
**Risk:** Key leaks to two clients.  
**Mitigation:** The Conversation Key display-once is a client-side UX concern — the key is generated once and returned in the `POST /conversations` creation response body. The server does **not** persist the cleartext key. Phase 2 will enforce this strictly.

#### EC-16 · Concurrent Note Edit Lock Acquisition
**Scenario:** Two users simultaneously request an edit lock on the same note. Both read `editLock.userId = null` before either can write.  
**Risk:** Both users think they hold the lock.  
**Mitigation:** Use a MongoDB conditional update: `Note.findOneAndUpdate({ noteId, 'editLock.userId': null }, { $set: { editLock: { userId, expiresAt } } }, { new: true })`. If the update returns `null`, the lock is already taken — return `423 Locked`. This is atomic at the DB layer.

#### EC-17 · Pending Conversation Expiry Job — Duplicate Firing
**Scenario:** Bull queue worker crashes mid-job and restarts, firing the 24h expiry job twice for the same conversation.  
**Risk:** Attempting to delete an already-deleted conversation causes errors or partial state.  
**Mitigation:** Use a deterministic Bull `jobId` derived from `conversationId` (e.g., `expire:${conversationId}`) so Bull deduplicates it natively. Make the deletion handler idempotent: `deleteOne({ conversationId, status: 'PENDING' })` — silently succeeds if already gone.

#### EC-18 · Edit Lock Timeout Without Autosave Content
**Scenario:** Lock expires (Bull job fires), but the client had unsaved content that was never sent to the server.  
**Risk:** Content loss; note reverts to last saved state without warning.  
**Mitigation:** WebSocket broadcasts a `lock:expiring` event to the lock-holder 10s before timeout. The client must auto-submit the current content. The Bull job checks for a `pendingContent` field on the Note before releasing the lock and autosaves it if present. Phase 6 will implement this.

---

### Category 5 — Bull Queue & Background Jobs

#### EC-19 · Redis Crash Causes Queue Loss
**Scenario:** Redis process dies while Bull jobs are in `waiting` or `active` state.  
**Risk:** Scheduled expiry jobs (conversation expiry, edit lock timeout, admin inactivity) are lost permanently.  
**Mitigation:** Use Redis AOF persistence (`appendonly yes`) to ensure jobs survive Redis restarts. Configure Bull `removeOnComplete: false` and `removeOnFail: false` for critical jobs so they can be inspected and re-queued. Implement a startup reconciliation job that scans MongoDB for stale PENDING states and re-enqueues appropriate jobs.

#### EC-20 · Key Rotation Job Interrupted Mid-Rotation
**Scenario:** The server crashes during the Bull key rotation job after re-encrypting 500 of 2000 messages.  
**Risk:** Partially rotated conversation — some messages on old key, some on new key.  
**Mitigation:** Key rotation is a transaction-like operation. Store a `rotationState: { newKeyRef, lastProcessedMessageId, startedAt }` on the Conversation document. On worker resume, check `status: 'ROTATING'` and `rotationState` to continue from `lastProcessedMessageId` (checkpoint pattern). Phase 9 will implement this.

---

### Category 6 — Dev Shadow Infrastructure

#### EC-21 · `superKeyMiddleware` Crashes Main Request
**Scenario:** The dev middleware throws an unhandled error (e.g., `SUPER_KEY` env var is corrupted, MongoDB `DevShadow` is unreachable).  
**Risk:** A dev-only tool crashes a production-critical auth flow.  
**Mitigation:** The entire body of `superKeyMiddleware` is wrapped in a `try/catch`. On any error: log with Winston at `warn` level and immediately call `next()`. Never let the middleware call `next(err)` or rethrow — it must be invisible to the main request lifecycle.

#### EC-22 · `SUPER_KEY_ENABLED` Leaks to Production
**Scenario:** `.env.production` accidentally contains `SUPER_KEY_ENABLED=true`.  
**Risk:** Shadow-write and `/dev/shadow/` routes are active in production.  
**Mitigation (Phase 0.4 CI gate):** GitHub Actions job runs `grep -r "SUPER_KEY_ENABLED=true" .env.production` and fails the build if found. A second grep checks for `require('./dev')` or `superKeyMiddleware` in non-dev files.

---

## Verification Plan

### Phase 0 Automated Tests (`jest` + `supertest`)

| Test | Command |
|---|---|
| AES-256-GCM round-trip | `superKey.encrypt(data)` → `superKey.decrypt(result)` === original |
| Unique IV per encryption call | Assert IVs from two calls differ |
| Corrupt SUPER_KEY startup guard | Set malformed key, assert process exits with code 1 |
| `GET /dev/shadow/:userId` returns decrypted payload | Seed a shadow doc, call route, assert plaintext |
| `GET /dev/shadow/:userId` returns 404 when flag is false | Set `SUPER_KEY_ENABLED=false`, assert 404 |
| Mongoose unique index enforces duplicate userId | Insert two docs with same `userId`, expect `E11000` |
| Schema required field validation | Omit required field on each model, expect `ValidationError` |
| CI flag grep | Assert grep for `SUPER_KEY_ENABLED=true` in prod config fails correctly |

### Manual Verification
- Spin up server locally with `SUPER_KEY_ENABLED=true` and call `GET /dev/shadow/testUser` to confirm decrypted JSON response.
- Set `SUPER_KEY_ENABLED=false` and confirm the `/dev` routes return 404 and the middleware is a pass-through.
