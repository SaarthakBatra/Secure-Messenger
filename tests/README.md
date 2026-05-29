# MultiLingo Testing Suite & Orchestration

Welcome to the **MultiLingo Testing Suite**. This directory contains the centrally aggregated test suites for all backend, mobile, and shared modules in the application.

---

## 1. Directory Structure

To maintain separation of concerns, test files live in this root folder and are structured to mirror their respective modules:

```
tests/
├── backend/                  ← Centrally aggregated Node.js/Jest tests
│   ├── auth/                 ← Auth endpoints & session checks
│   ├── conversations/        ← Room creations & aliases
│   ├── messaging/            ← WebSocket connections & queues
│   └── ...                   ← Individual backend subfolders
├── mobile/                   ← Centrally aggregated Flutter/Dart tests
│   ├── cover/                ← Decoy learning layouts & translation
│   ├── vault-auth/           ← Setup wizards & PIN triggers
│   ├── security/             ← Screen lock policies & local wipes
│   └── ...                   ← Individual mobile subfolders
├── shared/                   ← Shared core library & utility tests
├── tests-spec.md             ← Strict specification for AI Agents
└── run_all.sh                ← Unified test runner & audit orchestrator
```

---

## 2. Recursive Test Discovery

This suite utilizes a **zero-registration, recursive discovery** model. 
All test files that follow standard naming conventions (`*_test.js` for backend, `*_test.dart` for mobile) are recursively scanned and run by [run_all.sh](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/tests/run_all.sh). 

You do not need to manually link or configure new tests to the runner script.

---

## 3. How to Execute Tests

### Run Everything (Recommended)
This is the absolute source of truth for repository health, executing linters, security flag audits, and both platform test suites:
```bash
./tests/run_all.sh
```

### Run Backend Tests Only
Ensure you are inside the backend directory or run Jest locally targeting this path:
```bash
cd modules/backend
npm test -- ../../tests/backend
```

### Run Mobile Tests Only
Execute Flutter's built-in test runner targeting the central mobile folder:
```bash
flutter test tests/mobile
```

---

## 4. Writing New Tests
Refer directly to the agent-facing [tests-spec.md](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/tests/tests-spec.md) for structural rules and schemas when introducing new assertions.
