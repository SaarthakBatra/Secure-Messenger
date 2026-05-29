# Phase B: State Management (Riverpod Providers) - Detailed Implementation Plan

This plan details the exact architectural design, class interfaces, state schemas, and rigorous test cases for **Phase B: State Management**.

---

## 1. Feature Specifications & Riverpod Layout

We will implement three core Riverpod state providers under `modules/mobile/lib/features/cover/providers/`:
1. `streak_provider.dart` (StateNotifierProvider managing daily streak counts)
2. `translation_provider.dart` (Exposes dictionary search and wrapping TranslationSyncService)
3. `word_of_day_provider.dart` (FutureProvider exposing the Word of the Day)

### A. Shared Preferences Provider (`shared_prefs_provider` / dependency)
To allow clean mocking in tests and decoupled integration in the main application:
```dart
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override sharedPrefsProvider in main.dart or tests');
});
```

---

### B. Streak Provider (`streak_provider.dart`)
- **Type**: `StateNotifierProvider<StreakNotifier, int>`
- **State**: `int` (represents current daily streak count)
- **SharedPreferences Keys**:
  - `last_active_date` (String, formatted as "YYYY-MM-DD")
  - `daily_streak` (Int)
- **Increment & Reset Logic**:
  Upon initialization, the notifier reads SharedPreferences and performs a chronological audit:
  1. **First Launch (No last active date)**:
     - Set `last_active_date = today`
     - Set `daily_streak = 1`
     - State evaluates to `1`
  2. **Opened on Same Day (`last_active_date == today`)**:
     - Do not increment the streak.
     - State evaluates to `daily_streak`
  3. **Opened on Consecutive Day (`last_active_date == yesterday` / difference = 1 day)**:
     - Increment the streak: `daily_streak = daily_streak + 1`
     - Set `last_active_date = today`
     - State evaluates to the new incremented value.
  4. **Opened after 2 or more days (difference > 1 day)**:
     - Streak is broken. Set `daily_streak = 0`
     - Set `last_active_date = today`
     - State evaluates to `0`

---

### C. Translation Provider (`translation_provider.dart`)
- **Type**: `FutureProvider.family<String, ({String text, String from, String to})>`
- **Logic**:
  - Exposes a `translationServiceProvider` returning a concrete instance of `TranslationSyncService`.
  - Exposes an easily queryable family FutureProvider that components can listen to using text inputs.
  ```dart
  final translationServiceProvider = Provider<TranslationSyncService>((ref) {
    return TranslationSyncService();
  });

  final translationSearchProvider = FutureProvider.family<String, ({String text, String from, String to})>((ref, arg) async {
    final service = ref.watch(translationServiceProvider);
    return await service.translate(arg.text, from: arg.from, to: arg.to);
  });
  ```

---

### D. Word of the Day Provider (`word_of_day_provider.dart`)
- **Type**: `FutureProvider<WordOfDay>`
- **Logic**:
  - Exposes a `wotdServiceProvider` returning a concrete instance of `WotdSyncService`.
  - Exposes `wotdProvider` which automatically fetches the word of the day (supporting online/offline mechanisms implemented in Phase A).
  ```dart
  final wotdServiceProvider = Provider<WotdSyncService>((ref) {
    return WotdSyncService();
  });

  final wotdProvider = FutureProvider<WordOfDay>((ref) async {
    final service = ref.watch(wotdServiceProvider);
    return await service.fetchWotd();
  });
  ```

---

## 2. Rigorous Testing Strategy (`providers_test.dart`)

All state transitions, streak increments, resets, and date audits will be verified in `tests/mobile/cover/providers_test.dart`.

### SharedPreferences Mocking
We will utilize the official `SharedPreferences.setMockInitialValues` method to populate clean, predictable state before running each test case.

### Tests Checklist
1. **Streak Provider tests**:
   - *Normal Flow - First Launch*: SharedPreferences is empty. Verify streak starts at `1` and `last_active_date` is set to today.
   - *Normal Flow - Consecutive Day*: SharedPreferences contains `last_active_date` set to yesterday, `daily_streak = 3`. Verify streak increments to `4`.
   - *Edge Case - Same Day Reopening*: SharedPreferences contains `last_active_date` set to today, `daily_streak = 3`. Verify streak remains at `3`.
   - *Edge Case - Missed Days (2+ Days)*: SharedPreferences contains `last_active_date` set to 2 days ago, `daily_streak = 5`. Verify streak resets to `0`.

2. **Translation & WOTD Provider tests**:
   - Verify providers correctly proxy responses from their underlying sync services.
   - Ensure loading and error states are handled properly when the services fail.
