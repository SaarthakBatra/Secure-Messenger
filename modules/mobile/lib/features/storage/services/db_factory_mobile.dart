import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

void initDbFactory() {
  // sqflite handles its own initialization on mobile.
}

Future<sqflite.Database> openDb(String path, {required int version, required sqflite.OnDatabaseCreateFn onCreate, String? password}) async {
  if (Platform.isLinux || Platform.isWindows) {
    debugPrint('[STORAGE] Desktop platform detected. Opening standard SQLite database without SQLCipher.');
    return await sqflite.openDatabase(
      path,
      version: version,
      onCreate: onCreate,
    );
  } else {
    debugPrint('[STORAGE] Mobile platform detected. Opening encrypted database with SQLCipher.');
    final db = await sqlcipher.openDatabase(
      path,
      version: version,
      onCreate: (db, version) async {
        await onCreate(db as sqflite.Database, version);
      },
      password: password,
    );
    return db as sqflite.Database;
  }
}
