import 'dart:convert';
import 'dart:typed_data';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:flutter/foundation.dart';
import '../../security/services/sodium_crypto_service.dart';
import 'profile_helper.dart';
import 'db_factory.dart' as db_factory;

class VaultDbService {
  static final VaultDbService instance = VaultDbService._init();
  static sqflite.Database? _database;

  VaultDbService._init();

  Future<sqflite.Database> get database async {
    if (_database != null) return _database!;
    throw StateError('[STORAGE] Database is not open. Call getDatabase(msk) first.');
  }

  Future<sqflite.Database> getDatabase([Uint8List? msk]) async {
    if (_database != null) return _database!;
    if (msk == null) {
      throw StateError('[STORAGE] Database is not initialized and no TranslationCacheConfig (MSK) was provided.');
    }
    _database = await _initDB('conversations.db', msk);
    return _database!;
  }

  Future<sqflite.Database> _initDB(String filePath, Uint8List msk) async {
    final dbPath = await sqflite.getDatabasesPath();
    final profile = getProfile();
    final path = profile != null && profile.isNotEmpty
        ? join(dbPath, 'profile_$profile', filePath)
        : join(dbPath, filePath);
    
    final password = base64.encode(msk);

    return await db_factory.openDb(
      path,
      version: 1,
      onCreate: _createDB,
      password: password,
    );
  }

  Future _createDB(sqflite.Database db, int version) async {
    debugPrint('[STORAGE] Creating database tables...');
    await db.execute('''
      CREATE TABLE conversations (
        conversation_id TEXT PRIMARY KEY,
        local_alias TEXT,
        conversation_key TEXT,
        admin_user_id TEXT,
        status TEXT,
        partner_username TEXT,
        created_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        message_id TEXT PRIMARY KEY,
        conversation_id TEXT,
        sender_id TEXT,
        encrypted_payload TEXT,
        timestamp INTEGER,
        delivery_status TEXT,
        chapter_hash TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_messages_convo ON messages(conversation_id)');
    await db.execute('CREATE INDEX idx_messages_chapter ON messages(chapter_hash)');

    await db.execute('''
      CREATE TABLE cached_chapters (
        chapter_hash TEXT PRIMARY KEY,
        conversation_id TEXT,
        previous_chapter_hash TEXT,
        created_at INTEGER
      )
    ''');
    await db.execute('CREATE INDEX idx_chapters_convo ON cached_chapters(conversation_id)');

    await db.execute('''
      CREATE TABLE active_page_metadata (
        conversation_id TEXT PRIMARY KEY,
        local_updated_at INTEGER
      )
    ''');
  }

  Future<void> storeConversationKey(
    String conversationId,
    String plaintextKey,
    Uint8List msk, {
    String? localAlias,
    String? status,
  }) async {
    final db = await getDatabase(msk);
    final encryptedKey = SodiumCryptoService.encryptSymmetric(plaintextKey, msk);
    
    String? encryptedAlias;
    if (localAlias != null) {
      encryptedAlias = SodiumCryptoService.encryptSymmetric(localAlias, msk);
    }
    
    await db.insert(
      'conversations',
      {
        'conversation_id': conversationId,
        'conversation_key': encryptedKey,
        'local_alias': encryptedAlias,
        'status': status ?? 'PENDING',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
    debugPrint('[STORAGE] Stored escrowed key for $conversationId');
  }

  Future<String?> getConversationKey(String conversationId, Uint8List msk) async {
    final db = await getDatabase(msk);
    final maps = await db.query(
      'conversations',
      columns: ['conversation_key'],
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );

    if (maps.isNotEmpty) {
      final encrypted = maps.first['conversation_key'] as String?;
      if (encrypted != null) {
        return SodiumCryptoService.decryptSymmetric(encrypted, msk);
      }
    }
    return null;
  }

  Future<void> wipeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    final dbPath = await sqflite.getDatabasesPath();
    final profile = getProfile();
    final path = profile != null && profile.isNotEmpty
        ? join(dbPath, 'profile_$profile', 'conversations.db')
        : join(dbPath, 'conversations.db');
    await sqflite.deleteDatabase(path);
    debugPrint('[STORAGE] Database file deleted completely.');
  }
}
