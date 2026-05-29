// Argon2id KDF Service (Node.js)
const sodium = require('libsodium-wrappers-sumo');

/**
 * Hashes a PIN for database storage using Argon2id (crypto_pwhash_str).
 * Returns a self-contained string including salt and parameters.
 * @param {string} pin
 * @returns {Promise<string>}
 */
async function hashPin(pin) {
  await sodium.ready;
  return sodium.crypto_pwhash_str(
    pin,
    sodium.crypto_pwhash_OPSLIMIT_INTERACTIVE,
    sodium.crypto_pwhash_MEMLIMIT_INTERACTIVE
  );
}

/**
 * Verifies a PIN against a database-stored Argon2id hash.
 * @param {string} pin
 * @param {string} storedHash
 * @returns {Promise<boolean>}
 */
async function verifyPin(pin, storedHash) {
  await sodium.ready;
  try {
    return sodium.crypto_pwhash_str_verify(storedHash, pin);
  } catch (error) {
    return false;
  }
}

/**
 * Derives a raw 32-byte key from a PIN and a 16-byte salt using crypto_pwhash.
 * @param {string} pin
 * @param {Buffer|Uint8Array} salt - 16 bytes
 * @returns {Promise<Buffer>}
 */
async function deriveRawKey(pin, salt) {
  await sodium.ready;
  const key = sodium.crypto_pwhash(
    32,
    pin,
    salt,
    sodium.crypto_pwhash_OPSLIMIT_INTERACTIVE,
    sodium.crypto_pwhash_MEMLIMIT_INTERACTIVE,
    sodium.crypto_pwhash_ALG_ARGON2ID13
  );
  return Buffer.from(key);
}

module.exports = {
  hashPin,
  verifyPin,
  deriveRawKey,
};
