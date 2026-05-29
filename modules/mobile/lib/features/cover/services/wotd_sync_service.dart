import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

class WordOfDay {
  final String word;
  final String translation;
  final String definition;

  WordOfDay({
    required this.word,
    required this.translation,
    required this.definition,
  });

  factory WordOfDay.fromJson(Map<String, dynamic> json) {
    return WordOfDay(
      word: json['word'] ?? '',
      translation: json['translation'] ?? '',
      definition: json['definition'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'word': word,
    'translation': translation,
    'definition': definition,
  };
}

class WotdSyncService {
  final Dio _dio;
  final AssetBundle _assetBundle;
  final String baseUrl;

  WotdSyncService({
    Dio? dio,
    AssetBundle? assetBundle,
    this.baseUrl = 'http://localhost:5000',
  })  : _dio = dio ?? Dio(),
        _assetBundle = assetBundle ?? rootBundle {
    _dio.options.connectTimeout = const Duration(seconds: 3);
    _dio.options.receiveTimeout = const Duration(seconds: 3);
    _dio.options.sendTimeout = const Duration(seconds: 3);
  }

  Future<WordOfDay> fetchWotd() async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/decoy/wotd',
        options: Options(
          receiveTimeout: const Duration(seconds: 3),
          sendTimeout: const Duration(seconds: 3),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final Map<String, dynamic> jsonMap = data is String ? jsonDecode(data) : data;
        return WordOfDay.fromJson(jsonMap);
      }
      throw DioException(requestOptions: RequestOptions(path: ''));
    } catch (e) {
      return await _fallbackWotd();
    }
  }

  Future<WordOfDay> _fallbackWotd() async {
    try {
      final jsonString = await _assetBundle.loadString('assets/words.json');
      final List<dynamic> wordsList = jsonDecode(jsonString);
      
      if (wordsList.isNotEmpty) {
        final daysSinceEpoch = DateTime.now().millisecondsSinceEpoch ~/ 86400000;
        final index = daysSinceEpoch % wordsList.length;
        final Map<String, dynamic> wordJson = wordsList[index];
        return WordOfDay.fromJson(wordJson);
      }
    } catch (_) {
      // Fallback fallback to protect against malformed JSON or loading errors
    }
    
    // Default fallback word
    return WordOfDay(
      word: 'welcome',
      translation: 'bienvenido',
      definition: 'Used to greet someone in a polite or friendly way.',
    );
  }
}
