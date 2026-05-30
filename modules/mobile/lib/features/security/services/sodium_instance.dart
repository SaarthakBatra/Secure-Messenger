import 'package:sodium_libs/sodium_libs.dart';

class SodiumInstance {
  static late final Sodium sodium;

  static Future<void> init() async {
    sodium = await SodiumInit.init();
  }
}
