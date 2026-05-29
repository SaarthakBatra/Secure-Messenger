import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/router/app_router.dart';
import '../providers/setup_wizard_provider.dart';

class VaultDevTestingScreen extends ConsumerWidget {
  const VaultDevTestingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vault Home (Dev Sandbox)')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: () async {
                  try {
                    final token = ref.read(vaultSessionNotifierProvider).token;
                    if (token == null) throw Exception('No active session token in memory');
                    final api = ref.read(authApiServiceProvider);
                    await api.fetchEscrowedKeys(token: token);
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ping backend successful!')));
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ping failed: $e')));
                  }
                },
                child: const Text('Ping Backend (Fetch Escrowed Keys)'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  ref.read(mockNetworkResponseProvider.notifier).state = {
                    'statusCode': 401,
                    'data': {'code': 'REFRESH_EXPIRED', 'error': 'Mock Refresh Expired'}
                  };
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mocked 401 REFRESH_EXPIRED. Next ping will trigger silent refresh.')));
                },
                child: const Text('Simulate 401 (Silent Refresh)'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.read(mockNetworkResponseProvider.notifier).state = {
                    'statusCode': 401,
                    'data': {'code': 'SESSION_EXPIRED', 'error': 'Mock Session Expired'}
                  };
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mocked 401 SESSION_EXPIRED. Next ping will trigger Re-Auth.')));
                },
                child: const Text('Simulate 401 (PIN Re-Auth)'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.read(mockNetworkResponseProvider.notifier).state = {
                    'statusCode': 403,
                    'data': {'code': 'HACK_DETECTED', 'error': 'Mock Hack Detected'}
                  };
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mocked 403 HACK_DETECTED. Next ping will trigger Burn Protocol.')));
                },
                child: const Text('Simulate 403 (Burn Protocol)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
