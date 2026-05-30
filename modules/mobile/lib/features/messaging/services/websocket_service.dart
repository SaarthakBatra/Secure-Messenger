import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import '../../vault_auth/providers/setup_wizard_provider.dart';
import '../../../app/router/app_router.dart';
import '../../storage/services/vault_db_service.dart';
import 'message_crypto_service.dart';
import 'hashing_alignment_service.dart';
import 'active_page_sync_service.dart';
import '../../conversations/providers/conversations_provider.dart';
import '../providers/messages_provider.dart';

final wsSyncStatusProvider = StateProvider<bool>((ref) => false);

class WebSocketService {
  final Ref _ref;
  WebSocket? _socket;
  Timer? _reconnectTimer;
  bool _isDisposed = false;
  String? _currentToken;

  WebSocketService(this._ref);

  void connect(String token) async {
    if (_isDisposed) return;
    _currentToken = token;
    _reconnectTimer?.cancel();

    try {
      final wsBase = (dotenv.isInitialized ? dotenv.env['WS_URL'] : null) ?? 'ws://localhost:3000';
      final wsUrl = '$wsBase/ws?token=$token';
      debugPrint('[WEBSOCKET] Connecting to $wsUrl');
      _socket = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 5));
      
      _ref.read(wsSyncStatusProvider.notifier).state = true;
      debugPrint('[WEBSOCKET] Connected successfully');

