// Argon2id KDF Service (Dart)
import 'dart:typed_data';
import 'package:flutter_sodium/flutter_sodium.dart';

class KdfService {
  /// Derives a 32-byte vault key using Argon2id.
  /// passwd: PIN converted to byte array.
  /// salt: 16-byte random salt.
  /// opslimit: 3 (interactive)
  /// memlimit: 67108864 (64 MiB interactive)
  /// alg: Argon2id13
  static Future<Uint8List> deriveVaultKey({
    required String pin,
    required Uint8List salt,
  }) async {
    final Uint8List passwd = Uint8List.fromList(pin.codeUnits);
    return Sodium.cryptoPwhash(
      32,
      passwd,
      salt,
      3,
      67108864,
      Sodium.cryptoPwhashAlgArgon2id13,
    );
  }

  /// Generates a cryptographically random 16-byte salt via libsodium.
  static Uint8List generateSalt() {
    return Sodium.randombytesBuf(16);
  }
}
