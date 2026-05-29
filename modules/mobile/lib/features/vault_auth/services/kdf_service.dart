import 'dart:typed_data';
import 'package:flutter_sodium/flutter_sodium.dart';

abstract class KdfServiceInterface {
  Future<Uint8List> deriveVaultKey({required String pin, required Uint8List salt});
  Uint8List generateSalt();
  Uint8List hashKey(Uint8List key);
}

class KdfService implements KdfServiceInterface {
  @override
  Future<Uint8List> deriveVaultKey({required String pin, required Uint8List salt}) async {
    final passwd = Uint8List.fromList(pin.codeUnits);
    return Sodium.cryptoPwhash(
      32,
      passwd,
      salt,
      3,
      67108864,
      Sodium.cryptoPwhashAlgArgon2id13,
    );
  }

  @override
  Uint8List generateSalt() {
    return Sodium.randombytesBuf(16);
  }

  @override
  Uint8List hashKey(Uint8List key) {
    return Sodium.cryptoGenerichash(32, key, null);
  }
}
