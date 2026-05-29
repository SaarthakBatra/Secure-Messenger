import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'dart:convert';

import '../../../modules/mobile/lib/features/cover/services/translation_sync_service.dart';
import '../../../modules/mobile/lib/features/cover/services/wotd_sync_service.dart';
import 'services_test.dart'; // Reuse MockAssetBundle and MockAdapter

void main() {
  test('Interactive Cover Utilities Run', () async {
    // Print clear outputs directly so the user can see real values.
    print('\n===============================================================');
    print('          MULTILINGO COVER UTILITY DIRECT RUNNER (SIMULATION)');
    print('===============================================================\n');

    final mockBundle = MockAssetBundle({
      'assets/dictionary.json': jsonEncode({
        'apple': 'manzana',
        'hello': 'hola',
        'dog': 'perro',
        'cat': 'gato',
      }),
      'assets/words.json': jsonEncode([
        {
          'word': 'freedom',
          'translation': 'libertad',
          'definition': 'The power or right to act, speak, or think as one wants.'
        },
        {
          'word': 'peace',
          'translation': 'paz',
          'definition': 'Freedom from disturbance; tranquility.'
        }
      ]),
    });

    // -------------------------------------------------------------
    // Utility 1: Live Translation (Online API Simulation)
    // -------------------------------------------------------------
    final onlineDio = Dio();
    onlineDio.httpClientAdapter = MockAdapter((options) async {
      final responsePayload = {
        'responseData': {
          'translatedText': 'Hola (Translated via MyMemory Online API)',
          'match': 1,
        },
        'responseStatus': 200,
      };
      return ResponseBody.fromString(
        jsonEncode(responsePayload),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final translatorOnline = TranslationSyncService(dio: onlineDio, assetBundle: mockBundle);
    
    print('[UTILITY 1] Translating "hello" (English -> Spanish) via Online API...');
    try {
      final result = await translatorOnline.translate('hello', from: 'en', to: 'es');
      print('  -> Input: "hello"');
      print('  -> Result: "$result"');
    } catch (e) {
      print('  -> Online API Error: $e');
    }

    // -------------------------------------------------------------
    // Utility 2: Live Translation (Offline Fallback - Exact Match)
    // -------------------------------------------------------------
    final offlineDio = Dio();
    offlineDio.httpClientAdapter = MockAdapter((options) async {
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
    });
    final translatorOffline = TranslationSyncService(dio: offlineDio, assetBundle: mockBundle);
    
    print('\n[UTILITY 2] Translating "dog" (English -> Spanish) with simulated Offline state...');
    try {
      final result = await translatorOffline.translate('dog', from: 'en', to: 'es');
      print('  -> Input: "dog"');
      print('  -> Result (Exact local match): "$result"');
    } catch (e) {
      print('  -> Offline Translation Error: $e');
    }

    // -------------------------------------------------------------
    // Utility 3: Live Translation (Offline Fallback - Substring Match)
    // -------------------------------------------------------------
    print('\n[UTILITY 3] Translating partial "dogs" (English -> Spanish) with simulated Offline state...');
    try {
      final result = await translatorOffline.translate('dogs', from: 'en', to: 'es');
      print('  -> Input: "dogs"');
      print('  -> Result (Substring local match): "$result"');
    } catch (e) {
      print('  -> Offline Translation Error: $e');
    }

    // -------------------------------------------------------------
    // Utility 4: Word of the Day (WOTD) Fetching (Online API Simulation)
    // -------------------------------------------------------------
    final onlineWotdDio = Dio();
    onlineWotdDio.httpClientAdapter = MockAdapter((options) async {
      final responsePayload = {
        'word': 'cherry',
        'translation': 'cereza',
        'definition': 'A small round red fruit.',
      };
      return ResponseBody.fromString(
        jsonEncode(responsePayload),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final wotdOnlineService = WotdSyncService(dio: onlineWotdDio, assetBundle: mockBundle);
    print('\n[UTILITY 4] Fetching Word of the Day (Online Decoy Server Simulation)...');
    try {
      final wotd = await wotdOnlineService.fetchWotd();
      print('  -> Daily Word: "${wotd.word}"');
      print('  -> Daily Translation: "${wotd.translation}"');
      print('  -> Daily Definition: "${wotd.definition}"');
    } catch (e) {
      print('  -> WOTD Online Error: $e');
    }

    // -------------------------------------------------------------
    // Utility 5: Word of the Day (WOTD) Fetching (Offline chronological list)
    // -------------------------------------------------------------
    final wotdOfflineService = WotdSyncService(dio: offlineDio, assetBundle: mockBundle);
    print('\n[UTILITY 5] Fetching Word of the Day (Simulated Offline state)...');
    try {
      final wotd = await wotdOfflineService.fetchWotd();
      print('  -> Daily Word: "${wotd.word}"');
      print('  -> Daily Translation: "${wotd.translation}"');
      print('  -> Daily Definition: "${wotd.definition}"');
    } catch (e) {
      print('  -> WOTD Offline Error: $e');
    }

    print('\n===============================================================');
  });
}
