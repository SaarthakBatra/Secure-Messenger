# Module Dependency Graph: Backend Conversation Architecture

```mermaid
graph TD
    classDef default fill:#111,stroke:#333,stroke-width:1px,color:#eee;
    classDef target fill:#1a3a2a,stroke:#2b664c,stroke-width:2px,color:#eee;
    
    SubAgent["Backend Conversation Architecture Agent"] --> targetModule["modules/backend/conversations/"]:::target
    targetModule --> Shared["modules/shared/"]
    targetModule --> Auth["modules/backend/auth/" or "mobile/vault-auth/"]

    %% Style definitions
    class targetModule target;
```

## System Data Flow (Happy Path)
```mermaid
sequenceDiagram
    autonumber
    actor User as User Interface
    participant Module as Backend Conversation Architecture
    participant CoreDB as Database / Storage
    
    User->>Module: Trigger Action / Input payload
    Note over Module: Sanitize, Validate, & Process E2EE Ciphertexts
    Module->>CoreDB: Write ciphertext record / Save state
    CoreDB-->>Module: Acknowledge write status
    Module-->>User: Render updated GUI states / Return HTTP response
```

## Conversation Key Escrow Flow
```mermaid
sequenceDiagram
    autonumber
    actor User as Mobile Client
    participant Module as Backend Conversation Architecture
    participant CoreDB as Database / Storage
    
    Note over User: Create/Join Conversation.<br/>Encrypt Conversation Key with MSK.
    User->>Module: POST /conversations/escrow (encryptedConversationKey, localAlias)
    Module->>CoreDB: Save UserConversationKey record
    CoreDB-->>Module: Acknowledge write
    Module-->>User: 200 OK / 201 Created
```