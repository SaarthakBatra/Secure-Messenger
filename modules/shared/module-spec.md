# Module Specification: Shared Cryptographic & Core Utilities

## 1. Overview
- **Path:** `modules/shared/`
- **Module ID:** `shared`
- **Implementation Phase:** Phase 0
- **Core Intent:** Centralized repository for cryptographic operations, standard error codes, constants, validation logic, and shared structures for both backend (Node.js) and mobile (Flutter/Dart).

### Inter-Module Dependency Layer
- **Allowed Dependencies:** None. This is a pure core utility module.
- **Data Flow Contract:** Direct E2EE compliant integration. The shared module supplies the core cryptographic primitives that other modules consume to enforce zero plaintext on the server.

---

## 2. API / Interface Contracts

This is a pure library with no public HTTP endpoints or UI screens. It exports reusable cryptographic modules for both platforms.

### 2.1 Dart Exports (`modules/shared/dart/`)

#### 1. `kdf_service.dart`
- `Future<Uint8List> deriveVaultKey({required String pin, required Uint8List salt})`
  - Derives a 32-byte vault key using Argon2id.
  - Memlimit: `64 MiB` (67108864), Opslimit: `3`, Algorithm: `Argon2id13`.
- `Uint8List generateSalt()`
  - Generates a cryptographically random 16-byte salt via libsodium.

#### 2. `subkey_service.dart`
- `Uint8List deriveSubKey({required Uint8List masterKey, required SubKeyContext context})`
  - Derives a 32-byte sub-key from a master key using BLAKE2b-based `crypto_kdf_derive_from_key`.
  - Context string: `"MLINGO_1"` (exactly 8 ASCII bytes).
  - Sub-key IDs: `messages` = 1, `notes` = 2, `media` = 3.

#### 3. `cipher_service.dart`
- `String encrypt({required Uint8List key, required String plaintext, required String conversationId, required String entityId})`
  - Encrypts plaintext using `ChaCha20-Poly1305-IETF`.
  - Additional Authenticated Data (AAD): `"${conversationId}:${entityId}"`.
  - Layout: `Base64url(nonce[12 bytes] || ciphertext || tag[16 bytes])`.
- `String? decrypt({required Uint8List key, required String blob, required String conversationId, required String entityId})`
  - Decrypts and authenticates a Base64url blob. Returns `null` on validation or integrity failure.

#### 4. `mnemonic_service.dart`
- `String generateMnemonic()`
  - Generates a 12-word BIP-39 phrase using libsodium entropy.
- `List<int> generateConfirmationIndices()`
  - Generates 3 unique sorted random indices from `0` to `11` for Screen 3 onboarding confirmation.

#### 5. `crypto_error_codes.dart`
- Holds a map of static string error constants (`CRYPTO_001` through `CRYPTO_008`).

---

### 2.2 Node.js Exports (`modules/shared/node/`)

#### 1. `kdf_service.js`
- `async hashPin(pin)`
  - Hashes a PIN for database storage using Argon2id (`crypto_pwhash_str`).
- `async verifyPin(pin, storedHash)`
  - Verifies a PIN against a database-stored hash (`crypto_pwhash_str_verify`).
- `async deriveRawKey(pin, salt)`
  - Derives a raw 32-byte key from a PIN and a 16-byte salt using `crypto_pwhash`.

#### 2. `subkey_service.js`
- `async deriveSubKey(masterKey, context)`
  - Derives a 32-byte sub-key using `crypto_kdf_derive_from_key` with context `"MLINGO_1"` and matching context IDs.

#### 3. `cipher_service.js`
- `async encrypt(key, plaintext, conversationId, entityId)`
  - Encrypts plaintext using `ChaCha20-Poly1305-IETF` returning a Base64url blob.
- `async decrypt(key, blob, conversationId, entityId)`
  - Decrypts and authenticates a Base64url blob. Returns `null` on verification failure.

#### 4. `mnemonic_service.js`
- `async deriveMnemonicHash(mnemonic, salt)`
  - Hashes a BIP-39 mnemonic string using PBKDF2-HMAC-SHA256 (600,000 iterations) with a 16-byte random salt. Returns a 32-byte buffer.
- `async verifyMnemonic(mnemonic, saltHex, storedHashHex)`
  - Performs a timing-safe verification of a recovery mnemonic against the stored PBKDF2 hash.

#### 5. `crypto_error_codes.js`
- Exports error code constants identical to the Dart implementation.

---

## 3. Data Architecture & Schemas

### 3.1 Input Validation Contracts
Before executing any encryption or decryption, the `cipher_service` enforces strict validation of parameters:
- **Conversation ID / Entity ID (Message ID, Note ID, etc.):** Must match `^[a-zA-Z0-9]+$` (strictly alphanumeric). This prevents separator injection attacks in AAD strings.
- **Base64url Blob Structure:** Decoded binary length must be $\ge 28$ bytes (12-byte nonce + 16-byte minimum auth tag). Any shorter payload returns `CRYPTO_008` (Malformed Blob) or `null` immediately.

### 3.2 MongoDB Field Types (Reference)
The fields managed by other modules must use these shared formats:
- `users.pinHash`: Argon2id self-contained hash string (starts with `$argon2id$`).
- `users.duressPinHash`: Argon2id self-contained hash string.
- `users.recoveryPhraseHash`: Hex string of the derived 32-byte PBKDF2 key.
- `users.mnemonicSalt`: 32-character hex-encoded string (representing a 16-byte random salt).

---

