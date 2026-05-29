# Module Dependency Graph: Mobile Conversation Setup & Rooms

```mermaid
graph TD
    classDef default fill:#111,stroke:#333,stroke-width:1px,color:#eee;
    classDef target fill:#1a3a2a,stroke:#2b664c,stroke-width:2px,color:#eee;
    
    SubAgent["Mobile Conversation Setup & Rooms Agent"] --> targetModule["modules/mobile/conversations/"]:::target
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
    participant Module as Mobile Conversation Setup & Rooms
    participant DB as SQLite (conversations.db)
    
    User->>Module: Click start/join conversation
    Note over Module: Generate/input conversation key.<br/>Encrypt key locally using active MSK.
    Module->>DB: Write encrypted conversation key
    DB-->>Module: Acknowledge write
    Module-->>User: Navigate to conversation screen
```

## Key Escrow & Restoration Flow
```mermaid
sequenceDiagram
    autonumber
    actor User as User Interface
    participant Module as Mobile Conversation Setup & Rooms
    participant API as Backend API
    participant DB as SQLite (conversations.db)
    
    Note over Module: On successful entry, unlock MSK.<br/>Request escrowed keys from server.
    Module->>API: GET /conversations/escrow (Session Token)
    API-->>Module: Return encrypted conversation keys list
    loop For each escrowed key
        Note over Module: Decrypt key using in-memory MSK.<br/>Encrypt key with local database wrapper.
        Module->>DB: Populate local conversations table
    end
    Module-->>User: Render populated conversations list
```