# MultiLingo Testing and Quality Requirements

## 1. Backend Testing Specifications

### Framework and Scope
- **Testing Engine:** Jest
- **Integration Framework:** `supertest` for Express REST API endpoint verification
- **Database Isolation:** Use `mongodb-memory-server` for database state isolation during tests. Production or development Mongo database states must never be mutated during test runner execution.

### Requirements:
- **Unit Tests:** Every service function (`*_service.js`) must be tested in isolation. Mock all MongoDB queries, websocket broadcast commands, and Firebase notification dispatches.
- **Integration Tests:** Target all HTTP endpoints using `supertest`. Assert:
  - 200/201 status and payload formats on successful inputs.
  - 400 Bad Request on malformed inputs (Zod failures).
  - 401 Unauthorized on missing/invalid session tokens.
  - 403 Forbidden on circular permissions (e.g. non-admin attempting key changes).
- **WebSocket Testing:** Write mock clients using `ws` to verify subscription authentication, room isolation, message broadcasting, and tick updates.

---

## 2. Mobile (Flutter) Testing Specifications

### Framework and Scope
- **Unit Tests:** Using standard `flutter_test` framework. Test providers, encrypt/decrypt sodium bindings, KDF outputs, and local SQLite data models.
- **Widget Tests:** Target core interface transitions, ensuring PIN layout keypads, decoy streak UI, and note editor states respond correctly to mock providers.
- **Integration Tests (E2E):** Using `integration_test` to simulate the full operational duality:
  - Initial decoy launch → Premium Button press → 8-screen onboarding.
  - PIN submissions in decoy forms → Vault entry → Conversation setup.
  - Verification of screen capture block triggers.

---

## 3. Mandatory Manual Testing Checklist Integration
Automated testing is excellent, but manual verification is REQUIRED before closing any development phase. Every module's `module-spec.md` must contain a physical **Manual Verification Checklist** targeting normal flows and module-specific edge cases.

All 16 edge cases (E1–E16) must map explicitly to either:
1. An automated Jest/Flutter test suite case.
2. A detailed manual checklist verification process.

---

## 4. Central Test Orchestration (`tests/run_all.sh`)
The central orchestrator in `/tests/run_all.sh` must execute the complete verification stack. The CI pipeline runs this shell script on every pull request.

### Steps executed by `run_all.sh`:
1. **Linter Scans:** Run `npm run lint` in the backend directory and `flutter lints` (or equivalent analyzer commands) in the mobile directory.
2. **Backend Suites:** Run Jest unit and integration tests with coverage reporting.
3. **Mobile Suites:** Run Dart/Flutter unit and widget tests.
4. **Super Key Scan:** Grep for unauthorized production environment credentials, Dev shadow collection hooks, or active flag leaks.
