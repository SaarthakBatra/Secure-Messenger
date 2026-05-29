# Module Dependency Graph: Mobile Vault Onboarding & Entry

```mermaid
graph TD
    classDef default fill:#111,stroke:#333,stroke-width:1px,color:#eee;
    classDef target fill:#1a3a2a,stroke:#2b664c,stroke-width:2px,color:#eee;
    
    SubAgent["Mobile Vault Onboarding & Entry Agent"] --> targetModule["modules/mobile/vault-auth/ (Docs)"]:::target
    SubAgent --> codeModule["modules/mobile/lib/features/vault_auth/"]:::target
    SubAgent --> secModule["modules/mobile/lib/features/security/"]:::target
    codeModule --> Shared["modules/shared/"]
    secModule --> Shared["modules/shared/"]

    %% Style definitions
    class targetModule,codeModule,secModule target;
```

## System Data Flow (Happy Path)
```mermaid
sequenceDiagram
    autonumber
    actor User as User Interface
    participant Module as Mobile Vault Onboarding & Entry
    participant CoreDB as Database / Storage
    
    User->>Module: Trigger Action / Input payload
    Note over Module: Sanitize, Validate, & Process E2EE Ciphertexts
    Module->>CoreDB: Write ciphertext record / Save state
    CoreDB-->>Module: Acknowledge write status
    Module-->>User: Render updated GUI states / Return HTTP response
```

---

## Phase 1.4 Unified Vault Entry & MSK Recovery
```mermaid
sequenceDiagram
    autonumber
    actor User
    participant DecoyUI as Report Issue Form
    participant Orchestrator as main.dart (Stealth Listener)
    participant Crypto as SodiumCryptoService
    participant API as Backend
    participant Auth as VaultSessionNotifier
    participant MSK as MskSessionProvider
    participant Router as GoRouter

    User->>DecoyUI: Enters 6-digit PIN in Reference Code
    User->>DecoyUI: Taps Submit
    DecoyUI->>Orchestrator: issueReportProvider state updates
    Note over Orchestrator: Intercepts! (vault_burned == false)
    
    Orchestrator->>Crypto: generateClientKey(PIN, fingerprint)
    Crypto-->>Orchestrator: SHA256 Hash
    Orchestrator->>API: POST /auth/login { userId, clientKey }
    API-->>Orchestrator: 200 OK { sessionType: "vault" | "duress", sessionToken }
    
    Orchestrator->>Auth: setSession(type, token: sessionToken)
    Note over Auth: Stores sessionType & token in memory
    Auth->>Router: refreshListenable triggers
    
    alt sessionType == 'vault'
        Orchestrator->>API: GET /auth/msk (Session Token)
        API-->>Orchestrator: Returns { pinWrappedMsk, phraseWrappedMsk }
        Orchestrator->>Crypto: PBKDF2-SHA256 & Decrypt pinWrappedMsk
        Crypto-->>Orchestrator: 256-bit Symmetric MSK
        Orchestrator->>MSK: Store MSK in memory
        Orchestrator->>Router: go('/vault')
    else sessionType == 'duress'
        Orchestrator->>Router: go('/vault/empty')
    end
```

---

## The Active Burn Protocol (Coercion Lockout & Hack Detection)
```mermaid
sequenceDiagram
    autonumber
    actor Attacker
    participant Interceptor as SessionInterceptor (Dio)
    participant API as Backend
    participant Prefs as SharedPreferences
    participant DB as VaultDbService

    Attacker->>Interceptor: Any Network Request or reauth
    Interceptor->>API: Executes Request
    
    alt returns 401 Unauthorized
        API-->>Interceptor: 401
        Interceptor->>Prefs: Increment wrong_pin_attempts
        alt wrong_pin_attempts >= 3
            Note over Interceptor: Coercion Lockout Triggered!
            Interceptor->>API: Backend sets 423 LOCKED_OUT for future
        end
    else returns 403 HACK_DETECTED or 423 LOCKED_OUT
        API-->>Interceptor: 403 / 423
        Note over Interceptor: Active Burn Protocol Triggered!
        Interceptor->>DB: wipeDatabase()
        Interceptor->>Prefs: DELETE vault_is_configured, user_id, recovery_phrase_words
        Interceptor->>Prefs: SET vault_burned = true
        Interceptor-->>Attacker: Return dummy `200 OK` (Plausible Deniability)
    end
```

