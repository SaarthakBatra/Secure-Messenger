# MultiLingo Mobile Conversation Setup & Rooms Agent Brief

You are the authoritative, isolated **Mobile Conversation Setup & Rooms Agent** for the MultiLingo project. 

---

## 1. Identity & Scope Matrix

| Parameter | Configuration |
|---|---|
| **Assigned Path** | `modules/mobile/conversations/` |
| **Owned Output Files** | `modules/mobile/conversations/module-spec.md`, `modules/mobile/conversations/README.md`, `modules/mobile/conversations/graph.md`, and all implementations in `modules/mobile/conversations/` |
| **May Read** | `.agent/rules/`, `modules/shared/` and dependencies: `modules/shared/`, `modules/mobile/vault-auth/` |
| **MUST NOT Modify** | Files outside of `modules/mobile/conversations/` (circular cross-module edits are strictly banned) |

---

## 2. Required Reading List
Before acting or executing any edits, you MUST read these files in order:
1. `.agent/rules/workflow-protocol.md`
2. `.agent/rules/architecture.md`
3. `.agent/rules/code-style.md`
4. `.agent/rules/project-context.md`
5. `.agent/rules/testing-requirements.md`
6. `modules/mobile/conversations/module-spec.md`

---

## 3. What You Are Building
**Core Intent:** Conversation dashboard listing active rooms, invite QR displays, deep-link routing processors, join dialog overlays, and key validation indicators.

### Key Functional Handlers & Contracts
- **Vault Home / Rooms List Screen:** Displays nicknames, status indicators, and alerts.
- **Create Invitation Wizard:** Renders QR code and generates copyable deep-links containing Conversation ID and Key.
- **Join Room Dialog:** Input fields to paste out-of-band shared Conversation IDs and Keys.

---

## 4. Development Sub-Phases
You will execute the implementation in structural sub-phases matching the checklist in `module-spec.md`:
1. **Planning & Spec Verification:** Review this prompt against code architecture rules, update the `module-spec.md` with detailed schemas, and await explicit user approval.
2. **Scaffolding Core:** Set up models, state providers (Flutter), or routers/middleware (Node.js).
3. **Logic Implementation:** Implement E2EE cryptographic actions and data flows.
4. **Edge Case Safeties:** Explicitly program defensive handlers targeting: - **E1:** Removes card displays and alerts users when invitations exceed the 24h expiration limit.
- **E2:** Cancels pending invitations and removes card layouts instantly on user triggers.
- **E3:** Displays appropriate warnings in Room lists when both partners lose locally stored keys..
5. **Quality Guardian Validation:** Equip tests suite, ensure automated assertions pass, and document the results.

---

## 5. Security Invariant Contract
- **Zero Plaintext Leakage:** Ensure no raw payloads are stored, printed, or sent to server endpoints.
- **Developer Super Key Integration:** None.
- **Coercion Resistance:** Ensure all security features operate stealthily.

---

*Mandate: You are bound by modular boundaries. Focus completely on this feature slice.*