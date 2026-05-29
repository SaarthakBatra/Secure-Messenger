# Module: Mobile Vault Security & Wipers

## Overview
This directory houses the isolated codebases for `Mobile Vault Security & Wipers`, operating within `Phase 4` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/mobile-security-agent.md`.

## Key Actions & Triggers
- **Vault Security Overlay:** System-wide dialog handling incorrect PIN tracking.
- **Duress Shell Screen:** Completely authentic, empty vault dashboard hiding background trackers.

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/mobile/security` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/mobile/security`

---

## Detailed Workflow Examples

### 1. Zero-Leakage OS Snapshot Prevention (Edge Case 2)
**Normal Flow:**
The user is inside the encrypted Vault, viewing secure messages. They swipe up to open the iOS or Android App Switcher to switch to another app.
- **Android:** The OS detects `FLAG_SECURE`. It completely blocks the Vault screen from being previewed in the App Switcher. The app appears as a blank white/black card.
- **iOS:** The `screen_protector` library intercepts the transition the millisecond the home bar is touched, actively drawing a `#0F2027` colored layer over the screen so the App Switcher preview is completely obscured.
*When the user taps back into the app, the protection is lifted seamlessly.*