# Module: Shared Cryptographic & Core Utilities

## 1. Overview
This module houses the core cryptographic primitives, error codes, and shared validation logic for MultiLingo. It guarantees absolute platform parity between `flutter_sodium` (Dart FFI) and `libsodium-wrappers` (Node.js).

---

## 2. Directory Layout & Module Registry
The module contains two subdirectories to cleanly isolate platform-specific implementations:

```
modules/shared/
├── README.md               ← This guide
├── module-spec.md          ← Strictly enforced API contracts
├── graph.md                ← Mermaid sequence diagrams
├── dart/                   ← Mobile implementation layer
│   ├── bip39_wordlist.dart      ← Static 2048 English word array
│   ├── kdf_service.dart         ← Argon2id PIN key derivation
│   ├── subkey_service.dart      ← BLAKE2b sub-key expansion
│   ├── cipher_service.dart      ← ChaCha20-Poly1305-IETF + AAD
│   ├── mnemonic_service.dart    ← Inlined BIP-39 mnemonic generation
│   └── crypto_error_codes.dart  ← Dart error constant mapping
└── node/                   ← Backend implementation layer
    ├── kdf_service.js           ← Argon2id PIN verification
    ├── subkey_service.js        ← BLAKE2b sub-key expansion
    ├── cipher_service.js        ← ChaCha20-Poly1305-IETF + AAD
    ├── mnemonic_service.js      ← PBKDF2 mnemonic hash & timing-safe verify
    └── crypto_error_codes.js    ← Node.js error constant mapping
```

---

## 3. Real-World Execution Examples

### 3.1 Normal Workflow: Key Derivation & Message Decryption

A mobile device receives a WebSocket message containing a Base64url blob. It must securely derive the message decryption sub-key and decrypt the payload.

```dart
// 1. Retrieve master conversation key (32 bytes) from local secure storage
final Uint8List masterKey = await secureStorage.readBytes(key: 'master_key_conv_123');

// 2. Derive the dedicated message sub-key via BLAKE2b
final Uint8List messageKey = SubKeyService.deriveSubKey(
  masterKey: masterKey,
  context: SubKeyContext.messages, // Maps internally to ID = 1
);

// 3. Decrypt the Base64url blob using AAD binding
final String? plaintext = CipherService.decrypt(
  key: messageKey,
  blob: 'A4g93kLp2M1n...wire_blob...', // Base64url wire format
  conversationId: 'conv123',
  entityId: 'msg456',
);

if (plaintext != null) {
  // Successful Path: Render message plaintext in the UI bubble
  renderMessage(plaintext);
} else {
  // Error Path: Handle tag mismatch
  handleDecryptError(CryptoErrorCodes.tagMismatch);
}
```

### 3.2 Edge Case: Malformed Payload Recovery (`CRYPTO_008` & `CRYPTO_001`)

An attacker attempts to send an invalid or truncated payload to disrupt the app, or a network glitch cuts off transmission bytes.

```js
// Backend or Client-Side verification of a truncated blob
const incomingBlob = "A4g93k=="; // Base64url decoded length < 28 bytes

const decrypted = await cipherService.decrypt(
  key, 
  incomingBlob, 
  "conversationId123", 
  "messageId456"
);

if (decrypted === null) {
  // 1. Prevent garbled text rendering!
  // 2. Map structural error packet
  logger.warn({
    code: cryptoErrorCodes.ERR_BLOB_MALFORMED,
    message: "Payload structurally malformed or failed authentication check. Drop silently."
  });
  
  // 3. UI renders a secure standard layout block, keeping the database intact
  renderErrorPlaceholder();
}
```

### 3.3 Edge Case: 3-Strike Wrong Key Wipe Trigger (`CRYPTO_004`)

When key rotation occurs (Phase 9) and a partner's device fails to obtain the updated key, decryption tag mismatches will occur repeatedly.

