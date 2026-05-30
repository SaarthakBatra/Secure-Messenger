import 'dart:typed_data';
import 'package:sodium_libs/sodium_libs.dart';
import '../../security/services/sodium_instance.dart';

abstract class KdfServiceInterface {
  Future<Uint8List> deriveVaultKey({required String pin, required Uint8List salt});
  Uint8List generateSalt();
  Uint8List hashKey(Uint8List key);
}

class KdfService implements KdfServiceInterface {
  @override
  Future<Uint8List> deriveVaultKey({required String pin, required Uint8List salt}) async {
    final passwd = Uint8List.fromList(pin.codeUnits);
    
    final derived = SodiumInstance.sodium.crypto.pwhash.call(
      outLen: 32,
      password: passwd,
      salt: salt,
      opsLimit: 3,
      memLimit: 67108864,
      algo: CryptoPwhashAlgorithm.argon2id13,
    );
    
    // SecureKey.extractBytes removes the underlying memory protection to give us the Uint8List
    return derived.extractBytes();
  }

  @override
  Uint8List generateSalt() {
    return SodiumInstance.sodium.randombytes.buf(
      SodiumInstance.sodium.crypto.pwhash.saltBytes,
    );
  }

  @override
  Uint8List hashKey(Uint8List key) {
    return SodiumInstance.sodium.crypto.genericHash.call(
      message: key,
      outLen: 32,
    );
  }
}
