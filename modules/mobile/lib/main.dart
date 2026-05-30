import 'dart:io';
import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide databaseFactory;
import 'package:sqflite/sqflite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app/router/app_router.dart';
import 'app/theme/app_theme.dart';
import 'features/cover/providers/streak_provider.dart';
import 'features/cover/providers/issue_report_provider.dart';
import 'features/cover/screens/decoy_home_screen.dart';
import 'features/vault_auth/widgets/reauth_overlay_widget.dart';
import 'features/vault_auth/services/auth_api_service.dart';
import 'features/vault_auth/providers/setup_wizard_provider.dart';
import 'features/security/services/sodium_crypto_service.dart';
import 'features/security/services/sodium_instance.dart';
import 'features/storage/services/vault_db_service.dart';
import 'features/storage/services/profile_helper.dart';
import 'features/storage/services/profile_shared_preferences.dart';
import 'features/storage/services/db_factory.dart' as db_factory;
import 'utils/platform_security.dart';

final vaultBurnedProvider = StateProvider<bool>((ref) => false);
final isReauthOverlayActiveProvider = StateProvider<Completer<bool>?>((ref) => null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('[ENV] Failed to load .env file: $e');
  }

  await SodiumInstance.init();
  db_factory.initDbFactory();
  
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  final rawPrefs = await SharedPreferences.getInstance();
  final profile = getProfile() ?? '';
  final prefs = ProfileSharedPreferences(rawPrefs, profile);
  final hasCompletedOnboarding = prefs.getBool('has_completed_onboarding');
  final isVaultConfigured = prefs.getBool('vault_is_configured') ?? false;
  final isVaultBurned = prefs.getBool('vault_burned') ?? false;

  debugPrint('[BOOT] isVaultConfigured: $isVaultConfigured, hasOnboarded: $hasCompletedOnboarding, isBurned: $isVaultBurned');

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsOnboardingProvider.overrideWith((ref) => hasCompletedOnboarding),
        sharedPrefsProvider.overrideWith((ref) => prefs),
        vaultConfiguredProvider.overrideWith((ref) => isVaultConfigured),
        vaultBurnedProvider.overrideWith((ref) => isVaultBurned),
        coverLogoLongPressCallbackProvider.overrideWith((ref) {
          return () {
            final isBurned = ref.read(vaultBurnedProvider);
            if (isBurned) return; // Burn protocol: do nothing
            final isConfigured = ref.read(vaultConfiguredProvider);
            debugPrint('[STEALTH] Long press triggered. isConfigured: $isConfigured');
            
            if (isConfigured) {
              debugPrint('[STEALTH] Routing to /home/report-issue');
              ref.read(appRouterProvider).go('/home/report-issue');
            } else {
              debugPrint('[STEALTH] Routing to /vault/setup');
              ref.read(appRouterProvider).go('/vault/setup');
            }
          };
        }),
      ],
      child: const MultiLingoApp(),
    ),
  );
}

class MultiLingoApp extends ConsumerStatefulWidget {
  const MultiLingoApp({super.key});

  @override
  ConsumerState<MultiLingoApp> createState() => _MultiLingoAppState();
}