## 4. Key Contracts & Validation
- **Zero Plaintext Leakage:** Cryptographic primitives operate purely in-memory. They must never print values to system stdout/stderr or persist raw states to logfiles.
- **Timing-Attack Resistance:** The Node.js verification systems (e.g. `verifyMnemonic`) must use Node's `crypto.timingSafeEqual` to check hashes, preventing timing oracle attacks.

---

## 5. Security & Edge Case Handling
- **E11 Mitigation:** If decryption fails, `cipher_service.decrypt` returns `null` instead of raising exceptions or throwing garbled data. The UI must detect the null state and render a standardized warning layout.
- **Wrong Key Counter:** The UI tracks decryption errors locally per conversation. When tag mismatch occurs (`CRYPTO_001`), the counter increments. On the 3rd consecutive mismatch, it triggers `CRYPTO_004` (Wipe) locally and dispatches a standard event to the backend.

---

## 6. Implementation Checklist & Phases

### Sub-Task Development Matrix
| Sub-Task | Description | Done |
|---|---|:---:|
| **T.1** | Scaffold schemas, models, and dependencies for Dart & Node.js. | [x] |
| **T.2** | Implement Argon2id KDF & BLAKE2b Sub-key derivation on both platforms. | [x] |
| **T.3** | Implement ChaCha20-Poly1305-IETF + AAD cipher wrappers with alphanumeric verification. | [x] |
| **T.4** | Implement BIP-39 mnemonic generation (vendored) and PBKDF2 server-side verification. | [x] |
| **T.5** | Add complete unit tests covering correct, incorrect, and malformed inputs. | [x] |

### Manual Verification Checklist
- [x] Verify that a ciphertext generated by the Dart `cipher_service` is decrypted successfully by the Node.js `cipher_service` given identical key/AAD parameters.
- [x] Verify that any modification of a single byte in a Base64url blob results in a decryption return value of `null` (authentication failure).
- [x] Verify that attempting to encrypt or decrypt with a non-alphanumeric `conversationId` or `entityId` triggers an assertion failure.
- [x] Verify that a generated 12-word recovery phrase passes standard BIP-39 validation on external tools.

---

## 7. Multi-Phase Cryptographic Integration Protocol

This section details the strict integration contracts that subsequent monorepo modules must respect during all future development phases.

### 7.1 Phase 1 Integration (Anonymous Identity & Auth)
* **Backend Module (`modules/backend/auth/`):**
  * When executing a user registration request (`POST /auth/register`), the auth controller must store the pre-computed `pinHash` and `duressPinHash` (Argon2id self-contained strings starting with `$argon2id$`) and the pre-computed PBKDF2 hex `recoveryPhraseHash` directly in the database.
  * When validating Vault PIN login (`POST /auth/login`), the auth controller must invoke `kdfService.verifyPin(enteredPin, user.pinHash)` and verify it returns `true`.
  * When validating Duress PIN login (`POST /auth/login/duress`), the controller must invoke `kdfService.verifyPin(enteredPin, user.duressPinHash)`.
  * Mnemonic Recovery Logins (`POST /auth/login/recovery`) must invoke `mnemonicService.verifyMnemonic(mnemonic, user.mnemonicSalt, user.recoveryPhraseHash)`.
* **Mobile Module (`modules/mobile/vault-auth/`):**
  * On initial 8-screen onboarding setup, the client must trigger BIP-39 phrase generation locally via `MnemonicService.generateMnemonic()`, and generate a 16-byte random salt via `KdfService.generateSalt()`.
  * Vault key derivation must execute strictly using the interactive parameter constants specified in `kdf_service.dart`.
  * The client must enforce that Vault PIN and Duress PIN are non-identical.

### 7.2 Phase 2 Integration (Conversations)
* **Join Verification Contract:**
  * When a participant requests to join an existing conversation room, the mobile client must present the Conversation Encryption Key.
  * The mobile client hashes the entered key using BLAKE2b (keyed subkey context) or a simple SHA-256 validation check, and the server validates it against `conversations.keyValidationHash`.
  * Plaintext conversation keys must never be transmitted or stored on the server under any circumstance.

### 7.3 Phase 3 & 4 Integration (Messaging, WebSockets, & Notes)
* **BLAKE2b Subkey Isolation:**
  * Developer agents building messaging and notes modules must strictly expand the master conversation key using the BLAKE2b KDF subkey context IDs:
    * `SubKeyContext.messages` (ID = `1`) for messaging.
    * `SubKeyContext.notes` (ID = `2`) for shared notebooks.
    * `SubKeyContext.media` (ID = `3`) for attachment references.
  * *Contract constraint:* A key derived for context ID `1` must never be used to decrypt note titles or contents under context ID `2`, ensuring absolute mathematical domain isolation.
* **ChaCha20-Poly1305 AAD Strings:**
  * Encryption payloads must strictly bind the entity IDs:
    * Messages: `"${conversationId}:${messageId}"`
    * Notes: `"${conversationId}:${noteId}"`
    * Media Reference metadata: `"${conversationId}:${mediaId}"`
  * Developer agents must execute the strict alphanumeric assertion (`^[a-zA-Z0-9]+$`) on both inputs before dispatching encryption/decryption requests. Non-compliant IDs must trigger an assertion exception (client) or return null immediately (server).

### 7.4 Phase 9 Integration (Key Rotation & Coercion Recovery)
* **Key Rotation Protocols:**
  * When the admin triggers key rotation, a new master conversation key is generated.
  * The old key is immediately purged from the participant device keychains.
  * All subsequent messages and notes are encrypted using subkeys derived from the new master key.
  * Stale client devices decrypting with old keys will hit the `E11` recovery hook (receiving `null` payload), triggering the 3-strike local wipe and initiating the standard key restoration workflow.