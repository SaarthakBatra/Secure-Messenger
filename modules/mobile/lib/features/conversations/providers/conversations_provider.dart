import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/router/app_router.dart';
import '../../security/services/sodium_crypto_service.dart';
import '../../storage/services/vault_db_service.dart';
import '../../vault_auth/providers/setup_wizard_provider.dart';
import '../../cover/providers/streak_provider.dart';
import '../../messaging/services/websocket_service.dart';
import '../screens/vault_home_screen.dart';

class PendingInvite {
  final String conversationId;
  final String message;
  final String bobInvite;
  final String senderUserId;

  PendingInvite({
    required this.conversationId,
    required this.message,
    required this.bobInvite,
    required this.senderUserId,
  });

  factory PendingInvite.fromJson(Map<String, dynamic> json) {
    return PendingInvite(
      conversationId: json['conversationId'] as String,
      message: json['message'] as String,
      bobInvite: json['bobInvite'] as String,
      senderUserId: json['senderUserId'] as String,
    );
  }
}

final translationSyncTokenProvider = Provider.autoDispose<Uint8List?>((ref) {
  final msk = ref.watch(mskSessionProvider);
  if (msk == null) return null;
  final prefs = ref.watch(sharedPrefsProvider);
  String? encKey = prefs.getString('encrypted_identity_private_key');
  if (encKey == null) {
    debugPrint('[CRYPTO] Missing identity private key. Generating one on the fly (self-healing migration)...');
    try {
      final identityKeypair = SodiumCryptoService.generateIdentityKeypair();
      final syncProfileId = base64Encode(identityKeypair.pk);
      final encryptedIdentityPrivateKey = SodiumCryptoService.encryptSymmetric(
        base64Encode(identityKeypair.sk),
        msk,
      );
      
      // Save it locally synchronously (shared preferences background thread updates it)
      prefs.setString('encrypted_identity_private_key', encryptedIdentityPrivateKey);
      encKey = encryptedIdentityPrivateKey;
    } catch (e) {
      debugPrint('[CRYPTO] Failed to auto-generate identity key: $e');
      return null;
    }
  }
  try {
    final skBase64 = SodiumCryptoService.decryptSymmetric(encKey, msk);
    return base64Decode(skBase64);
  } catch (e) {
    debugPrint('Failed to decrypt identity private key: $e');
    return null;
  }
});

class PendingInvitesNotifier extends StateNotifier<List<PendingInvite>> {
  final Ref _ref;

  PendingInvitesNotifier(this._ref) : super([]) {
    fetchInvites();
  }

  Future<void> fetchInvites() async {
    final session = _ref.read(vaultSessionNotifierProvider);
    if (!session.isActive || session.token == null) return;
    
    try {
      final api = _ref.read(authApiServiceProvider);
      final rawList = await api.fetchPendingConversations(token: session.token!);
      state = rawList.map((e) => PendingInvite.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Failed to fetch pending invites: $e');
    }
  }

  void addInvite(PendingInvite invite) {
    if (!state.any((e) => e.conversationId == invite.conversationId)) {
      state = [...state, invite];
    }
  }

  void removeInvite(String conversationId) {
    state = state.where((e) => e.conversationId != conversationId).toList();
  }
}

final pendingInvitesProvider = StateNotifierProvider.autoDispose<PendingInvitesNotifier, List<PendingInvite>>((ref) {
  return PendingInvitesNotifier(ref);
});

final vaultWebSocketProvider = Provider.autoDispose<void>((ref) {
  final session = ref.watch(vaultSessionNotifierProvider);
  if (!session.isActive || session.token == null) return;

  final token = session.token!;
  WebSocket? ws;
  Timer? reconnectTimer;
  bool isDisposed = false;

  late void Function() connect;
  late void Function() reconnect;

  connect = () async {
    if (isDisposed) return;
    try {
      // Hardcoded host mapping for local dev matching auth_api_service baseUrl
      final wsUrl = 'ws://localhost:3000/ws?token=$token';
      debugPrint('[WEBSOCKET] Connecting to $wsUrl');
      ws = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 5));
      
      ref.read(wsSyncStatusProvider.notifier).state = true;
      debugPrint('[WEBSOCKET] Connected successfully');

      ws!.listen(
        (data) {
          try {
            debugPrint('[WEBSOCKET] Received: $data');
            final parsed = jsonDecode(data as String) as Map<String, dynamic>;
            final type = parsed['type'] as String?;
            if (type == 'PENDING_INVITE') {
              final payload = parsed['payload'] as Map<String, dynamic>;
              final invite = PendingInvite.fromJson(payload);
              ref.read(pendingInvitesProvider.notifier).addInvite(invite);
            }
          } catch (e) {
            debugPrint('[WEBSOCKET] Error parsing frame: $e');
          }
        },
        onError: (err) {
          debugPrint('[WEBSOCKET] Error: $err');
          ref.read(wsSyncStatusProvider.notifier).state = false;
          reconnect();
        },
        onDone: () {
          debugPrint('[WEBSOCKET] Closed');
          ref.read(wsSyncStatusProvider.notifier).state = false;
          reconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[WEBSOCKET] Connection failed: $e');
      ref.read(wsSyncStatusProvider.notifier).state = false;
      reconnect();
    }
  };

  reconnect = () {
    if (isDisposed) return;
    reconnectTimer?.cancel();
    reconnectTimer = Timer(const Duration(seconds: 10), () {
      connect();
    });
  };

  connect();

  ref.onDispose(() {
    isDisposed = true;
    reconnectTimer?.cancel();
    ws?.close();
    debugPrint('[WEBSOCKET] Disposed');
  });
});
