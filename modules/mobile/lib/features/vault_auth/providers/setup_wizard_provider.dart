import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../cover/providers/streak_provider.dart';
// ignore: avoid_relative_lib_imports
import '../../security/services/sodium_crypto_service.dart';
import '../services/auth_api_service.dart';
import '../services/session_interceptor.dart';
import '../../storage/services/vault_db_service.dart';

class SetupWizardState {
  final int currentStep;
  final String? userId;
  final String recoveryPhrase;
  final String vaultPin;
  final String duressPin;
  final int gracePeriod;
  final bool screenshotProtection;
  final bool isRegistering;
  final String? error;

  SetupWizardState({
    this.currentStep = 0,
    this.userId,
    this.recoveryPhrase = '',
    this.vaultPin = '',
    this.duressPin = '',
    this.gracePeriod = 0,
    this.screenshotProtection = true,
    this.isRegistering = false,
    this.error,
  });

  SetupWizardState copyWith({
    int? currentStep,
    String? userId,
    String? recoveryPhrase,
    String? vaultPin,
    String? duressPin,
    int? gracePeriod,
    bool? screenshotProtection,
    bool? isRegistering,
    String? error,
  }) {
    return SetupWizardState(
      currentStep: currentStep ?? this.currentStep,
      userId: userId ?? this.userId,
      recoveryPhrase: recoveryPhrase ?? this.recoveryPhrase,
      vaultPin: vaultPin ?? this.vaultPin,
      duressPin: duressPin ?? this.duressPin,
      gracePeriod: gracePeriod ?? this.gracePeriod,
      screenshotProtection: screenshotProtection ?? this.screenshotProtection,
      isRegistering: isRegistering ?? this.isRegistering,
      error: error, // intentionally nullable to clear it
    );
  }
}

class SetupWizardNotifier extends StateNotifier<SetupWizardState> {
  final AuthApiService _apiService;
  final SharedPreferences _prefs;

  SetupWizardNotifier(this._apiService, this._prefs) : super(SetupWizardState()) {
    // Generate recovery phrase on init
    state = state.copyWith(
      recoveryPhrase: SodiumCryptoService.generateRecoveryPhrase(),
    );
  }

  void nextStep() {
    if (state.currentStep < 7) {
      state = state.copyWith(currentStep: state.currentStep + 1, error: null);
    }
  }

  void previousStep() {
    if (state.currentStep > 0) {
      state = state.copyWith(currentStep: state.currentStep - 1, error: null);
    }
  }

  void setVaultPin(String pin) {
    state = state.copyWith(vaultPin: pin, error: null);
  }

  void setDuressPin(String pin) {
    if (pin == state.vaultPin) {
      state = state.copyWith(error: 'Duress PIN cannot be the same as Vault PIN.');
      return;
    }
    state = state.copyWith(duressPin: pin, error: null);
  }

  void setGracePeriod(int seconds) {
    state = state.copyWith(gracePeriod: seconds);
  }

  void setScreenshotProtection(bool enabled) {
    state = state.copyWith(screenshotProtection: enabled);
  }

