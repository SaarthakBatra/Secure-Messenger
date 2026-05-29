# Module Specification: Mobile Decoy App UI & Helper

## 1. Overview
- **Path:** `modules/mobile/cover/`
- **Module ID:** `mobile-cover`
- **Implementation Phase:** Phase 1.0
- **Core Intent:** Functional decoy layer of the application. Disguised as a language learning utility, it provides live translations, words of the day, streaks, and settings screens. Crucially, it conceals the vault entry triggers using stealth hooks.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`
- **Data Flow Contract:** Zero plaintext leakage. Normal actions store data locally via `SharedPreferences`.

---

## 2. API / Interface Contracts & Stealth Hooks

### Decoy Onboarding Screen (`decoy_onboarding_screen.dart`)
- **Action:** Sets `has_completed_onboarding = true` in SharedPreferences.
- **Routing:** Routes user to `/home` upon completion.
- **Stealth:** None. Acts purely as a legitimacy builder.

### Decoy Home Screen (`decoy_home_screen.dart`)
- **Action:** Renders the user's daily streak (StreakBadge) and the Word of the Day card.
- **Stealth Hook:** A **3-second long press** on the main application logo triggers `coverLogoLongPressCallbackProvider`, acting as a covert entry point into the vault auth flow.

### Live Translation Screen (`offline_translation_screen.dart`)
- **Action:** Interactive text input translating phrases using the `translation_provider`.
- **Network Logic:** 
  - Attempts to use a free public API (e.g., LibreTranslate) via `translation_sync_service`.
  - **Offline Fallback:** If the network is unavailable or times out, seamlessly falls back to querying `assets/dictionary.json` using a fast, case-insensitive substring search.

### Report Issue Form Screen (`report_issue_form_screen.dart`)
- **Action:** Standard feedback page allowing users to type an issue description and submit it. Submitting performs a dummy HTTP POST to a `/api/decoy/feedback` mock endpoint.
- **Stealth Hook:** Features an optional numeric 'Error Code' field. If exactly 6 digits are provided, the description validation (requires >= 10 chars) is completely bypassed to permit stealth vault triggers. Submitting updates the `issueReportProvider`.

### Decoy Settings Screen (`decoy_settings_screen.dart`)
- **Action:** Premium settings page for toggling preferences and selecting learning goals.
- **Stealth Hook:** Features a System Diagnostics input field. Submitting updates the `issueReportProvider` with the code and an empty description (`body: ''`).

---

## 3. Data Architecture & Services

### `translation_sync_service.dart`
- **Primary:** Dio GET/POST to a public translation API.
- **Fallback:** Parses `assets/dictionary.json` to memory. Implements `.where()` substring matching.

### `wotd_sync_service.dart`
- **Primary:** Dio GET to `/api/decoy/wotd`.
- **Fallback:** Parses `assets/words.json` and returns a default word object.

### `streak_provider.dart` & `word_of_day_provider.dart` (Riverpod)
- **State Schema (SharedPreferences):**
  - `target_language` (String)
  - `daily_streak` (Int)
  - `last_active_date` (String, ISO-8601 YYYY-MM-DD)
- **Logic:** `streak_provider` increments `daily_streak` if `last_active_date` is exactly yesterday. Resets to 1 if older than yesterday. Does nothing if today.

### `issue_report_provider.dart` (Riverpod)
- **State Schema:** Atomic record `({String code, String body})` bridging the decoy module to the vault module. It securely captures diagnostic codes from the settings or report screens.

---

## 4. Testing Requirements (Strict)

Agents implementing this module MUST adhere to the following test coverage schemas located in `tests/mobile/cover/`:

1. **`services_test.dart`**: Tests JSON asset parsing, offline fallback triggering on network timeouts, and case-insensitive substring matching.
2. **`providers_test.dart`**: Mocks SharedPreferences dates to verify streak incrementing exactly by 1, and resetting on missed days.
3. **`ui_test.dart`**: Verifies normal rendering without overflow. Critically verifies `CoverFormKeys.issueErrorCodeField` is present, and simulates a 3s long press on the home logo to ensure the callback fires.

---

## 5. Implementation Checklist & Verification (Phase 1.0 Status)

### Sub-Task Development Matrix
| Sub-Task | Description | Status |
|---|---|:---:|
| **T.1** | **Global Scaffolding:** Initialize `pubspec.yaml`, `main.dart`, and base routing via `go_router`. | [x] |
| **T.2** | **Phase A (Data Services):** Implement `translation_sync_service` and `wotd_sync_service` with offline JSON fallbacks. | [x] |
| **T.3** | **Phase B (State Management):** Implement `streak_provider`, translation reactive state, and WOTD modifiers. | [x] |
| **T.4** | **Phase C (UI & Stealth Hooks):** Build decoy onboarding, home screen (3s long-press hook), and feedback form (Error Code hook). | [x] |
| **T.5** | **Test Suites:** Provide comprehensive widget and service tests inside `tests/mobile/cover/`. | [x] |

### Manual Verification Completed
- [x] Verified `pubspec.yaml` contains `go_router`, `flutter_riverpod`, `shared_preferences`, and `dio`.
- [x] Verified `CoverFormKeys.issueErrorCodeField` is explicitly mapped and globally discoverable for Phase 1 `vault-auth` interception.
- [x] Verified `coverLogoLongPressCallbackProvider` is scaffolded and ready to be overridden by the Vault Entry controllers.
- [x] Verified local fallback translation JSONs (`assets/dictionary.json`, `assets/words.json`) are registered in `pubspec.yaml`.