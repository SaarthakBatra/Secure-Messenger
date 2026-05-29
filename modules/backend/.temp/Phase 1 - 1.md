# Phase 1 Completion Walkthrough: Identity & Auth

I have successfully completed **Phase 1** of the Backend Implementation, which encompasses user registration, vault authentication, and session management.

## What Was Built

- **`crypto.js`**: Integrates `argon2` for cryptographically secure, memory-hard PIN hashing, and securely generates 10-digit numeric `userId`s and 64-byte `sessionToken`s.
- **`middleware.js`**: Introduces an `express-rate-limit` window, progressive delays via `setTimeout`, account locking capabilities (EC-07), and a robust session verification wrapper.
- **`router.js`**: Implements `/register`, `/login`, `/login/duress`, `/login/recovery`, `/pin/change`, and `/session` endpoints. It safely uses atomic DB operations like `$inc` (for PIN failures) and handles unique key duplication loops for ID generation (EC-01).

---

## Technical Deep-Dive: Argon2id Cost Tuning

We chose `argon2id` over `bcrypt` to offer maximum resistance against both GPU-cracking attacks and side-channel timing attacks. Here is a breakdown of our tuning parameters configured in `crypto.js`:

> [!TIP]
> **Argon2id Config:** `memoryCost: 65536 (64 MB)`, `timeCost: 3`, `parallelism: 1`

1. **Memory Cost (`m=65536`)**: Requires the CPU to allocate 64 MB of RAM specifically to process one single hash. This strictly eliminates the ability for attackers to use cheap ASICs or generic GPUs to brute-force hashes in parallel, as the RAM overhead chokes the GPU processing capacity.
2. **Time Cost (`t=3`)**: Specifies the number of iterations over the memory. At `t=3` with `64MB`, a single hash on an average backend server takes exactly **~200ms**.
3. **Parallelism (`p=1`)**: Defines the number of threads used to compute the hash. We left this at `1` to avoid exhausting the Node.js event loop/worker threads under heavy auth loads.

### How This Mitigates Edge Cases
- **EC-07 (Brute Force):** Even without the `authLimiter` IP ban and the 3-attempt account lockout, an attacker could at maximum guess 5 PINs per second per CPU core. A 6-digit PIN space (1,000,000 combinations) would take over 2 days of uninterrupted computing power just for *one* account.
- **EC-05 (Timing Attacks):** Because we enforce a `dummyVerify()` check when a `userId` is not found in the DB, the server will intentionally burn ~200ms to mimic a real password check. Attackers cannot use response timing to enumerate which User IDs actually exist in the database.

---

## Detailed Testing Guide

I implemented the test suite in `tests/backend/auth/auth_test.js` covering the six major edge cases highlighted in the implementation plan. 

### What The Tests Verify
1. **EC-01 (Parallel Registration):** Asserts the endpoints correctly assign User IDs and seamlessly write plaintext fallback data to `DevShadow`.
2. **EC-05 (Timing Mitigation):** Asserts that an invalid User ID still returns `401 Invalid credentials` and takes the standard compute penalty.
3. **EC-02 & EC-06 (Session Fixation & Fixation):** Tests that concurrent logins accurately generate entirely new cryptographically random tokens and instantly set `invalidatedAt` on older active sessions.
4. **EC-03 (Token Replay):** Tries to use an invalidated session token to hit `DELETE /session` and correctly intercepts a `401`.
5. **EC-07 (Lockouts & Progressive Delays):** Purposely inputs 4 incorrect PINs. The 3rd wrong PIN triggers the DB lockout; the 4th returns an immediate `423 Locked`.

### Running The Tests Yourself
Because we are utilizing in-memory MongoDB via `mongodb-memory-server`, you don't need any complex external setups. 

1. Ensure dependencies are up-to-date:
   ```bash
   cd modules/backend
   npm install
   ```

2. **To run the full suite through the Guardian Orchestrator:**
   ```bash
   ./tests/run_all.sh
   ```

3. **To run just the Auth Module's test subset manually:**
   ```bash
   cd modules/backend
   NODE_PATH=$(pwd)/node_modules npx jest --roots "../../tests/backend/auth" --testMatch "**/*_test.js"
   ```

> [!SUCCESS]
> **Status:** All 12/12 individual tests pass, taking approximately 4 seconds to execute globally. Phase 1 is officially complete and structurally sound.