      _socket!.listen(
        (data) => _handleIncomingFrame(data as String),
        onError: (err) {
          debugPrint('[WEBSOCKET] Error: $err');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('[WEBSOCKET] Closed');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[WEBSOCKET] Connection failed: $e');
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _ref.read(wsSyncStatusProvider.notifier).state = false;
    if (_isDisposed || _currentToken == null) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      if (_currentToken != null) {
        connect(_currentToken!);
      }
    });
  }

  void sendMessage(String messageId, String conversationId, String encryptedBlob) {
    if (_socket == null || _socket!.readyState != WebSocket.open) {
      debugPrint('[WEBSOCKET] Socket not open. Cannot send message.');
      return;
    }

    final frame = {
      'type': 'chat',
      'payload': {
        'messageId': messageId,
        'conversationId': conversationId,
        'encryptedBlob': encryptedBlob,
      }
    };
    _socket!.add(jsonEncode(frame));
  }

  void sendReceipt(String messageId, String tickStatus) {
    if (_socket == null || _socket!.readyState != WebSocket.open) return;

    final frame = {
      'type': 'receipt',
      'payload': {
        'messageId': messageId,
        'tickStatus': tickStatus,
      }
    };
    _socket!.add(jsonEncode(frame));
  }

  void _handleIncomingFrame(String data) async {
    try {
      final parsed = jsonDecode(data) as Map<String, dynamic>;
      final type = parsed['type'] as String?;
      final payload = parsed['payload'] as Map<String, dynamic>?;

      if (payload == null) return;

      if (type == 'chat') {
        _handleChatFrame(payload);
      } else if (type == 'receipt') {
        _handleReceiptFrame(payload);
      } else if (type == 'PENDING_INVITE') {
        final invite = PendingInvite.fromJson(payload);
        _ref.read(pendingInvitesProvider.notifier).addInvite(invite);
      }
    } catch (e) {
      debugPrint('[WEBSOCKET] Error parsing incoming frame: $e');
    }
  }

  void _handleChatFrame(Map<String, dynamic> payload) async {
    final messageId = payload['messageId'] as String?;
    final conversationId = payload['conversationId'] as String?;
    final senderUserId = payload['senderUserId'] as String?;
    final encryptedBlob = payload['encryptedBlob'] as String?;
    final rawTimestamp = payload['timestamp'];
    final int timestamp = rawTimestamp is int
        ? rawTimestamp
        : (rawTimestamp is String ? (int.tryParse(rawTimestamp) ?? DateTime.now().millisecondsSinceEpoch) : DateTime.now().millisecondsSinceEpoch);

    if (messageId == null || conversationId == null || senderUserId == null || encryptedBlob == null) {
      return;
    }

    final msk = _ref.read(mskSessionProvider);
    if (msk == null) return;

    final lessonKey = await VaultDbService.instance.getConversationKey(conversationId, msk);
    if (lessonKey == null) return;

    // Attempt decryption
    String? decrypted = MessageCryptoService.decryptMessage(
      lessonKeyHex: lessonKey,
      base64Payload: encryptedBlob,
      conversationId: conversationId,
      messageId: messageId,
    );

    if (decrypted == null) {
      if (messageId.startsWith('ctrl_')) {
        debugPrint('[WEBSOCKET] Decryption failed for control frame $messageId. Discarding silently.');
        return;
      }
      debugPrint('[WEBSOCKET] Decryption failed for $messageId. Starting E11 recovery chain.');
      _runE11Recovery(messageId, conversationId, senderUserId, encryptedBlob, timestamp);
      return;
    }

    if (messageId.startsWith('ctrl_')) {
      // It's a control message. Process control payload if decryption succeeded, then return.
      try {
        final envelope = jsonDecode(decrypted) as Map<String, dynamic>;
        final content = envelope['content'] as String?;
        if (content != null && content.startsWith('{') && content.endsWith('}')) {
          final ctrl = jsonDecode(content) as Map<String, dynamic>;
          final ctrlType = ctrl['type'] as String?;
          if (ctrlType == 'resend_request') {
            _handleResendRequest(ctrl['targetMessageId'] as String?, conversationId, lessonKey);
          } else if (ctrlType == 'sync_request') {
            _handleSyncRequest(conversationId, lessonKey);
          } else if (ctrlType == 'failed_decryption') {
            _handleFailedDecryptionNotification(ctrl['targetMessageId'] as String?, conversationId);
          }
        }
      } catch (e) {
        debugPrint('[WEBSOCKET] Error processing control message content: $e');
      }
      return;
    }

    // Process decrypted content
    try {
      final envelope = jsonDecode(decrypted) as Map<String, dynamic>;
      final content = envelope['content'] as String?;
      final peerHash = envelope['hash'] as String?;

      if (content == null) return;

      // Write to SQLite
      final db = await VaultDbService.instance.database;
      await db.insert(
        'messages',
        {
          'message_id': messageId,
          'conversation_id': conversationId,
          'sender_id': senderUserId,
          'encrypted_payload': encryptedBlob,
          'timestamp': timestamp,
          'delivery_status': 'acknowledged',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Respond with receipt
      sendReceipt(messageId, 'acknowledged');

      // Invalidate messages provider to update UI reactively
      _ref.invalidate(messagesProvider(conversationId));

      // Trigger upload backup so that server has the latest aligned active page
      _ref.read(activePageSyncServiceProvider).uploadBackup(conversationId, msk).catchError((err) {
        debugPrint('[WEBSOCKET] Failed to upload active page backup on receipt: $err');
      });

      // Verify hash alignment
      if (peerHash != null) {
        final localHash = await HashingAlignmentService.computeActivePageHash(conversationId, msk);
        if (localHash != peerHash) {
          debugPrint('[WEBSOCKET] Hash mismatch: local=$localHash peer=$peerHash. Triggering P2P sync.');
          _triggerP2PSyncRequest(conversationId, senderUserId, lessonKey);
        }
      }
    } catch (e) {
      debugPrint('[WEBSOCKET] Error processing chat frame content: $e');
    }
  }

  void _handleReceiptFrame(Map<String, dynamic> payload) async {
    final messageId = payload['messageId'] as String?;
    final tickStatus = payload['tickStatus'] as String?;

    if (messageId == null || tickStatus == null) return;

    try {
      final db = await VaultDbService.instance.database;
      final maps = await db.query(
        'messages',
        columns: ['conversation_id'],
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      String? conversationId;
      if (maps.isNotEmpty) {
        conversationId = maps.first['conversation_id'] as String?;
      }

      await db.update(
        'messages',
        {'delivery_status': tickStatus},
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      debugPrint('[WEBSOCKET] Updated message $messageId status to $tickStatus');

      if (conversationId != null) {
        _ref.invalidate(messagesProvider(conversationId));
      }
    } catch (e) {
      debugPrint('[WEBSOCKET] Error updating receipt status in DB: $e');
    }
  }

  void _handleResendRequest(String? targetMsgId, String conversationId, String lessonKey) async {
    if (targetMsgId == null) return;
    try {
      final db = await VaultDbService.instance.database;
      final maps = await db.query('messages', where: 'message_id = ?', whereArgs: [targetMsgId]);
      if (maps.isNotEmpty) {
        final payload = maps.first['encrypted_payload'] as String?;
        if (payload != null) {
          // Re-send original E2EE payload
          sendMessage(targetMsgId, conversationId, payload);
          debugPrint('[WEBSOCKET] Handled resend request for $targetMsgId');
        }
      }
    } catch (e) {
      debugPrint('[WEBSOCKET] Error handling resend request: $e');
    }
  }

  void _handleSyncRequest(String conversationId, String lessonKey) async {
    try {
      final db = await VaultDbService.instance.database;
      final maps = await db.query(
        'messages',
        where: 'conversation_id = ? AND chapter_hash IS NULL',
        whereArgs: [conversationId],
        orderBy: 'timestamp ASC',
      );
      for (final map in maps) {
        final msgId = map['message_id'] as String;
        final payload = map['encrypted_payload'] as String;
        sendMessage(msgId, conversationId, payload);
      }
      debugPrint('[WEBSOCKET] Handled active sync request for $conversationId');
    } catch (e) {
      debugPrint('[WEBSOCKET] Error handling active sync request: $e');
    }
  }

  void _handleFailedDecryptionNotification(String? targetMsgId, String conversationId) async {
    if (targetMsgId == null) return;
    try {
      final db = await VaultDbService.instance.database;
      await db.update(
        'messages',
        {'delivery_status': 'FAILED_DECRYPTION'},
        where: 'message_id = ?',
        whereArgs: [targetMsgId],
      );
      debugPrint('[WEBSOCKET] Peer reported decryption failure for $targetMsgId. Updated status locally.');
    } catch (e) {
      debugPrint('[WEBSOCKET] Error handling peer decryption failure notification: $e');
    }
  }

  void _triggerP2PSyncRequest(String conversationId, String peerId, String lessonKey) {
    final controlPayload = jsonEncode({
      'type': 'sync_request',
    });
    final msgId = 'ctrl_sync_${DateTime.now().millisecondsSinceEpoch}';
    final encrypted = MessageCryptoService.encryptMessage(
      lessonKeyHex: lessonKey,
      plaintext: controlPayload,
      conversationId: conversationId,
      messageId: msgId,
    );
    sendMessage(msgId, conversationId, encrypted);
  }

  void _runE11Recovery(
    String messageId,
    String conversationId,
    String senderUserId,
    String encryptedBlob,
    int timestamp,
  ) async {
    final msk = _ref.read(mskSessionProvider);
    if (msk == null) return;
    final lessonKey = await VaultDbService.instance.getConversationKey(conversationId, msk);
    if (lessonKey == null) return;

    // Step 1: Peer Re-query (P2P)
    final controlPayload = jsonEncode({
      'type': 'resend_request',
      'targetMessageId': messageId,
    });
    final resendMsgId = 'ctrl_resend_${DateTime.now().millisecondsSinceEpoch}';
    final encryptedCtrl = MessageCryptoService.encryptMessage(
      lessonKeyHex: lessonKey,
      plaintext: controlPayload,
      conversationId: conversationId,
      messageId: resendMsgId,
    );
    sendMessage(resendMsgId, conversationId, encryptedCtrl);

    // Step 2: Query Server
    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.get('/conversations/$conversationId/messages');
      if (response.statusCode == 200) {
        final messages = response.data['messages'] as List<dynamic>?;
        if (messages != null) {
          for (final msg in messages) {
            if (msg['messageId'] == messageId) {
              final newBlob = msg['encryptedBlob'] as String;
              final decryptResult = MessageCryptoService.decryptMessage(
                lessonKeyHex: lessonKey,
                base64Payload: newBlob,
                conversationId: conversationId,
                messageId: messageId,
              );
              if (decryptResult != null) {
                // Success decryption from server fetch
                final db = await VaultDbService.instance.database;
                await db.insert(
                  'messages',
                  {
                    'message_id': messageId,
                    'conversation_id': conversationId,
                    'sender_id': senderUserId,
                    'encrypted_payload': newBlob,
                    'timestamp': timestamp,
                    'delivery_status': 'acknowledged',
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
                sendReceipt(messageId, 'acknowledged');
                debugPrint('[WEBSOCKET] Successfully recovered and decrypted message $messageId from server messages endpoint.');
                return;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[WEBSOCKET] Failed to recover message $messageId from server: $e');
    }

    // Step 3: Failure Escalation
    final db = await VaultDbService.instance.database;
    await db.insert(
      'messages',
      {
        'message_id': messageId,
        'conversation_id': conversationId,
        'sender_id': senderUserId,
        'encrypted_payload': encryptedBlob,
        'timestamp': timestamp,
        'delivery_status': 'FAILED_DECRYPTION',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Notify peer
    final failPayload = jsonEncode({
      'type': 'failed_decryption',
      'targetMessageId': messageId,
    });
    final failMsgId = 'ctrl_fail_${DateTime.now().millisecondsSinceEpoch}';
    final encFailCtrl = MessageCryptoService.encryptMessage(
      lessonKeyHex: lessonKey,
      plaintext: failPayload,
      conversationId: conversationId,
      messageId: failMsgId,
    );
    sendMessage(failMsgId, conversationId, encFailCtrl);
  }

  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _socket?.close();
  }
}

final websocketServiceProvider = Provider.autoDispose<WebSocketService>((ref) {
  final session = ref.watch(vaultSessionNotifierProvider);
  final service = WebSocketService(ref);
  if (session.isActive && session.token != null) {
    service.connect(session.token!);
  }
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});
