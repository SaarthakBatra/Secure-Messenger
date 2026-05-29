// BIP-39 Mnemonic Service (Node.js)
const crypto = require('crypto');

/**
 * Hashes a BIP-39 mnemonic string using PBKDF2-HMAC-SHA256 (600,000 iterations) with a 16-byte salt.
 * @param {string} mnemonic - Space-separated words
 * @param {string|Buffer} salt - 16-byte salt (if hex string, gets converted to Buffer)
 * @returns {Promise<Buffer>} 32-byte derived key buffer
 */
async function deriveMnemonicHash(mnemonic, salt) {
  const saltBuffer = typeof salt === 'string' ? Buffer.from(salt, 'hex') : salt;
  return new Promise((resolve, reject) => {
    // 600,000 iterations of SHA-256 to compute a 32-byte (256-bit) hash
    crypto.pbkdf2(mnemonic.trim(), saltBuffer, 600000, 32, 'sha256', (err, derivedKey) => {
      if (err) reject(err);
      else resolve(derivedKey);
    });
  });
}

/**
 * Performs a timing-safe verification of a recovery mnemonic against the stored PBKDF2 hash.
 * @param {string} mnemonic
 * @param {string} saltHex
 * @param {string} storedHashHex
 * @returns {Promise<boolean>}
 */
async function verifyMnemonic(mnemonic, saltHex, storedHashHex) {
  try {
    const derived = await deriveMnemonicHash(mnemonic, saltHex);
    const stored = Buffer.from(storedHashHex, 'hex');

    if (derived.length !== stored.length) {
      return false;
    }

    // crypto.timingSafeEqual prevents timing oracle attacks
    return crypto.timingSafeEqual(derived, stored);
  } catch (error) {
    return false;
  }
}

module.exports = {
  deriveMnemonicHash,
  verifyMnemonic,
};
