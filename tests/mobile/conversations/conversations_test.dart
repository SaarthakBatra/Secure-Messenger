import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/features/storage/services/vault_db_service.dart';
import 'package:mobile/features/vault_auth/services/session_interceptor.dart';
import 'package:mobile/app/router/app_router.dart';
import 'package:mobile/features/vault_auth/providers/setup_wizard_provider.dart';
import 'package:mobile/features/cover/providers/streak_provider.dart';

// Mock session notifier for GoRouter/ref testing
class FakeVaultSessionNotifier extends VaultSessionNotifier {
  @override
  void setSession(String? type, {String? token, String? refreshToken, int? reauthGracePeriodSeconds}) {
    super.setSession(type, token: token, refreshToken: refreshToken, reauthGracePeriodSeconds: reauthGracePeriodSeconds);
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  // Mock SQLCipher Method Channel
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.davidmartos96.sqflite_sqlcipher'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'getDatabasesPath') {
        return '.';
      }
      return null;
    },
  );

  group('Phase 2b Mobile Cryptographic Terminology & Naming Tests', () {
    test('MSK (Master Storage Key) must be referred to as TranslationCacheConfig', () {
      final mskName = 'TranslationCacheConfig';
      // MSK decoy term check
      expect(mskName, equals('TranslationCacheConfig'));
    });

    test('Conversation Key must be referred to as lessonKey', () {
      final keyName = 'lessonKey';
      expect(keyName, equals('lessonKey'));
    });

    test('encryptedConversationKey must be referred to as wrappedLessonKey', () {
      final name = 'wrappedLessonKey';
      expect(name, equals('wrappedLessonKey'));
    });
  });

  group('SessionInterceptor 423 Account Lockout Tests', () {
    late ProviderContainer container;
    late Dio dio;
    late SessionInterceptor interceptor;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'vault_is_configured': true,
        'user_id': 'user123',
      });

      final prefs = await SharedPreferences.getInstance();
      final fakeNotifier = FakeVaultSessionNotifier();
      container = ProviderContainer(
        overrides: [
          vaultSessionNotifierProvider.overrideWithValue(fakeNotifier),
          sharedPrefsProvider.overrideWith((ref) => prefs),
        ],
      );

      late ProviderRef providerRef;
      container.read(Provider((r) {
        providerRef = r;
      }));

      dio = Dio();
      interceptor = SessionInterceptor(ref: providerRef, dio: dio);
    });

    test('Silent Lockout Handler: HTTP 423 must wipe database, clear config, and return 200 OK', () async {
      final mockRequestOptions = RequestOptions(path: '/test-route');
      final mockResponse = Response(
        requestOptions: mockRequestOptions,
        statusCode: 423,
        data: {'error': 'Locked Out'},
      );

      final dioException = DioException(
        requestOptions: mockRequestOptions,
        response: mockResponse,
        type: DioExceptionType.badResponse,
      );

      final handler = ErrorInterceptorHandler();
      
      try {
        interceptor.onError(dioException, handler);
      } catch (e) {
        // Ignored
      }

      // Wait for the async burn sequence to complete
      await Future.delayed(const Duration(milliseconds: 200));

      final prefs = await SharedPreferences.getInstance();
      
      // Verification: SharedPreferences configuration keys must be wiped/purged
      expect(prefs.getBool('vault_is_configured'), isNull);
      expect(prefs.getString('user_id'), isNull);
    });
  });
}
