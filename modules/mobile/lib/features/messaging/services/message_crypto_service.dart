import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_sodium/flutter_sodium.dart';
import 'package:pointycastle/export.dart';
// ignore: avoid_relative_lib_imports
import '../../../shared/dart/subkey_service.dart';

class MessageCryptoService {
  /// Zeroes out the memory of a Uint8List.
  static void zeroMemory(Uint8List list) {
    list.fillRange(0, list.length, 0);
  }

  /// Decodes hex string to Uint8List.
  static Uint8List hexDecode(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Encodes Uint8List to hex string.
  static String hexEncode(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  /// Low-level AES-256-GCM encryption.
  /// Returns a Base64-encoded package: nonce (12 bytes) || ciphertext || tag (16 bytes).
  static String _encryptAESGCM({
    required Uint8List key,
    required String plaintext,
    required String aadString,
  }) {
    final nonce = Sodium.randombytesBuf(12);
    final aad = Uint8List.fromList(utf8.encode(aadString));
    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(KeyParameter(key), 128, nonce, aad);
    cipher.init(true, params);

    final ctAndTag = cipher.process(plaintextBytes);

    final combined = Uint8List(nonce.length + ctAndTag.length)
      ..setRange(0, nonce.length, nonce)
      ..setRange(nonce.length, nonce.length + ctAndTag.length, ctAndTag);

    return base64Encode(combined);
  }

  /// Low-level AES-256-GCM decryption.
  /// Expects a Base64-encoded package: nonce (12 bytes) || ciphertext || tag (16 bytes).
  static String? _decryptAESGCM({
    required Uint8List key,
    required String base64Payload,
    required String aadString,
  }) {
    try {
      final combined = base64Decode(base64Payload);
      if (combined.length < 28) {
        return null; // Less than nonce (12) + tag (16)
      }

      final nonce = combined.sublist(0, 12);
      final ctAndTag = combined.sublist(12);
      final aad = Uint8List.fromList(utf8.encode(aadString));

      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(KeyParameter(key), 128, nonce, aad);
      cipher.init(false, params);

      final ptBytes = cipher.process(ctAndTag);
      return utf8.decode(ptBytes);
    } catch (e) {
      debugPrint('[CRYPTO] AES-GCM decryption failed: $e');
      return null;
    }
  }

  /// Encrypts an individual message payload using the derived messaging subkey.
  /// The master symmetric `lessonKey` is passed as a hex string.
  /// AAD used: "${conversationId}:${messageId}".
  static String encryptMessage({
    required String lessonKeyHex,
    required String plaintext,
    required String conversationId,
    required String messageId,
  }) {
    final lessonKeyBytes = hexDecode(lessonKeyHex);
    final subkey = SubKeyService.deriveSubKey(
      masterKey: lessonKeyBytes,
      context: SubKeyContext.messages,
    );

    try {
      final aad = '$conversationId:$messageId';
      return _encryptAESGCM(key: subkey, plaintext: plaintext, aadString: aad);
    } finally {
      zeroMemory(lessonKeyBytes);
      zeroMemory(subkey);
    }
  }

  /// Decrypts an individual message payload using the derived messaging subkey.
  /// The master symmetric `lessonKey` is passed as a hex string.
  /// AAD used: "${conversationId}:${messageId}".
  static String? decryptMessage({
    required String lessonKeyHex,
    required String base64Payload,
    required String conversationId,
    required String messageId,
  }) {
    final lessonKeyBytes = hexDecode(lessonKeyHex);
    final subkey = SubKeyService.deriveSubKey(
      masterKey: lessonKeyBytes,
      context: SubKeyContext.messages,
    );

    try {
      final aad = '$conversationId:$messageId';
      return _decryptAESGCM(key: subkey, base64Payload: base64Payload, aadString: aad);
    } finally {
      zeroMemory(lessonKeyBytes);
      zeroMemory(subkey);
    }
  }

  /// Encrypts the overall `ActiveLessonPage` (Active Page Blob) or `LessonChapter` (Chapters)
  /// using the symmetric master `lessonKey` directly.
  /// AAD used: conversationId.
  static String encryptPayload({
    required String lessonKeyHex,
    required String plaintext,
    required String conversationId,
  }) {
    final lessonKeyBytes = hexDecode(lessonKeyHex);
    try {
      return _encryptAESGCM(key: lessonKeyBytes, plaintext: plaintext, aadString: conversationId);
    } finally {
      zeroMemory(lessonKeyBytes);
    }
  }

  /// Decrypts the overall `ActiveLessonPage` (Active Page Blob) or `LessonChapter` (Chapters)
  /// using the symmetric master `lessonKey` directly.
  /// AAD used: conversationId.
  static String? decryptPayload({
    required String lessonKeyHex,
    required String base64Payload,
    required String conversationId,
  }) {
    final lessonKeyBytes = hexDecode(lessonKeyHex);
    try {
      return _decryptAESGCM(key: lessonKeyBytes, base64Payload: base64Payload, aadString: conversationId);
    } finally {
      zeroMemory(lessonKeyBytes);
    }
  }
}
