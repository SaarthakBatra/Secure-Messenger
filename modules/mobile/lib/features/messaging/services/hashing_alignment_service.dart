import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/digests/sha256.dart';
import '../../storage/services/vault_db_service.dart';
import 'message_crypto_service.dart';

class HashingAlignmentService {
  /// Computes a SHA-256 hash of the active messages in the chat window.
  static Future<String> computeActivePageHash(
    String conversationId,
    Uint8List msk, {
    Map<String, dynamic>? pendingMessage,
  }) async {
    try {
      final lessonKey = await VaultDbService.instance.getConversationKey(conversationId, msk);
      if (lessonKey == null) return '';

      final db = await VaultDbService.instance.database;

      // 1. Fetch active messages sorted by messageId ascending
      final maps = await db.query(
        'messages',
        where: 'conversation_id = ? AND chapter_hash IS NULL',
        whereArgs: [conversationId],
        orderBy: 'message_id ASC',
      );

      final List<Map<String, dynamic>> canonicalList = [];

      for (final map in maps) {
        final messageId = map['message_id'] as String;
        final senderId = map['sender_id'] as String;
        final encryptedPayload = map['encrypted_payload'] as String;
        final timestamp = map['timestamp'] as int;

        // Decrypt content to compile hash
        final decrypted = MessageCryptoService.decryptMessage(
          lessonKeyHex: lessonKey,
          base64Payload: encryptedPayload,
          conversationId: conversationId,
          messageId: messageId,
        );

        String content = '';
        if (decrypted != null) {
          try {
            final envelope = jsonDecode(decrypted) as Map<String, dynamic>;
            content = envelope['content'] as String? ?? '';
          } catch (_) {
            content = decrypted;
          }
        }

        // Extract dictionary with sorted keys: c, id, s, t
        canonicalList.add({
          'c': content,
          'id': messageId,
          's': senderId,
          't': timestamp,
        });
      }

      if (pendingMessage != null) {
        canonicalList.add({
          'c': pendingMessage['content'] as String,
          'id': pendingMessage['message_id'] as String,
          's': pendingMessage['sender_id'] as String,
          't': pendingMessage['timestamp'] as int,
        });
      }

      // Sort by messageId ascending
      canonicalList.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

      // 3. Serialize list to canonical JSON array string (zero whitespace)
      final canonicalJson = jsonEncode(canonicalList);
      final jsonBytes = utf8.encode(canonicalJson);

      // 4. Compute SHA-256
      final digest = SHA256Digest();
      final hashBytes = digest.process(Uint8List.fromList(jsonBytes));

      return MessageCryptoService.hexEncode(hashBytes);
    } catch (e) {
      debugPrint('[HASH] Error computing active page hash: $e');
      return '';
    }
  }
}
