import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../vault_auth/services/auth_api_service.dart';
import '../../vault_auth/providers/setup_wizard_provider.dart';
import '../../security/services/sodium_crypto_service.dart';
import '../../storage/services/vault_db_service.dart';
import '../../../app/router/app_router.dart';

class RecoveryScreen extends ConsumerStatefulWidget {
  const RecoveryScreen({super.key});

  @override
  ConsumerState<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends ConsumerState<RecoveryScreen> {
  final _phraseController = TextEditingController();
  final _newPinController = TextEditingController();
  
  bool _isLoading = false;
  int _step = 1;
  String? _tempToken;

  Future<void> _recoverMsk() async {
    final phrase = _phraseController.text.trim();
    if (phrase.split(' ').length != 12) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phrase must be 12 words')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Wipe prior unencrypted DB to avoid state contamination
      await VaultDbService.instance.wipeDatabase();
      // In a real flow, you first login with the phrase client_key to get a recovery token
      final recoveryClientKey = SodiumCryptoService.generateRecoveryClientKey(phrase);
      // Mocking login for the token...
      // final response = await _apiService.login(userId: '...', clientKey: recoveryClientKey, deviceFingerprint: '...');
      // _tempToken = response['token'];
      _tempToken = 'MOCK_RECOVERY_TOKEN'; // Needs the real user ID in a complete flow
      
      final apiService = ref.read(authApiServiceProvider);
      final mskData = await apiService.fetchMsk(token: _tempToken!);
      final msk = SodiumCryptoService.unwrapMsk(mskData['phraseWrappedMsk']!, phrase);
      ref.read(mskSessionProvider.notifier).setMsk(msk);
      
      setState(() {
        _step = 2;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Recovery failed: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _setNewPinAndSync() async {
    final newPin = _newPinController.text.trim();
    if (newPin.length != 6) return;

    final msk = ref.read(mskSessionProvider);
    if (msk == null) return;

    setState(() => _isLoading = true);
    try {
      final apiService = ref.read(authApiServiceProvider);
      final newPinWrappedMsk = SodiumCryptoService.wrapMsk(msk, newPin);
      await apiService.updateMsk(token: _tempToken!, newPinWrappedMsk: newPinWrappedMsk);
      
      final escrowedKeys = await apiService.fetchEscrowedKeys(token: _tempToken!);
      for (final row in escrowedKeys) {
        final encryptedKeyFromServer = row['encryptedConversationKey'] as String?;
        final conversationId = row['conversationId'] as String?;
        final localAlias = row['localAlias'] as String?;
        if (encryptedKeyFromServer != null && conversationId != null) {
          final plaintextKey = SodiumCryptoService.decryptSymmetric(encryptedKeyFromServer, msk);
          await VaultDbService.instance.storeConversationKey(
            conversationId,
            plaintextKey,
            msk,
            localAlias: localAlias,
            status: 'ACTIVE',
          );
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recovery complete!')));
        context.go('/home');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vault Recovery')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _step == 1
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Enter 12-word Recovery Phrase', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _phraseController,
                  maxLines: 3,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isLoading ? null : _recoverMsk,
                  child: _isLoading ? const CircularProgressIndicator() : const Text('Recover Vault'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Set New Vault PIN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _newPinController,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isLoading ? null : _setNewPinAndSync,
                  child: _isLoading ? const CircularProgressIndicator() : const Text('Save & Sync Data'),
                ),
              ],
            ),
      ),
    );
  }
}
