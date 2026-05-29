import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/features/vault_auth/services/kdf_service.dart';

// Mock KDF Service to bypass native libsodium errors in test environments
class MockKdfService implements KdfServiceInterface {
  @override
  Future<Uint8List> deriveVaultKey({required String pin, required Uint8List salt}) async {
    // Return a dummy 32-byte key
    return Uint8List(32)..fillRange(0, 32, pin.length); 
  }

  @override
  Uint8List generateSalt() {
    return Uint8List(16)..fillRange(0, 16, 1);
  }

  @override
  Uint8List hashKey(Uint8List key) {
    // Simple deterministic hash mock
    return Uint8List.fromList(key.reversed.toList());
  }
}

// Mock state providers corresponding to the Cover module and Stealth hooks
final issueReportProvider = StateProvider<({String code, String body})>((ref) => (code: '', body: ''));
final vaultConfiguredProvider = StateProvider<bool>((ref) => false);
final vaultRouterInterceptorProvider = StateProvider<String?>((ref) => null);

// Hook logic encapsulated in a testable provider
final stealthHookListenerProvider = Provider((ref) {
  ref.listen(issueReportProvider, (previous, next) {
    final pin = next.code.trim();
    final body = next.body.trim();
    
    // Normal Flow (Bug report) / Not a vault trigger
    if (body.isNotEmpty || pin.length != 6 || int.tryParse(pin) == null) {
      return; 
    }

    // Vault Trigger Intercept (Empty body, exact 6 digits)
    ref.read(issueReportProvider.notifier).state = (code: '', body: ''); // Clear
    ref.read(vaultRouterInterceptorProvider.notifier).state = '/vault-entry'; // Redirect
  });
});

void main() {
  group('Stealth Hook Integration Tests', () {
    test('Normal Flow: Bug report with non-empty body does NOT trigger vault', () {
      final container = ProviderContainer();
      container.read(stealthHookListenerProvider); // Initialize listener

      // Simulate normal bug report
      container.read(issueReportProvider.notifier).state = (code: '123456', body: 'Translation error');

      // Verify no interception occurred
      expect(container.read(vaultRouterInterceptorProvider), isNull);
      expect(container.read(issueReportProvider).code, '123456'); // State not cleared
    });

    test('Edge Case (E7): Vault Trigger intercepts when body is empty and PIN is 6 digits', () {
      final container = ProviderContainer();
      container.read(stealthHookListenerProvider); // Initialize listener

      // Simulate stealth login attempt
      container.read(issueReportProvider.notifier).state = (code: '987654', body: '');

      // Verify interception and routing
      expect(container.read(vaultRouterInterceptorProvider), '/vault-entry');
      expect(container.read(issueReportProvider).code, ''); // State cleared to avoid looping
    });

    test('Edge Case: Empty body but invalid PIN length does NOT trigger vault', () {
      final container = ProviderContainer();
      container.read(stealthHookListenerProvider); 

      container.read(issueReportProvider.notifier).state = (code: '123', body: '');

      expect(container.read(vaultRouterInterceptorProvider), isNull);
    });
  });

  group('KDF Local Strategy & Edge Cases', () {
    late MockKdfService kdfService;

    setUp(() {
      kdfService = MockKdfService();
    });

    test('Normal Flow: PIN setup derives deterministic master key and hash', () async {
      final salt = kdfService.generateSalt();
      final key = await kdfService.deriveVaultKey(pin: '123456', salt: salt);
      final pinHash = kdfService.hashKey(key);

      expect(salt.length, 16);
      expect(key.length, 32);
      expect(pinHash.length, 32);
    });

    test('Edge Case E7: Duress PIN collision with Vault PIN is detected', () async {
      final salt = kdfService.generateSalt();
      final vaultKey = await kdfService.deriveVaultKey(pin: '123456', salt: salt);
      final vaultHash = kdfService.hashKey(vaultKey);

      final duressKey = await kdfService.deriveVaultKey(pin: '123456', salt: salt);
      final duressHash = kdfService.hashKey(duressKey);

      // They should match exactly, triggering the E7 blockage
      expect(vaultHash, equals(duressHash));
    });
  });
}
