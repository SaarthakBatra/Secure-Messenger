// ChaCha20-Poly1305-IETF Cipher Integration Service (Dart)
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_sodium/flutter_sodium.dart';

class CipherService {
  static final RegExp _idRegex = RegExp(r'^[a-zA-Z0-9]+$');

  /// Encrypts plaintext using ChaCha20-Poly1305-IETF.
  /// AAD: "${conversationId}:${entityId}".
  /// Layout: Base64url(nonce[12] || ciphertext || tag[16]).
  static String encrypt({
    required Uint8List key,
    required String plaintext,
    required String conversationId,
    required String entityId,
  }) {
    // Assert strict alphanumeric IDs to prevent delimiter injection attacks
    if (!_idRegex.hasMatch(conversationId) || !_idRegex.hasMatch(entityId)) {
      throw ArgumentError('CRYPTO_008: Non-alphanumeric conversationId or entityId');
    }

    final String aad = '$conversationId:$entityId';
    final Uint8List nonce = Sodium.randombytesBuf(12);

    final Uint8List ct = ChaCha20Poly1305Ietf.encryptString(
      plaintext,
      nonce,
      key,
      additionalData: aad,
    );

    final Uint8List blob = Uint8List(12 + ct.length)
      ..setRange(0, 12, nonce)
      ..setRange(12, 12 + ct.length, ct);

    return base64Url.encode(blob).replaceAll('=', '');
  }

  /// Decrypts and authenticates a Base64url blob. Returns null on validation or integrity failure.
  static String? decrypt({
    required Uint8List key,
    required String blob,
    required String conversationId,
    required String entityId,
  }) {
    // Assert strict alphanumeric IDs
    if (!_idRegex.hasMatch(conversationId) || !_idRegex.hasMatch(entityId)) {
      return null;
    }

    try {
      // Add padding back if it was stripped
      final String paddedBlob = blob.padRight(blob.length + (4 - blob.length % 4) % 4, '=');
      final Uint8List bytes = base64Url.decode(paddedBlob);
      
      // Minimum length must be 28 bytes (12-byte nonce + 16-byte minimum auth tag/ciphertext)
      if (bytes.length < 28) {
        return null;
      }

      final Uint8List nonce = bytes.sublist(0, 12);
      final Uint8List ct = bytes.sublist(12);
      final String aad = '$conversationId:$entityId';

      return ChaCha20Poly1305Ietf.decryptString(
        ct,
        nonce,
        key,
        additionalData: aad,
      );
    } catch (_) {
      return null; // Gracefully return null on decryption/verification failure
    }
  }
}
