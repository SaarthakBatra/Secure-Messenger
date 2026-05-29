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

class CreateConvoSheet extends ConsumerStatefulWidget {
  const CreateConvoSheet({super.key});

  @override
  ConsumerState<CreateConvoSheet> createState() => _CreateConvoSheetState();
}

class _CreateConvoSheetState extends ConsumerState<CreateConvoSheet> {
  final _partnerIdController = TextEditingController();
  final _aliasController = TextEditingController();
  late final TextEditingController _messageController;
  
  bool _isLoading = false;
  String? _error;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    // Fetch local user id to prefill message
    final prefs = ref.read(sharedPrefsProvider);
    final userId = prefs.getString('user_id') ?? 'unknown';
    _messageController = TextEditingController(
      text: 'User $userId wants to start a project...',
    );
  }

  @override
  void dispose() {
    _partnerIdController.dispose();
    _aliasController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _createProject() async {
    final partnerId = _partnerIdController.text.trim();
    final alias = _aliasController.text.trim();
    final invitationMessage = _messageController.text.trim();

    if (partnerId.isEmpty || alias.isEmpty || invitationMessage.isEmpty) {
      setState(() => _error = 'All fields are required.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = ref.read(vaultSessionNotifierProvider).token;
      final msk = ref.read(mskSessionProvider);
      final syncToken = ref.read(translationSyncTokenProvider);

      debugPrint('[CREATE_CONVO] token: ${token != null}, msk: ${msk != null}, syncToken: ${syncToken != null}');

      if (token == null || msk == null || syncToken == null) {
        throw Exception('Vault session or security keys not fully initialized (token: ${token != null}, msk: ${msk != null}, syncToken: ${syncToken != null}).');
      }

      final api = ref.read(authApiServiceProvider);
      
      // Verify partner user exists
      final partnerExists = await api.checkUserExists(partnerId);
      if (!partnerExists) {
        throw Exception('Partner User ID is invalid or not registered.');
      }

      // 1. Create on server (server generates key, wraps it, and returns Alice's payload)
      final response = await api.createConversation(
        token: token,
        recipientUserId: partnerId,
        invitationMessage: invitationMessage,
      );

      final conversationId = response['conversationId'] as String;
      final aliceInvitePayload = response['aliceInvite'] as String;

      // Fetch Alice's (our own) public key to decrypt her payload
      final prefs = ref.read(sharedPrefsProvider);
      final userId = prefs.getString('user_id') ?? '';
      final alicePublicKeyBase64 = await api.fetchPartnerPublicKey(userId);
      final alicePublicKey = base64Decode(alicePublicKeyBase64);

      // 2. Decrypt Alice_Invite_Payload using Alice's public key and Alice's private key (syncToken)
      final lessonKey = SodiumCryptoService.decryptSealedBox(
        aliceInvitePayload,
        alicePublicKey,
        syncToken,
      );

      // 3. Encrypt lessonKey with Alice's MSK to create wrappedLessonKey
      final wrappedLessonKey = SodiumCryptoService.encryptSymmetric(lessonKey, msk);

      // 4. POST Alice's escrow payload to backend
      await api.escrowConversationKey(
        token: token,
        conversationId: conversationId,
        encryptedConversationKey: wrappedLessonKey,
        localAlias: alias,
      );

      // 5. Save to local SQLite database
      await VaultDbService.instance.storeConversationKey(
        conversationId,
        lessonKey,
        msk,
        localAlias: alias,
      );

      setState(() {
        _isSuccess = true;
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception:', '').trim();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                Text(
                  _isSuccess ? 'Invitation Sent' : 'Create Translation Project',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
            if (!_isSuccess) ...[
              TextField(
                controller: _partnerIdController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Partner User ID',
                  labelStyle: const TextStyle(color: Colors.white60),
                  hintText: 'e.g. 102938475',
                  hintStyle: const TextStyle(color: Colors.white30),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white24),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFF00E676)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _aliasController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Project Alias (Local Label)',
                  labelStyle: const TextStyle(color: Colors.white60),
                  hintText: 'e.g. Russia Trade Project',
                  hintStyle: const TextStyle(color: Colors.white30),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white24),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFF00E676)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _messageController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Invitation Message',
                  labelStyle: const TextStyle(color: Colors.white60),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white24),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFF00E676)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isLoading ? null : _createProject,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                      )
                    : const Text('Create Project', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ] else ...[
              const Icon(
                Icons.check_circle_outline,
                color: Color(0xFF00E676),
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'Project invitation sent successfully!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'The encryption keys have been established securely in the background. The project will show in your dashboard as soon as your partner accepts the invitation.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
