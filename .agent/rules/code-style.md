# MultiLingo Code Style and Standards Guide

## 1. Flutter / Dart Standards

### General Conventions
- **File Naming:** Files must follow `snake_case.dart` exclusively.
- **Class and Extension Naming:** Follow `UpperCamelCase` (e.g., `SecureStorageService`).
- **Method and Variable Naming:** Follow `lowerCamelCase` (e.g., `decryptMessage`).
- **Linting:** Adhere to `package:flutter_lints` and specific rules in `analysis_options.yaml`.

### State Management & Riverpod Patterns
- **No Direct Business Logic in Widgets:** Widgets are purely representational. They only watch state or trigger provider methods.
- **Provider Architecture:** Use Riverpod 2.x `Notifier` and `AsyncNotifier` structures.
  ```dart
  @riverpod
  class ConversationNotifier extends _$ConversationNotifier {
    @override
    FutureOr<List<Conversation>> build() async {
      return ref.read(apiServiceProvider).fetchConversations();
    }
  }
  ```
- **State Immutability:** State objects must be immutable. Use `@freezed` or copy methods.
- **Explicit Scoping:** Keep providers modular. A mobile module should export public providers through a clean API surface.

### Widget Separation & Build Methods
- **Max Build Method Length:** Avoid build methods longer than 60 lines. Break UI elements into small, stateless, private helper widgets (`_ConversationBubble`) or local classes within the same folder.
- **Constants:** Never hardcode layout metrics. Use a unified `AppDimensions` and `AppColors` layout scheme.

---

## 2. Node.js Backend Standards

### Linting & Formatting
- **Linter:** Strict Airbnb ESLint ruleset.
- **Formatter:** Prettier ruleset (semi: true, trailingComma: "all", singleQuote: true, printWidth: 100).
- **File Naming:** Follow `snake_case.js` to mirror mobile structures.

### Layered Architecture (SCS Structure)
Every route must be structured with strict separation of duties:
1. **Route layer (`*_routes.js`):** Registers paths, applies authentication middlewares, and handles initial `zod` payload schema validation. No database or computational logic.
2. **Controller layer (`*_controller.js`):** Extracts parameters, calls service layer functions, maps result to HTTP statuses, and manages response packaging.
3. **Service layer (`*_service.js`):** Houses pure business logic, cryptography, transactions, and calls database drivers.

### Safety Protocols & Async Execution
- **Error Boundaries:** Every single async service/controller function MUST be wrapped in a `try/catch` block or integrated with a global `express-async-handler` wrapper. Unhandled promise rejections are strictly forbidden.
- **Logging:** Use the unified `winston` log layer. `console.log` is strictly banned in production code. Use levels: `logger.error`, `logger.warn`, `logger.info`, `logger.debug`.
- **Validation:** Use `zod` schemas for all incoming HTTP request bodies, query params, and WebSocket data packets. Fail fast with a `400 Bad Request`.
