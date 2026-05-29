import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../vault_auth/services/auth_api_service.dart';
import '../../vault_auth/providers/setup_wizard_provider.dart';
import '../../security/services/sodium_crypto_service.dart';
import '../../../app/router/app_router.dart';

class VaultSettingsScreen extends ConsumerStatefulWidget {
  const VaultSettingsScreen({super.key});

  @override
  ConsumerState<VaultSettingsScreen> createState() => _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends ConsumerState<VaultSettingsScreen> {
  final _newPinController = TextEditingController();
  final _newDuressPinController = TextEditingController();
  final _currentPinController = TextEditingController();
  
  bool _isLoading = false;
  int _wrongAttempts = 0;

  void _ejectUser() {
    debugPrint('[SECURITY] Settings re-auth failed 3 times. Ejecting to decoy home.');
    ref.read(vaultSessionNotifierProvider).setSession(null);
    context.go('/home');
  }

  Future<void> _showReauthDialog({
    required Function(String currentPin) onReauthSuccess,
  }) async {
    _currentPinController.clear();
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF14242C),
          title: const Text('Confirm Identity', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Please enter your current 6-digit Vault PIN to authorize this change.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _currentPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Current PIN',
                  labelStyle: TextStyle(color: Colors.white60),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E676))),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                final currentPin = _currentPinController.text.trim();
                if (currentPin.length != 6) return;
                
                Navigator.pop(context);
                await _performReauth(currentPin, onReauthSuccess);
              },
              child: const Text('Confirm', style: TextStyle(color: Color(0xFF00E676))),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performReauth(String currentPin, Function(String currentPin) onReauthSuccess) async {
    setState(() => _isLoading = true);
    
    final token = ref.read(vaultSessionNotifierProvider).token;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: No active session')));
      setState(() => _isLoading = false);
      return;
    }

    try {
      final currentClientKey = SodiumCryptoService.generateClientKey(currentPin, 'dev-fingerprint-mobile');
      final apiService = ref.read(authApiServiceProvider);
      
      final reauthData = await apiService.reauth(sessionToken: token, clientKey: currentClientKey);
      final newToken = reauthData['sessionToken'] as String;
      
      // Update session token in provider
      ref.read(vaultSessionNotifierProvider).setSession(
        'vault',
        token: newToken,
        refreshToken: reauthData['refreshToken'] as String?,
      );

      _wrongAttempts = 0; // Reset on success
      await onReauthSuccess(currentPin);

    } catch (e) {
      _wrongAttempts++;
      final remaining = 3 - _wrongAttempts;
      if (_wrongAttempts >= 3) {
        _ejectUser();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid current PIN. $remaining attempts remaining.'))
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateVaultPin() async {
    final newPin = _newPinController.text.trim();
    if (newPin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN must be exactly 6 digits.')));
      return;
    }

    await _showReauthDialog(
      onReauthSuccess: (currentPin) async {
        final msk = ref.read(mskSessionProvider);
        final token = ref.read(vaultSessionNotifierProvider).token;
        if (msk == null || token == null) throw Exception('No active MSK session');

        final apiService = ref.read(authApiServiceProvider);
        
        // 1. Change Vault PIN on the backend
        final currentClientKey = SodiumCryptoService.generateClientKey(currentPin, 'dev-fingerprint-mobile');
        final newClientKey = SodiumCryptoService.generateClientKey(newPin, 'dev-fingerprint-mobile');
        final pinChangeSuccess = await apiService.changePin(
          token: token,
          currentClientKey: currentClientKey,
          newClientKey: newClientKey,
        );

        if (!pinChangeSuccess) throw Exception('Failed to update PIN in backend');

        // 2. Wrap MSK with the new PIN and update pinWrappedMsk
        final newPinWrappedMsk = SodiumCryptoService.wrapMsk(msk, newPin);
        final mskUpdateSuccess = await apiService.updateMsk(token: token, newPinWrappedMsk: newPinWrappedMsk);

        if (!mskUpdateSuccess) throw Exception('Failed to update escrow configuration');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN updated successfully')));
          _newPinController.clear();
        }
      },
    );
  }

  Future<void> _updateDuressPin() async {
    final newDuressPin = _newDuressPinController.text.trim();
    if (newDuressPin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Duress PIN must be exactly 6 digits.')));
      return;
    }

    await _showReauthDialog(
      onReauthSuccess: (currentPin) async {
        if (newDuressPin == currentPin) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Duress PIN cannot match the primary Vault PIN.'))
          );
          return;
        }

        final token = ref.read(vaultSessionNotifierProvider).token;
        if (token == null) throw Exception('No active session token');

        final apiService = ref.read(authApiServiceProvider);
        final currentClientKey = SodiumCryptoService.generateClientKey(currentPin, 'dev-fingerprint-mobile');
        final newDuressClientKey = SodiumCryptoService.generateClientKey(newDuressPin, 'dev-fingerprint-mobile');
        
        final success = await apiService.changeDuressPin(
          token: token,
          currentClientKey: currentClientKey,
          newDuressClientKey: newDuressClientKey,
        );

        if (!success) throw Exception('Failed to update Duress PIN');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Duress PIN updated successfully')));
          _newDuressPinController.clear();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F2027),
      appBar: AppBar(
        title: const Text('Vault Settings', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF14242C),
        iconTheme: const IconThemeData(color: Colors.white70),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Change Vault PIN',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPinController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'New 6-digit PIN',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E676))),
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isLoading ? null : _updateVaultPin,
              child: const Text('Update Vault PIN', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 48, color: Colors.white12),
            const Text(
              'Change Duress PIN',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newDuressPinController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'New 6-digit Duress PIN',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E676))),
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isLoading ? null : _updateDuressPin,
              child: const Text('Update Duress PIN', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
