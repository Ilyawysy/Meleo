import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_provider.dart';
import '../models/chat_thread.dart';
import '../models/message.dart';
import '../../../../core/id_generator.dart';

class ChatDb {
  static final ChatDb _instance = ChatDb._internal();
  factory ChatDb() => _instance;
  ChatDb._internal();

  Future<Database> _getDb() async {
    return await DatabaseProvider().getDatabase();
  }

  // Thread operations
  Future<List<ChatThread>> listThreads({int limit = 50, int offset = 0}) async {
    final db = await _getDb();
    final rows = await db.query(
      'chat_threads',
      where: 'pending_delete = 0',
      orderBy: 'updated_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_threadFromRow).toList();
  }

  Future<ChatThread?> getThread(String id) async {
    final db = await _getDb();
    final rows = await db.query(
      'chat_threads',
      where: 'id = ? AND pending_delete = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _threadFromRow(rows.first);
  }

  Future<ChatThread?> findByRemoteId(String remoteId) async {
    final db = await _getDb();
    final rows = await db.query(
      'chat_threads',
      where: 'remote_id = ? AND pending_delete = 0',
      whereArgs: [remoteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _threadFromRow(rows.first);
  }

  Future<ChatThread> createThread({
    required String title,
  }) async {
    final db = await _getDb();
    final now = DateTime.now();
    final id = generateLocalId();
    final row = <String, Object?>{
      'id': id,
      'title': title,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'remote_id': null,
      'version': 0,
      'dirty': 1,
      'pending_delete': 0,
    };
    await db.insert('chat_threads', row, conflictAlgorithm: ConflictAlgorithm.replace);
    return _threadFromRow(row);
  }

  Future<ChatThread> updateThread(
    String id, {
    String? title,
  }) async {
    final db = await _getDb();
    final now = DateTime.now();
    final values = <String, Object?>{
      'updated_at': now.toIso8601String(),
      'dirty': 1,
    };
    if (title != null) values['title'] = title;
    await db.update('chat_threads', values, where: 'id = ?', whereArgs: [id]);
    final rows = await db.query(
      'chat_threads',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('Thread not found after update');
    }
    return _threadFromRow(rows.first);
  }

  Future<void> deleteThread(String id) async {
    final db = await _getDb();
    await db.update(
      'chat_threads',
      {
        'pending_delete': 1,
        'dirty': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteThreadHard(String id) async {
    final db = await _getDb();
    await db.delete('chat_threads', where: 'id = ?', whereArgs: [id]);
  }

  ChatThread _threadFromRow(Map<String, Object?> row) {
    return ChatThread(
      id: row['id'] as String,
      title: row['title'] as String,
      remoteId: row['remote_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  // Message operations
  Future<List<Message>> listMessages({
    required String threadId,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await _getDb();
    final rows = await db.query(
      'chat_messages',
      where: 'thread_id = ? AND pending_delete = 0',
      whereArgs: [threadId],
      orderBy: 'order_index ASC, created_at ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_messageFromRow).toList();
  }

  Future<Message?> getMessage(String id) async {
    final db = await _getDb();
    final rows = await db.query(
      'chat_messages',
      where: 'id = ? AND pending_delete = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _messageFromRow(rows.first);
  }

  Future<Message?> findMessageByRemoteId(String remoteId) async {
    final db = await _getDb();
    final rows = await db.query(
      'chat_messages',
      where: 'remote_id = ? AND pending_delete = 0',
      whereArgs: [remoteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _messageFromRow(rows.first);
  }

  Future<Message> createMessage({
    required String threadId,
    required String text,
    required bool isMe,
    int? order,
  }) async {
    final db = await _getDb();
    final now = DateTime.now();
    final id = generateLocalId();

    // Если order не указан, вычисляем следующий порядковый номер
    int messageOrder = order ?? 0;
    if (order == null) {
      final existingMessages = await db.query(
        'chat_messages',
        columns: ['order_index'],
        where: 'thread_id = ?',
        whereArgs: [threadId],
      );
      if (existingMessages.isNotEmpty) {
        final maxOrder = existingMessages
            .map((r) => (r['order_index'] as int?) ?? 0)
            .reduce((a, b) => a > b ? a : b);
        messageOrder = maxOrder + 1;
      }
    }

    final row = <String, Object?>{
      'id': id,
      'thread_id': threadId,
      'text': text,
      'is_me': isMe ? 1 : 0,
      'created_at': now.toIso8601String(),
      'remote_id': null,
      'order_index': messageOrder,
      'version': 0,
      'dirty': 1,
      'pending_delete': 0,
    };
    await db.insert('chat_messages', row, conflictAlgorithm: ConflictAlgorithm.replace);
    
    // Обновляем updated_at треда
    await db.update(
      'chat_threads',
      {'updated_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [threadId],
    );
    
    return _messageFromRow(row);
  }

  Future<void> deleteMessage(String id) async {
    final db = await _getDb();
    await db.update(
      'chat_messages',
      {
        'pending_delete': 1,
        'dirty': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Message _messageFromRow(Map<String, Object?> row) {
    return Message(
      id: row['id'] as String,
      text: row['text'] as String,
      isMe: (row['is_me'] as int? ?? 0) == 1,
      ts: DateTime.parse(row['created_at'] as String),
      threadId: row['thread_id'] as String,
      remoteId: row['remote_id'] as String?,
      order: (row['order_index'] as int?) ?? 0,
    );
  }

  // Sync helpers
  Future<List<Map<String, Object?>>> dirtyThreads() async {
    final db = await _getDb();
    return db.query('chat_threads', where: 'dirty = 1');
  }

  Future<List<Map<String, Object?>>> dirtyMessages() async {
    final db = await _getDb();
    return db.query('chat_messages', where: 'dirty = 1');
  }

  Future<bool> hasDirtyRows() async {
    final db = await _getDb();
    final result = await db.rawQuery(
      'SELECT EXISTS('
      'SELECT 1 FROM chat_threads WHERE dirty = 1 '
      'UNION ALL '
      'SELECT 1 FROM chat_messages WHERE dirty = 1 '
      'LIMIT 1'
      ') AS has_dirty',
    );
    return (result.first['has_dirty'] as int) == 1;
  }

  Future<void> setThreadSynced(String localId, {required String remoteId}) async {
    final db = await _getDb();
    await db.update(
      'chat_threads',
      {
        'remote_id': remoteId,
        'dirty': 0,
        'version': (await _currentThreadVersion(db, localId)) + 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> setThreadClean(String localId) async {
    final db = await _getDb();
    await db.update(
      'chat_threads',
      {'dirty': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> setMessageSynced(String localId, {required String remoteId}) async {
    final db = await _getDb();
    await db.update(
      'chat_messages',
      {
        'remote_id': remoteId,
        'dirty': 0,
        'version': (await _currentMessageVersion(db, localId)) + 1,
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> setMessageClean(String localId) async {
    final db = await _getDb();
    await db.update(
      'chat_messages',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<int> _currentThreadVersion(Database db, String id) async {
    final rows = await db.query(
      'chat_threads',
      columns: ['version'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['version'] as int?) ?? 0;
  }

  Future<int> _currentMessageVersion(Database db, String id) async {
    final rows = await db.query(
      'chat_messages',
      columns: ['version'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['version'] as int?) ?? 0;
  }

  // Upsert from remote
  Future<bool> upsertThreadFromRemote(ChatThread remote) async {
    final db = await _getDb();
    final existing = await db.query(
      'chat_threads',
      where: 'remote_id = ?',
      whereArgs: [remote.remoteId ?? remote.id],
      limit: 1,
    );

    final row = <String, Object?>{
      'id': existing.isNotEmpty ? existing.first['id'] as String : remote.id,
      'title': remote.title,
      'created_at': remote.createdAt.toIso8601String(),
      'updated_at': remote.updatedAt.toIso8601String(),
      'remote_id': remote.remoteId ?? remote.id,
      'dirty': 0,
    };

    if (existing.isNotEmpty) {
      final isDirty = (existing.first['dirty'] as int? ?? 0) == 1;
      if (isDirty) return false; // Keep local changes

      final existingUpdatedAt = existing.first['updated_at'] as String?;
      final existingTitle = existing.first['title'] as String?;
      final incomingUpdatedAt = remote.updatedAt.toIso8601String();
      if (existingUpdatedAt == incomingUpdatedAt && existingTitle == remote.title) {
        return false;
      }
      await db.update(
        'chat_threads',
        row,
        where: 'id = ?',
        whereArgs: [existing.first['id'] as String],
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.insert(
        'chat_threads',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return true;
  }

  Future<void> upsertMessageFromRemote(Message remote, String threadId) async {
    final db = await _getDb();
    final existing = await db.query(
      'chat_messages',
      where: 'remote_id = ?',
      whereArgs: [remote.remoteId ?? remote.id],
      limit: 1,
    );

    final row = <String, Object?>{
      'id': existing.isNotEmpty ? existing.first['id'] as String : remote.id,
      'thread_id': threadId,
      'text': remote.text,
      'is_me': remote.isMe ? 1 : 0,
      'created_at': remote.ts.toIso8601String(),
      'remote_id': remote.remoteId ?? remote.id,
      'order_index': remote.order,
      'dirty': 0,
    };

    if (existing.isNotEmpty) {
      final isDirty = (existing.first['dirty'] as int? ?? 0) == 1;
      if (isDirty) return; // Keep local changes
      await db.update(
        'chat_messages',
        row,
        where: 'id = ?',
        whereArgs: [existing.first['id'] as String],
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.insert(
        'chat_messages',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

}

