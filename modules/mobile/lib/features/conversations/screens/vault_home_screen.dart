import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_router.dart';
import '../../storage/services/vault_db_service.dart';
import '../widgets/create_convo_sheet.dart';
import '../widgets/join_convo_sheet.dart';
import '../providers/conversations_provider.dart';
import '../../cover/providers/streak_provider.dart';
import '../../vault_auth/providers/setup_wizard_provider.dart';
import '../../security/services/sodium_crypto_service.dart';
import '../../messaging/services/websocket_service.dart';

final conversationListProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final msk = ref.watch(mskSessionProvider);
  if (msk == null) return [];
  
  final session = ref.watch(vaultSessionNotifierProvider);
  if (session.isActive && session.token != null) {
    try {
      final api = ref.read(authApiServiceProvider);
      final serverConvos = await api.fetchConversations(token: session.token!);
      final db = await VaultDbService.instance.getDatabase(msk);
      
      for (final convo in serverConvos) {
        final id = convo['conversationId'] as String;
        final status = convo['status'] as String;
        
        await db.update(
          'conversations',
          {'status': status},
          where: 'conversation_id = ?',
          whereArgs: [id],
        );
      }
    } catch (e) {
      debugPrint('[SYNC] Failed to sync conversation list: $e');
    }
  }
  
  final db = await VaultDbService.instance.getDatabase(msk);
  return await db.query('conversations', orderBy: 'created_at DESC');
});

class VaultHomeScreen extends ConsumerStatefulWidget {
  const VaultHomeScreen({super.key});

