import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LanguageData {
  final String code;
  final String name;
  final String flag;
  LanguageData({required this.code, required this.name, required this.flag});
  
  factory LanguageData.fromJson(Map<String, dynamic> json) {
    return LanguageData(
      code: json['code'] as String,
      name: json['name'] as String,
      flag: json['flag'] as String,
    );
  }
}

final languagesProvider = FutureProvider<List<LanguageData>>((ref) async {
  final jsonString = await rootBundle.loadString('assets/languages_data.json');
  final List<dynamic> jsonList = jsonDecode(jsonString);
  return jsonList.map((e) => LanguageData.fromJson(e)).toList();
});

final targetLanguageProvider = StateProvider<String>((ref) => 'es');
