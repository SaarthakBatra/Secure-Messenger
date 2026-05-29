# Module Dependency Graph: Backend Core

```mermaid
graph TD
    classDef default fill:#111,stroke:#333,stroke-width:1px,color:#eee;
    classDef target fill:#1a3a2a,stroke:#2b664c,stroke-width:2px,color:#eee;
    
    SubAgent["Backend Phase 2 Agent"] --> targetModule["modules/backend/ (Docs)"]:::target
    SubAgent --> codeModule["modules/backend/src/"]:::target
    codeModule --> Auth["Auth / Session Logic"]
    codeModule --> Crypto["Argon2 / Dev Shadow"]

    %% Style definitions
    class targetModule,codeModule target;
```

## System Data Flow (Happy Path)
```mermaid
sequenceDiagram
    autonumber
    actor Client
    participant API as Express Router
    participant Auth as Auth Controller
    participant DB as MongoDB
    
    Client->>API: POST /auth/login
    API->>Auth: rate-limited request
    Auth->>DB: Check for user & existing sessions
    DB-->>Auth: return user
    Auth->>DB: create short-lived session
    Auth-->>Client: 200 OK { sessionToken, refreshToken, sessionType }
```

---

## Token Refresh & Hack Detection Workflow
```mermaid
sequenceDiagram
    autonumber
    actor Client
    participant Auth as Auth Controller
    participant DB as Session & User DB

    Client->>Auth: POST /auth/refresh { sessionToken, refreshToken }
    Auth->>DB: Lookup session by token
    
    alt Session Valid & Refresh Token Matched
        Auth->>DB: Rotate refreshToken, update timestamps
        Auth-->>Client: 200 OK { new refreshToken }
    else Session Not Found or Expired
        Auth-->>Client: 401 SESSION_EXPIRED
    else Refresh Token Mismatch / Replay Attack (> 15m)
        Note over Auth, DB: Active Intrusion Detected!
        Auth->>DB: DELETE ALL user sessions
        Auth-->>Client: 403 HACK_DETECTED
    end
```

---

## Vault PIN Re-Authentication Workflow
```mermaid
sequenceDiagram
    autonumber
    actor Client
    participant API as Auth Controller (POST /auth/reauth)
    participant RateLimiter as progressiveReauthLimiter
    participant DB as User DB

    Client->>API: POST /auth/reauth { sessionToken, clientKey }
    API->>RateLimiter: Check limit (Max 3 attempts)
    
    alt Rate Limit Exceeded
        API-->>Client: 429 Too Many Requests
    else Within Limit
        API->>DB: Lookup user by session
        alt clientKey == vaultClientKey
            API->>DB: Reset wrongPinAttempts, rotate refreshToken
            API-->>Client: 200 OK { sessionToken, refreshToken }
        else clientKey invalid
            API->>DB: Increment wrongPinAttempts
            alt wrongPinAttempts >= 3
                API->>DB: Lock User (lockedUntil), Delete Sessions
                API-->>Client: 423 LOCKED_OUT
            else
                API-->>Client: 401 Unauthorized
            end
        end
    end
```

---

## MSK Escrow & Vault Registration
```mermaid
sequenceDiagram
    autonumber
    actor Client
    participant API as Auth Controller (POST /auth/register)
    participant Crypto as Argon2 (Worker Pool)
    participant DB as MongoDB

    Client->>API: POST /auth/register { clientKeys, pinWrappedMsk, phraseWrappedMsk }
    API->>Crypto: Hash deterministic clientKeys asynchronously
    Crypto-->>API: Argon2id hashes
    API->>DB: Save User { vaultClientKeyHash, ..., pinWrappedMsk, phraseWrappedMsk }
    API-->>Client: 201 Created { userId }
```

---

## E2EE Active Page Backup & Sync Flow

### Normal Active Page Backup
```mermaid
sequenceDiagram
    autonumber
    actor Client
    participant API as Conversations Controller (POST /conversations/:id/active-page)
    participant DB as MongoDB (ActivePage Collection)

    Client->>Client: Compile active messages & encrypt via lessonKey -> encryptedActivePage
    Client->>API: POST /conversations/:id/active-page { encryptedActivePage, updatedAt }
    Note over API: Verify client is participant of conversation
    API->>DB: Upsert ActivePage { conversationId, encryptedActivePage, updatedAt }
    API-->>Client: 200 OK { success: true }
```

