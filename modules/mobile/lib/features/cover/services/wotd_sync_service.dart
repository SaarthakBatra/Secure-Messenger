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

  Future<WordOfDay> fetchWotd(String langCode) async {
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
      return await _fallbackWotd(langCode);
    }
  }

  Future<WordOfDay> _fallbackWotd(String langCode) async {
    final Map<String, Map<String, String>> mockWotd = {
      'es': {'word': 'apple', 'translation': 'manzana', 'definition': 'A round fruit.'},
      'fr': {'word': 'apple', 'translation': 'pomme', 'definition': 'A round fruit.'},
      'ja': {'word': 'apple', 'translation': 'りんご (Ringo)', 'definition': 'A round fruit.'},
      'de': {'word': 'apple', 'translation': 'Apfel', 'definition': 'A round fruit.'},
      'it': {'word': 'apple', 'translation': 'mela', 'definition': 'A round fruit.'},
    };
    final data = mockWotd[langCode] ?? mockWotd['es']!;
    return WordOfDay(
      word: data['word']!,
      translation: data['translation']!,
      definition: data['definition']!,
    );
  }
}
