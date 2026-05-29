// Standardized Cryptographic Error Constants for MultiLingo (Dart)

class CryptoErrorCodes {
  /// Decryption authentication tag mismatch (CRYPTO_001)
  static const String tagMismatch = 'CRYPTO_001';

  /// First incorrect key decryption attempt (CRYPTO_002)
  static const String wrongKeyAttempt1 = 'CRYPTO_002';

  /// Second incorrect key decryption attempt (CRYPTO_003)
  static const String wrongKeyAttempt2 = 'CRYPTO_003';

  /// Third consecutive incorrect attempt, triggering local client purge (CRYPTO_004)
  static const String wrongKeyWipe = 'CRYPTO_004';

  /// Salt or parameter configuration mismatch during raw KDF re-derivation (CRYPTO_005)
  static const String kdfParamMismatch = 'CRYPTO_005';

  /// BLAKE2b sub-key expansion requested with an unknown derivation context ID (CRYPTO_006)
  static const String subKeyIdUnknown = 'CRYPTO_006';

  /// Wire payload base64url decoded length is less than the required 12-byte nonce (CRYPTO_007)
  static const String nonceLengthInvalid = 'CRYPTO_007';

  /// Wire payload base64url decoding failed or is structurally truncated (CRYPTO_008)
  static const String blobMalformed = 'CRYPTO_008';
}
