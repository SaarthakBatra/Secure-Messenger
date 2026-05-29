// Standardized Cryptographic Error Constants for MultiLingo (Node.js)

module.exports = {
  /// Decryption authentication tag mismatch (CRYPTO_001)
  ERR_DECRYPT_TAG_MISMATCH: 'CRYPTO_001',

  /// First incorrect key decryption attempt (CRYPTO_002)
  ERR_WRONG_KEY_ATTEMPT_1: 'CRYPTO_002',

  /// Second incorrect key decryption attempt (CRYPTO_003)
  ERR_WRONG_KEY_ATTEMPT_2: 'CRYPTO_003',

  /// Third consecutive incorrect attempt, triggering local client purge (CRYPTO_004)
  ERR_WRONG_KEY_WIPE: 'CRYPTO_004',

  /// Salt or parameter configuration mismatch during raw KDF re-derivation (CRYPTO_005)
  ERR_KDF_PARAM_MISMATCH: 'CRYPTO_005',

  /// BLAKE2b sub-key expansion requested with an unknown derivation context ID (CRYPTO_006)
  ERR_SUBKEY_ID_UNKNOWN: 'CRYPTO_006',

  /// Wire payload base64url decoded length is less than the required 12-byte nonce (CRYPTO_007)
  ERR_NONCE_LENGTH_INVALID: 'CRYPTO_007',

  /// Wire payload base64url decoding failed or is structurally truncated (CRYPTO_008)
  ERR_BLOB_MALFORMED: 'CRYPTO_008',
};
