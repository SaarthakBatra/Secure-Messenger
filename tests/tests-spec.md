# MultiLingo Testing Specification (Agent-Facing)

## 1. Overview
This specification governs the automated testing pipeline for all MultiLingo AI agents. Every agent tasked with building features, initializing modules, or patching bugs MUST adhere to this specification.

- **Universal Orchestrator:** The absolute source of truth for test discovery and verification is [run_all.sh](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/tests/run_all.sh).
- **Single Scoping Exception:** While agents are strictly scoped to editing their respective `modules/<module_name>/` directories, they are granted explicit, parallel authorization to write and edit test files under the central `tests/` directory within their module's test path.

---

## 2. Test File Placement & Namespaces
To maintain isolation between product logic and test setups, all test suites are **centrally aggregated** in the root `tests/` directory. Tests MUST NOT be written inside the `modules/` folders.

Agents must write tests in the following exact locations matching their target platform:

### A. Backend Modules (`modules/backend/<module_name>/`)
- **Path:** `tests/backend/<module_name>/`
- **Naming Pattern:** `*_test.js` (e.g., `tests/backend/auth/login_test.js`)
- **Framework:** Jest + `supertest` for REST API endpoints + in-memory MongoDB.

### B. Mobile Modules (`modules/mobile/<module_name>/`)
- **Path:** `tests/mobile/<module_name>/`
- **Naming Pattern:** `*_test.dart` (e.g., `tests/mobile/vault-auth/pin_setup_test.dart`)
- **Framework:** standard `flutter_test` (for unit & widget checks) or `integration_test` (for E2E flows).

### C. Shared Modules (`modules/shared/`)
- **Path:** `tests/shared/`
- **Naming Pattern:** `*_test.js` or `*_test.dart` (matching the platform utilizing the helper).

---

## 3. Recursive Discovery Protocol
The master orchestrator [run_all.sh](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/tests/run_all.sh) operates via **recursive directory scanning**. It is designed to automatically capture and execute new tests without manual registration.

- **Backend Scan:** Jest is configured to recursively scan all subfolders of `tests/backend/` for files ending in `*.test.js` or `*_test.js`.
- **Mobile Scan:** The Flutter compiler recursively scans all subfolders of `tests/mobile/` for `*_test.dart` files.

---

## 4. Agent Checklist: Creating a New Test Suite

Whenever an agent builds a new feature or resolves a bug, it must execute these exact steps:

1. **Locate Target Path:** Identify the exact test directory (e.g., `tests/backend/auth/` for `modules/backend/auth/`).
2. **Create Test File:** Generate a test file following standard naming patterns.
3. **Implement Suite:** Write isolated, deterministic assertions. All databases and network calls must be fully mocked (or run in-memory).
4. **Local Verification:** Execute tests locally to confirm they pass.
5. **Orchestrator Run:** Execute the master orchestrator to verify automatic recursive discovery:
   ```bash
   ./tests/run_all.sh
   ```
6. **Feature Flag Audit:** Ensure no `SUPER_KEY_ENABLED` or shadow collections leak into production paths (the script will fail if flag checks are violated).
