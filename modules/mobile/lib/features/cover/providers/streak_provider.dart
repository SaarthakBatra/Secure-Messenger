import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Scoped provider for SharedPreferences, overriden in main.dart
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPrefsProvider must be overridden in the ProviderScope');
});

class StreakNotifier extends StateNotifier<int> {
  final SharedPreferences? _prefs;

  StreakNotifier(this._prefs) : super(0) {
    _checkAndUpdateStreak();
  }

  void _checkAndUpdateStreak() {
    if (_prefs == null) {
      state = 0;
      return;
    }
    final lastActive = _prefs!.getString('last_active_date');
    final currentStreak = _prefs!.getInt('daily_streak') ?? 0;
    
    final now = DateTime.now();
    final todayStr = _formatDate(now);

    if (lastActive == null) {
      // First launch
      _prefs!.setString('last_active_date', todayStr);
      _prefs!.setInt('daily_streak', 1);
      state = 1;
      return;
    }

    if (lastActive == todayStr) {
      // Opened on the same day: no increment, preserve current streak
      state = currentStreak;
      return;
    }

    try {
      final lastActiveDate = DateTime.parse(lastActive);
      
      // Normalize both dates to midnight to calculate true day differences
      final todayMidnight = DateTime(now.year, now.month, now.day);
      final lastMidnight = DateTime(lastActiveDate.year, lastActiveDate.month, lastActiveDate.day);
      final daysDiff = todayMidnight.difference(lastMidnight).inDays;

      if (daysDiff == 1) {
        // Consecutive day
        final newStreak = currentStreak + 1;
        _prefs!.setString('last_active_date', todayStr);
        _prefs!.setInt('daily_streak', newStreak);
        state = newStreak;
      } else if (daysDiff > 1) {
        // Opened after 2 or more days: streak resets to 0
        _prefs!.setString('last_active_date', todayStr);
        _prefs!.setInt('daily_streak', 0);
        state = 0;
      } else {
        // Safe guard in case clock was set backwards
        state = currentStreak;
      }
    } catch (_) {
      // Handle parsing failures defensively
      _prefs!.setString('last_active_date', todayStr);
      _prefs!.setInt('daily_streak', 1);
      state = 1;
    }
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }
}

final streakProvider = StateNotifierProvider<StreakNotifier, int>((ref) {
  SharedPreferences? prefs;
  try {
    prefs = ref.watch(sharedPrefsProvider);
  } catch (_) {
    // Resilient fallback for testing environments
  }
  return StreakNotifier(prefs);
});
