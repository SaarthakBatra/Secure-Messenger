// Mobile Cryptographic Integration & Parity Test Suite (Dart)
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sodium/flutter_sodium.dart';
import '../../modules/shared/dart/kdf_service.dart';
import '../../modules/shared/dart/subkey_service.dart';
import '../../modules/shared/dart/cipher_service.dart';
import '../../modules/shared/dart/mnemonic_service.dart';
import '../../modules/shared/dart/bip39_wordlist.dart';

void main() {
  // Always initialize Sodium FFI before executing FFI cryptos
  setUpAll(() async {
    await Sodium.init();
  });

  group('Cryptographic Parity & Core Utilities - Mobile Suite', () {
    // T.3 Argon2id KDF Checks
    group('Argon2id KDF Service', () {
      test('should derive raw keys deterministically from PIN and salt', () async {
        const pin = '123456';
        final salt = Uint8List(16)..fillRange(0, 16, 0x09);
        
        final key1 = await KdfService.deriveVaultKey(pin: pin, salt: salt);
        final key2 = await KdfService.deriveVaultKey(pin: pin, salt: salt);
        
        expect(key1.length, equals(32));
        expect(key1, equals(key2));

        final differentSalt = Uint8List(16)..fillRange(0, 16, 0x0a);
        final key3 = await KdfService.deriveVaultKey(pin: pin, salt: differentSalt);
        expect(key1, isNot(equals(key3)));
      });

      test('should generate cryptographically random 16-byte salts', () {
        final salt1 = KdfService.generateSalt();
        final salt2 = KdfService.generateSalt();
        
        expect(salt1.length, equals(16));
        expect(salt2.length, equals(16));
        expect(salt1, isNot(equals(salt2)));
      });
    });

    // T.4 BLAKE2b KDF Sub-Key derivation checks
    group('BLAKE2b Sub-Key Derivation', () {
      test('should derive correct sub-keys deterministically', () {
        final masterKey = Uint8List(32)..fillRange(0, 32, 0x42);
        
        final messageKey = SubKeyService.deriveSubKey(masterKey: masterKey, context: SubKeyContext.messages);
        final notesKey = SubKeyService.deriveSubKey(masterKey: masterKey, context: SubKeyContext.notes);
        final mediaKey = SubKeyService.deriveSubKey(masterKey: masterKey, context: SubKeyContext.media);

        expect(messageKey.length, equals(32));
        expect(notesKey.length, equals(32));
        expect(mediaKey.length, equals(32));

        expect(messageKey, isNot(equals(notesKey)));
        expect(messageKey, isNot(equals(mediaKey)));

        final messageKey2 = SubKeyService.deriveSubKey(masterKey: masterKey, context: SubKeyContext.messages);
        expect(messageKey, equals(messageKey2));
      });
    });

    // T.5 ChaCha20-Poly1305 Cipher Checks
    group('ChaCha20-Poly1305 AEAD Cipher', () {
      late Uint8List key;
      setUp(() {
        key = Uint8List(32)..fillRange(0, 32, 0x55);
      });

      test('should encrypt and decrypt plaintext under correct conditions', () {
        const plaintext = 'Covert Operation MultiLingo';
        const convId = 'room123';
        const msgId = 'msg456';

        final blob = CipherService.encrypt(key: key, plaintext: plaintext, conversationId: convId, entityId: msgId);
        expect(blob, isNotEmpty);
        
        final decrypted = CipherService.decrypt(key: key, blob: blob, conversationId: convId, entityId: msgId);
        expect(decrypted, equals(plaintext));
      });

      test('should return null when decryption tag verification fails (E11 / CRYPTO_001)', () {
        const plaintext = 'Covert Operation MultiLingo';
        const convId = 'room123';
        const msgId = 'msg456';

        final blob = CipherService.encrypt(key: key, plaintext: plaintext, conversationId: convId, entityId: msgId);
        
        final badKey = Uint8List(32)..fillRange(0, 32, 0x66);
        final decryptedBadKey = CipherService.decrypt(key: badKey, blob: blob, conversationId: convId, entityId: msgId);
        expect(decryptedBadKey, isNull);
      });

      test('should enforce strict alphanumeric assertions and throw on encrypt', () {
        const plaintext = 'Secret';
        const badConvId = 'room:123';
        const msgId = 'msg456';

        expect(
          () => CipherService.encrypt(key: key, plaintext: plaintext, conversationId: badConvId, entityId: msgId),
          throwsArgumentError,
        );

        final decryptedBad = CipherService.decrypt(key: key, blob: 'valid_blob', conversationId: badConvId, entityId: msgId);
        expect(decryptedBad, isNull);
      });

      test('should return null for malformed/truncated blobs', () {
        const shortBlob = 'A4g93k==';
        final decrypted = CipherService.decrypt(key: key, blob: shortBlob, conversationId: 'room123', entityId: 'msg456');
        expect(decrypted, isNull);
      });
    });

    // T.6 BIP-39 Recovery Management Checks
    group('BIP-39 Mnemonic Service', () {
      test('should generate valid 12-word BIP-39 recovery phrases', () {
        final phrase = MnemonicService.generateMnemonic();
        final words = phrase.split(' ');
        
        expect(words.length, equals(12));
        for (final word in words) {
          expect(bip39Wordlist.contains(word), isTrue);
        }
      });

      test('should generate unique sorted confirmation indices', () {
        final indices = MnemonicService.generateConfirmationIndices();
        expect(indices.length, equals(3));
        
        // Ensure sorted
        expect(indices[0] < indices[1], isTrue);
        expect(indices[1] < indices[2], isTrue);
        
        // Range check
        for (final idx in indices) {
          expect(idx >= 0 && idx <= 11, isTrue);
        }
      });
    });
  });
}
