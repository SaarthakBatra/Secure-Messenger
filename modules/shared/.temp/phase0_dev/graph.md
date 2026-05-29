# Module Dependency Graph: Shared Cryptographic & Core Utilities

```mermaid
graph TD
    classDef default fill:#111,stroke:#333,stroke-width:1px,color:#eee;
    classDef target fill:#1a3a2a,stroke:#2b664c,stroke-width:2px,color:#eee;
    
    SubAgent["Shared Cryptographic Utilities Agent"] --> targetModule["modules/shared/"]:::target
    targetModule --> Dart["modules/shared/dart/"]
    targetModule --> Node["modules/shared/node/"]

    %% Style definitions
    class targetModule target;
```

---

## 1. Normal Cryptographic Duality (Setup, Encryption, Decryption)

This sequence diagram illustrates the lifecycle of identity setup, room registration, message encryption, transport, and remote decryption.

```mermaid
sequenceDiagram
    autonumber
    actor ClientA as Mobile Client A (Sender)
    participant SharedA as Shared Lib (Dart)
    actor ClientB as Mobile Client B (Receiver)
    participant SharedB as Shared Lib (Dart)
    participant Server as Node.js Backend

    %% Onboarding / Setup
    Note over ClientA, SharedA: Onboarding Phase
    ClientA->>SharedA: generateMnemonic()
    SharedA-->>ClientA: 12-Word Phrase + Mnemonic Salt (16-byte random)
    ClientA->>SharedA: hashMnemonic(phrase, salt)
    SharedA-->>ClientA: recoveryPhraseHash
    ClientA->>Server: POST /auth/register { userId, recoveryPhraseHash, mnemonicSalt }
    Server->>Server: Store in Database

    %% Conversation Setup & Message Encryption
    Note over ClientA, Server: E2EE Message Flow
    ClientA->>SharedA: deriveSubKey(masterKey, "messages")
    SharedA-->>ClientA: messageEncryptionKey (32 bytes)
    ClientA->>SharedA: encrypt(key, plaintext, convId, messageId)
    Note over SharedA: AAD = "convId:messageId"<br/>Nonce = Random(12 bytes)<br/>Ciphertext = ChaCha20-Poly1305-IETF
    SharedA-->>ClientA: Base64url Wire Blob
    ClientA->>Server: WebSocket/HTTP dispatch E2EE payload
    Server->>Server: Opaque storage of ciphertext (No decryption key)
    Server->>ClientB: Relay Base64url Wire Blob

    %% Decryption Flow
    ClientB->>SharedB: deriveSubKey(masterKey, "messages")
    SharedB-->>ClientB: messageEncryptionKey (32 bytes)
    ClientB->>SharedB: decrypt(key, blob, convId, messageId)
    Note over SharedB: Base64url Decode<br/>Extract 12-byte Nonce & ciphertext<br/>Verify AAD "convId:messageId"
    SharedB-->>ClientB: plaintext (Verified & Decrypted)
```

---

## 2. Edge Case E11 — Wrong Key Wiping Flow

This diagram documents the error propagation and localized data destruction flow when a user attempts to decrypt with an incorrect or stale key (e.g. after a key rotation mismatch).

```mermaid
sequenceDiagram
    autonumber
    actor Client as Mobile Client
    participant Storage as flutter_secure_storage
    participant Shared as Shared Lib (Dart)
    participant Server as Node.js Backend

    Client->>Shared: decrypt(staleKey, incomingBlob, convId, messageId)
    Note over Shared: ChaCha20-Poly1305-IETF Auth Tag Check
    Shared-->>Client: returns null (Decryption/Integrity Mismatch)
    
    Note over Client: Detects Failure (CRYPTO_001)
    Client->>Storage: Read wrongKeyCounter[convId]
    
    alt Counter < 2
        Note over Client: Attempt 1 or 2
        Client->>Storage: Increment wrongKeyCounter[convId]
        Client-->>Client: Render Toast: "Wrong Key/Signature Mismatch" (CRYPTO_002 / CRYPTO_003)
    else Counter >= 2
        Note over Client: Attempt 3 (Fatal Mismatch)
        Client->>Storage: Trigger Local Wipe of convId records
        Client->>Storage: Reset wrongKeyCounter[convId] to 0
        Client->>Server: POST /events { type: "WRONG_KEY", conversationId: convId }
        Server->>Server: Log event to events collection
        Client-->>Client: Wipe local messages & redirect to restoration request screen (CRYPTO_004)
    end
```

---

## 3. Duress PIN Activation Flow

This diagram illustrates the stealth execution triggered by entering the Duress PIN instead of the Vault PIN. The UI displays a seemingly empty vault shell, while cryptographically executing background notifications.

```mermaid
sequenceDiagram
    autonumber
    actor User as Coerced User
    participant App as Mobile Client
    participant Shared as Shared Lib (Dart)
    participant Server as Node.js Backend
    participant Partner as Conversation Partner

    User->>App: Submits Duress PIN
    App->>Shared: Compare Vault PIN Hash vs Duress PIN Hash
    Note over Shared: Enforced as distinct values in Onboarding E7
    App->>Server: POST /auth/login/duress { userId, duressPinHash }
    Server->>Server: Verify Argon2id hash correctness
    Server-->>App: Return clean-shell Session Token
    
    par Background Dispatch
        App->>Server: POST /events/duress { conversationId, GPS: lat/long (if permitted) }
        Server->>Server: Log event to events collection
    and Partner Alerting
        Server->>Partner: Dispatch Disguised FCM Notification (Language-Learning context)
        Note over Partner: "Silent Duress Alert parsed in background<br/>Logs Duress event in local Notifications Tab"
    end
    
    App-->>User: Open Empty Cover App Shell (No messages visible)
```
