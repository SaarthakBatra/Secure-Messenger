# Module: Mobile Decoy App UI & Helper

## Overview
This directory houses the isolated codebases for `Mobile Decoy App UI & Helper`, operating within `Phase 1.0` development. The module serves as a fully functional, legitimate-looking language learning app to act as a decoy cover, while secretly embedding stealth hooks to enter the encrypted vault.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/mobile-cover-agent.md`.

---

## Key Actions, Triggers & Stealth Hooks
- **Decoy Onboarding Screen:** Set up language preferences and daily lesson timers.
- **Decoy Home Screen:** Renders streaks, word of the day widget, and daily exercises.
  - **Stealth Trigger:** 3-second long press on the main logo initiates the vault entry sequence.
- **Live Translation Screen:** Interactive input translating phrases.
- **Report Issue Form Screen:** Standard feedback page.
  - **Stealth Trigger:** A numeric 'Error Code' field (`CoverFormKeys.issueErrorCodeField`) doubles as a vault trigger when the correct PIN is submitted.

---

## Detailed Workflow Examples

### 1. Translation Workflow
**Normal Flow:** 
The user is connected to Wi-Fi and navigates to the Translation screen. They type "Hello". The `translation_sync_service.dart` queries a free public translation API via a Dio GET request. The API returns a 200 OK with detailed translation JSON. The provider updates the UI dynamically, and the user sees "Hola".

**Edge Case (Offline / Timeout):**
The user is in airplane mode. They type "Hello". The Dio request instantly fails or times out. The `translation_sync_service` catches the `DioException` and seamlessly falls back to reading `assets/dictionary.json`. It performs a case-insensitive substring match and returns the local translation for "Hello" so the app remains fully functional and unsuspicious.

### 2. Daily Streak & Word of the Day Workflow
**Normal Flow:**
The user opens the app on a Monday. The `streak_provider.dart` checks `SharedPreferences` for `last_active_date`. It was Sunday. The streak increments from 4 to 5. The `wotd_sync_service.dart` queries `/api/decoy/wotd` and fetches the new daily word for Monday.

**Edge Cases:**
- **Same-Day Reopening:** If the user closes and reopens the app later on Monday, `last_active_date` is today. The streak logic does nothing; the streak remains 5.
- **Missed Days:** The user forgets to open the app on Tuesday. They open it on Wednesday. `last_active_date` is Monday (difference > 1 day). The streak resets to 1 to maintain the illusion of a standard language learning app.

### 3. Stealth Hook Vault Entry Workflow
**Normal Flow:**
An adversary forces the user to open the app. They see standard vocabulary tests and translation screens. They go to "Report Issue", type "App is slow", leave the Error Code blank, and hit Submit. A mock HTTP POST is fired, and a standard "Thank you for your feedback" toast appears. Nothing suspicious occurs.

**Edge Case (Legitimate User Entry):**
The legitimate user navigates to the "Report Issue" form. They enter their 6-digit Vault PIN into the `issueErrorCodeField`. When they hit Submit, the application completely bypasses the mock HTTP POST, aborts the decoy flow, and fires the `vaultDecryptionProvider`, tearing down the Decoy UI and booting the Secure Messenger Vault.

---

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/mobile/cover` (or targeted Jest suites)
- **Mobile tests:** `flutter test tests/mobile/cover`
- **Global Orchestrator:** `./tests/run_all.sh`