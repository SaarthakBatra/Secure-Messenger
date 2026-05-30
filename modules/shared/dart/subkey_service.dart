// BLAKE2b Sub-Key Derivation Service (Dart)
import 'dart:typed_data';
import 'dart:convert';
import 'package:sodium_libs/sodium_libs.dart';
import '../../features/security/services/sodium_instance.dart';

enum SubKeyContext { messages, notes, media }

class SubKeyService {
  static const String _contextString = 'MLINGO_1'; // exactly 8 ASCII bytes

  static const Map<SubKeyContext, int> _subKeyIds = {
    SubKeyContext.messages: 1,
    SubKeyContext.notes: 2,
    SubKeyContext.media: 3,
  };

  static Uint8List deriveSubKey({
    required Uint8List masterKey,
    required SubKeyContext context,
  }) {
    final int? subkeyId = _subKeyIds[context];
    if (subkeyId == null) {
      throw ArgumentError('CRYPTO_006: Unknown subkey context');
    }
    
    final derived = SodiumInstance.sodium.crypto.kdf.deriveFromKey(
      masterKey: SecureKey.fromList(SodiumInstance.sodium, masterKey),
      context: _contextString,
      subkeyId: BigInt.from(subkeyId),
      subkeyLen: 32,
    );
    return derived.extractBytes();
  }
}
