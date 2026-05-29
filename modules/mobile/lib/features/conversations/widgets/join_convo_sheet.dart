import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/router/app_router.dart';
import '../../vault_auth/providers/setup_wizard_provider.dart';
import '../../security/services/sodium_crypto_service.dart';
import '../../storage/services/vault_db_service.dart';
import '../../cover/providers/streak_provider.dart';
import '../providers/conversations_provider.dart';

class JoinConvoSheet extends ConsumerStatefulWidget {
  const JoinConvoSheet({super.key});

  @override
  ConsumerState<JoinConvoSheet> createState() => _JoinConvoSheetState();
}

class _JoinConvoSheetState extends ConsumerState<JoinConvoSheet> {
  bool _isLoading = false;
  String? _error;

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

  Future<void> _acceptInvite(PendingInvite invite) async {
    final alias = await _showAliasDialog(context);
    if (alias == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = ref.read(vaultSessionNotifierProvider).token;
      final msk = ref.read(mskSessionProvider);
      final syncToken = ref.read(translationSyncTokenProvider);

      debugPrint('[JOIN_CONVO] token: ${token != null}, msk: ${msk != null}, syncToken: ${syncToken != null}');

      if (token == null || msk == null || syncToken == null) {
        throw Exception('Vault session or security keys not fully initialized (token: ${token != null}, msk: ${msk != null}, syncToken: ${syncToken != null}).');
      }

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
      
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully joined project!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception:', '').trim();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingInvites = ref.watch(pendingInvitesProvider);

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20,
        left: 20,
        right: 20,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF14242C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Join Translation Project',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(color: Color(0xFF00E676)),
                ),
              )
            else if (pendingInvites.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.mail_outline,
                        size: 48,
                        color: Colors.white.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No pending invitations found.',
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ask your partner to create a project and invite your User ID.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              const Text(
                'Select a pending project invitation below to accept and join:',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: pendingInvites.length,
                itemBuilder: (context, index) {
                  final invite = pendingInvites[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: ListTile(
                      title: Text(
                        invite.message,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          'Sender: ${invite.senderUserId}',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                        ),
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _acceptInvite(invite),
                        child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
