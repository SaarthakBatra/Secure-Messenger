import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter/foundation.dart';

void initDbFactory() {
  databaseFactory = databaseFactoryFfiWeb;
}

Future<Database> openDb(String path, {required int version, required OnDatabaseCreateFn onCreate, String? password}) async {
  debugPrint('[STORAGE] Web platform detected. Opening database using FFI Web (IndexedDB). Password ignored.');
  final factory = databaseFactoryFfiWeb;
  return await factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onCreate: onCreate,
    ),
  );
}
