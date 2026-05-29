# Module Dependency Graph: Mobile Unified Settings Controller

```mermaid
graph TD
    classDef default fill:#111,stroke:#333,stroke-width:1px,color:#eee;
    classDef target fill:#1a3a2a,stroke:#2b664c,stroke-width:2px,color:#eee;
    
    SubAgent["Mobile Unified Settings Controller Agent"] --> targetModule["modules/mobile/settings/"]:::target
    targetModule --> Shared["modules/shared/"]
    targetModule --> Auth["modules/backend/auth/" or "mobile/vault-auth/"]
    targetModule --> Convos["modules/backend/conversations/" or "mobile/conversations/"]
    targetModule --> Security["modules/mobile/security/"]

    %% Style definitions
    class targetModule target;
```

## System Data Flow (Happy Path)
```mermaid
sequenceDiagram
    autonumber
    actor User as User Interface
    participant Module as Mobile Unified Settings Controller
    participant MSK as MskSessionProvider
    participant API as Backend API
    
    User->>Module: Submit new Vault PIN
    Module->>MSK: Fetch active raw MSK
    MSK-->>Module: Return raw MSK
    Note over Module: Derive KDF key from new PIN.<br/>Wrap MSK with new key.
    Module->>API: POST /auth/msk/update-pin { newPinWrappedMsk }
    API-->>Module: 200 OK
    Module->>API: POST /auth/pin/change { currentClientKey, newClientKey }
    API-->>Module: 200 OK
    Module-->>User: Show success SnackBar
```