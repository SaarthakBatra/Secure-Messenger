import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import '../../../modules/mobile/lib/features/cover/services/translation_sync_service.dart';
import '../../../modules/mobile/lib/features/cover/services/wotd_sync_service.dart';

// Custom Mock AssetBundle to avoid file system reads during unit tests
class MockAssetBundle extends AssetBundle {
  final Map<String, String> assets;

  MockAssetBundle(this.assets);

  @override
  Future<ByteData> load(String key) async {
    final list = utf8.encode(assets[key] ?? '');
    return ByteData.sublistView(Uint8List.fromList(list));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (assets.containsKey(key)) {
      return assets[key]!;
    }
    throw Exception('Asset not found: $key');
  }
}

// Custom Dio Adapter to mock HTTP calls reliably
class MockAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  MockAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('TranslationSyncService Tests', () {
    late MockAssetBundle mockBundle;
    late Map<String, String> dictionaryData;

    setUp(() {
      dictionaryData = {
        'apple': 'manzana',
        'hello': 'hola',
        'world': 'mundo',
        'dog': 'perro',
      };
      mockBundle = MockAssetBundle({
        'assets/dictionary.json': jsonEncode(dictionaryData),
      });
    });

    test('Normal Flow: Online Translation API returns 200 OK', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockAdapter((options) async {
        final responsePayload = {
          'responseData': {
            'translatedText': 'Hola',
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

      final service = TranslationSyncService(dio: dio, assetBundle: mockBundle);
      final result = await service.translate('hello', from: 'en', to: 'es');
      expect(result, equals('Hola'));
    });

    test('Edge Case: Offline/Timeout triggers exact match fallback', () async {
      final dio = Dio();
      // Force dio to fail immediately to simulate offline state
      dio.httpClientAdapter = MockAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      });

      final service = TranslationSyncService(dio: dio, assetBundle: mockBundle);
      final result = await service.translate('dog', from: 'en', to: 'es');
      expect(result, equals('perro'));
    });

    test('Edge Case: Offline/Timeout triggers substring match fallback (case-insensitive)', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });

      final service = TranslationSyncService(dio: dio, assetBundle: mockBundle);
      
      // Match query containing key
      final result1 = await service.translate('dOgS', from: 'en', to: 'es');
      expect(result1, equals('perro'));

      // Match key containing query
      final result2 = await service.translate('ApP', from: 'en', to: 'es');
      expect(result2, equals('manzana'));
    });

    test('Edge Case: Offline/Timeout with missing/malformed local asset returns query string', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockAdapter((options) async {
        throw DioException(requestOptions: options);
      });

      final badBundle = MockAssetBundle({
        'assets/dictionary.json': '{ invalid json }',
      });

      final service = TranslationSyncService(dio: dio, assetBundle: badBundle);
      final result = await service.translate('something', from: 'en', to: 'es');
      expect(result, equals('something'));
    });
  });

  group('WotdSyncService Tests', () {
    late MockAssetBundle mockBundle;
    late List<Map<String, String>> wordsData;

    setUp(() {
      wordsData = [
        {
          'word': 'apple',
          'translation': 'manzana',
          'definition': 'A round fruit.',
        },
        {
          'word': 'banana',
          'translation': 'plátano',
          'definition': 'A yellow curved fruit.',
        }
      ];
      mockBundle = MockAssetBundle({
        'assets/words.json': jsonEncode(wordsData),
      });
    });

    test('Normal Flow: Online Decoy API returns 200 OK word', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockAdapter((options) async {
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

      final service = WotdSyncService(dio: dio, assetBundle: mockBundle);
      final wotd = await service.fetchWotd();
      expect(wotd.word, equals('cherry'));
      expect(wotd.translation, equals('cereza'));
      expect(wotd.definition, equals('A small round red fruit.'));
    });

    test('Edge Case: Offline fallback returns chronological word from words.json', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockAdapter((options) async {
        throw DioException(requestOptions: options);
      });

      final service = WotdSyncService(dio: dio, assetBundle: mockBundle);
      final wotd = await service.fetchWotd();
      
      // Calculate expected chronological index
      final daysSinceEpoch = DateTime.now().millisecondsSinceEpoch ~/ 86400000;
      final expectedIndex = daysSinceEpoch % wordsData.length;
      final expectedWord = wordsData[expectedIndex];

      expect(wotd.word, equals(expectedWord['word']));
      expect(wotd.translation, equals(expectedWord['translation']));
      expect(wotd.definition, equals(expectedWord['definition']));
    });

    test('Edge Case: Offline fallback with missing/malformed local asset returns default safety word', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockAdapter((options) async {
        throw DioException(requestOptions: options);
      });

      final badBundle = MockAssetBundle({
        'assets/words.json': 'not a list',
      });

      final service = WotdSyncService(dio: dio, assetBundle: badBundle);
      final wotd = await service.fetchWotd();
      
      // Should fall back to hardcoded safety word 'welcome'
      expect(wotd.word, equals('welcome'));
      expect(wotd.translation, equals('bienvenido'));
      expect(wotd.definition, isNotEmpty);
    });
  });
}
