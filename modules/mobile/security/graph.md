# Module Dependency Graph: Mobile Vault Security & Wipers

```mermaid
graph TD
    classDef default fill:#111,stroke:#333,stroke-width:1px,color:#eee;
    classDef target fill:#1a3a2a,stroke:#2b664c,stroke-width:2px,color:#eee;
    
    SubAgent["Mobile Vault Security & Wipers Agent"] --> targetModule["modules/mobile/security/"]:::target
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
    participant Module as Mobile Vault Security & Wipers
    participant CoreDB as Database / Storage
    
    User->>Module: Trigger Action / Input payload
    Note over Module: Sanitize, Validate, & Process E2EE Ciphertexts
    Module->>CoreDB: Write ciphertext record / Save state
    CoreDB-->>Module: Acknowledge write status
    Module-->>User: Render updated GUI states / Return HTTP response
```

---

## Edge Case 2: Zero-Leakage App Switcher Snapshot Prevention
```mermaid
sequenceDiagram
    autonumber
    actor User
    participant OS as Mobile OS
    participant App as Flutter App (main.dart)
    participant SecLayer as Screen Protector / WindowManager

    Note over User, App: User is actively viewing decrypted vault messages
    User->>OS: Swipes up to trigger App Switcher

    alt Android OS
        OS->>SecLayer: Notifies WindowManager
        Note over SecLayer: FLAG_SECURE is active
        SecLayer-->>OS: Force draw blank black card in preview
    else iOS
        OS->>App: Triggers inactive lifecycle (Home bar touched)
        App->>SecLayer: screen_protector triggers instantly
        Note over SecLayer: Draws #0F2027 overlay over entire Flutter view
        SecLayer-->>OS: OS captures snapshot of the safe #0F2027 overlay
    end

    User->>OS: Taps back into MultiLingo
    OS->>App: Transitions to resumed lifecycle
    App->>SecLayer: Lift iOS overlay / Android naturally resumes
    App-->>User: Vault UI is visible again
```