import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import '../../vault_auth/providers/setup_wizard_provider.dart';
import '../../storage/services/vault_db_service.dart';
import 'message_crypto_service.dart';

class LazyLoadingService {
  final Ref _ref;

  LazyLoadingService(this._ref);

  /// Loads the next previous chapter of chat history for a conversation.
  /// Returns the decrypted messages list or an empty list if no history remains.
  Future<List<Map<String, dynamic>>> loadPreviousChapter(String conversationId, Uint8List msk) async {
    final lessonKey = await VaultDbService.instance.getConversationKey(conversationId, msk);
    if (lessonKey == null) return [];

    final db = await VaultDbService.instance.database;

    // Find the next chapter hash to retrieve.
    // We check the oldest cached chapter's previous_chapter_hash.
    final cachedList = await db.query(
      'cached_chapters',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC', // Oldest cached first
    );

    String? nextChapterHash;
    if (cachedList.isNotEmpty) {
      nextChapterHash = cachedList.first['previous_chapter_hash'] as String?;
      if (nextChapterHash == null) {
        debugPrint('[LAZY] Reached beginning of history chain (previousChapterHash is null).');
        return [];
      }
    } else {
      // No chapters cached yet. Query server for the tail pointer.
      try {
        final dio = _ref.read(dioProvider);
        final response = await dio.get('/conversations/$conversationId/latest-chapter');
        if (response.statusCode == 200) {
          nextChapterHash = response.data['latestChapterHash'] as String?;
        }
      } catch (e) {
        debugPrint('[LAZY] Failed to retrieve tail pointer from server: $e');
        return [];
      }
    }

    if (nextChapterHash == null) {
      debugPrint('[LAZY] No archived chapters exist for this conversation.');
      return [];
    }

    debugPrint('[LAZY] Downloading chapter: $nextChapterHash');

    // 1. Fetch GET presigned URL
    String? downloadUrl;
    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.post(
        '/conversations/messages/download-chapter-url',
        data: {
          'conversationId': conversationId,
          'chapter_hash': nextChapterHash,
        },
      );
      if (response.statusCode == 200) {
        downloadUrl = response.data['downloadUrl'] as String?;
      }
    } catch (e) {
      debugPrint('[LAZY] Failed to request presigned download URL: $e');
      return [];
    }

    if (downloadUrl == null) {
      // Mock fallback: if downloadUrl is not returned by the server because it is missing,
      // construct the fallback mock download URL
      downloadUrl = 'https://mock-r2.local/download/convo_$conversationId/chapter_$nextChapterHash?token=mock';
    }

    // 2. Download the binary payload
    Uint8List encryptedBytes;
    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.get(
        downloadUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      encryptedBytes = Uint8List.fromList(response.data as List<int>);
    } catch (e) {
      debugPrint('[LAZY] Failed to download chapter binary: $e');
      return [];
    }

    // 3. Decrypt on-the-fly in RAM
    final encryptedBase64 = base64Encode(encryptedBytes);
    final decryptedStr = MessageCryptoService.decryptPayload(
      lessonKeyHex: lessonKey,
      base64Payload: encryptedBase64,
      conversationId: conversationId,
    );

    if (decryptedStr == null) {
      debugPrint('[LAZY] Failed to decrypt chapter $nextChapterHash payload.');
      return [];
    }

    final chapterMap = jsonDecode(decryptedStr) as Map<String, dynamic>;
    final previousChapterHash = chapterMap['previousChapterHash'] as String?;
    final messages = chapterMap['messages'] as List<dynamic>;

    // 4. Save messages to SQLite and tag them with the chapter hash
    final List<Map<String, dynamic>> loadedMessages = [];
    await db.transaction((txn) async {
      for (final msg in messages) {
        final m = msg as Map<String, dynamic>;
        await txn.insert(
          'messages',
          {
            'message_id': m['message_id'],
            'conversation_id': conversationId,
            'sender_id': m['sender_id'],
            'encrypted_payload': m['encrypted_payload'],
            'timestamp': m['timestamp'],
            'delivery_status': m['delivery_status'],
            'chapter_hash': nextChapterHash,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        loadedMessages.add(m);
      }

      // 5. Register chapter metadata locally
      await txn.insert(
        'cached_chapters',
        {
          'chapter_hash': nextChapterHash,
          'conversation_id': conversationId,
          'previous_chapter_hash': previousChapterHash,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    // 6. Enforce local cache constraint (O(2 chapters) limit)
    final chaptersList = await db.query(
      'cached_chapters',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );

    if (chaptersList.length > 2) {
      final toPurgeCount = chaptersList.length - 2;
      for (var i = 0; i < toPurgeCount; i++) {
        final purgeHash = chaptersList[i]['chapter_hash'] as String;
        await db.transaction((txn) async {
          await txn.delete('messages', where: 'chapter_hash = ?', whereArgs: [purgeHash]);
          await txn.delete('cached_chapters', where: 'chapter_hash = ?', whereArgs: [purgeHash]);
        });
        debugPrint('[LAZY] SQLite local cache constraint enforced. Purged chapter $purgeHash.');
      }
    }

    return loadedMessages;
  }
}

final lazyLoadingServiceProvider = Provider.autoDispose<LazyLoadingService>((ref) {
  return LazyLoadingService(ref);
});
