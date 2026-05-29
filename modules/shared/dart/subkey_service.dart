// BLAKE2b Sub-Key Derivation Service (Dart)
import 'dart:typed_data';
import 'package:flutter_sodium/flutter_sodium.dart';

enum SubKeyContext { messages, notes, media }

class SubKeyService {
  static const String _contextString = 'MLINGO_1'; // exactly 8 ASCII bytes

  static const Map<SubKeyContext, int> _subKeyIds = {
    SubKeyContext.messages: 1,
    SubKeyContext.notes: 2,
    SubKeyContext.media: 3,
  };

  /// Derives a 32-byte sub-key from a master key using BLAKE2b-based `crypto_kdf_derive_from_key`.
  static Uint8List deriveSubKey({
    required Uint8List masterKey,
    required SubKeyContext context,
  }) {
    final int? subkeyId = _subKeyIds[context];
    if (subkeyId == null) {
      throw ArgumentError('CRYPTO_006: Unknown subkey context');
    }
    return Sodium.cryptoKdfDeriveFromKey(
      32,
      subkeyId,
      Uint8List.fromList(_contextString.codeUnits),
      masterKey,
    );
  }
}
