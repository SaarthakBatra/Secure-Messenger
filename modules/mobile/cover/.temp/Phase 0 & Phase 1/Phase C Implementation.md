# Phase C: Decoy UI Screens & Stealth Hooks - Detailed Implementation Plan

This document outlines the detailed user interface structures, routing updates, keys, stealth hook callbacks, and testing strategies for **Phase C: Decoy UI Screens & Stealth Hooks**.

---

## 1. Interface & Stealth Specifications

### Feature C.1: Onboarding Screen (`decoy_onboarding_screen.dart`)
- **Route**: `/onboarding`
- **UI Design**: A clean, premium-looking screen welcoming the user, displaying a language preference dropdown (e.g. English to Spanish), and a "Start Learning" button.
- **Onboarding Logic**:
  - When the "Start Learning" button is clicked:
    1. Sets `has_completed_onboarding = true` in `SharedPreferences`.
    2. Overrides the reactive state or forces router navigation to `/home`.

---

### Feature C.2: Home Screen (`decoy_home_screen.dart`)
- **Route**: `/home`
- **UI Design**: 
  - A premium dashboard showcasing:
    - **Header**: Main app logo and the user's current streak (StreakBadge showing `streakProvider` value).
    - **Body**: The dynamic "Word of the Day" card (loading, error, and data states bound to `wotdProvider`), plus standard quick access buttons to navigate to translation and reporting forms.
- **Stealth Hook (3s Long Press)**:
  - We will define `coverLogoLongPressCallbackProvider` in a shared location or locally:
    ```dart
    final coverLogoLongPressCallbackProvider = Provider<void Function()>((ref) {
      return () {}; // Mock default callback, overridden by core vault module
    });
    ```
  - The main logo widget detects interaction:
    - A standard `GestureDetector` with `onLongPress` might trigger too quickly.
    - We will implement a custom `GestureDetector` that utilizes a timer on `onTapDown` and `onTapUp` to strictly measure a **3-second duration** (3000ms), or a standard custom long press handler that satisfies the widget test expectations.

---

### Feature C.3: Offline Translation Screen (`offline_translation_screen.dart`)
- **Route**: `/home/translation` (or navigated as a standard full screen page)
- **UI Design**:
  - Input text field for typing English phrases.
  - Interactive language switcher.
  - Results card displaying the live translation.
- **Translation Logic**:
  - Listening to changes in the text field. We will use a debounced approach or a text controller to update translation state reactively using `translationSearchProvider` to keep the UI smooth and prevent rate-limiting on MyMemory API.

---

### Feature C.4: Report Issue Form Screen (`report_issue_form_screen.dart`)
- **Route**: `/home/report-issue`
- **UI Design**:
  - Standard user feedback form containing:
    - Issue category selector.
    - Description text field.
    - Numeric "Error Code" text field.
    - "Submit Report" button.
- **Stealth Hook Key & Submission Logic**:
  - Numeric 'Error Code' field uses `Key('issue_error_code_field')` exported via `CoverFormKeys.issueErrorCodeField`.
  - Submitting a normal issue performs a dummy HTTP POST request to `/api/decoy/feedback` via Dio.
  - **Vault Interface Contract**: By exposing `CoverFormKeys.issueErrorCodeField` and binding it to `Key('issue_error_code_field')`, we allow external modules (like the Secure Vault) to hook into the form input, discover the field via widget tests/finders, and intercept input to trigger vault decryption when the user enters their master key instead of a regular error code.

---

## 2. Router Integration (`app_router.dart`)

We will update [app_router.dart](file:///home/saarthak.batra/Documents/Antigravity/Secure%20Messenger/modules/mobile/lib/app/router/app_router.dart) to cleanly register our new screen routes, substituting the dummy placeholders:
- `/onboarding` -> `DecoyOnboardingScreen`
- `/home` -> `DecoyHomeScreen`
- Sub-routes for `/home/translation` and `/home/report-issue` for modern, standard navigation.

---

## 3. Rigorous Widget Testing Strategy (`ui_test.dart`)

All visual hierarchies, button triggers, form keys, and stealth timers will be verified in `tests/mobile/cover/ui_test.dart`.

### Tests Checklist
1. **Onboarding UI Tests**:
   - Verify layout builds, and pressing "Start Learning" triggers SharedPreferences write and routes to `/home`.
2. **Home UI Tests**:
   - Verify layout renders without viewport overflows.
   - Verify the word card and the streak badge display the expected states.
   - *Edge Case*: Simulating a 3-second long press on the logo correctly fires the `coverLogoLongPressCallbackProvider`, but a 2-second press does not.
3. **Translation UI Tests**:
   - Verify input text triggers translation rendering on the page.
4. **Report Issue UI Tests**:
   - Verify that the numeric error field is discoverable using `find.byKey(CoverFormKeys.issueErrorCodeField)`.
   - Verify that normal form submissions trigger a mock HTTP POST.
