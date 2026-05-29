import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

class TranslationSyncService {
  final Dio _dio;
  final AssetBundle _assetBundle;

  TranslationSyncService({
    Dio? dio,
    AssetBundle? assetBundle,
  })  : _dio = dio ?? Dio(),
        _assetBundle = assetBundle ?? rootBundle {
    _dio.options.connectTimeout = const Duration(seconds: 3);
    _dio.options.receiveTimeout = const Duration(seconds: 3);
    _dio.options.sendTimeout = const Duration(seconds: 3);
  }

  Future<String> translate(String text, {required String from, required String to}) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return "";

    try {
      final response = await _dio.get(
        'https://api.mymemory.translated.net/get',
        queryParameters: {
          'q': cleanText,
          'langpair': '$from|$to',
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 3),
          sendTimeout: const Duration(seconds: 3),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final Map<String, dynamic> jsonMap = data is String ? jsonDecode(data) : data;
        if (jsonMap.containsKey('responseData')) {
          final responseData = jsonMap['responseData'];
          if (responseData is Map<String, dynamic>) {
            final translated = responseData['translatedText'];
            if (translated != null && translated.toString().isNotEmpty) {
              return translated.toString();
            }
          }
        }
      }
      throw DioException(requestOptions: RequestOptions(path: ''));
    } catch (e) {
      // Offline fallback
      return await _fallbackTranslate(cleanText);
    }
  }

  Future<String> _fallbackTranslate(String text) async {
    try {
      final jsonString = await _assetBundle.loadString('assets/dictionary.json');
      final Map<String, dynamic> dictionary = jsonDecode(jsonString);
      
      final queryLower = text.toLowerCase();
      
      // 1. Exact match
      if (dictionary.containsKey(queryLower)) {
        return dictionary[queryLower]!.toString();
      }
      
      // 2. Substring match (case-insensitive)
      for (final entry in dictionary.entries) {
        if (entry.key.toLowerCase().contains(queryLower) || queryLower.contains(entry.key.toLowerCase())) {
          return entry.value.toString();
        }
      }
    } catch (_) {
      // Fallback fallback to protect against malformed JSON or loading errors
    }
    return text; // Return query string as default fallback
  }
}
