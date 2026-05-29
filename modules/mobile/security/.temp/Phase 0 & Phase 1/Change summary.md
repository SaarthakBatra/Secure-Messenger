# MultiLingo Vault Interception Architecture

This document summarizes the stealth hooks, lifecycle protections, and routing architecture successfully deployed to seamlessly bridge the decoy language app and the hidden encrypted vault.

## 1. Stealth Entry Triggers

We successfully implemented two covert entry paths, fully decoupled from the decoy application's UI logic:

1. **The Configuration Long-Press:** A strict 3-second long press on the main `DecoyHomeScreen` logo. If the vault is unconfigured, it routes the user to `/vault/setup`. If the vault is already configured, it forces them to the Decoy Report Issue screen.
2. **The Numeric PIN Intercept:** A riverpod `ref.listen` attached to the Cover module's form data (`issueReportProvider`). If a user inputs exactly 6 digits into the Reference Code field and leaves the description entirely empty, the submission is instantly intercepted. The provider state is cleared, the `VaultSessionNotifier` is authenticated, and the user is dropped directly into the `/vault` via `GoRouter`.

> [!NOTE]
> All stealth triggers emit real-time `[STEALTH]` diagnostic logs to the debug console to trace configuration checks and routing logic.

## 2. GoRouter Riverpod Integration (The `refreshListenable` Architecture)

During testing, we discovered that watching a `StateProvider` (`vaultSessionProvider`) directly inside the `Provider<GoRouter>` caused the entire navigation stack to be destroyed and reset on every authentication event.

**The Solution:** We deployed a `VaultSessionNotifier` (a `ChangeNotifier`). By assigning this to the GoRouter's `refreshListenable`, the router now correctly re-evaluates its `redirect` guards *without* rebuilding the core router instance. This allows a seamless stack preservation from `/home/report-issue` directly to `/vault` without forcing the user through the `/onboarding` initial location.

## 3. The "E9" Zero-Leakage Lifecycle Protection

To prevent the Vault UI from bleeding into the iOS/Android App Switcher snapshots, we deployed a hybrid native and flutter-level defense strategy.

### Native UI Shielding
We injected native OS plugins directly into `main.dart`:
- **Android (`flutter_windowmanager`):** `FLAG_SECURE` is active, instantly blocking all screenshots and blacking out the App Switcher.
- **iOS (`screen_protector`):** Taps into `applicationWillResignActive` to throw a native `#0F2027` (dark blue) color block over the UI the millisecond the user touches the home bar, entirely bypassing the Flutter rendering thread.

### The Debounced Flutter Ejection Hook
We utilize a `WidgetsBindingObserver` to listen to Flutter's `AppLifecycleState`. 
Because Android/Desktop fires `inactive` whenever the software keyboard is dismissed (like tapping "Submit" on our PIN form), relying strictly on `inactive` to eject the user from the vault causes false positives.

We implemented an **800ms debounce timer**:
1. When `inactive` fires, the timer starts.
2. If the app hits `resumed` before 800ms (standard for keyboard dismissal), the timer cancels.
3. If the timer expires and the user is anywhere inside the `/vault` path, the session is forcefully revoked, and `router.go('/home')` is executed, completely removing the vault from the background stack.

## 4. Verification

The architecture has been fully manually verified. The shared preferences persistent storage layer correctly transitions states from First Boot -> Vault Setup -> Decoy Operation -> Vault Access. Cross-module injection was successfully coordinated with the Cover Module Agent to ensure reactive onboarding states.