```dart
void onDecryptionFailure(String conversationId) async {
  final currentCount = await secureStorage.readInt(key: 'wrong_key_count_$conversationId') ?? 0;
  
  if (currentCount < 2) {
    // Striking warnings
    final newCount = currentCount + 1;
    await secureStorage.writeInt(key: 'wrong_key_count_$conversationId', value: newCount);
    
    showToast(newCount == 1 
      ? CryptoErrorCodes.wrongKeyAttempt1 
      : CryptoErrorCodes.wrongKeyAttempt2
    );
  } else {
    // 3rd strike: Trigger local conversation purge
    await secureStorage.writeInt(key: 'wrong_key_count_$conversationId', value: 0);
    await database.purgeConversation(conversationId);
    
    // Notify server of wipe event
    await apiService.logEvent(
      conversationId: conversationId, 
      type: 'WRONG_KEY'
    );
    
    // Redirect to restoration flow
    navigator.pushReplacementNamed('/restoration', arguments: conversationId);
  }
}
```

---

## 4. Developer Verification Commands

To perform architectural tests and confirm mathematical parity between the Node.js and Dart environments, developers should execute the following test scripts:

### 4.1 Backend Test Runner (Jest)
Targeted unit testing for Node.js cryptographic algorithms, KDF structures, and PBKDF2 timings:
```bash
# In the root or backend folder
npm run test -- modules/shared
```

### 4.2 Mobile Test Runner (Flutter)
Targeted unit testing for Dart libsodium bindings, inlined BIP-39 generations, and AAD alphanumeric filters:
```bash
# In the root or mobile folder
flutter test modules/shared
```

### 4.3 Automated Cross-Platform Parity Script
A custom CI validation runner in `tests/` executes a round-trip test: encrypting a set of standard test vectors on Node.js and validating successful decryption inside the Dart VM environment. Ensure both tests pass before committing branch updates.

---

## 5. Multi-Phase Consumer Integration Reference

This section serves as a direct reference for future developer agents when integrating cryptographic functions into backend and mobile modules.

### 5.1 Node.js (Backend Modules)
When developing backend handlers (e.g. `modules/backend/auth/` or `modules/backend/messaging/`), always import the modular services directly:

```javascript
// 1. PIN hashing and verification for authentication
const { hashPin, verifyPin } = require('../../shared/node/kdf_service');

// 2. Sub-key derivation
const { deriveSubKey } = require('../../shared/node/subkey_service');

// 3. Encrypted block manipulation
const { encrypt, decrypt } = require('../../shared/node/cipher_service');

// 4. Mnemonic timing-safe validations
const { verifyMnemonic } = require('../../shared/node/mnemonic_service');
```

*Note:* All Node.js services automatically handle `await sodium.ready` internally before executing operations, eliminating race conditions.

### 5.2 Flutter / Dart (Mobile Modules)
When developing client-side modules (e.g. `modules/mobile/vault-auth/` or `modules/mobile/messaging/`), use relative path imports:

```dart
// 1. Local PIN Vault KDF
import '../../../shared/dart/kdf_service.dart';

// 2. BLAKE2b sub-key expansion
import '../../../shared/dart/subkey_service.dart';

// 3. E2EE ChaCha20-Poly1305 encryption
import '../../../shared/dart/cipher_service.dart';

// 4. BIP-39 Mobile Mnemonic generation
import '../../../shared/dart/mnemonic_service.dart';
```

*Note:* Ensure that the global initializer `await Sodium.init()` has executed successfully on client startup before calling these functions.

---

## 6. Detailed Cryptographic Workflows (Normal & Edge Cases)

### 6.1 Normal Flow 1: Onboarding & Account Registration
1. **Client Setup:**
   * Generate BIP-39 mnemonic: `MnemonicService.generateMnemonic()`
   * Generate cryptographically secure salt: `KdfService.generateSalt()`
   * Hash recovery mnemonic locally: `crypto.pbkdf2(mnemonic, salt, 600000, 32, 'sha256')`
   * Derives vault key: `KdfService.deriveVaultKey(pin, salt)`
