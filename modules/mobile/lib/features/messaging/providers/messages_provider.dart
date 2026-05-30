import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../storage/services/vault_db_service.dart';
import '../../vault_auth/providers/setup_wizard_provider.dart';
import '../services/message_crypto_service.dart';
import '../../../app/router/app_router.dart';

final messagesProvider = FutureProvider.family.autoDispose<List<Map<String, dynamic>>, String>((ref, conversationId) async {
  final msk = ref.watch(mskSessionProvider);
  if (msk == null) return [];
  
  final lessonKey = await VaultDbService.instance.getConversationKey(conversationId, msk);
  if (lessonKey == null) return [];
  
  final db = await VaultDbService.instance.getDatabase(msk);
  final maps = await db.query(
    'messages',
    where: 'conversation_id = ?',
    whereArgs: [conversationId],
    orderBy: 'timestamp ASC',
  );
  
  final List<Map<String, dynamic>> decryptedMessages = [];
  for (final map in maps) {
    final messageId = map['message_id'] as String;
    final senderId = map['sender_id'] as String;
    final encryptedPayload = map['encrypted_payload'] as String;
    final timestamp = map['timestamp'] as int;
    final deliveryStatus = map['delivery_status'] as String? ?? 'sent';
    
    final decrypted = MessageCryptoService.decryptMessage(
      lessonKeyHex: lessonKey,
      base64Payload: encryptedPayload,
      conversationId: conversationId,
      messageId: messageId,
    );
    
    String content = '';
    String? replyToMessageId;
    String? replyToContent;
    if (decrypted != null) {
      try {
        final envelope = jsonDecode(decrypted) as Map<String, dynamic>;
        content = envelope['content'] as String? ?? '';
        replyToMessageId = envelope['replyToMessageId'] as String?;
        replyToContent = envelope['replyToContent'] as String?;
      } catch (_) {
        content = decrypted;
      }
    } else {
      content = '[Decryption Failed]';
    }
    
    // Filter out control frames from UI display (they contain control type payloads)
    if (content.startsWith('{"type":')) {
      continue;
    }
    
    decryptedMessages.add({
      'message_id': messageId,
      'sender_id': senderId,
      'content': content,
      'timestamp': timestamp,
      'delivery_status': deliveryStatus,
      'replyToMessageId': replyToMessageId,
      'replyToContent': replyToContent,
    });
  }
  return decryptedMessages;
});
