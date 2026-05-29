import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../modules/mobile/lib/features/cover/providers/streak_provider.dart';
import '../../../modules/mobile/lib/features/cover/providers/translation_provider.dart';
import '../../../modules/mobile/lib/features/cover/providers/word_of_day_provider.dart';
import '../../../modules/mobile/lib/features/cover/services/translation_sync_service.dart';
import '../../../modules/mobile/lib/features/cover/services/wotd_sync_service.dart';

// Helper to format date consistent with StreakNotifier
String formatDate(DateTime date) {
  return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
}

void main() {
  group('StreakProvider Tests', () {
    test('Normal Flow: First Launch sets streak to 1 and last active date to today', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final streak = container.read(streakProvider);
      expect(streak, equals(1));
      expect(prefs.getInt('daily_streak'), equals(1));
      expect(prefs.getString('last_active_date'), equals(formatDate(DateTime.now())));
    });

    test('Normal Flow: Consecutive day increments streak by 1', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      SharedPreferences.setMockInitialValues({
        'last_active_date': formatDate(yesterday),
        'daily_streak': 3,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final streak = container.read(streakProvider);
      expect(streak, equals(4));
      expect(prefs.getInt('daily_streak'), equals(4));
      expect(prefs.getString('last_active_date'), equals(formatDate(DateTime.now())));
    });

    test('Edge Case: App opened on same day does not increment streak', () async {
      final todayStr = formatDate(DateTime.now());
      SharedPreferences.setMockInitialValues({
        'last_active_date': todayStr,
        'daily_streak': 3,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final streak = container.read(streakProvider);
      expect(streak, equals(3));
      expect(prefs.getInt('daily_streak'), equals(3));
      expect(prefs.getString('last_active_date'), equals(todayStr));
    });

    test('Edge Case: App opened after 2 days resets streak to 0', () async {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      SharedPreferences.setMockInitialValues({
        'last_active_date': formatDate(twoDaysAgo),
        'daily_streak': 5,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final streak = container.read(streakProvider);
      expect(streak, equals(0));
      expect(prefs.getInt('daily_streak'), equals(0));
      expect(prefs.getString('last_active_date'), equals(formatDate(DateTime.now())));
    });
  });

  group('Service Provider Proxies Tests', () {
    test('Verify translationServiceProvider returns TranslationSyncService instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(translationServiceProvider);
      expect(service, isA<TranslationSyncService>());
    });

    test('Verify wotdServiceProvider returns WotdSyncService instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(wotdServiceProvider);
      expect(service, isA<WotdSyncService>());
    });
  });
}