class _MultiLingoAppState extends ConsumerState<MultiLingoApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateNativeSecurity(false);
  }

  void _updateNativeSecurity(bool isVaultActive) async {
    await PlatformSecurityService.updateNativeSecurity(isVaultActive);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateNativeSecurity(false);
    super.dispose();
  }

  Timer? _inactiveDebounceTimer;
  bool _isAppInactive = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[LIFECYCLE] State changed to: $state');

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (mounted) {
        setState(() => _isAppInactive = true);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (mounted) {
        setState(() => _isAppInactive = false);
      }
    }

    if (state == AppLifecycleState.resumed) {
      debugPrint('[LIFECYCLE] App resumed — cancelling debounce timer.');
      _inactiveDebounceTimer?.cancel();
    } else {
      // Handle inactive, paused, and hidden states
      if (_inactiveDebounceTimer == null || !_inactiveDebounceTimer!.isActive) {
        final prefs = ref.read(sharedPrefsProvider);
        final gracePeriodSeconds = prefs.getInt('grace_period_duration') ?? 0;
        
        int debounceMs = gracePeriodSeconds > 0 ? (gracePeriodSeconds * 1000) : 800;
        
        // Developer friction bypass: on desktop, losing focus immediately triggers inactive. 
        // We extend the minimum debounce to 5s to allow checking terminal logs without ejection.
        if (gracePeriodSeconds == 0 && (!kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows))) {
          debounceMs = 5000;
        }

        debugPrint('[LIFECYCLE] Background state detected — starting ${debounceMs}ms grace period timer');
        _inactiveDebounceTimer = Timer(Duration(milliseconds: debounceMs), () {
          debugPrint('[LIFECYCLE] Grace period expired. Checking route...');
          
          final overlayCompleter = ref.read(isReauthOverlayActiveProvider);
          if (overlayCompleter != null && !overlayCompleter.isCompleted) {
             debugPrint('[SECURITY] Grace period expired during Re-Auth. Ejecting.');
             overlayCompleter.complete(false);
             ref.read(vaultSessionNotifierProvider).setSession(null);
             ref.read(appRouterProvider).go('/home');
             return;
          }

          final router = ref.read(appRouterProvider);
          final currentRoute = router.routerDelegate.currentConfiguration.uri.toString();
          debugPrint('[LIFECYCLE] Current route: $currentRoute');
          
          if (currentRoute.startsWith('/vault')) {
            debugPrint('[SECURITY] Vault route detected while backgrounded — ejecting!');
            ref.read(vaultSessionNotifierProvider).setSession(null);
            router.go('/home');
          } else {
            debugPrint('[LIFECYCLE] Not in vault, no action taken.');
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final isVaultActive = ref.watch(vaultSessionNotifierProvider.select((n) => n.isActive));

    // Listen to vault session active status to toggle secure screen flags
    ref.listen<bool>(
      vaultSessionNotifierProvider.select((n) => n.isActive),
      (previous, next) {
        debugPrint('[SECURITY] Vault session active changed from $previous to $next');
        _updateNativeSecurity(next ?? false);
      },
    );

    // E7 & Vault Stealth Interception Hook
    ref.listen(issueReportProvider, (previous, next) {
      final pin = next.code.trim();
      final body = next.body.trim();
      
      if (pin.startsWith('#') && pin.length > 1 && body.isEmpty) {
        final actualPin = pin.substring(1);
        debugPrint('[STEALTH] PIN intercepted. code=$actualPin, body empty: true');
        // Intercept with empty body
        // Clear provider state in a microtask to avoid state modification during build
        Future.microtask(() async {
          ref.read(issueReportProvider.notifier).state = (code: '', body: '');
          ref.read(stealthLoginStateProvider.notifier).state = StealthLoginState.authenticating;
          
          final isBurned = ref.read(vaultBurnedProvider);
          if (isBurned) {
            ref.read(stealthLoginStateProvider.notifier).state = StealthLoginState.failure;
            return; // Burn protocol: do nothing
          }

          final isConfigured = ref.read(vaultConfiguredProvider);
          
          if (isConfigured) {
            debugPrint('[STEALTH] isConfigured: true -> initiating login');
            try {
              final prefs = ref.read(sharedPrefsProvider);
              final userId = prefs.getString('user_id') ?? '';
              
              final clientKey = SodiumCryptoService.generateClientKey(actualPin, 'dev-fingerprint-mobile');
              final apiService = ref.read(authApiServiceProvider);
              
              final response = await apiService.login(
                userId: userId,
                clientKey: clientKey,
                deviceFingerprint: 'dev-fingerprint-mobile',
              );
              
              final sessionType = response['sessionType'] as String;
              final token = response['token'] as String;
              final refreshToken = response['refreshToken'] as String?;
              final reauthGracePeriodSeconds = response['reauthGracePeriodSeconds'] as int?;
              final encryptedIdentityPrivateKey = response['encryptedIdentityPrivateKey'] as String?;
              
              if (encryptedIdentityPrivateKey != null) {
                await prefs.setString('encrypted_identity_private_key', encryptedIdentityPrivateKey);
              }
              
              ref.read(vaultSessionNotifierProvider).setSession(
                sessionType, 
                token: token,
                refreshToken: refreshToken,
                reauthGracePeriodSeconds: reauthGracePeriodSeconds,
              );
              
              if (sessionType == 'vault') {
                debugPrint('[STEALTH] Fetching MSK...');
                final mskData = await apiService.fetchMsk(token: token);
                final msk = SodiumCryptoService.unwrapMsk(mskData['pinWrappedMsk']!, actualPin);
                ref.read(mskSessionProvider.notifier).setMsk(msk);
                
                debugPrint('[STEALTH] Fetching escrowed keys...');
                await VaultDbService.instance.wipeDatabase();
                final escrowedKeys = await apiService.fetchEscrowedKeys(token: token);
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
              }
              
              ref.read(stealthLoginStateProvider.notifier).state = StealthLoginState.success;
              
              // Route based on sessionType
              if (sessionType == 'vault' || sessionType == 'duress' || sessionType == 'recovery') {
                router.go('/vault');
              }
              
              // Reset wrong attempts on success
              await prefs.setInt('wrong_pin_attempts', 0);
              
            } catch (e) {
              debugPrint('[STEALTH] Login failed: $e');
              ref.read(stealthLoginStateProvider.notifier).state = StealthLoginState.failure;
              
              if (e.toString().contains('Unauthorized')) {
                final prefs = ref.read(sharedPrefsProvider);
                int attempts = (prefs.getInt('wrong_pin_attempts') ?? 0) + 1;
                debugPrint('[STEALTH] Wrong PIN attempt $attempts');
                
                if (attempts >= 3) {
                  debugPrint('[STEALTH] BURN PROTOCOL INITIATED');
                  await prefs.setBool('vault_burned', true);
                  await prefs.remove('vault_is_configured');
                  await prefs.remove('user_id');
                  await prefs.remove('recovery_phrase_words');
                  await prefs.remove('wrong_pin_attempts');
                  ref.read(vaultBurnedProvider.notifier).state = true;
                  ref.read(vaultConfiguredProvider.notifier).state = false;
                } else {
                  await prefs.setInt('wrong_pin_attempts', attempts);
                }
              }
            }
          } else {
            debugPrint('[STEALTH] isConfigured: false -> routing to /vault/setup');
            ref.read(stealthLoginStateProvider.notifier).state = StealthLoginState.success;
            // First time setup
            router.go('/vault/setup');
          }
        });
      }
    });

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          MaterialApp.router(
            title: 'MultiLingo',
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
          Consumer(builder: (context, ref, child) {
            final activeCompleter = ref.watch(isReauthOverlayActiveProvider);
            if (activeCompleter == null) return const SizedBox.shrink();
            return Positioned.fill(
              child: ReauthOverlayWidget(completer: activeCompleter),
            );
          }),
          if (_isAppInactive && isVaultActive == true)
            Positioned.fill(
              child: Container(color: Colors.black),
            ),
        ],
      ),
    );
  }
}
