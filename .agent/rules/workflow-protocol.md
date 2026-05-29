# MultiLingo Modular Development Protocol (Workflow Rules)

## 1. Core Principles
Every feature, service, or interface component in MultiLingo MUST be developed in absolute isolation within its assigned module directory. Integration is conducted strictly via the orchestration layer.

### Separation of Concerns (SoC)
- Code that does not belong to a module's core responsibility must never reside in that module.
- Cross-module edits are strictly prohibited. You must only read other modules for context and use pre-defined API endpoints or shared library utilities to interact.
- **One Class/Service Per File:** Strive for atomic, singular files. A single file should contain one primary class, service, or interface, maintaining a low cognitive load.
- **Orchestration Separation:** Entry points (e.g., `index.js`, `main.dart`, or route registration files) are strictly for wireframe routing, initialization, and registering handlers. They MUST NOT contain business logic.

---

## 2. The Hybrid Spec System (CRITICAL)
Development operates in two synchronized state tiers:

### A. Transient State (Agent-Level Artifacts)
- **Planning & Checklist:** Use native Antigravity planning, checklists (`task.md`), and walkthroughs (`walkthrough.md`) to plan immediately, track hourly progress, and summarize actions. These files are temporary guides and should be marked as `/` (in progress), `x` (done), or ` ` (todo).

### B. Permanent Contracts (Repository-Level Specifications)
- **The Spec Document:** Every module MUST contain a physical `module-spec.md` and `README.md` at its root. 
- **Spec-First Mandate:** BEFORE writing a single line of executable source code or running modifying commands, you MUST read the module's existing `module-spec.md`, design the updates, write down the updated specs, and obtain user approval. No exceptions!
- **Documentation Updates:** If any change is made to data schemas, functions, API signatures, or navigation during implementation, the `module-spec.md` must be immediately updated. The physical contract must always reflect truth.

---

## 3. The 95% Confidence Protocol
- Before executing any command, file edit, or making decisions, you must achieve **95% confidence** in your understanding of the requirement, architecture, and code context.
- If you are below 95% confidence, you must perform deep analysis, read dependency specifications, search files using `grep_search`, and ask the user clarifying questions. **Never guess.**

---

## 4. Strict Scoping & Module Scarcity
- **One Agent Per Module:** An agent instance is summoned for a single module at a time. It is locked to `modules/<module_name>/`. It can read `modules/shared/` or other modules for context, but is strictly prohibited from editing them.
- **Integration Workspace:** Cross-module updates can only be executed in a dedicated Integration workspace, under explicit instruction from the user, and must be documented in a global integration plan.
- **No Unsolicited Refactoring:** Do not clean up, reformat, or alter code that is outside the immediate target area. Refactoring unrelated to the requested change creates bugs and breaks module isolation.

---

## 5. Development Phase Workflow
For every coding cycle, you must follow this sequence:
1. **Context Load:** Read all rules in `.agent/rules/` and the target `modules/<module_name>/module-spec.md`.
2. **Scaffold Spec & Plan:** Propose API/widget structures in `module-spec.md` and outline a list of tasks in `task.md`.
3. **Approval Gate:** Wait for the user to review the spec.
4. **Implement:** Write modular code, keeping business logic clean.
5. **Verify:** Run automated tests and update the manual checklist in `walkthrough.md`.
6. **Documentation Sync:** Clean up `README.md` and sync any changes to the spec.
