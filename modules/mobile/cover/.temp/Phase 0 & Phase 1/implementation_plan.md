# Phase 1.0 Mobile Cover App Implementation Plan

This plan details the structured, phase-by-phase implementation of Phase 1.0 for the MultiLingo Cover App. We strictly follow a modular approach, ensuring each phase (Data Services, State Management, UI/Stealth Hooks) is fully implemented, verified with normal/edge case tests, and proven robust before moving to the next.

## User Review Required

- **Free Translation API**: We will integrate a free public API (such as LibreTranslate or MyMemory) for translation. We need to ensure no rate-limiting issues disrupt the testing suite. 
- **Stealth Hooks Alignment**: We need to ensure the dummy endpoints or stealth hook keys (`CoverFormKeys.issueErrorCodeField`) align with the broader global orchestrator testing strategy.

---

## Spec-First Updates (Pre-requisites)

Before starting the code implementation, we will perform extensive updates to the module's documentation so that any agent has the required detail to proceed autonomously.
#### [MODIFY] [module-spec.md](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/modules/mobile/cover/module-spec.md)
Update to be highly detailed, reflecting Phase 1.0 specifics, detailing stealth hooks, and the new online-first translation API mechanism.
#### [MODIFY] [graph.md](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/modules/mobile/cover/graph.md)
Update the architecture graph to show detailed component interactions, including the remote API calls and offline fallback paths for both translation and WOTD.
#### [MODIFY] [README.md](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/modules/mobile/cover/README.md)
Update to include highly detailed workflow examples for the module, covering both normal flows and edge cases, along with developer verification commands.

---

## Phase A: Data Services (Asset Parsing & Sync)

**Feature**: Core logic for translating words via a free remote API (with offline fallback) and fetching the "Word of the Day".

**Real-World Use Example**: 
A user opens the app while commuting on a subway with no cellular service. They try to search for the translation of "Apple". The translation service attempts to query the free online translation API, fails due to lack of internet, and gracefully falls back to the embedded `assets/dictionary.json` performing a fast substring search. This ensures the app looks completely legit. Similarly, the `wotd_sync_service` attempts to fetch the new daily word, fails due to lack of network, and seamlessly falls back to `assets/words.json` to keep the app functional and unsuspicious. When online, translations provide rich, detailed API responses.

### Proposed Changes
#### [NEW] [translation_sync_service.dart](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/modules/mobile/lib/features/cover/services/translation_sync_service.dart)
Uses Dio to query a free public translation API (e.g., LibreTranslate) for detailed translations. If it fails or times out, loads `assets/dictionary.json` and implements fast substring search functionality as an offline fallback.
#### [NEW] [wotd_sync_service.dart](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/modules/mobile/lib/features/cover/services/wotd_sync_service.dart)
Dio GET `/api/decoy/wotd` with local `assets/words.json` fallback to handle offline scenarios.

### Rigorous Testing (Phase A)
#### [NEW] [services_test.dart](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/tests/mobile/cover/services_test.dart)
- **Normal Flow**:
  - Validate Dio GET request processes the online API translation payload correctly.
  - Ensure correct WOTD fetching when online.
- **Edge Cases**:
  - Network timeout triggers offline fallback for translation (parsing local JSON asset successfully).
  - Network timeout triggers offline fallback for WOTD without crashing.
  - Malformed JSON handling: ensure both online responses and offline assets catch parsing errors and default to empty/safe responses.

---

## Phase B: State Management (Streak & Daily Logic)

**Feature**: Management of user streaks and daily dynamic data (Word of the Day) based on chronological interactions.

**Real-World Use Example**: 
A user has been practicing languages consistently. They open the app on Tuesday, and their streak increments from 4 to 5. The app then shows the Word of the Day dynamically updated for Tuesday. If they close the app and reopen it later on Tuesday, the streak remains 5. If they forget to open it on Wednesday and open it on Thursday, their streak is reset to 1. This reinforces the legitimacy of the "language app" decoy.

