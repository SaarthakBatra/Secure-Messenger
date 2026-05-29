# Phase A: Data Services (Asset Parsing & Sync) - Detailed Implementation Plan

This document details the exact class designs, API specifications, and testing strategies for **Phase A: Data Services (Asset Parsing & Sync)**. 

---

## 1. Feature Specifications

### Feature A.1: Translation Sync Service (`translation_sync_service.dart`)
- **Objective**: Translate inputs from one language to another using a free public API when online, falling back to a local JSON dictionary when offline.
- **Online Target API**: MyMemory API (`https://api.mymemory.translated.net/get?q={text}&langpair={from}|{to}`)
  - **Method**: GET
  - **Success Response Structure**:
    ```json
    {
      "responseData": {
        "translatedText": "Hola",
        "match": 1
      },
      "responseStatus": 200
    }
    ```
- **Offline Fallback Asset**: `assets/dictionary.json`
  - **Path**: `modules/mobile/assets/dictionary.json`
  - **JSON Schema**: A simple flat key-value map mapping lowercase source language words to target language words.
    ```json
    {
      "apple": "manzana",
      "hello": "hola",
      "world": "mundo",
      "dog": "perro"
    }
    ```
- **Fallback Logic**: 
  1. Catch all exceptions from the Dio call (timeouts, network unreachable, invalid response status code).
  2. Parse the local `assets/dictionary.json` asset using `rootBundle.loadString`.
  3. Perform a fast, case-insensitive lookup:
     - Check for exact match of lowercase word.
     - If not found, perform a substring match across keys (case-insensitive) and return the first matching entry.
     - If still not found, return the query string unchanged (standard translation fallback).

---

### Feature A.2: Word of the Day Sync Service (`wotd_sync_service.dart`)
- **Objective**: Fetch a daily word with its translation and definition from the decoy backend API, falling back to a local JSON wordlist if the API is offline.
- **Online Target Endpoint**: `/api/decoy/wotd` (using a base URL configured in Dio, defaulting to `http://localhost:5000` or whatever the backend environment runs on).
  - **Method**: GET
  - **Success Response Structure**:
    ```json
    {
      "word": "apple",
      "translation": "manzana",
      "definition": "A round fruit with red, green, or yellow skin."
    }
    ```
- **Offline Fallback Asset**: `assets/words.json`
  - **Path**: `modules/mobile/assets/words.json`
  - **JSON Schema**: An array of word objects.
    ```json
    [
      {
        "word": "apple",
        "translation": "manzana",
        "definition": "A round fruit with red, green, or yellow skin."
      },
      {
        "word": "banana",
        "translation": "plátano",
        "definition": "A long curved fruit which grows in clusters and has soft pulpy flesh and yellow skin."
      }
    ]
    ```
- **Fallback Logic**:
  1. Catch all exceptions from the Dio call.
  2. Parse the local `assets/words.json` asset using `rootBundle.loadString`.
  3. Calculate a daily index using: `(DateTime.now().millisecondsSinceEpoch ~/ 86400000) % listLength`.
  4. Return the word object at that index. If the array is empty, return a default hardcoded word to ensure zero crashes.

---

## 2. Class Signatures & Implementation Details

### `translation_sync_service.dart`
```dart
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
        _assetBundle = assetBundle ?? rootBundle;

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
        // Handle both parsed map and raw string
        final Map<String, dynamic> jsonMap = data is String ? jsonDecode(data) : data;
        if (jsonMap.containsKey('responseData')) {
          final translated = jsonMap['responseData']['translatedText'];
          if (translated != null && translated.toString().isNotEmpty) {
            return translated.toString();
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
        if (entry.key.contains(queryLower) || queryLower.contains(entry.key)) {
          return entry.value.toString();
        }
      }
    } catch (_) {
      // Fallback fallback to protect against malformed JSON or loading errors
    }
    return text; // Return query string as default fallback
  }
}
```

### `wotd_sync_service.dart`
```dart
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
        _assetBundle = assetBundle ?? rootBundle;

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
    
    // Solid fallback object to prevent crashing
    return WordOfDay(
      word: 'welcome',
      translation: 'bienvenido',
      definition: 'Used to greet someone in a polite or friendly way.',
    );
  }
}
```

---

## 3. Rigorous Testing Strategy (`services_test.dart`)

We will write a comprehensive unit test suite in `tests/mobile/cover/services_test.dart` that tests all normal flows and edge cases in isolation by mocking the dependencies:
- **MockDio**: Mocking GET requests using custom adapters or mock implementations to trigger success/failure/timeout cases.
- **MockAssetBundle**: Mocking `rootBundle` to load pre-defined JSON dictionaries/wordlists, including malformed JSON.

### Tests Checklist
1. **Translation Service**:
   - *Normal Flow*: Remote API returns 200 OK translation. Ensure translation service parses and returns the result.
   - *Edge Case - Network Timeout / Offline*: Dio throws an exception. Ensure service queries the mock AssetBundle and correctly finds:
     - Exact match (e.g. "dog" -> "perro").
     - Partial substring match (e.g. "do" or "dogs" matches "dog").
     - Case insensitivity (e.g. "DOG" -> "perro").
   - *Edge Case - Malformed Local Asset*: Local JSON is malformed. Ensure service handles the parsing error and safely returns the input text as fallback.

2. **WOTD Service**:
   - *Normal Flow*: Remote decoy endpoint returns 200 OK with custom word. Ensure it's correctly mapped to a `WordOfDay` instance.
   - *Edge Case - Network Timeout / Offline*: Dio throws exception. Ensure it reads local words and:
     - Selects a stable index based on day modulo.
     - Gracefully falls back to hardcoded default word if local file is missing, empty, or malformed.
