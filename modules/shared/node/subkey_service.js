// BLAKE2b Sub-Key Derivation Service (Node.js)
const sodium = require('libsodium-wrappers-sumo');

const CTX = 'MLINGO_1'; // exactly 8 ASCII bytes
const SUBKEY_IDS = {
  messages: 1,
  notes: 2,
  media: 3,
};

/**
 * Derives a 32-byte sub-key from a 32-byte master conversation key using crypto_kdf_derive_from_key.
 * @param {Buffer|Uint8Array} masterKey - 32 bytes
 * @param {'messages'|'notes'|'media'} context
 * @returns {Promise<Buffer>}
 */
async function deriveSubKey(masterKey, context) {
  await sodium.ready;
  const subkeyId = SUBKEY_IDS[context];
  if (!subkeyId) {
    throw new Error('CRYPTO_006: Unknown subkey context');
  }
  const subKey = sodium.crypto_kdf_derive_from_key(
    32,
    subkeyId,
    CTX,
    masterKey
  );
  return Buffer.from(subKey);
}

module.exports = {
  deriveSubKey,
};
