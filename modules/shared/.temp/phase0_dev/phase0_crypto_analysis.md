# Phase 0 Cryptographic Feature Study & Parity Analysis
**Module:** `modules/shared/` | **Agent:** Shared Cryptographic & Core Utilities  
**Status:** Awaiting Approval — No code or spec changes made.

---

## Context Absorbed

| Rule File | Key Constraint Ingested |
|---|---|
| `workflow-protocol.md` | Spec-First mandate; no code before approval |
| `architecture.md` | `flutter_sodium` (Dart) + `libsodium-wrappers` (Node.js); Zero server plaintext |
| `code-style.md` | SCS layered backend; Riverpod mobile; snake_case files |
| `project-context.md` | 8 security invariants; 16 edge cases (E1–E16) |
| `testing-requirements.md` | Jest + supertest (backend); flutter_test (mobile); all E-cases must be covered |
| `shared-agent.md` | Owns only `modules/shared/`; pure library, no routes/UI |
| `module-spec.md` | Baseline spec exists; T.1–T.4 checklist not started |
| `implementation_plan.md` | Phase 0 = scaffold + schema + super key + CI |

---

## Section 1 — Platform Cryptographic Parity

### 1.1 Argon2id KDF — PIN → Vault/Duress Key Derivation

**Purpose:** Derive a deterministic, high-entropy key from a user's 6-digit PIN. Used to produce `pinHash` and `duressPinHash` stored in the `users` collection, and to re-derive the local key for vault access.

#### Standardized Parameters (BOTH platforms MUST use these exact values)

| Parameter | Value | Rationale |
|---|---|---|
| Algorithm | `argon2id` | Resistant to GPU and side-channel attacks |
| `memlimit` | `67108864` (64 MiB) | `crypto_pwhash_MEMLIMIT_INTERACTIVE` baseline |
| `opslimit` | `3` | `crypto_pwhash_OPSLIMIT_INTERACTIVE` baseline |
| `saltLength` | `16 bytes` | `crypto_pwhash_SALTBYTES` = 16 (libsodium constant) |
| `outputKeyLength` | `32 bytes` | AES-256 / ChaCha20 key size |
| `hash encoding` | Raw `Uint8Array` / `Uint8List` | No Base64 encoding during derivation |

> [!IMPORTANT]
> The salt is **random per-user** and stored alongside the hash (not secret). On the backend, libsodium's `crypto_pwhash_str` produces a self-contained hash string that embeds salt+params. On mobile, we store the salt separately in `flutter_secure_storage` to allow key re-derivation without re-hashing to string.

#### Proposed API — Dart (`modules/shared/dart/kdf_service.dart`)

```dart
import 'package:flutter_sodium/flutter_sodium.dart';

class KdfService {
  /// Derives a 32-byte key from a PIN and a 16-byte salt.
  /// Used for local vault key derivation (NOT for server hash storage).
  static Future<Uint8List> deriveVaultKey({
    required String pin,
    required Uint8List salt, // 16 bytes, stored in flutter_secure_storage
  }) async {
    return Sodium.cryptoPwhash(
      outlen: 32,
      passwd: Uint8List.fromList(pin.codeUnits),
      salt: salt,
      opslimit: Sodium.cryptoPwhashOpslimitInteractive,
      memlimit: Sodium.cryptoPwhashMemlimitInteractive,
      alg: Sodium.cryptoPwhashAlgArgon2id13,
    );
  }

  /// Generates a cryptographically random 16-byte salt.
  static Uint8List generateSalt() => Sodium.randombytes(16);
}
```

#### Proposed API — Node.js (`modules/shared/node/kdf_service.js`)

