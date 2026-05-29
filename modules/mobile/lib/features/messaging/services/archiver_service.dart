import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:pointycastle/digests/sha256.dart';
import '../../vault_auth/providers/setup_wizard_provider.dart';
import '../../storage/services/vault_db_service.dart';
import 'message_crypto_service.dart';

class ArchiverService {
  final Ref _ref;

  ArchiverService(this._ref);

  /// Archives older messages if the local SQLite storage exceeds 1000 active messages.
  Future<void> archiveIfNeeded(String conversationId, Uint8List msk) async {
    final lessonKey = await VaultDbService.instance.getConversationKey(conversationId, msk);
    if (lessonKey == null) return;

    final db = await VaultDbService.instance.database;

    // 1. Check if messages count exceeds active window (1000)
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE conversation_id = ? AND chapter_hash IS NULL',
      [conversationId],
    );
    final count = countResult.first['count'] as int? ?? 0;

    if (count <= 1000) {
      debugPrint('[ARCHIVER] Active message count is $count (<= 1000). Skipping archiving.');
      return;
    }

    debugPrint('[ARCHIVER] Active messages count is $count. Archiving oldest 1000 messages.');

    // 2. Fetch backend's latest tail pointer
    String? latestChapterHash;
    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.get('/conversations/$conversationId/latest-chapter');
      if (response.statusCode == 200) {
        latestChapterHash = response.data['latestChapterHash'] as String?;
      }
    } catch (e) {
      debugPrint('[ARCHIVER] Failed to retrieve latest chapter pointer from server: $e');
      return; // Halt if we cannot establish the pointer chain
    }

    // 3. Package oldest 1000 messages
    final maps = await db.query(
      'messages',
      where: 'conversation_id = ? AND chapter_hash IS NULL',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
      limit: 1000,
    );

    final messageIds = maps.map((e) => e['message_id'] as String).toList();
    final List<Map<String, dynamic>> messagesToArchive = maps.map((e) => {
      'message_id': e['message_id'],
      'sender_id': e['sender_id'],
      'encrypted_payload': e['encrypted_payload'],
      'timestamp': e['timestamp'],
      'delivery_status': e['delivery_status'],
    }).toList();

    final chapterMap = {
      'previousChapterHash': latestChapterHash,
      'messages': messagesToArchive,
    };

    final plaintext = jsonEncode(chapterMap);

    // 4. Encrypt the chapter and compute SHA-256 hash of the binary
    final encryptedBase64 = MessageCryptoService.encryptPayload(
      lessonKeyHex: lessonKey,
      plaintext: plaintext,
      conversationId: conversationId,
    );
    final encryptedBytes = base64Decode(encryptedBase64);

    final digest = SHA256Digest();
    final newChapterHashBytes = digest.process(encryptedBytes);
    final newChapterHash = MessageCryptoService.hexEncode(newChapterHashBytes);

    // 5. Request presigned PUT URL
    String? uploadUrl;
    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.post(
        '/conversations/messages/upload-chapter-url',
        data: {
          'conversationId': conversationId,
          'new_chapter_hash': newChapterHash,
        },
      );
      if (response.statusCode == 200) {
        uploadUrl = response.data['uploadUrl'] as String?;
      }
    } catch (e) {
      debugPrint('[ARCHIVER] Failed to request presigned upload URL: $e');
      return;
    }

    if (uploadUrl == null) return;

    // 6. Upload directly to Cloudflare R2
    try {
      final dio = _ref.read(dioProvider);
      await dio.put(
        uploadUrl,
        data: Stream.fromIterable([encryptedBytes]),
        options: Options(
          headers: {
            Headers.contentLengthHeader: encryptedBytes.length,
          },
        ),
      );
      debugPrint('[ARCHIVER] Successfully uploaded chapter $newChapterHash binary to R2');
    } catch (e) {
      debugPrint('[ARCHIVER] Failed to upload chapter to R2: $e');
      return; // Do NOT finalize on server or delete locally if upload fails
    }

    // 7. Finalize pointer on backend
    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.post(
        '/conversations/messages/archive-chapter',
        data: {
          'conversationId': conversationId,
          'new_chapter_hash': newChapterHash,
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        // Purge the 1000 messages from local SQLite
        await db.transaction((txn) async {
          final placeholders = List.filled(messageIds.length, '?').join(',');
          await txn.delete(
            'messages',
            where: 'message_id IN ($placeholders)',
            whereArgs: messageIds,
          );
        });
        debugPrint('[ARCHIVER] Successfully finalized chapter and purged 1000 messages locally.');
      }
    } catch (e) {
      debugPrint('[ARCHIVER] Failed to finalize pointer update on backend: $e');
    }
  }
}

final archiverServiceProvider = Provider.autoDispose<ArchiverService>((ref) {
  return ArchiverService(ref);
});
