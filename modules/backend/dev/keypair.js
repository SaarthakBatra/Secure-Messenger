const sodium = require('libsodium-wrappers');
const winston = require('winston');

let keypair = null;

async function initKeypair() {
  await sodium.ready;
  if (!keypair) {
    keypair = sodium.crypto_box_keypair();
    winston.info('Libsodium X25519 Dev Shadow Keypair Generated');
  }
}

function getPublicKeyBase64() {
  if (!keypair) return null;
  return Buffer.from(keypair.publicKey).toString('base64');
}

function decryptSealedBox(base64Ciphertext) {
  if (!keypair) throw new Error('Keypair not initialized');
  try {
    const ciphertext = new Uint8Array(Buffer.from(base64Ciphertext, 'base64'));
    const decrypted = sodium.crypto_box_seal_open(ciphertext, keypair.publicKey, keypair.privateKey);
    return sodium.to_string(decrypted);
  } catch (err) {
    winston.error('Failed to decrypt sealed credentials:', err);
    return null;
  }
}

module.exports = {
  initKeypair,
  getPublicKeyBase64,
  decryptSealedBox
};
