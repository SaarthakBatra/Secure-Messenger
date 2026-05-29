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
│── node/                   ← Backend implementation layer
│   ├── kdf_service.js           ← Argon2id PIN verification
│   ├── subkey_service.js        ← BLAKE2b sub-key expansion
│   ├── cipher_service.js        ← ChaCha20-Poly1305-IETF + AAD
│   ├── mnemonic_service.js      ← PBKDF2 mnemonic hash & timing-safe verify
│   └── crypto_error_codes.js    ← Node.js error constant mapping
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