### Proposed Changes
#### [NEW] [streak_provider.dart](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/modules/mobile/lib/features/cover/providers/streak_provider.dart)
Auto-increment streak based on `last_active_date` stored in `SharedPreferences`.
#### [NEW] [translation_provider.dart](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/modules/mobile/lib/features/cover/providers/translation_provider.dart)
Exposes the dictionary search from `translation_sync_service` with reactive state.
#### [NEW] [word_of_day_provider.dart](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/modules/mobile/lib/features/cover/providers/word_of_day_provider.dart)
Modulo logic for daily word based on the date, leveraging `wotd_sync_service`.

### Rigorous Testing (Phase B)
#### [NEW] [providers_test.dart](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/tests/mobile/cover/providers_test.dart)
- **Normal Flow**:
  - Streak increments exactly by 1 when opened on consecutive calendar days.
  - WOTD provider correctly emits new words based on simulated date advancement.
- **Edge Cases**:
  - App opened multiple times on the same day: streak does not increment.
  - App opened after 2+ days: streak correctly resets to 1 (or 0, depending on spec logic).
  - Time zone shifts: ensure date calculations rely on normalized local dates.

---

## Phase C: Decoy UI Screens & Stealth Hooks

**Feature**: Rendering the legitimate-looking language app UI while planting hidden stealth hooks to transition the user into the encrypted vault without raising suspicion.

**Real-World Use Example**: 
An adversary forces the user to open the app. They see a normal onboarding screen, select Spanish, and enter the Home Screen. They see their daily streak and a Word of the Day. Everything looks normal. However, when the actual user is alone, they navigate to the "Report Issue" form and enter a specific PIN into the `issueErrorCodeField` (the stealth hook) and press submit, which silently intercepts the flow and triggers the encrypted vault decryption process instead of sending a feedback POST. Alternatively, a 3-second long press on the home screen logo triggers another stealth entry.

### Proposed Changes
#### [NEW] [decoy_onboarding_screen.dart](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/modules/mobile/lib/features/cover/screens/decoy_onboarding_screen.dart)
Sets `has_completed_onboarding = true` and routes to `/home`.
#### [NEW] [decoy_home_screen.dart](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/modules/mobile/lib/features/cover/screens/decoy_home_screen.dart)
StreakBadge, WOTD card. 
**Stealth**: 3s long-press on logo calls `coverLogoLongPressCallbackProvider`.
#### [NEW] [offline_translation_screen.dart](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/modules/mobile/lib/features/cover/screens/offline_translation_screen.dart)
UI for translations with debounced input, calling the provider that seamlessly handles online/offline logic.
#### [NEW] [report_issue_form_screen.dart](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/modules/mobile/lib/features/cover/screens/report_issue_form_screen.dart)
Standard feedback form.
**Stealth**: Exposes `CoverFormKeys.issueErrorCodeField` for external module hooking. Submit performs a dummy HTTP POST for standard queries.

### Rigorous Testing (Phase C)
#### [NEW] [ui_test.dart](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/tests/mobile/cover/ui_test.dart)
- **Normal Flow**:
  - UI renders without overflow across standard mobile viewports.
  - Translating text dynamically updates the UI via the TranslationProvider.
  - Submitting normal text in the Report Issue form fires a mocked dummy POST request.
- **Edge Cases**:
  - Ensure `CoverFormKeys.issueErrorCodeField` is discoverable via `find.byKey` to guarantee global vault integrability.
  - Ensure the 3s long-press on the logo successfully fires the callback but a 2s press does not.
  - Handle rapid consecutive form submissions to ensure idempotency.

---

## Final Verification
After all phases are completed and locally verified with `flutter test`, we will run the global orchestrator (`tests/run_all.sh`) to guarantee full ecosystem compatibility before generating the final `walkthrough.md`.