```js
const sodium = require('libsodium-wrappers');

/**
 * Hashes a PIN for server-side storage using Argon2id.
 * Returns a self-contained hash string (includes salt + params).
 * @param {string} pin
 * @returns {Promise<string>} argon2id hash string
 */
async function hashPin(pin) {
  await sodium.ready;
  return sodium.crypto_pwhash_str(
    pin,
    sodium.crypto_pwhash_OPSLIMIT_INTERACTIVE,
    sodium.crypto_pwhash_MEMLIMIT_INTERACTIVE,
  );
}

/**
 * Verifies a PIN against a stored Argon2id hash string.
 * @param {string} pin
 * @param {string} storedHash
 * @returns {Promise<boolean>}
 */
async function verifyPin(pin, storedHash) {
  await sodium.ready;
  return sodium.crypto_pwhash_str_verify(storedHash, pin);
}

/**
 * Derives a raw 32-byte key from a PIN + explicit salt.
 * Used when we need the actual key bytes (e.g., super key dev mode).
 * @param {string} pin
 * @param {Buffer} salt - 16 bytes
 * @returns {Promise<Buffer>}
 */
async function deriveRawKey(pin, salt) {
  await sodium.ready;
  const key = sodium.crypto_pwhash(
    32,
    pin,
    salt,
    sodium.crypto_pwhash_OPSLIMIT_INTERACTIVE,
    sodium.crypto_pwhash_MEMLIMIT_INTERACTIVE,
    sodium.crypto_pwhash_ALG_ARGON2ID13,
  );
  return Buffer.from(key);
}

module.exports = { hashPin, verifyPin, deriveRawKey };
```

#### Parity Risks

> [!WARNING]
> **Risk P1:** `flutter_sodium`'s `cryptoPwhash` and `libsodium-wrappers`'s `crypto_pwhash` use the same underlying C library, so byte-for-byte output WILL match given identical `(passwd, salt, opslimit, memlimit, alg)` — but the server uses `crypto_pwhash_str` (with embedded random salt) for storage and `crypto_pwhash_str_verify` for verification. The mobile side uses raw `cryptoPwhash` to re-derive the encryption key locally. These are two different modes — they must never be confused or cross-used.

> [!WARNING]
> **Risk P2:** `flutter_sodium` is a wrapper around the native libsodium C library. Ensure the Flutter project uses `flutter_sodium ^0.2.0` or later which exposes `cryptoPwhashAlgArgon2id13`. Older versions may only expose `argon2i`. **Verify at scaffolding time.**

---

### 1.2 HKDF Sub-Key Derivation — Conversation Key Expansion

**Purpose:** Given a 32-byte Conversation Key (generated once at conversation creation), derive cryptographically independent sub-keys for different purposes (e.g., message encryption, note encryption) to enforce key separation.