### Active Page Conflict Resolution (On Vault Unlock)
```mermaid
sequenceDiagram
    autonumber
    actor Client
    participant API as Conversations Controller
    participant DB as MongoDB (ActivePage Collection)

    Client->>API: GET /conversations/:id/active-page
    API->>DB: Fetch ActivePage document
    DB-->>API: Return { encryptedActivePage, updatedAt (server_updatedAt) }
    API-->>Client: 200 OK { encryptedActivePage, updatedAt }
    
    alt server_updatedAt > local_updatedAt (Server is newer)
        Client->>Client: Decrypt server active page, merge messages in local SQLite, update local_updatedAt = server_updatedAt
    else local_updatedAt > server_updatedAt (Client is newer)
        Client->>Client: Encrypt local active messages -> new encryptedActivePage
        Client->>API: POST /conversations/:id/active-page { encryptedActivePage, local_updatedAt }
        API->>DB: Update ActivePage document
        API-->>Client: 200 OK { success: true }
    end
```

---

## Singly Linked-List R2 Cold-Storage Archiving Flow

### Normal Archiving Sequence
```mermaid
sequenceDiagram
    autonumber
    actor Client
    participant API as Express Router
    participant DB as MongoDB (Conversation Collection)
    participant R2 as Cloudflare R2

    Client->>Client: SQLite reaches MESSAGE_BUNDLE_SIZE (1000)
    Client->>API: GET /conversations/:id/latest-chapter
    API->>DB: Fetch conversation.latestChapterHash
    DB-->>API: Return hash (e.g. "old_hash")
    API-->>Client: 200 OK { latestChapterHash: "old_hash" }

    Client->>Client: Compile oldest 1000 messages
    Client->>Client: Create LessonChapter with previousChapterHash = "old_hash"
    Client->>Client: Encrypt Chapter via lessonKey -> Compute new_chapter_hash (SHA-256)
    
    Client->>API: POST /messages/upload-chapter-url { conversationId, new_chapter_hash }
    Note over API: Verify client is participant
    API-->>Client: 200 OK { uploadUrl: presigned PUT URL }

    Client->>R2: PUT encrypted chapter binary to presigned URL
    R2-->>Client: 200 OK

    Client->>API: POST /messages/archive-chapter { conversationId, new_chapter_hash }
    Note over API: Verify client is participant
    API->>DB: Update conversation.latestChapterHash = new_chapter_hash
    API->>DB: Delete ActivePage document for conversation
    API-->>Client: 200 OK { success: true }
    Client->>Client: Delete 1000 archived messages from local SQLite active table
```

### Edge Case: MongoDB Tail Pointer Update Fails
```mermaid
sequenceDiagram
    autonumber
    actor Client
    participant API as Express Router
    participant DB as MongoDB (Conversation Collection)
    participant R2 as Cloudflare R2

    Client->>R2: PUT encrypted chapter binary to presigned URL
    R2-->>Client: 200 OK
    Client->>API: POST /messages/archive-chapter { conversationId, new_chapter_hash }
    API->XDB: MongoDB timeout / network error during save
    API-->>Client: 500 Internal Server Error
    
    Note over Client: DB tail pointer is still "old_hash" in MongoDB.
    Note over Client: SQLite messages are NOT purged.
    Note over Client: Retry cycle initiates:
    
    Client->>API: GET /conversations/:id/latest-chapter
    API->>DB: Fetch latestChapterHash
    DB-->>API: Return "old_hash"
    API-->>Client: 200 OK { latestChapterHash: "old_hash" }
    
    Note over Client: Client regenerates chapter pointing to "old_hash", uploads to R2, and retries POST /messages/archive-chapter
    Client->>API: POST /messages/archive-chapter { conversationId, new_chapter_hash }
    API->>DB: Update tail pointer and delete active page
    API-->>Client: 200 OK { success: true }
    Client->>Client: Purge local SQLite messages
```

---

