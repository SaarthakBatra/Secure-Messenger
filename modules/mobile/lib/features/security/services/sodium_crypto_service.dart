import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_sodium/flutter_sodium.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:pointycastle/export.dart';
import 'dart:math';

class SodiumCryptoService {
  /// Initializes the library if required (stub for lazy init)
  static Future<void> init() async {
    // Some flutter_sodium versions require SodiumInit.init()
    // If it fails, we will remove this or fix it.
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  /// Generates a deterministic SHA-256 Client_Key for Vault/Duress PINs
  static String generateClientKey(String pin, String deviceFingerprint) {
    final message = utf8.encode(pin + deviceFingerprint);
    final hashBytes = Sodium.cryptoGenerichash(Sodium.cryptoGenerichashBytes, message, null);
    return _bytesToHex(hashBytes);
  }

  /// Generates a deterministic SHA-256 Client_Key for the Recovery Phrase
  static String generateRecoveryClientKey(String recoveryPhrase) {
    final message = utf8.encode(recoveryPhrase);
    final hashBytes = Sodium.cryptoGenerichash(Sodium.cryptoGenerichashBytes, message, null);
    return _bytesToHex(hashBytes);
  }

  /// Generates a BIP-39 recovery phrase
  static String generateRecoveryPhrase() {
    return bip39.generateMnemonic();
  }

  /// Seals a payload using Curve25519 crypto_box_seal
  static String sealPayload(String payload, Uint8List publicKey) {
    final message = utf8.encode(payload);
    final sealedBox = Sodium.cryptoBoxSeal(message, publicKey);
    return base64Encode(sealedBox);
  }

  /// Generates a 256-bit (32 bytes) Master Storage Key
  static Uint8List generateMsk() {
    return Sodium.randombytesBuf(32);
  }

  /// Derives a 32-byte Key Encryption Key (KEK) using PBKDF2-SHA256 (100k iterations)
  static Uint8List deriveKek(String secret, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, 100000, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(secret)));
  }

  /// Wraps the MSK using the derived secret
  static String wrapMsk(Uint8List msk, String secret) {
    final salt = Sodium.randombytesBuf(16);
    final kek = deriveKek(secret, salt);
    final nonce = Sodium.randombytesBuf(Sodium.cryptoSecretboxNoncebytes);
    
    final ciphertext = Sodium.cryptoSecretboxEasy(msk, nonce, kek);
    
    // Payload: [salt 16b] [nonce] [ciphertext]
    final combined = Uint8List(16 + nonce.length + ciphertext.length);
    combined.setAll(0, salt);
    combined.setAll(16, nonce);
    combined.setAll(16 + nonce.length, ciphertext);
    
    return base64Encode(combined);
  }

  /// Unwraps the MSK using the derived secret
  static Uint8List unwrapMsk(String wrappedMskBase64, String secret) {
    final combined = base64Decode(wrappedMskBase64);
    const saltLen = 16;
    final nonceLen = Sodium.cryptoSecretboxNoncebytes;
    
    final salt = combined.sublist(0, saltLen);
    final nonce = combined.sublist(saltLen, saltLen + nonceLen);
    final ciphertext = combined.sublist(saltLen + nonceLen);
    
    final kek = deriveKek(secret, salt);
    return Sodium.cryptoSecretboxOpenEasy(ciphertext, nonce, kek);
  }

  /// Encrypts a conversation key using the MSK
  static String encryptSymmetric(String plaintext, Uint8List msk) {
    final nonce = Sodium.randombytesBuf(Sodium.cryptoSecretboxNoncebytes);
    final ciphertext = Sodium.cryptoSecretboxEasy(Uint8List.fromList(utf8.encode(plaintext)), nonce, msk);
    
    final combined = Uint8List(nonce.length + ciphertext.length);
    combined.setAll(0, nonce);
    combined.setAll(nonce.length, ciphertext);
    
    return base64Encode(combined);
  }

  /// Decrypts a conversation key using the MSK
  static String decryptSymmetric(String encryptedBase64, Uint8List msk) {
    final combined = base64Decode(encryptedBase64);
    final nonceLen = Sodium.cryptoSecretboxNoncebytes;
    
    final nonce = combined.sublist(0, nonceLen);
    final ciphertext = combined.sublist(nonceLen);
    
    final plaintextBytes = Sodium.cryptoSecretboxOpenEasy(ciphertext, nonce, msk);
    return utf8.decode(plaintextBytes);
  }

  /// Generates X25519 asymmetric Identity Keypair (covert terms: syncProfileId / translationSyncToken)
  static KeyPair generateIdentityKeypair() {
    return Sodium.cryptoBoxKeypair();
  }

  /// Decrypts an invitation payload encrypted with Bob's X25519 public key (syncProfileId)
  static String decryptSealedBox(String base64Ciphertext, Uint8List publicKey, Uint8List privateKey) {
    final ciphertext = base64Decode(base64Ciphertext);
    final decryptedBytes = Sodium.cryptoBoxSealOpen(ciphertext, publicKey, privateKey);
    return utf8.decode(decryptedBytes);
  }
}