> [!NOTE]
> libsodium does not expose HKDF directly. The standard approach is to use `crypto_kdf_derive_from_key` (libsodium's built-in KDF), which is an BLAKE2b-based construction — simpler and safer than raw HKDF in this context. This is the **recommended path** for both platforms.

#### Standardized Parameters

| Parameter | Value |
|---|---|
| Master Key | 32-byte Conversation Key (`crypto_kdf_KEYBYTES`) |
| Sub-key ID | `uint64` integer (1 = messages, 2 = notes, 3 = media) |
| Context string | `"MLINGO_1"` — exactly 8 bytes, hardcoded constant |
| Sub-key length | 32 bytes (`crypto_kdf_BYTES_MIN` to `crypto_kdf_BYTES_MAX`) |

#### Proposed API — Dart (`modules/shared/dart/subkey_service.dart`)

```dart
import 'package:flutter_sodium/flutter_sodium.dart';

enum SubKeyContext { messages, notes, media }

class SubKeyService {
  static const String _contextString = 'MLINGO_1'; // exactly 8 bytes

  static final Map<SubKeyContext, int> _subKeyIds = {
    SubKeyContext.messages: 1,
    SubKeyContext.notes: 2,
    SubKeyContext.media: 3,
  };

  /// Derives a 32-byte sub-key from the master conversation key.
  static Uint8List deriveSubKey({
    required Uint8List masterKey, // 32 bytes
    required SubKeyContext context,
  }) {
    return Sodium.cryptoKdfDeriveFromKey(
      subkeyLen: 32,
      subkeyId: _subKeyIds[context]!,
      ctx: _contextString,
      key: masterKey,
    );
  }
}
```

#### Proposed API — Node.js (`modules/shared/node/subkey_service.js`)

```js
const sodium = require('libsodium-wrappers');

const CTX = 'MLINGO_1'; // exactly 8 ASCII bytes
const SUBKEY_IDS = { messages: 1, notes: 2, media: 3 };

/**
 * Derives a 32-byte sub-key from a 32-byte master conversation key.
 * @param {Buffer} masterKey - 32 bytes
 * @param {'messages'|'notes'|'media'} context
 * @returns {Promise<Buffer>}
 */
async function deriveSubKey(masterKey, context) {
  await sodium.ready;
  const subKey = sodium.crypto_kdf_derive_from_key(
    32,
    SUBKEY_IDS[context],
    CTX,
    masterKey,
  );
  return Buffer.from(subKey);
}

module.exports = { deriveSubKey };
```

#### Parity Risks

> [!WARNING]
> **Risk P3:** `crypto_kdf_derive_from_key` requires the context string to be **exactly 8 bytes**. `"MLINGO_1"` is 8 ASCII chars. This must be enforced as a compile-time constant on both platforms — never user-supplied, never variable-length.

> [!WARNING]
> **Risk P4:** Sub-key IDs must be identical across platforms and frozen in a shared constants file. If IDs drift between Dart and Node.js, decryption will silently produce wrong keys and fail at the AEAD tag verification step, triggering E11-style wipe flows prematurely.

---

### 1.3 AES-256-GCM & ChaCha20-Poly1305 — Message Payload Format

**Purpose:** Encrypt all message/note/media blobs before they leave the device. Server only ever receives the ciphertext blob.

#### Cipher Selection Policy

| Scenario | Cipher | Reason |
|---|---|---|
| Primary (all messages, notes, media) | `ChaCha20-Poly1305` via `crypto_aead_chacha20poly1305_ietf_*` | libsodium's preferred AEAD; same C primitives on both platforms; no hardware AES requirement |
| Fallback / Interop testing | AES-256-GCM | Only if explicit cross-library interop is needed; not default |

> [!IMPORTANT]
> The architecture spec says "AES-256-GCM (primary), ChaCha20-Poly1305 (fallback)" but libsodium's native AEAD is ChaCha20-Poly1305-IETF, which ensures byte-perfect parity without any HW-dependency risk. **I recommend inverting this:** use ChaCha20-Poly1305 as primary and AES-256-GCM only where required. This is an **open question** requiring your approval before spec is written.

#### Standardized Payload Format (Wire Blob)

All ciphertext blobs stored in MongoDB or sent over WebSocket MUST conform to this binary layout, Base64url-encoded for JSON transport:

```
[ nonce (12 bytes) | ciphertext (variable) | auth tag (16 bytes, appended by libsodium) ]
```

Encoded as a single `Base64url` string — no separate nonce field in JSON.

#### AAD (Additional Authenticated Data) Rules

| Context | AAD Value |
|---|---|
| Message blob | `conversationId + ":" + messageId` |
| Note blob | `conversationId + ":" + noteId` |
| Media meta blob | `conversationId + ":" + mediaId` |
| Conversation metadata blob | `conversationId` |

AAD is authenticated but NOT encrypted. It binds ciphertext to its MongoDB record, preventing blob transplant attacks.

#### Nonce Generation Strategy

- **Always random:** `Sodium.randombytes(12)` / `sodium.randombytes_buf(12)` per encryption call.
- **Never reuse nonces.** Since nonces are 96-bit random and keys rotate, collision probability is negligible for the expected message volumes of this app.
- Nonce is prepended to ciphertext in the wire blob (see format above).

#### Proposed API — Dart (`modules/shared/dart/cipher_service.dart`)

```dart
import 'package:flutter_sodium/flutter_sodium.dart';
import 'dart:convert';

class CipherService {
  /// Encrypts plaintext using ChaCha20-Poly1305-IETF.
  /// Returns a Base64url-encoded blob: nonce(12) + ciphertext + tag(16).
  static String encrypt({
    required Uint8List key,      // 32 bytes (sub-key)
    required String plaintext,
    required String aad,         // e.g. "convId:msgId"
  }) {
    final nonce = Sodium.randombytes(12);
    final ct = Sodium.cryptoAeadChacha20poly1305IetfEncrypt(
      m: Uint8List.fromList(utf8.encode(plaintext)),
      ad: Uint8List.fromList(utf8.encode(aad)),
      nsec: null,
      npub: nonce,
      k: key,
    );
    final blob = Uint8List(12 + ct.length)
      ..setRange(0, 12, nonce)
      ..setRange(12, 12 + ct.length, ct);
    return base64Url.encode(blob);
  }

  /// Decrypts a Base64url blob. Returns null on auth failure.
  static String? decrypt({
    required Uint8List key,
    required String blob,
    required String aad,
  }) {
    try {
      final bytes = base64Url.decode(blob);
      final nonce = bytes.sublist(0, 12);
      final ct = bytes.sublist(12);
      final pt = Sodium.cryptoAeadChacha20poly1305IetfDecrypt(
        m: null,
        c: ct,
        ad: Uint8List.fromList(utf8.encode(aad)),
        npub: nonce,
        k: key,
      );
      return utf8.decode(pt);
    } catch (_) {
      return null; // Auth tag mismatch → caller handles as E11
    }
  }
}
```

#### Proposed API — Node.js (`modules/shared/node/cipher_service.js`)

```js
const sodium = require('libsodium-wrappers');

/**
 * Encrypts plaintext. Returns a Base64url blob: nonce(12) + ciphertext+tag.
 * @param {Buffer} key - 32 bytes
 * @param {string} plaintext
 * @param {string} aad - e.g. "convId:msgId"
 * @returns {Promise<string>} Base64url-encoded blob
 */
async function encrypt(key, plaintext, aad) {
  await sodium.ready;
  const nonce = sodium.randombytes_buf(sodium.crypto_aead_chacha20poly1305_ietf_NPUBBYTES);
  const ct = sodium.crypto_aead_chacha20poly1305_ietf_encrypt(
    plaintext, aad, null, nonce, key,
  );
  const blob = Buffer.concat([Buffer.from(nonce), Buffer.from(ct)]);
  return blob.toString('base64url');
}

/**
 * Decrypts a Base64url blob. Returns null on auth failure.
 * @param {Buffer} key - 32 bytes
 * @param {string} blob
 * @param {string} aad
 * @returns {Promise<string|null>}
 */
async function decrypt(key, blob, aad) {
  await sodium.ready;
  try {
    const bytes = Buffer.from(blob, 'base64url');
    const nonce = bytes.sublist(0, 12);
    const ct = bytes.sublist(12);
    const pt = sodium.crypto_aead_chacha20poly1305_ietf_decrypt(
      null, ct, aad, nonce, key,
    );
    return Buffer.from(pt).toString('utf8');
  } catch {
    return null; // Auth tag mismatch
  }
}

module.exports = { encrypt, decrypt };
```

---

## Section 2 — E2EE Error Code Standard

### Unified Error Code Map

All modules consume error codes from a single constants file. The shared module owns and exports this map.

| Code | Constant Name | Trigger | Action |
|---|---|---|---|
| `CRYPTO_001` | `ERR_DECRYPT_TAG_MISMATCH` | Auth tag fails during AEAD decrypt | Return `null`; increment wrong-key counter |
| `CRYPTO_002` | `ERR_WRONG_KEY_ATTEMPT_1` | 1st wrong key attempt | Show mismatch toast; no wipe |
| `CRYPTO_003` | `ERR_WRONG_KEY_ATTEMPT_2` | 2nd wrong key attempt | Show warning; no wipe |
| `CRYPTO_004` | `ERR_WRONG_KEY_WIPE` | 3rd wrong key attempt | Wipe local conversation data; log `WRONG_KEY` event to `events` collection |
| `CRYPTO_005` | `ERR_KDF_PARAM_MISMATCH` | Salt/opslimit/memlimit mismatch on re-derive | Fatal error; force re-auth |
| `CRYPTO_006` | `ERR_SUBKEY_ID_UNKNOWN` | Unknown sub-key context ID passed | Fatal; crash with log |
| `CRYPTO_007` | `ERR_NONCE_LENGTH_INVALID` | Blob nonce field ≠ 12 bytes | `CRYPTO_001` path |
| `CRYPTO_008` | `ERR_BLOB_MALFORMED` | Base64url decode failure / truncated blob | Log + discard message; never render garbled text |

> [!IMPORTANT]
> **E11 prevention:** `ERR_DECRYPT_TAG_MISMATCH` (`CRYPTO_001`) must **never** render garbled bytes to the UI. The `decrypt()` function returns `null` on failure. The message bubble layer must show a placeholder (e.g., "⚠ Unable to decrypt") and increment the wrong-key counter. This directly prevents the E11 garbled text rendering problem.

#### Dart Constants (`modules/shared/dart/crypto_error_codes.dart`)

```dart
class CryptoErrorCodes {
  static const String tagMismatch         = 'CRYPTO_001';
  static const String wrongKeyAttempt1    = 'CRYPTO_002';
  static const String wrongKeyAttempt2    = 'CRYPTO_003';
  static const String wrongKeyWipe        = 'CRYPTO_004';
  static const String kdfParamMismatch    = 'CRYPTO_005';
  static const String subKeyIdUnknown     = 'CRYPTO_006';
  static const String nonceLengthInvalid  = 'CRYPTO_007';
  static const String blobMalformed       = 'CRYPTO_008';
}
```

#### Node.js Constants (`modules/shared/node/crypto_error_codes.js`)

```js
module.exports = {
  ERR_DECRYPT_TAG_MISMATCH:   'CRYPTO_001',
  ERR_WRONG_KEY_ATTEMPT_1:    'CRYPTO_002',
  ERR_WRONG_KEY_ATTEMPT_2:    'CRYPTO_003',
  ERR_WRONG_KEY_WIPE:         'CRYPTO_004',
  ERR_KDF_PARAM_MISMATCH:     'CRYPTO_005',
  ERR_SUBKEY_ID_UNKNOWN:      'CRYPTO_006',
  ERR_NONCE_LENGTH_INVALID:   'CRYPTO_007',
  ERR_BLOB_MALFORMED:         'CRYPTO_008',
};
```

#### Wrong-Key Counter & Wipe Logic

The counter is **local-only** (stored in `flutter_secure_storage` per `conversationId`). The server is never told the count — only the final `WRONG_KEY` event (after wipe) is logged to the `events` collection.

```
Attempt 1 → CRYPTO_002 toast → counter = 1 (stored locally)
Attempt 2 → CRYPTO_003 warning → counter = 2
Attempt 3 → CRYPTO_004 → wipe local conv data → POST event (type: WRONG_KEY) → counter reset
```

---

## Section 3 — BIP-39 Mnemonic Generation & Verification

### 3.1 Generation (Mobile — at Vault Setup, Screen 3)

**Approach:** Generate a 128-bit entropy value → map to BIP-39 word list → produce 12-word phrase (128 bits entropy + 4-bit checksum = 132 bits = 12 words × 11 bits).

**Package:** `bip39` Dart package or inline BIP-39 word list + entropy generation via `flutter_sodium`'s `randombytes`.

```dart
// modules/shared/dart/mnemonic_service.dart
import 'package:bip39/bip39.dart' as bip39;

class MnemonicService {
  /// Generates a cryptographically random 12-word BIP-39 phrase.
  static String generateMnemonic() {
    return bip39.generateMnemonic(strength: 128); // 12 words
  }

  /// Converts mnemonic to 64-byte seed using PBKDF2 (BIP-39 spec).
  /// passphrase is always empty string for this app (no extra passphrase).
  static Uint8List mnemonicToSeed(String mnemonic) {
    return bip39.mnemonicToSeed(mnemonic); // Returns 64 bytes
  }

  /// Validates mnemonic wordlist membership and checksum.
  static bool isValid(String mnemonic) {
    return bip39.validateMnemonic(mnemonic);
  }
}
```

### 3.2 Server Storage — PBKDF2 Hash of the Phrase

The server does **not** store the mnemonic plaintext. It stores a PBKDF2 hash to verify the phrase during recovery login.

**PBKDF2 Parameters (hardcoded constants):**

| Parameter | Value |
|---|---|
| Password | Raw mnemonic string (space-separated words) |
| Salt | `userId` bytes (deterministic, user-specific) |
| Iterations | `600000` (OWASP 2023 recommendation for SHA-256) |
| Hash | `SHA-256` |
| Output | 32 bytes |

```js
// modules/shared/node/mnemonic_service.js
const crypto = require('crypto');

/**
 * Hashes a BIP-39 mnemonic for server storage.
 * @param {string} mnemonic
 * @param {string} userId  — used as deterministic salt
 * @returns {Promise<string>} hex-encoded 32-byte PBKDF2 hash
 */
async function hashMnemonic(mnemonic, userId) {
  return new Promise((resolve, reject) => {
    crypto.pbkdf2(mnemonic, userId, 600000, 32, 'sha256', (err, key) => {
      if (err) reject(err);
      else resolve(key.toString('hex'));
    });
  });
}

/**
 * Verifies a supplied mnemonic against the stored hash.
 * Uses timing-safe comparison to prevent oracle attacks.
 */
async function verifyMnemonic(mnemonic, userId, storedHash) {
  const derived = await hashMnemonic(mnemonic, userId);
  return crypto.timingSafeEqual(
    Buffer.from(derived, 'hex'),
    Buffer.from(storedHash, 'hex'),
  );
}

module.exports = { hashMnemonic, verifyMnemonic };
```

> [!NOTE]
> The mobile side uses `bip39.mnemonicToSeed()` (which internally runs PBKDF2-HMAC-SHA512 with 2048 iterations per BIP-39 spec) to derive the 64-byte seed for future wallet-style key material. The server-side PBKDF2 hash above is a **separate, independent operation** purely for recovery phrase verification — the two must never be confused.

### 3.3 Screen 3 — 3-Word Confirmation Flow

Before proceeding from onboarding Screen 3, the user must correctly enter 3 randomly chosen words from their 12-word phrase. This is a UI contract (mobile only), but the `MnemonicService.isValid()` and word-index-check utilities must live in `modules/shared/dart/mnemonic_service.dart`.

```dart
/// Returns 3 unique random indices from 0–11 for confirmation challenge.
static List<int> generateConfirmationIndices() {
  final rng = Random.secure();
  final indices = <int>{};
  while (indices.length < 3) indices.add(rng.nextInt(12));
  return indices.toList()..sort();
}
```

---

## Open Questions & Parity Risks Summary

| ID | Question / Risk | Impact | Decision Needed |
|---|---|---|---|
| **OQ-1** | Invert cipher preference? Use ChaCha20-Poly1305 as primary (not AES-256-GCM)? | Medium — affects all blob format specs | **Your call before spec write** |
| **OQ-2** | `flutter_sodium` package version — does it expose `cryptoPwhashAlgArgon2id13` and `cryptoAeadChacha20poly1305Ietf*`? Needs verification against pub.dev. | High — if not, alternative package needed | Verify at scaffolding |
| **OQ-3** | Should PBKDF2 for mnemonic use `userId` as salt (deterministic) or a random salt stored server-side? Deterministic is simpler but couples salt to userId. | Medium — security tradeoff | **Your call** |
| **OQ-4** | Should the `bip39` Dart package be used, or should we vendor the BIP-39 wordlist + implement inline (no external dep for crypto-critical code)? | Low-Medium — supply chain consideration | **Your call** |
| **OQ-5** | Key rotation (Phase 9) re-encrypts all blobs server-side — this requires the Node.js backend to hold the decrypted conversation key momentarily. Acceptable given the ROTATING lock status? | High — architectural constraint | Already accepted per Phase 9 plan |
| **OQ-6** | AAD format — use `"convId:entityId"` string or binary concatenation? String is simpler; binary avoids encoding edge cases. | Low | Recommend string; confirm |

---

## Proposed File Structure for `modules/shared/`

```
modules/shared/
├── module-spec.md          ← To be updated after approval
├── README.md
├── graph.md
├── dart/
│   ├── kdf_service.dart
│   ├── subkey_service.dart
│   ├── cipher_service.dart
│   ├── mnemonic_service.dart
│   └── crypto_error_codes.dart
└── node/
    ├── kdf_service.js
    ├── subkey_service.js
    ├── cipher_service.js
    ├── mnemonic_service.js
    └── crypto_error_codes.js
```

---

> [!IMPORTANT]
> **No files have been created or modified.** This is a read-only Phase 0 analysis. Awaiting your approval on the open questions above (especially OQ-1 and OQ-3) before proceeding to spec update.
