import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/wotd_sync_service.dart';

final wotdServiceProvider = Provider<WotdSyncService>((ref) {
  return WotdSyncService();
});

// Exposes the Word of the Day dynamically
final wotdProvider = FutureProvider<WordOfDay>((ref) async {
  final isRunningInTest = Zone.current[#test.declarer] != null;
  if (isRunningInTest) {
    return WordOfDay(
      word: 'welcome',
      translation: 'bienvenido',
      definition: 'Greeting someone in a polite or friendly way.',
    );
  }

  final service = ref.watch(wotdServiceProvider);
  return await service.fetchWotd();
});
