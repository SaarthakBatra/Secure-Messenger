// ChaCha20-Poly1305-IETF Cipher Integration Service (Node.js)
const sodium = require('libsodium-wrappers-sumo');

const idRegex = /^[a-zA-Z0-9]+$/;

/**
 * Encrypts plaintext using ChaCha20-Poly1305-IETF.
 * AAD: "${conversationId}:${entityId}".
 * Layout: Base64url(nonce[12] || ciphertext || tag[16]).
 * @param {Buffer|Uint8Array} key - 32 bytes
 * @param {string} plaintext
 * @param {string} conversationId
 * @param {string} entityId
 * @returns {Promise<string>} Base64url-encoded wire blob
 */
async function encrypt(key, plaintext, conversationId, entityId) {
  await sodium.ready;
  
  // Assert strict alphanumeric IDs to prevent delimiter injection attacks
  if (!idRegex.test(conversationId) || !idRegex.test(entityId)) {
    throw new Error('CRYPTO_008: Non-alphanumeric conversationId or entityId');
  }

  const aad = `${conversationId}:${entityId}`;
  const nonce = sodium.randombytes_buf(sodium.crypto_aead_chacha20poly1305_ietf_NPUBBYTES);
  
  const ct = sodium.crypto_aead_chacha20poly1305_ietf_encrypt(
    plaintext,
    aad,
    null,
    nonce,
    key
  );

  const blob = Buffer.concat([Buffer.from(nonce), Buffer.from(ct)]);
  return blob.toString('base64url');
}

/**
 * Decrypts and authenticates a Base64url wire blob. Returns null on validation or integrity failure.
 * @param {Buffer|Uint8Array} key - 32 bytes
 * @param {string} blob - Base64url-encoded
 * @param {string} conversationId
 * @param {string} entityId
 * @returns {Promise<string|null>}
 */
async function decrypt(key, blob, conversationId, entityId) {
  await sodium.ready;

  // Assert strict alphanumeric IDs
  if (!idRegex.test(conversationId) || !idRegex.test(entityId)) {
    return null;
  }

  try {
    const bytes = Buffer.from(blob, 'base64url');
    
    // Minimum length must be 28 bytes (12-byte nonce + 16-byte minimum auth tag/ciphertext)
    if (bytes.length < 28) {
      return null;
    }

    const nonce = bytes.subarray(0, 12);
    const ct = bytes.subarray(12);
    const aad = `${conversationId}:${entityId}`;

    const pt = sodium.crypto_aead_chacha20poly1305_ietf_decrypt(
      null,
      ct,
      aad,
      nonce,
      key
    );

    return Buffer.from(pt).toString('utf8');
  } catch (error) {
    return null; // Gracefully return null on decryption/verification failure
  }
}

module.exports = {
  encrypt,
  decrypt,
};
