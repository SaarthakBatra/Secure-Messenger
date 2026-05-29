import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite/sqflite.dart';
import '../../storage/services/vault_db_service.dart';
import '../../vault_auth/providers/setup_wizard_provider.dart';
import '../../cover/providers/streak_provider.dart';
import '../services/message_crypto_service.dart';
import '../services/websocket_service.dart';
import '../services/active_page_sync_service.dart';
import '../services/hashing_alignment_service.dart';
import '../providers/messages_provider.dart';
import '../../../app/router/app_router.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  String _projectAlias = 'Loading...';
  String _projectStatus = 'PENDING';
  String _currentUserId = '';
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadProjectDetails();
    _syncActivePage();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProjectDetails() async {
    final msk = ref.read(mskSessionProvider);
    if (msk == null) return;

    try {
      final db = await VaultDbService.instance.getDatabase(msk);
      final maps = await db.query(
        'conversations',
        where: 'conversation_id = ?',
        whereArgs: [widget.conversationId],
      );

      if (maps.isNotEmpty) {
        setState(() {
          _projectAlias = maps.first['local_alias'] as String? ?? 'Translation Project';
          _projectStatus = maps.first['status'] as String? ?? 'PENDING';
        });
      }

      final prefs = ref.read(sharedPrefsProvider);
      setState(() {
        _currentUserId = prefs.getString('user_id') ?? '';
      });
    } catch (e) {
      debugPrint('Failed to load project details: $e');
    }
  }

  Future<void> _syncActivePage() async {
    final msk = ref.read(mskSessionProvider);
    if (msk == null) return;

    setState(() => _isSyncing = true);
    try {
      await ref.read(activePageSyncServiceProvider).syncActivePage(widget.conversationId, msk);
      ref.invalidate(messagesProvider(widget.conversationId));
    } catch (e) {
      debugPrint('Error syncing active page: $e');
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final msk = ref.read(mskSessionProvider);
    final token = ref.read(vaultSessionNotifierProvider).token;
    if (msk == null || token == null) return;

    _messageController.clear();

    try {
      final lessonKey = await VaultDbService.instance.getConversationKey(widget.conversationId, msk);
      if (lessonKey == null) throw Exception('Conversation key not found');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final messageId = 'msg_${timestamp}_${_currentUserId.hashCode}';

      final pending = {
        'message_id': messageId,
        'sender_id': _currentUserId,
        'content': text,
        'timestamp': timestamp,
      };

      final pageHash = await HashingAlignmentService.computeActivePageHash(
        widget.conversationId,
        msk,
        pendingMessage: pending,
      );

      final plaintext = jsonEncode({
        'content': text,
        'hash': pageHash,
      });

      final encrypted = MessageCryptoService.encryptMessage(
        lessonKeyHex: lessonKey,
        plaintext: plaintext,
        conversationId: widget.conversationId,
        messageId: messageId,
      );

      final db = await VaultDbService.instance.database;

      await db.insert(
        'messages',
        {
          'message_id': messageId,
          'conversation_id': widget.conversationId,
          'sender_id': _currentUserId,
          'encrypted_payload': encrypted,
          'timestamp': timestamp,
          'delivery_status': 'sent',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      ref.read(websocketServiceProvider).sendMessage(messageId, widget.conversationId, encrypted);
      ref.invalidate(messagesProvider(widget.conversationId));

      // Trigger upload backup so that server has the latest aligned active page
      ref.read(activePageSyncServiceProvider).uploadBackup(widget.conversationId, msk).catchError((err) {
        debugPrint('Failed to upload active page backup: $err');
      });

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to encrypt/send message: $e')),
        );
      }
    }
  }

  Widget _buildStatusIndicator(String status) {
    switch (status) {
      case 'read':
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_all, size: 14, color: Color(0xFF00E676)),
          ],
        );
      case 'acknowledged':
      case 'delivered':
        return const Icon(Icons.done_all, size: 14, color: Colors.white30);
      case 'sent':
        return const Icon(Icons.done, size: 14, color: Colors.white30);
      case 'FAILED_DECRYPTION':
        return const Icon(Icons.error_outline_rounded, size: 14, color: Colors.redAccent);
      default:
        return const Icon(Icons.schedule, size: 14, color: Colors.white30);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep WebSocket connection active
    ref.watch(websocketServiceProvider);

    final messagesAsync = ref.watch(messagesProvider(widget.conversationId));

    // Scroll to bottom when list changes
    ref.listen(messagesProvider(widget.conversationId), (prev, next) {
      if (next.hasValue) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2027),
        elevation: 1,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _projectAlias,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _projectStatus == 'ACTIVE' ? const Color(0xFF00E676) : Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _projectStatus,
                  style: TextStyle(
                    color: _projectStatus == 'ACTIVE' ? const Color(0xFF00E676) : Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_isSyncing)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E676)),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.sync_rounded, color: Colors.white70),
            onPressed: _syncActivePage,
            tooltip: 'Sync Active Page',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: messagesAsync.when(
                  data: (messages) {
                    if (messages.isEmpty) {
                      return Center(
                        child: Text(
                          'No messages in this enclave project.',
                          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = msg['sender_id'] == _currentUserId;
                        final content = msg['content'] as String;
                        final timestamp = msg['timestamp'] as int;
                        final status = msg['delivery_status'] as String;
                        final timeStr = TimeOfDay.fromDateTime(
                          DateTime.fromMillisecondsSinceEpoch(timestamp),
                        ).format(context);

                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.75,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? const Color(0xFF00E676).withOpacity(0.15)
                                  : Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(0),
                                bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
                              ),
                              border: Border.all(
                                color: isMe
                                    ? const Color(0xFF00E676).withOpacity(0.3)
                                    : Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  content,
                                  style: TextStyle(
                                    color: content == '[Decryption Failed]' ? Colors.redAccent : Colors.white,
                                    fontSize: 15,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      timeStr,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.4),
                                        fontSize: 10,
                                      ),
                                    ),
                                    if (isMe) ...[
                                      const SizedBox(width: 4),
                                      _buildStatusIndicator(status),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00E676)),
                  ),
                  error: (err, stack) => Center(
                    child: Text(
                      'Failed to load messages: $err',
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ),
              ),
              
              // Input bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF14242C),
                  border: Border(top: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Enter secure translation message...',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.2),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF00E676),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Color(0xFF0F2027)),
                        onPressed: _sendMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