2. **Server Registration Dispatch:**
   * Send anonymous payload containing derived hashes:
     ```json
     {
       "userId": "928374829",
       "pinHash": "$argon2id$v=19$m=65536,t=3,p=1$...",
       "duressPinHash": "$argon2id$v=19$m=65536,t=3,p=1$...",
       "recoveryPhraseHash": "a1b2c3d4...",
       "mnemonicSalt": "f8e9d0c1..."
     }
     ```
   * *Security Invariant:* The plaintext PIN and plaintext recovery phrase are never sent to the server.

### 6.2 Normal Flow 2: Zero-Plaintext Message Transport
1. **Encryption (Sender):**
   * Sender derives room message key: `SubKeyService.deriveSubKey(masterKey, SubKeyContext.messages)`
   * Sender encrypts payload: `CipherService.encrypt(messageKey, plaintext, conversationId, messageId)`
   * AAD is bound to: `"${conversationId}:${messageId}"`. Nonce is prepended.
2. **Decryption (Receiver):**
   * Receiver derives identical room message key via BLAKE2b.
   * Receiver decrypts Base64url blob: `CipherService.decrypt(messageKey, blob, conversationId, messageId)`
   * Invariant verified: AAD ensures the message cannot be copied or replayed under another room or message ID.

### 6.3 Edge Case E7: Onboarding PIN Collision Prevention
* **Scenario:** User attempts to set Vault PIN and Duress PIN to the exact same value.
* **Resolution:** Client checks if `vaultPin == duressPin`. During registration, the server double-checks by comparing the two Argon2id hashes. If identical, the registration request is blocked, returning a custom validation error code (`CRYPTO_007`), preventing the system from falling into an ambiguous state.

### 6.4 Edge Case E8: Duress PIN Stealth Activation
* **Scenario:** The user is coerced to unlock the app and inputs the Duress PIN.
* **Resolution:**
  1. Local comparison of the entered PIN hash maps to the `duressPinHash`.
  2. The mobile client transmits standard duress credentials: `POST /auth/login/duress { userId, duressPinHash }`.
  3. Server returns a restricted "clean shell" token and logs a silent `DURESS` event in the database.
  4. Server broadcasts disguised FCM pings to all of the user's active conversation partners, notifying them that a duress event occurred for that user.
  5. The mobile client loads a fake cover interface showing no active messages, preventing visual leakage of private communications.

### 6.5 Edge Case E11: 3-Strike Decryption Failure & Local Wipe
* **Scenario:** Stale key used to decrypt messages (e.g., following a missed key rotation event).
* **Resolution:**
  * Every decryption failure returns `null` (`CRYPTO_001` - Integrity Mismatch).
  * The client increments `wrongKeyCount`. On the 3rd consecutive strike:
    1. Instantly purges local secure storage conversation keys.
    2. Drops the local SQLite messages database for that room.
    3. Dispatches event notification: `POST /events { type: "WRONG_KEY", conversationId }`.
    4. Redirects the UI to the restoration request wizard.

### 6.6 Edge Case E13: Session Hijack Detection & Instant Revocation
* **Scenario:** An attacker attempts to reuse a hijacked session token or log in with credentials on another device.
* **Resolution:**
  * High-entropy `sessionToken` validation is checked on every Express/WebSocket handshake.
  * When a login or recovery login executes on Device B:
    1. Server immediately updates the `users.sessionToken` to the new token.
    2. Flags all existing sessions for that `userId` as invalidated in the `sessions` collection (`invalidatedAt = Date.now`).
    3. Triggers WebSocket disconnect on the old session's connection with a `401 Session Revoked` code, prompting Device A to immediately clear local memory and return to the cover app decoy layer.