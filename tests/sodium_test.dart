import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sodium/flutter_sodium.dart';

void main() {
  test('Sodium initialization and randombytes test', () async {
    // If this fails with FFI/MissingPluginException, we must mock KdfService
    await Sodium.init();
    final salt = Sodium.randombytes(16);
    expect(salt.length, 16);
    print("Sodium native bindings are working locally!");
  });
}
