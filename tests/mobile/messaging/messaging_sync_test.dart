import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/features/storage/services/vault_db_service.dart';
import 'package:mobile/features/messaging/services/message_crypto_service.dart';
import 'package:mobile/features/messaging/services/websocket_service.dart';
import 'package:mobile/features/messaging/services/active_page_sync_service.dart';
import 'package:mobile/features/messaging/services/hashing_alignment_service.dart';
import 'package:mobile/features/messaging/services/archiver_service.dart';
import 'package:mobile/features/messaging/services/lazy_loading_service.dart';
import 'package:mobile/features/vault_auth/providers/setup_wizard_provider.dart';
import 'package:mobile/app/router/app_router.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock SQLCipher Method Channel
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.davidmartos96.sqflite_sqlcipher'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'getDatabasesPath') {
        return '.';
      }
      return null;
    },
  );

  group('Phase 3b Mobile Messaging Cryptography Tests', () {
    late Uint8List dummyMsk;
    late String dummyLessonKeyHex;

    setUp(() {
      dummyMsk = Uint8List.fromList(List.generate(32, (i) => i));
      dummyLessonKeyHex = MessageCryptoService.hexEncode(
        Uint8List.fromList(List.generate(32, (i) => i + 10)),
      );
    });

    test('Should encrypt and decrypt individual messages using derived subkey (AES-256-GCM)', () {
      const plaintext = '{"content":"Secret Message","hash":"some_hash"}';
      const conversationId = 'convo123';
      const messageId = 'msg456';

      final encrypted = MessageCryptoService.encryptMessage(
        lessonKeyHex: dummyLessonKeyHex,
        plaintext: plaintext,
        conversationId: conversationId,
        messageId: messageId,
      );

      expect(encrypted, isNotNull);
      expect(encrypted, isNot(equals(plaintext)));

      final decrypted = MessageCryptoService.decryptMessage(
        lessonKeyHex: dummyLessonKeyHex,
        base64Payload: encrypted,
        conversationId: conversationId,
        messageId: messageId,
      );

      expect(decrypted, equals(plaintext));
    });

    test('Should return null on decryption failure (E11)', () {
      const conversationId = 'convo123';
      const messageId = 'msg456';

      final decrypted = MessageCryptoService.decryptMessage(
        lessonKeyHex: dummyLessonKeyHex,
        base64Payload: base64Encode(Uint8List(30)), // corrupt block
        conversationId: conversationId,
        messageId: messageId,
      );

      expect(decrypted, isNull);
    });

    test('Should zero memory of sensitive keys', () {
      final key = Uint8List.fromList([1, 2, 3, 4]);
      MessageCryptoService.zeroMemory(key);
      expect(key, equals(Uint8List.fromList([0, 0, 0, 0])));
    });
  });

  group('Phase 3b Active Page Sync & Conflict Resolution Tests', () {
    late ProviderContainer container;
    late Uint8List msk;
    late String lessonKeyHex;
    const conversationId = 'convo789';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      msk = Uint8List.fromList(List.generate(32, (i) => i));
      lessonKeyHex = MessageCryptoService.hexEncode(msk);

      // Open database
      await VaultDbService.instance.wipeDatabase();
      await VaultDbService.instance.getDatabase(msk);
      await VaultDbService.instance.storeConversationKey(conversationId, lessonKeyHex, msk);
    });

    tearDown(() async {
      await VaultDbService.instance.wipeDatabase();
    });

    test('Case 2: Client Newer should upload local active page backup', () async {
      final db = await VaultDbService.instance.database;
      
      // Setup local mock data
      await db.insert('messages', {
        'message_id': 'm1',
        'conversation_id': conversationId,
        'sender_id': 'alice',
        'encrypted_payload': 'enc1',
        'timestamp': 1000,
        'delivery_status': 'sent',
      });
      await db.insert('active_page_metadata', {
        'conversation_id': conversationId,
        'local_updated_at': 2000,
      });

      var uploadCalled = false;

      container = ProviderContainer(
        overrides: [
          mockNetworkResponseProvider.overrideWith((ref) => {
            'statusCode': 200,
            'data': {
              'encryptedActivePage': 'old_server_page',
              'updatedAt': DateTime.fromMillisecondsSinceEpoch(500).toUtc().toIso8601String(),
            }
          }),
        ],
      );

      final syncService = container.read(activePageSyncServiceProvider);

      // Override dio adapter to capture the subsequent POST upload request
      final dio = container.read(dioProvider);
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'POST' && options.path.contains('/active-page')) {
            uploadCalled = true;
            handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'success': true},
            ));
            return;
          }
          handler.next(options);
        },
      ));

      await syncService.syncActivePage(conversationId, msk);

      expect(uploadCalled, isTrue);
    });
  });

  group('Phase 3b Hash Alignment & Canonical Hashing Tests', () {
    late Uint8List msk;
    late String lessonKeyHex;
    const conversationId = 'convoHash';

    setUp(() async {
      msk = Uint8List.fromList(List.generate(32, (i) => i));
      lessonKeyHex = MessageCryptoService.hexEncode(msk);

      await VaultDbService.instance.wipeDatabase();
      await VaultDbService.instance.getDatabase(msk);
      await VaultDbService.instance.storeConversationKey(conversationId, lessonKeyHex, msk);
    });

    tearDown(() async {
      await VaultDbService.instance.wipeDatabase();
    });

    test('Should sort active messages and build consistent activePageHash', () async {
      final db = await VaultDbService.instance.database;

      final encryptedMsg1 = MessageCryptoService.encryptMessage(
        lessonKeyHex: lessonKeyHex,
        plaintext: jsonEncode({'content': 'First', 'hash': ''}),
        conversationId: conversationId,
        messageId: 'm1',
      );

      final encryptedMsg2 = MessageCryptoService.encryptMessage(
        lessonKeyHex: lessonKeyHex,
        plaintext: jsonEncode({'content': 'Second', 'hash': ''}),
        conversationId: conversationId,
        messageId: 'm2',
      );

      // Insert in reverse order to ensure sorting logic takes place
      await db.insert('messages', {
        'message_id': 'm2',
        'conversation_id': conversationId,
        'sender_id': 'alice',
        'encrypted_payload': encryptedMsg2,
        'timestamp': 2000,
      });

      await db.insert('messages', {
        'message_id': 'm1',
        'conversation_id': conversationId,
        'sender_id': 'alice',
        'encrypted_payload': encryptedMsg1,
        'timestamp': 1000,
      });

      final hash = await HashingAlignmentService.computeActivePageHash(conversationId, msk);
      expect(hash, isNotEmpty);
      expect(hash.length, equals(64)); // Hex string of SHA-256
    });
  });

  group('Phase 3b Archiver and Lazy Loading Tests', () {
    late ProviderContainer container;
    late Uint8List msk;
    late String lessonKeyHex;
    const conversationId = 'convoArch';

    setUp(() async {
      msk = Uint8List.fromList(List.generate(32, (i) => i));
      lessonKeyHex = MessageCryptoService.hexEncode(msk);

      await VaultDbService.instance.wipeDatabase();
      await VaultDbService.instance.getDatabase(msk);
      await VaultDbService.instance.storeConversationKey(conversationId, lessonKeyHex, msk);
    });

    tearDown(() async {
      await VaultDbService.instance.wipeDatabase();
    });

    test('SQLite Cache Constraint: should purge oldest cached chapter when limit (2) is exceeded', () async {
      final db = await VaultDbService.instance.database;

      // Populate 3 chapters manually to exceed the cache limit
      await db.insert('cached_chapters', {
        'chapter_hash': 'ch1',
        'conversation_id': conversationId,
        'previous_chapter_hash': 'ch0',
        'created_at': 100, // Oldest
      });
      await db.insert('cached_chapters', {
        'chapter_hash': 'ch2',
        'conversation_id': conversationId,
        'previous_chapter_hash': 'ch1',
        'created_at': 200,
      });
      await db.insert('cached_chapters', {
        'chapter_hash': 'ch3',
        'conversation_id': conversationId,
        'previous_chapter_hash': 'ch2',
        'created_at': 300,
      });

      // Associated messages
      await db.insert('messages', {
        'message_id': 'msg_ch1',
        'conversation_id': conversationId,
        'sender_id': 'alice',
        'encrypted_payload': 'payload1',
        'timestamp': 1000,
        'chapter_hash': 'ch1',
      });
      await db.insert('messages', {
        'message_id': 'msg_ch3',
        'conversation_id': conversationId,
        'sender_id': 'bob',
        'encrypted_payload': 'payload3',
        'timestamp': 3000,
        'chapter_hash': 'ch3',
      });

      // Setup LazyLoadingService
      container = ProviderContainer();
      final lazyService = container.read(lazyLoadingServiceProvider);

      // Trigger cache purge by fetching previous chapter (simulated download fallback response will trigger chapters limit cleanup)
      final dio = container.read(dioProvider);
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.contains('/download-chapter-url') || options.path.contains('/latest-chapter')) {
            handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'downloadUrl': 'https://mock-r2.local/download/mock', 'latestChapterHash': 'ch3'},
            ));
            return;
          }
          if (options.path.contains('mock-r2.local/download')) {
            // Mock empty chapter body (binary representation of encrypted LessonChapter containing empty messages)
            final chapterMap = {
              'previousChapterHash': 'ch1',
              'messages': [],
            };
            final encryptedBase64 = MessageCryptoService.encryptPayload(
              lessonKeyHex: lessonKeyHex,
              plaintext: jsonEncode(chapterMap),
              conversationId: conversationId,
            );
            final binary = base64Decode(encryptedBase64);
            handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: binary.toList(),
            ));
            return;
          }
          handler.next(options);
        },
      ));

      // Trigger load which adds a new chapter and enforces cache limit of 2
      await lazyService.loadPreviousChapter(conversationId, msk);

      // Verify that chapter 'ch1' and its messages are purged from the local SQLite cache
      final msgList = await db.query('messages', where: "chapter_hash = 'ch1'");
      final chapList = await db.query('cached_chapters', where: "chapter_hash = 'ch1'");
      expect(msgList, isEmpty);
      expect(chapList, isEmpty);

      // Ensure recent chapters still exist
      final recentChapList = await db.query('cached_chapters', where: "chapter_hash = 'ch3'");
      expect(recentChapList, isNotEmpty);
    });
  });
}
