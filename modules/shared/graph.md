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

---

## 4. Edge Case E7 — PIN Collision Prevention Flow

This diagram shows how the system prevents the setup of identical PINs during the onboarding phase.

```mermaid
sequenceDiagram
    autonumber
    actor User as Mobile User
    participant App as Mobile Client
    participant Server as Node.js Backend

    User->>App: Submits Vault PIN & Duress PIN
    App->>App: Check if vaultPin == duressPin
    alt Identical Values Detected locally
        App-->>User: Trigger local validation error: "Pins must be distinct"
    else Non-Identical (Local check passes)
        App->>Server: POST /auth/register { userId, pinHash, duressPinHash }
        Note over Server: Server executes Argon2id hash comparison
        alt Hashes Match (Server-side check fails)
            Server-->>App: Return 400 Bad Request (CRYPTO_007 - PIN Collision)
            App-->>User: Trigger validation error: "Security pins must not collide"
        else Unique Hashes (Success)
            Server->>Server: Register anonymous user identity
            Server-->>App: Return 200 OK (Registration Success)
            App-->>User: Proceed to Screen 3 (Mnemonic Confirmation)
        end
    end
```

---

## 5. Edge Case E13 — Session Hijack Detection & Instant Revocation

This diagram illustrates how logging in from a new device instantly revokes and disconnects a hijacked session on the old device.

```mermaid
sequenceDiagram
    autonumber
    actor Attacker as Attacker (Device A / Old Token)
    participant WS_A as WebSocket Conn A
    participant Server as Node.js Backend
    actor User as Legitimate User (Device B)
    participant WS_B as WebSocket Conn B

    Attacker->>WS_A: Establishes socket connection with active Token A
    Server-->>Attacker: Connection granted, start streaming events

    Note over User: Legitimate User logs in on Device B
    User->>Server: POST /auth/login { userId, pinHash, deviceFingerprintB }
    Server->>Server: Validate credentials
    Server->>Server: Generate new sessionToken B
    Server->>Server: Flag old session as invalidated in Database (invalidatedAt = Date.now)

    Server->>WS_A: Force socket disconnection (401 Session Revoked)
    Note over WS_A: Disconnects immediately
    WS_A-->>Attacker: Redirect to Cover Decoy interface

    User->>WS_B: Establishes socket connection with Token B
    Server-->>User: Connection granted, start streaming events
```

---

## 6. Global Monorepo Cryptographic Consumer Architecture

This flowchart maps the architectural dependencies, illustrating how subsequent backend and mobile modules import and consume specific cryptographic layers inside `modules/shared/`.

```mermaid
graph TD
    classDef default fill:#111,stroke:#333,stroke-width:1px,color:#eee;
    classDef shared fill:#1a3a2a,stroke:#2b664c,stroke-width:2px,color:#eee;
    classDef backend fill:#1a2b3c,stroke:#2c5b8f,stroke-width:1px,color:#eee;
    classDef mobile fill:#3c2a1a,stroke:#8f5c2c,stroke-width:1px,color:#eee;

    subgraph shared_module ["modules/shared/ (Core Library)"]
        node_lib["node/ (Mongoose / Express helpers)"]:::shared
        dart_lib["dart/ (Flutter FFI libsodium)"]:::shared
    end

    subgraph backend_modules ["modules/backend/"]
        b_auth["auth/ (Identity & PIN)"]:::backend
        b_dev["dev/ (Dev shadow)"]:::backend
        b_msg["messaging/ (WebSocket Hub)"]:::backend
        b_loc["location/ (Discrete Pings)"]:::backend
        b_rest["restoration/ (Inactivity Escape)"]:::backend
    end

    subgraph mobile_modules ["modules/mobile/"]
        m_vault["vault-auth/ (Vault Trigger)"]:::mobile
        m_msg["messaging/ (Decrypt/Encrypt bubbles)"]:::mobile
        m_notes["notes/ (Notebook MD editor)"]:::mobile
        m_loc["location/ (Background trigger)"]:::mobile
        m_rest["restoration/ (Recovery recovery)"]:::mobile
        m_sett["settings/ (PIN rotate/wipe)"]:::mobile
    end

    %% Backend Dependencies
    b_auth -->|Imports hash/verifyPin| node_lib
    b_auth -->|Imports timingSafeVerify| node_lib
    b_dev -->|Encrypts credential shadow| node_lib
    b_msg -->|Verifies socket AAD bindings| node_lib
    b_loc -->|Validates ping payloads| node_lib
    b_rest -->|Validates PBKDF2 mnemonics| node_lib

    %% Mobile Dependencies
    m_vault -->|Derives vaultKey via Argon2id| dart_lib
    m_vault -->|Generates random salt| dart_lib
    m_msg -->|Derives messages subkey (ID=1)| dart_lib
    m_msg -->|Encrypts/Decrypts ChaCha20-Poly1305| dart_lib
    m_notes -->|Derives notes subkey (ID=2)| dart_lib
    m_notes -->|Encrypts note titles & content| dart_lib
    m_loc -->|Derives media subkey (ID=3)| dart_lib
    m_loc -->|Encrypts lat/long pings| dart_lib
    m_rest -->|Generates BIP-39 mnemonic| dart_lib
    m_rest -->|Derives restoration index checks| dart_lib
    m_sett -->|Handles wipes and key rotations| dart_lib
```