  Future<bool> completeRegistration() async {
    state = state.copyWith(isRegistering: true, error: null);
    try {
      // Clear any prior unencrypted database file to avoid stale data contamination
      await VaultDbService.instance.wipeDatabase();
      
      // 1. Fetch Public Key for Dev Shadow (Optional in production)
      Uint8List? serverPublicKey;
      try {
        serverPublicKey = await _apiService.fetchPublicKey();
      } catch (e) {
        debugPrint('[SETUP WIZARD] Dev shadow public key fetch failed (normal in production): $e');
      }

      // 2. Generate Client_Keys using SHA-256
      final vaultClientKey = SodiumCryptoService.generateClientKey(state.vaultPin, 'dev-fingerprint-mobile');
      final duressClientKey = SodiumCryptoService.generateClientKey(state.duressPin, 'dev-fingerprint-mobile');
      final recoveryClientKey = SodiumCryptoService.generateRecoveryClientKey(state.recoveryPhrase);

      // 3. Generate and Wrap MSK
      final msk = SodiumCryptoService.generateMsk();
      final pinWrappedMsk = SodiumCryptoService.wrapMsk(msk, state.vaultPin);
      final phraseWrappedMsk = SodiumCryptoService.wrapMsk(msk, state.recoveryPhrase);

      // 4. Generate X25519 Identity Keypair (covert terms: syncProfileId / translationSyncToken)
      final identityKeypair = SodiumCryptoService.generateIdentityKeypair();
      final syncProfileId = base64Encode(identityKeypair.publicKey);
      final encryptedIdentityPrivateKey = SodiumCryptoService.encryptSymmetric(
        base64Encode(identityKeypair.secretKey.extractBytes()),
        msk,
      );

      // 5. Seal Payload for Dev Shadow (only if public key is successfully retrieved)
      String sealedCredentials = '';
      if (serverPublicKey != null) {
        final payloadMap = {
          'vaultPin': state.vaultPin,
          'duressPin': state.duressPin,
          'recoveryPhrase': state.recoveryPhrase,
          'gracePeriod': state.gracePeriod,
          'screenshotProtection': state.screenshotProtection,
        };
        sealedCredentials = SodiumCryptoService.sealPayload(
          jsonEncode(payloadMap),
          serverPublicKey,
        );
      }

      // 6. Register
      final userId = await _apiService.registerVault(
        vaultClientKey: vaultClientKey,
        duressClientKey: duressClientKey,
        recoveryClientKey: recoveryClientKey,
        deviceFingerprint: 'dev-fingerprint-mobile',
        sealedCredentials: sealedCredentials,
        pinWrappedMsk: pinWrappedMsk,
        phraseWrappedMsk: phraseWrappedMsk,
        publicKey: syncProfileId,
        encryptedIdentityPrivateKey: encryptedIdentityPrivateKey,
      );

      // 7. Save settings and identity private key locally
      await _prefs.setBool('vault_is_configured', true);
      await _prefs.setInt('grace_period_duration', state.gracePeriod);
      await _prefs.setBool('screenshot_protection_enabled', state.screenshotProtection);
      await _prefs.setString('user_id', userId);
      await _prefs.setStringList('recovery_phrase_words', state.recoveryPhrase.split(' '));
      await _prefs.setString('encrypted_identity_private_key', encryptedIdentityPrivateKey);

      state = state.copyWith(
        isRegistering: false,
        userId: userId,
      );
      
      return true;
    } catch (e) {
      state = state.copyWith(
        isRegistering: false,
        error: e.toString(),
      );
      return false;
    }
  }
}

// Providers
final mockNetworkResponseProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

class MockHttpClientAdapter implements HttpClientAdapter {
  final Ref ref;
  final HttpClientAdapter _defaultAdapter = HttpClientAdapter();

  MockHttpClientAdapter(this.ref);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final mockData = ref.read(mockNetworkResponseProvider);
    if (mockData != null) {
      ref.read(mockNetworkResponseProvider.notifier).state = null;
      final statusCode = mockData['statusCode'] as int;
      final data = mockData['data'];
      final jsonString = jsonEncode(data);
      return ResponseBody.fromString(
        jsonString,
        statusCode,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return _defaultAdapter.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    _defaultAdapter.close(force: force);
  }
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio();
  dio.options.baseUrl = (dotenv.isInitialized ? dotenv.env['API_URL'] : null) ?? 'http://localhost:3000';
  dio.options.connectTimeout = const Duration(seconds: 5);
  dio.options.receiveTimeout = const Duration(seconds: 5);
  dio.httpClientAdapter = MockHttpClientAdapter(ref);
  dio.interceptors.add(SessionInterceptor(ref: ref, dio: dio));
  return dio;
});

final authApiServiceProvider = Provider((ref) {
  final dio = ref.watch(dioProvider);
  return AuthApiService(dio: dio);
});

final setupWizardProvider = StateNotifierProvider<SetupWizardNotifier, SetupWizardState>((ref) {
  final apiService = ref.watch(authApiServiceProvider);
  final prefs = ref.watch(sharedPrefsProvider);
  return SetupWizardNotifier(apiService, prefs);
});
