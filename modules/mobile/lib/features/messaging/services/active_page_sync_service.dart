import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import '../../vault_auth/providers/setup_wizard_provider.dart';
import '../../storage/services/vault_db_service.dart';
import 'message_crypto_service.dart';
import '../providers/messages_provider.dart';

class ActivePageSyncService {
  final Ref _ref;

  ActivePageSyncService(this._ref);

  /// Synchronizes the active messages page for a conversation.
  Future<void> syncActivePage(String conversationId, Uint8List msk) async {
    final lessonKey = await VaultDbService.instance.getConversationKey(conversationId, msk);
    if (lessonKey == null) return;

    final db = await VaultDbService.instance.database;
    final metadataMaps = await db.query(
      'active_page_metadata',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );

    int localUpdatedAt = 0;
    if (metadataMaps.isNotEmpty) {
      localUpdatedAt = metadataMaps.first['local_updated_at'] as int? ?? 0;
    }

    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.get('/conversations/$conversationId/active-page');
      
      if (response.statusCode == 200) {
        final serverEncBlob = response.data['encryptedActivePage'] as String?;
        final serverUpdatedAtStr = response.data['updatedAt'] as String?;

        if (serverEncBlob == null || serverUpdatedAtStr == null) {
          // Fallback to upload client if server returns malformed data
          await uploadBackup(conversationId, msk);
          return;
        }

        final serverUpdatedAt = DateTime.parse(serverUpdatedAtStr).millisecondsSinceEpoch;

        if (serverUpdatedAt > localUpdatedAt) {
          // Case 1: Server is newer
          debugPrint('[SYNC] Server active page is newer ($serverUpdatedAt > $localUpdatedAt). Downloading.');
          final decryptedStr = MessageCryptoService.decryptPayload(
            lessonKeyHex: lessonKey,
            base64Payload: serverEncBlob,
            conversationId: conversationId,
          );

          if (decryptedStr != null) {
            final List<dynamic> messageList = jsonDecode(decryptedStr) as List<dynamic>;
            
            // Merge missing messages into SQLite
            for (final msg in messageList) {
              final m = msg as Map<String, dynamic>;
              await db.insert(
                'messages',
                {
                  'message_id': m['message_id'],
                  'conversation_id': conversationId,
                  'sender_id': m['sender_id'],
                  'encrypted_payload': m['encrypted_payload'],
                  'timestamp': m['timestamp'],
                  'delivery_status': m['delivery_status'],
                  'chapter_hash': null, // active messages have no chapter
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
            // Invalidate to update UI reactively
            _ref.invalidate(messagesProvider(conversationId));
          }

          // Compile and upload merged list back to server
          await uploadBackup(conversationId, msk);
        } else if (localUpdatedAt > serverUpdatedAt) {
          // Case 2: Client is newer
          debugPrint('[SYNC] Client active page is newer ($localUpdatedAt > $serverUpdatedAt). Uploading.');
          await uploadBackup(conversationId, msk);
        } else {
          debugPrint('[SYNC] Active page is fully aligned.');
        }
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // Case 3: Server does not have a backup yet -> Upload ours
        debugPrint('[SYNC] No server active page backup found. Initializing server backup.');
        await uploadBackup(conversationId, msk);
      } else {
        debugPrint('[SYNC] Network error while syncing active page: $e');
      }
    } catch (e) {
      debugPrint('[SYNC] Error during active page sync: $e');
    }
  }

  /// Compiles local active messages, encrypts, and uploads to server.
  Future<void> uploadBackup(String conversationId, Uint8List msk) async {
    final lessonKey = await VaultDbService.instance.getConversationKey(conversationId, msk);
    if (lessonKey == null) return;

    final db = await VaultDbService.instance.database;

    // Fetch active messages
    final maps = await db.query(
      'messages',
      where: 'conversation_id = ? AND chapter_hash IS NULL',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
    );

    final List<Map<String, dynamic>> activeList = maps.map((e) => {
      'message_id': e['message_id'],
      'sender_id': e['sender_id'],
      'encrypted_payload': e['encrypted_payload'],
      'timestamp': e['timestamp'],
      'delivery_status': e['delivery_status'],
    }).toList();

    final plaintext = jsonEncode(activeList);
    final encryptedActivePage = MessageCryptoService.encryptPayload(
      lessonKeyHex: lessonKey,
      plaintext: plaintext,
      conversationId: conversationId,
    );

    final now = DateTime.now();
    try {
      final dio = _ref.read(dioProvider);
      await dio.post(
        '/conversations/$conversationId/active-page',
        data: {
          'encryptedActivePage': encryptedActivePage,
          'updatedAt': now.toUtc().toIso8601String(),
        },
      );

      // Save sync metadata locally
      await db.insert(
        'active_page_metadata',
        {
          'conversation_id': conversationId,
          'local_updated_at': now.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('[SYNC] Successfully backed up active page on server at ${now.millisecondsSinceEpoch}');
    } catch (e) {
      debugPrint('[SYNC] Failed to upload active page backup: $e');
    }
  }
}

final activePageSyncServiceProvider = Provider.autoDispose<ActivePageSyncService>((ref) {
  return ActivePageSyncService(ref);
});
