const sodium = require('libsodium-wrappers-sumo');
const kdfService = require('../../modules/shared/node/kdf_service');
const subkeyService = require('../../modules/shared/node/subkey_service');
const cipherService = require('../../modules/shared/node/cipher_service');
const mnemonicService = require('../../modules/shared/node/mnemonic_service');

describe('Cryptographic Parity & Core Utilities - Backend Suite', () => {
  beforeAll(async () => {
    await sodium.ready;
  });

  // T.3 Argon2id KDF Checks
  describe('Argon2id KDF Service', () => {
    it('should generate a valid storage hash and verify successfully', async () => {
      const pin = '123456';
      const hash = await kdfService.hashPin(pin);
      expect(hash).toContain('$argon2id$');
      
      const success = await kdfService.verifyPin(pin, hash);
      expect(success).toBe(true);

      const fail = await kdfService.verifyPin('654321', hash);
      expect(fail).toBe(false);
    });

    it('should derive raw interactive keys deterministically', async () => {
      const pin = '123456';
      const salt = Buffer.alloc(16, 0x09);
      
      const key1 = await kdfService.deriveRawKey(pin, salt);
      const key2 = await kdfService.deriveRawKey(pin, salt);
      
      expect(key1).toHaveLength(32);
      expect(key1.equals(key2)).toBe(true);

      const differentSalt = Buffer.alloc(16, 0x0a);
      const key3 = await kdfService.deriveRawKey(pin, differentSalt);
      expect(key1.equals(key3)).toBe(false);
    });
  });

  // T.4 BLAKE2b KDF Sub-Key expansion checks
  describe('BLAKE2b Sub-Key Derivation', () => {
    it('should derive matching sub-keys for standard rooms deterministically', async () => {
      const masterKey = Buffer.alloc(32, 0x42);
      
      const messageKey = await subkeyService.deriveSubKey(masterKey, 'messages');
      const notesKey = await subkeyService.deriveSubKey(masterKey, 'notes');
      const mediaKey = await subkeyService.deriveSubKey(masterKey, 'media');

      expect(messageKey).toHaveLength(32);
      expect(notesKey).toHaveLength(32);
      expect(mediaKey).toHaveLength(32);

      expect(messageKey.equals(notesKey)).toBe(false);
      expect(messageKey.equals(mediaKey)).toBe(false);

      // Verify deterministic derivation
      const messageKey2 = await subkeyService.deriveSubKey(masterKey, 'messages');
      expect(messageKey.equals(messageKey2)).toBe(true);
    });

    it('should throw CRYPTO_006 on unknown context', async () => {
      const masterKey = Buffer.alloc(32, 0x42);
      await expect(subkeyService.deriveSubKey(masterKey, 'invalid_context'))
        .rejects.toThrow('CRYPTO_006');
    });
  });

  // T.5 ChaCha20-Poly1305 Cipher Checks
  describe('ChaCha20-Poly1305 AEAD Cipher', () => {
    let key;
    beforeAll(() => {
      key = Buffer.alloc(32, 0x55);
    });

    it('should successfully encrypt and decrypt under correct conditions', async () => {
      const plaintext = 'Covert Operation MultiLingo';
      const convId = 'room123';
      const msgId = 'msg456';

      const blob = await cipherService.encrypt(key, plaintext, convId, msgId);
      expect(typeof blob).toBe('string');
      
      const decrypted = await cipherService.decrypt(key, blob, convId, msgId);
      expect(decrypted).toBe(plaintext);
    });

    it('should return null when decryption tag verification fails (E11 / CRYPTO_001)', async () => {
      const plaintext = 'Covert Operation MultiLingo';
      const convId = 'room123';
      const msgId = 'msg456';

      const blob = await cipherService.encrypt(key, plaintext, convId, msgId);
      
      // Decrypt with a different key
      const badKey = Buffer.alloc(32, 0x66);
      const decryptedBadKey = await cipherService.decrypt(badKey, blob, convId, msgId);
      expect(decryptedBadKey).toBeNull();

      // Decrypt with modified ciphertext bytes
      const bytes = Buffer.from(blob, 'base64url');
      bytes[15] ^= 0xFF; // Modify a byte of ciphertext/tag
      const modifiedBlob = bytes.toString('base64url');
      
      const decryptedModified = await cipherService.decrypt(key, modifiedBlob, convId, msgId);
      expect(decryptedModified).toBeNull();
    });

    it('should enforce strict alphanumeric assertions to block injection attacks', async () => {
      const plaintext = 'Secret';
      
      // Delimiter injection attempts
      const badConvId = 'room:123';
      const msgId = 'msg456';

      await expect(cipherService.encrypt(key, plaintext, badConvId, msgId))
        .rejects.toThrow();

      const badMsgId = 'msg/456';
      await expect(cipherService.encrypt(key, plaintext, 'room123', badMsgId))
        .rejects.toThrow();

      // Decryption with bad ID should silently return null
      const decryptedBad = await cipherService.decrypt(key, 'valid_blob', badConvId, msgId);
      expect(decryptedBad).toBeNull();
    });

    it('should silently return null for truncated/malformed blobs (CRYPTO_008)', async () => {
      const shortBlob = 'A4g93k=='; // Less than 28 bytes
      const decrypted = await cipherService.decrypt(key, shortBlob, 'room123', 'msg456');
      expect(decrypted).toBeNull();
    });
  });

  // T.6 BIP-39 Recovery Management Checks
  describe('BIP-39 Recovery Phrase Hashing', () => {
    it('should securely verify recovery phrases timing-safely', async () => {
      const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      const salt = '0102030405060708090a0b0c0d0e0f10'; // 16 bytes hex-encoded
      
      const hash = await mnemonicService.deriveMnemonicHash(mnemonic, salt);
      expect(hash).toHaveLength(32);

      const hashHex = hash.toString('hex');
      const success = await mnemonicService.verifyMnemonic(mnemonic, salt, hashHex);
      expect(success).toBe(true);

      const fail = await mnemonicService.verifyMnemonic(mnemonic + ' extra', salt, hashHex);
      expect(fail).toBe(false);
    });
  });
});
