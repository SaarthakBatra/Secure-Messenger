import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/cover/screens/decoy_onboarding_screen.dart';
import '../../features/cover/screens/decoy_home_screen.dart';
import '../../features/cover/screens/offline_translation_screen.dart';
import '../../features/cover/screens/report_issue_form_screen.dart';
import '../../features/cover/screens/decoy_settings_screen.dart';
// ignore: avoid_relative_lib_imports
import '../../features/vault_auth/screens/setup/vault_setup_wrapper.dart';
// Note: These need to be created
import '../../features/settings/screens/vault_settings_screen.dart';
import '../../features/restoration/screens/recovery_screen.dart';
import '../../features/conversations/screens/vault_home_screen.dart';
import '../../features/messaging/screens/chat_screen.dart';
import 'dart:typed_data';

// NEW: A ChangeNotifier bridge between Riverpod and GoRouter
class VaultSessionNotifier extends ChangeNotifier {
  String? _sessionType;
  String? _token;
  String? _refreshToken;
  int _reauthGracePeriodSeconds = 10;
  
  bool get isActive => _sessionType != null;
  String? get sessionType => _sessionType;
  String? get token => _token;
  String? get refreshToken => _refreshToken;
  int get reauthGracePeriodSeconds => _reauthGracePeriodSeconds;

  void setSession(String? type, {String? token, String? refreshToken, int? reauthGracePeriodSeconds}) {
    if (_sessionType != type || _token != token || _refreshToken != refreshToken || (reauthGracePeriodSeconds != null && _reauthGracePeriodSeconds != reauthGracePeriodSeconds)) {
      _sessionType = type;
      _token = token;
      _refreshToken = refreshToken;
      if (reauthGracePeriodSeconds != null) {
        _reauthGracePeriodSeconds = reauthGracePeriodSeconds;
      }
      debugPrint('[SECURITY] vaultSession set to: $_sessionType, token stored: ${token != null}, refresh stored: ${refreshToken != null}');
      notifyListeners(); // Triggers GoRouter redirect re-evaluation only
    }
  }
}

final vaultSessionNotifierProvider = Provider((ref) => VaultSessionNotifier());

class MskSessionNotifier extends StateNotifier<Uint8List?> {
  MskSessionNotifier() : super(null);
  void setMsk(Uint8List msk) => state = msk;
  void clear() => state = null;
}

final mskSessionProvider = StateNotifierProvider<MskSessionNotifier, Uint8List?>((ref) {
  // Automatically watch session status; if it becomes inactive, clear/nullify the MSK state
  final isSessionActive = ref.watch(vaultSessionNotifierProvider.select((n) => n.isActive));
  
  final notifier = MskSessionNotifier();
  if (!isSessionActive) {
    notifier.clear();
  }
  
  return notifier;
});

// Providers for dependencies
final sharedPrefsOnboardingProvider = StateProvider<bool?>((ref) => null);
final vaultConfiguredProvider = StateProvider<bool>((ref) => false); // Tracks if vault setup is complete

final appRouterProvider = Provider<GoRouter>((ref) {
  final hasCompletedOnboarding = ref.watch(sharedPrefsOnboardingProvider);
  final sessionNotifier = ref.watch(vaultSessionNotifierProvider);

  return GoRouter(
    refreshListenable: sessionNotifier,
    initialLocation: (hasCompletedOnboarding == true) ? '/home' : '/onboarding',
    redirect: (context, state) {
      final isGoingToVault = state.matchedLocation.startsWith('/vault');
      final isAuthenticated = sessionNotifier.isActive;
      
      debugPrint('[ROUTER] Redirect evaluated. going to: ${state.matchedLocation}, authenticated: $isAuthenticated');

      // Allow /vault/setup without auth, but protect /vault and other routes
      if (isGoingToVault && state.matchedLocation != '/vault/setup' && !isAuthenticated) {
        debugPrint('[ROUTER] Blocked unauthenticated vault access -> /home');
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const DecoyOnboardingScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const DecoyHomeScreen(),
        routes: [
          GoRoute(
            path: 'translation',
            builder: (context, state) => const OfflineTranslationScreen(),
          ),
          GoRoute(
            path: 'report-issue',
            builder: (context, state) => const ReportIssueFormScreen(),
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) => const DecoySettingsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/vault',
        builder: (context, state) => const VaultHomeScreen(),
        routes: [
          GoRoute(
            path: 'setup',
            builder: (context, state) => const VaultSetupWrapper(),
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) => const VaultSettingsScreen(),
          ),
          GoRoute(
            path: 'chat/:id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return ChatScreen(conversationId: id);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/recovery',
        builder: (context, state) => const RecoveryScreen(),
      ),
    ],
  );
});
