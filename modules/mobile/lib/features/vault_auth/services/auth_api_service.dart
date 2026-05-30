import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AuthApiService {
  final Dio _dio;
  
  // Hardcoded for local dev. In production, this would use a config provider.
  final String _baseUrl = (dotenv.isInitialized ? dotenv.env['API_URL'] : null) ?? 'http://localhost:3000';

  AuthApiService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.baseUrl = _baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 5);
    _dio.options.receiveTimeout = const Duration(seconds: 5);
  }

  /// Fetches the rotating development Curve25519 public key from the backend.
  /// Expected response: { "publicKey": "base64_encoded_key" }
  Future<Uint8List> fetchPublicKey() async {
    try {
      final response = await _dio.get('/dev/public-key');
      final keyString = response.data['publicKey'] as String;
      final normalizedKey = base64Url.normalize(keyString);
      return base64Url.decode(normalizedKey);
    } catch (e) {
      throw Exception('Failed to fetch public key: $e');
    }
  }

  /// Registers the vault with the backend.
  /// Expected response: { "userId": "..." }
  Future<String> registerVault({
    required String vaultClientKey,
    required String duressClientKey,
    required String recoveryClientKey,
    required String deviceFingerprint,
    required String sealedCredentials,
    required String pinWrappedMsk,
    required String phraseWrappedMsk,
    required String publicKey,
    required String encryptedIdentityPrivateKey,
  }) async {
    try {
      final response = await _dio.post('/auth/register', data: {
        'vaultClientKey': vaultClientKey,
        'duressClientKey': duressClientKey,
        'recoveryClientKey': recoveryClientKey,
        'deviceFingerprint': deviceFingerprint,
        'sealedCredentials': sealedCredentials,
        'pinWrappedMsk': pinWrappedMsk,
        'phraseWrappedMsk': phraseWrappedMsk,
        'publicKey': publicKey,
        'encryptedIdentityPrivateKey': encryptedIdentityPrivateKey,
      });
      return response.data['userId'] as String;
    } catch (e) {
      throw Exception('Failed to register vault: $e');
    }
  }


  /// Logs into the vault.
  /// Expected response: { "sessionType": "vault" | "duress" | "recovery", "token": "..." }
  Future<Map<String, dynamic>> login({
    required String userId,
    required String clientKey,
    required String deviceFingerprint,
  }) async {
    try {
      final response = await _dio.post('/auth/login', data: {
        'userId': userId,
        'clientKey': clientKey,
        'deviceFingerprint': deviceFingerprint,
      });
      return {
        'sessionType': response.data['sessionType'] as String,
        'token': response.data['sessionToken'] as String,
        'refreshToken': response.data['refreshToken'] as String?,
        'reauthGracePeriodSeconds': response.data['reauthGracePeriodSeconds'] as int?,
        'encryptedIdentityPrivateKey': response.data['encryptedIdentityPrivateKey'] as String?,
      };
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('Unauthorized');
      } else if (e.response?.statusCode == 429) {
        throw Exception('RateLimitExceeded');
      }
      throw Exception('Login failed: $e');
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  /// Fetches the wrapped MSK blobs.
  Future<Map<String, String>> fetchMsk({required String token}) async {
    try {
      final response = await _dio.get('/auth/msk', options: Options(headers: {'Authorization': 'Bearer $token'}));
      return {
        'pinWrappedMsk': response.data['pinWrappedMsk'] as String,
        'phraseWrappedMsk': response.data['phraseWrappedMsk'] as String,
      };
    } catch (e) {
      throw Exception('Failed to fetch MSK: $e');
    }
  }

  /// Updates the PIN wrapped MSK.
  Future<bool> updateMsk({required String token, required String newPinWrappedMsk}) async {
    try {
      await _dio.post('/auth/msk/update-pin',
          data: {'pinWrappedMsk': newPinWrappedMsk},
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Fetches the escrowed conversation keys.
  Future<List<dynamic>> fetchEscrowedKeys({required String token}) async {
    try {
      final response = await _dio.get('/conversations/escrow',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      return (response.data['escrows'] ?? []) as List<dynamic>;
    } catch (e) {
      throw Exception('Failed to fetch escrowed keys: $e');
    }
  }

  /// Creates a new PENDING conversation on the server.
  Future<Map<String, dynamic>> createConversation({
    required String token,
    required String recipientUserId,
    required String invitationMessage,
  }) async {
    try {
      final response = await _dio.post(
        '/conversations',
        data: {
          'recipientUserId': recipientUserId,
          'invitationMessage': invitationMessage,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to create conversation: $e');
    }
  }

  /// Fetches pending conversations for the authenticated user.
  Future<List<dynamic>> fetchPendingConversations({required String token}) async {
    try {
      final response = await _dio.get(
        '/conversations/pending',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.data is List) {
        return response.data as List<dynamic>;
      } else if (response.data is Map && response.data['pending'] is List) {
        return response.data['pending'] as List<dynamic>;
      }
      return [];
    } catch (e) {
      throw Exception('Failed to fetch pending conversations: $e');
    }
  }

  /// Joins an existing pending conversation.
  Future<bool> joinConversation({
    required String token,
    required String conversationId,
    required String conversationKey,
  }) async {
    try {
      final response = await _dio.post(
        '/conversations/$conversationId/join',
        data: {'conversationKey': conversationKey},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.statusCode == 200;
    } catch (e) {
      throw Exception('Failed to join conversation: $e');
    }
  }

  /// Escrows an encrypted conversation key to the backend.
  Future<bool> escrowConversationKey({
    required String token,
    required String conversationId,
    required String encryptedConversationKey,
    String? localAlias,
  }) async {
    try {
      final response = await _dio.post(
        '/conversations/escrow',
        data: {
          'conversationId': conversationId,
          'encryptedConversationKey': encryptedConversationKey,
          'localAlias': localAlias,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.statusCode == 201;
    } catch (e) {
      throw Exception('Failed to escrow conversation key: $e');
    }
  }

  /// Re-authenticates the session using the current PIN's client key.
  Future<Map<String, dynamic>> reauth({
    required String sessionToken,
    required String clientKey,
  }) async {
    try {
      final response = await _dio.post('/auth/reauth', data: {
        'sessionToken': sessionToken,
        'clientKey': clientKey,
      });
      return response.data as Map<String, dynamic>;
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        throw Exception('Unauthorized');
      } else if (e is DioException && e.response?.statusCode == 423) {
        throw Exception('LockedOut');
      }
      throw Exception('Reauth failed: $e');
    }
  }

  /// Rotates the Vault PIN on the backend.
  Future<bool> changePin({
    required String token,
    required String currentClientKey,
    required String newClientKey,
  }) async {
    try {
      await _dio.post(
        '/auth/pin/change',
        data: {
          'currentClientKey': currentClientKey,
          'newClientKey': newClientKey,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Rotates the Duress PIN on the backend.
  Future<bool> changeDuressPin({
    required String token,
    required String currentClientKey,
    required String newDuressClientKey,
  }) async {
    try {
      await _dio.post(
        '/auth/duress-pin/change',
        data: {
          'currentClientKey': currentClientKey,
          'newDuressClientKey': newDuressClientKey,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Checks if a user exists in the backend by attempting to hit their shadow document.
  Future<bool> checkUserExists(String userId) async {
    try {
      final response = await _dio.get('/dev/shadow/$userId');
      return response.statusCode == 200;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Fetches a partner user's public X25519 identity key (syncProfileId) from the backend.
  Future<String> fetchPartnerPublicKey(String userId) async {
    try {
      final response = await _dio.get('/auth/users/$userId/public-key');
      return response.data['publicKey'] as String;
    } catch (e) {
      throw Exception('Failed to fetch partner public key: $e');
    }
  }

  /// Fetches active and pending conversations for the authenticated user.
  Future<List<dynamic>> fetchConversations({required String token}) async {
    try {
      final response = await _dio.get(
        '/conversations',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (response.data['conversations'] ?? []) as List<dynamic>;
    } catch (e) {
      throw Exception('Failed to fetch conversations: $e');
    }
  }
}