---

## Edge Case 1: Keyboard Dismissal vs. Background Ejection
```mermaid
sequenceDiagram
    autonumber
    actor User
    participant OS as Mobile OS
    participant App as AppLifecycleListener
    participant Timer as 800ms Debounce / Grace Period Timer
    participant MSK as MskSessionProvider
    participant Auth as VaultSessionNotifier
    participant Router as GoRouter

    User->>OS: Taps 'Submit' or dismisses keyboard
    OS->>App: State changed to inactive / paused
    App->>Timer: Start grace period timer
    Note over Timer: Pads 5s if Desktop Platform,<br/>otherwise checks grace_period_duration

    alt User returns before Grace Period Expires
        OS->>App: State changed to resumed
        App->>Timer: Cancel timer
        Note over App, Router: Vault remains active
    else Grace Period Expires
        Note over Timer: Timer countdown completes
        Timer->>MSK: Wipe MSK from memory
        Timer->>Auth: clearSession()
        Timer->>Router: go('/home') (Ejection!)
    end
```

---

## Vault Setup Wizard & API Registration (Phase 1.3 / Phase 2 MSK Escrow)
```mermaid
sequenceDiagram
    autonumber
    actor User
    participant SetupUI as Setup Wizard
    participant Crypto as SodiumCryptoService
    participant API as Backend API
    
    User->>SetupUI: Completes PINs & Recovery Phrase
    SetupUI->>API: GET /dev/public-key
    API-->>SetupUI: Return base64 Curve25519 Public Key
    
    SetupUI->>Crypto: generateClientKey(PINs) & hash(Phrase)
    Crypto-->>SetupUI: SHA256 Client Keys
    SetupUI->>Crypto: Generate raw 256-bit MSK
    SetupUI->>Crypto: Wrap MSK with PIN key & Recovery Phrase key
    Crypto-->>SetupUI: pinWrappedMsk & phraseWrappedMsk blobs
    SetupUI->>Crypto: sealPayload(Plaintexts, PublicKey)
    Crypto-->>SetupUI: Sealed Box Payload
    
    SetupUI->>API: POST /auth/register (ClientKeys + Sealed Box + Wrapped MSKs)
    Note over API: Server performs Argon2id hashing
    API-->>SetupUI: 201 Created (User ID)
    SetupUI->>User: Display User ID & Copy Option
    SetupUI->>Router: Mark Configured & Route to /home
```

---

## Covert Identity Restoration (Device Migration)
```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Settings as Decoy Settings
    participant API as Backend (GET /dev/shadow)
    participant Auth as AuthApiService
    participant Prefs as SharedPreferences

    User->>Settings: Enters 9-11 digit User ID in Diagnostics
    Settings->>Auth: checkUserExists(userId)
    Auth->>API: GET /dev/shadow/:userId
    
    alt 200 OK
        API-->>Auth: User Found
        Settings->>Prefs: Save user_id, set vault_is_configured = true
        Settings->>User: Display "Diagnostic profile applied successfully."
    else 404 Not Found
        API-->>Auth: User Not Found
        Settings->>User: Fallback to regular Decoy "Settings saved successfully!"
    end
```

---

## Active ID Covert Query
```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Settings as Decoy Settings
    participant Dialog as Security Overlay
    participant Timer as 3-Second Timer

    User->>Settings: Enters '#*ID*#' in Diagnostics
    Settings->>Dialog: Render User ID Popup
    Dialog->>Timer: Start 3-second countdown
    
    alt User closes manually
        User->>Dialog: Taps close icon
        Dialog->>Timer: Cancel
        Dialog->>Settings: pop()
    else Auto-dismiss
        Timer->>Dialog: Countdown expires
        Dialog->>Settings: pop()
    end
```