## E2EE Asymmetric Invitation & Key Exchange Flow
```mermaid
sequenceDiagram
    autonumber
    actor Alice as Creator Client (Alice)
    actor Bob as Recipient Client (Bob)
    participant API as Express Router
    participant DB as MongoDB
    participant WS as WebSocket Connection Pool

    Alice->>API: POST /conversations { recipientUserId, invitationMessage }
    API->>DB: Fetch public keys for Alice and Bob
    DB-->>API: Return public keys (X25519)
    API->>API: Generate symmetric lessonKey (256-bit)
    API->>API: Encrypt lessonKey via crypto_box_seal for Alice -> aliceInvitePayload
    API->>API: Encrypt lessonKey via crypto_box_seal for Bob -> bobInvitePayload
    API->>API: Zero-out lessonKey memory buffers
    API->>DB: Save Conversation { status: PENDING, aliceInvitePayload, bobInvitePayload }
    
    alt Bob is Online
        API->>WS: Push PENDING_INVITE { conversationId, bobInvite, message, senderUserId }
        WS->>Bob: Send invite payload
    else Bob is Offline
        Note over Bob, API: Bob polls GET /conversations/pending later
    end

    API-->>Alice: 201 Created { conversationId, aliceInvite }
    Alice->>Alice: Decrypt aliceInvite using translationSyncToken (private key)
    Alice->>Alice: Encrypt lessonKey with MSK -> wrappedLessonKey
    Alice->>API: POST /conversations/escrow { wrappedLessonKey, localAlias }
    Alice->>Alice: Save lessonKey to local SQLite

    Bob->>Bob: Decrypt bobInvite using translationSyncToken (private key)
    Bob->>API: POST /conversations/:id/join { conversationKey: lessonKey }
    Note over API: Verify key matches Argon2id hash in encryptedBlob
    API->>DB: Set status to ACTIVE, purge bobInvitePayload
    API-->>Bob: 200 OK
    Bob-->>Bob: Save lessonKey to local SQLite
```

---

## WebSocket Status Ticks & Offline Active Page Sync Flow
```mermaid
sequenceDiagram
    autonumber
    actor Alice as Creator (Alice)
    actor Bob as Recipient (Bob)
    participant API as Express Router
    participant WS as WebSocket Server
    participant DB as MongoDB (Message & ActivePage Collections)

    Note over Alice, Bob: happy path (recipient online)
    Alice->>WS: Send Chat Frame { messageId, conversationId, encryptedBlob }
    WS->>DB: Save Message { tickStatus: "sent", timestamps.sent }
    
    alt Bob is Online
        WS->>Bob: Forward Chat Frame { tickStatus: "delivered" }
        WS->>DB: Update Message { tickStatus: "delivered", timestamps.delivered }
        WS-->>Alice: Push Receipt { tickStatus: "delivered" }
        Bob->>Bob: Write to local SQLite as delivered
        Bob->>WS: Push Receipt { tickStatus: "acknowledged" }
        WS->>DB: Update Message { tickStatus: "acknowledged", timestamps.acknowledged }
        WS-->>Alice: Push Receipt { tickStatus: "acknowledged" }
        
        Bob->>Bob: UI views conversation room
        Bob->>WS: Push Receipt { tickStatus: "read" }
        WS->>DB: Update Message { tickStatus: "read", timestamps.read }
        WS-->>Alice: Push Receipt { tickStatus: "read" }
    else Bob is Offline
        WS-->>Alice: Push Receipt { tickStatus: "sent", recipientOffline: true }
        Alice->>Alice: Compile active page, encrypt with lessonKey
        Alice->>API: POST /conversations/:id/active-page { encryptedActivePage, updatedAt }
        API->>DB: Upsert ActivePage document
        API-->>Alice: 200 OK
    end
```

---

## R2 Cold-Storage Chapter Download & On-Demand Lazy Loading
```mermaid
sequenceDiagram
    autonumber
    actor Client
    participant API as Express Router
    participant DB as MongoDB (Conversation Collection)
    participant R2 as Cloudflare R2

    Note over Client: User scrolls up to load historical messages
    Client->>Client: Detect latestChapterHash != null
    Client->>API: POST /conversations/messages/download-chapter-url { conversationId, chapter_hash }
    Note over API: Authenticate user is participant
    API->>DB: Verify conversation and participant
    DB-->>API: Validated
    API-->>Client: 200 OK { downloadUrl: presigned GET URL }
    
    alt Happy Path
        Client->>R2: GET downloadUrl
        R2-->>Client: 200 OK (Encrypted chapter payload)
        Client->>Client: Decrypt chapter in RAM via lessonKey
        Client->>Client: Render messages, extract previousChapterHash
    else Presigned URL Expired (15-min limit)
        Client->>R2: GET downloadUrl (expired)
        R2-->>Client: 403 Forbidden
        Client->>API: POST /conversations/messages/download-chapter-url (renew request)
        API-->>Client: 200 OK { downloadUrl: new presigned GET URL }
        Client->>R2: GET new downloadUrl
        R2-->>Client: 200 OK
    end
```



