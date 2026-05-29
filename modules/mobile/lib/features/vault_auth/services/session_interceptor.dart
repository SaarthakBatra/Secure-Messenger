import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../cover/providers/streak_provider.dart';
import '../../../main.dart'; // To access providers
import '../../../app/router/app_router.dart';
import '../../storage/services/vault_db_service.dart';

class SessionInterceptor extends QueuedInterceptor {
  final ProviderRef ref;
  final Dio dio;
  
  SessionInterceptor({required this.ref, required this.dio});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = ref.read(vaultSessionNotifierProvider).token;
    if (token != null && !options.headers.containsKey('Authorization')) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;
    final errorCode = err.response?.data?['code'] as String?;

    if (statusCode == 401) {
      if (errorCode == 'REFRESH_EXPIRED') {
        debugPrint('[INTERCEPTOR] 401 REFRESH_EXPIRED. Attempting background refresh...');
        try {
          final sessionNotifier = ref.read(vaultSessionNotifierProvider);
          final refreshToken = sessionNotifier.refreshToken;
          if (refreshToken == null) {
            throw Exception('No refresh token available');
          }

          // Use a clean Dio instance to avoid interceptor loops
          final cleanDio = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
          final refreshResponse = await cleanDio.post(
            '/auth/refresh',
            data: {
              'sessionToken': sessionNotifier.token,
              'refreshToken': refreshToken,
            },
          );

          final newRefreshToken = refreshResponse.data['refreshToken'] as String?;
          final currentSessionToken = sessionNotifier.token;
          
          sessionNotifier.setSession(
            sessionNotifier.sessionType,
            token: currentSessionToken,
            refreshToken: newRefreshToken,
          );

          debugPrint('[INTERCEPTOR] Background refresh successful. Retrying original request.');
          
          // Retry the original request
          final retryOptions = err.requestOptions;
          retryOptions.headers['Authorization'] = 'Bearer $currentSessionToken';
          final retryResponse = await cleanDio.fetch(retryOptions);
          return handler.resolve(retryResponse);
          
        } on DioException catch (refreshErr) {
          if (refreshErr.response?.statusCode == 403 && refreshErr.response?.data?['code'] == 'HACK_DETECTED') {
             await _triggerBurnProtocol();
             return handler.resolve(
               Response(
                 requestOptions: err.requestOptions,
                 statusCode: 200,
                 data: {'status': 'success', 'message': 'Burn executed silently'},
               ),
             );
          } else {
             _triggerEjection();
          }
          return handler.next(err); // Fail original request
        } catch (e) {
          _triggerEjection();
          return handler.next(err);
        }
      } else if (errorCode == 'SESSION_EXPIRED') {
        debugPrint('[INTERCEPTOR] 401 SESSION_EXPIRED. Triggering Re-Auth Overlay...');
        
        final sessionNotifier = ref.read(vaultSessionNotifierProvider);
        final completer = Completer<bool>();
        
        // Trigger the UI overlay
        ref.read(isReauthOverlayActiveProvider.notifier).state = completer;
        
        final success = await completer.future;
        
        // Clear the overlay state
        ref.read(isReauthOverlayActiveProvider.notifier).state = null;

        if (success) {
          debugPrint('[INTERCEPTOR] Re-Auth successful. Retrying original request.');
          final newToken = sessionNotifier.token; // Overlay should have updated this
          final retryOptions = err.requestOptions;
          retryOptions.headers['Authorization'] = 'Bearer $newToken';
          
          try {
            final cleanDio = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
            final retryResponse = await cleanDio.fetch(retryOptions);
            return handler.resolve(retryResponse);
          } catch (retryErr) {
            if (retryErr is DioException) return handler.next(retryErr);
            return handler.next(err);
          }
        } else {
          debugPrint('[INTERCEPTOR] Re-Auth failed or dismissed. Ejecting.');
          _triggerEjection();
          return handler.next(err);
        }
      }
    } else if (statusCode == 403 && errorCode == 'HACK_DETECTED') {
      debugPrint('[INTERCEPTOR] 403 HACK_DETECTED. Burn Protocol initiated.');
      await _triggerBurnProtocol();
      return handler.resolve(
        Response(
          requestOptions: err.requestOptions,
          statusCode: 200,
          data: {'status': 'success', 'message': 'Burn executed silently'},
        ),
      );
    } else if (statusCode == 423) {
      debugPrint('[INTERCEPTOR] 423 Account Lockout. Wiping local state silently...');
      await _triggerBurnProtocol();
      return handler.resolve(
        Response(
          requestOptions: err.requestOptions,
          statusCode: 200,
          data: {'status': 'success', 'message': 'Lockout handled silently'},
        ),
      );
    }
    
    // For any other error, just pass it along
    return handler.next(err);
  }

  Future<void> _triggerBurnProtocol() async {
    debugPrint('[BURN PROTOCOL] EXECUTING ACTIVE BURN PROTOCOL!');
    try {
      await VaultDbService.instance.wipeDatabase();
      SharedPreferences prefs;
      try {
        prefs = ref.read(sharedPrefsProvider);
      } catch (_) {
        prefs = await SharedPreferences.getInstance();
      }
      await prefs.setBool('vault_burned', true);
      await prefs.remove('vault_is_configured');
      await prefs.remove('user_id');
      await prefs.remove('recovery_phrase_words');
      await prefs.remove('wrong_pin_attempts');
      
      ref.read(vaultBurnedProvider.notifier).state = true;
      ref.read(vaultConfiguredProvider.notifier).state = false;
      
      _triggerEjection();
    } catch (e) {
      debugPrint('[BURN PROTOCOL] Failed to execute burn: $e');
      _triggerEjection();
    }
  }

  void _triggerEjection() {
    ref.read(vaultSessionNotifierProvider).setSession(null);
    ref.read(appRouterProvider).go('/home');
  }
}