  @override
  ConsumerState<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends ConsumerState<VaultHomeScreen> {
  Future<String?> _showAliasDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF14242C),
          title: const Text('Enter Project Alias', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'e.g., Project S',
              hintStyle: TextStyle(color: Colors.white30),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white30),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF00E676)),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                Navigator.pop(context, text.isNotEmpty ? text : null);
              },
              child: const Text('Accept', style: TextStyle(color: Color(0xFF00E676))),
            ),
          ],
        );
      },
    );
  }

  Future<void> _acceptInvite(BuildContext context, WidgetRef ref, PendingInvite invite) async {
    try {
      final token = ref.read(vaultSessionNotifierProvider).token;
      final msk = ref.read(mskSessionProvider);
      final syncToken = ref.read(translationSyncTokenProvider);

      debugPrint('[ACCEPT_INVITE] token: ${token != null}, msk: ${msk != null}, syncToken: ${syncToken != null}');

      if (token == null || msk == null || syncToken == null) {
        throw Exception('Security keys or vault session not fully initialized (token: ${token != null}, msk: ${msk != null}, syncToken: ${syncToken != null}).');
      }

      // Prompt Bob for the Local Project Alias
      final alias = await _showAliasDialog(context);
      if (alias == null) {
        // User cancelled alias prompt
        return;
      }

      // Show a loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF00E676)),
        ),
      );

      final prefs = ref.read(sharedPrefsProvider);
      final userId = prefs.getString('user_id') ?? '';
      final api = ref.read(authApiServiceProvider);
      
      // Fetch Bob's (our own) public key to use for sealed box decryption
      final bobPublicKeyBase64 = await api.fetchPartnerPublicKey(userId);
      final bobPublicKey = base64Decode(bobPublicKeyBase64);

      // Decrypt Bob_Invite_Payload using Bob's public key and Bob's private key (syncToken)
      final lessonKey = SodiumCryptoService.decryptSealedBox(
        invite.bobInvite,
        bobPublicKey,
        syncToken,
      );

      // Encrypt lessonKey with Bob's MSK to create wrappedLessonKey
      final wrappedLessonKey = SodiumCryptoService.encryptSymmetric(lessonKey, msk);

      // Join conversation on the server
      final joinSuccess = await api.joinConversation(
        token: token,
        conversationId: invite.conversationId,
        conversationKey: lessonKey,
      );

      if (!joinSuccess) {
        throw Exception('Invitation has expired or been cancelled.');
      }

      // Escrow Bob's key to the server
      await api.escrowConversationKey(
        token: token,
        conversationId: invite.conversationId,
        encryptedConversationKey: wrappedLessonKey,
        localAlias: alias,
      );

      // Save to local DB
      await VaultDbService.instance.storeConversationKey(
        invite.conversationId,
        lessonKey,
        msk,
        localAlias: alias,
        status: 'ACTIVE',
      );

      // Remove from the pending list and refresh list
      ref.read(pendingInvitesProvider.notifier).removeInvite(invite.conversationId);
      ref.invalidate(conversationListProvider);

      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully joined project!')),
        );
      }
    } catch (e) {
      debugPrint('Error accepting invite: $e');
      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF14242C),
            title: const Text('Acceptance Failed', style: TextStyle(color: Colors.white)),
            content: Text(
              'Failed to automatically accept invitation due to security key mismatch or connection error:\n$e',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK', style: TextStyle(color: Color(0xFF00E676))),
              )
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch WebSocket to keep connection alive during session
    ref.watch(websocketServiceProvider);

    final syncStatus = ref.watch(wsSyncStatusProvider);
    final convoAsync = ref.watch(conversationListProvider);
    final pendingInvites = ref.watch(pendingInvitesProvider);

    return Scaffold(
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Premium Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Translation Enclave',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: syncStatus ? const Color(0xFF00E676) : Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              syncStatus ? 'Sync Status: Connected' : 'Sync Status: Reconnecting...',
                              style: TextStyle(
                                color: syncStatus ? const Color(0xFF00E676) : Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white70),
                          onPressed: () {
                            ref.read(pendingInvitesProvider.notifier).fetchInvites();
                            ref.invalidate(conversationListProvider);
                          },
                          tooltip: 'Refresh Session',
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white70),
                          onPressed: () {
                            context.go('/vault/settings');
                          },
                          tooltip: 'Settings',
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.redAccent),
                          onPressed: () {
                            ref.read(vaultSessionNotifierProvider).setSession(null);
                          },
                          tooltip: 'Exit Vault',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              
              // Pending Invitations Section
              if (pendingInvites.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 8.0),
                  child: Text(
                    'Pending Requests (${pendingInvites.length})',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                ...pendingInvites.map((invite) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: ListTile(
                    title: Text(
                      invite.message,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        'From User ID: ${invite.senderUserId}',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                      ),
                    ),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _acceptInvite(context, ref, invite),
                      child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                )),
                const Divider(color: Colors.white12, height: 24),
              ],

              // Project list or empty state
              Expanded(
                child: convoAsync.when(
                  data: (projects) {
                    if (projects.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.translate,
                                size: 64,
                                color: Colors.white.withOpacity(0.2),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No translation projects active.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Create or join a project below to get started.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: projects.length,
                      itemBuilder: (context, index) {
                        final proj = projects[index];
                        final alias = proj['local_alias'] as String? ?? 'Translation Project';
                        final id = proj['conversation_id'] as String;
                        final status = proj['status'] as String? ?? 'PENDING';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            title: Text(
                              alias,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                'ID: $id',
                                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                              ),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: status == 'ACTIVE' 
                                    ? const Color(0xFF00E676).withOpacity(0.15) 
                                    : Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  color: status == 'ACTIVE' ? const Color(0xFF00E676) : Colors.orange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            onTap: () {
                              context.go('/vault/chat/$id');
                            },
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
                  error: (err, stack) => Center(
                    child: Text(
                      'Error loading projects: $err',
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ),
              ),
              
              // Bottom Action Buttons
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.08),
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) => const JoinConvoSheet(),
                          ).then((_) => ref.invalidate(conversationListProvider));
                        },
                        icon: const Icon(Icons.group_add),
                        label: const Text('Join Project', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) => const CreateConvoSheet(),
                          ).then((_) => ref.invalidate(conversationListProvider));
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Create Project', style: TextStyle(fontWeight: FontWeight.bold)),
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
