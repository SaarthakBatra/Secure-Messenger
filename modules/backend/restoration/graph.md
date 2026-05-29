# Module Dependency Graph: Backend Restoration Requests Admin

```mermaid
graph TD
    classDef default fill:#111,stroke:#333,stroke-width:1px,color:#eee;
    classDef target fill:#1a3a2a,stroke:#2b664c,stroke-width:2px,color:#eee;
    
    SubAgent["Backend Restoration Requests Admin Agent"] --> targetModule["modules/backend/restoration/"]:::target
    targetModule --> Shared["modules/shared/"]
    targetModule --> Auth["modules/backend/auth/" or "mobile/vault-auth/"]
    targetModule --> Convos["modules/backend/conversations/" or "mobile/conversations/"]

    %% Style definitions
    class targetModule target;
```

## System Data Flow (Happy Path)
```mermaid
sequenceDiagram
    autonumber
    actor User as User Interface
    participant Module as Backend Restoration Requests Admin
    participant CoreDB as Database / Storage
    
    User->>Module: Trigger Action / Input payload
    Note over Module: Sanitize, Validate, & Process E2EE Ciphertexts
    Module->>CoreDB: Write ciphertext record / Save state
    CoreDB-->>Module: Acknowledge write status
    Module-->>User: Render updated GUI states / Return HTTP response
```