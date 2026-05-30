import 'package:sqflite/sqflite.dart';

void initDbFactory() {}

Future<Database> openDb(String path, {required int version, required OnDatabaseCreateFn onCreate, String? password}) async {
  throw UnimplementedError();
}
