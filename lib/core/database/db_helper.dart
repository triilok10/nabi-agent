import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class DBHelper {
  DBHelper._();

  static final DBHelper instance = DBHelper._();
  static const int retentionDays = 30;
  static const String _databaseName = 'nabi_local_memory.db';

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final dbPath = path.join(await getDatabasesPath(), _databaseName);
    final opened = await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE call_assistant_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            caller_number TEXT,
            caller_name TEXT,
            call_timestamp TEXT NOT NULL,
            call_duration_seconds INTEGER NOT NULL DEFAULT 0,
            raw_transcript TEXT,
            ai_summary TEXT,
            urgency_level TEXT,
            is_archived INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE location_tracking_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            place_name TEXT,
            timestamp TEXT NOT NULL,
            stay_duration_minutes INTEGER,
            is_archived INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE system_action_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_command TEXT NOT NULL,
            executed_action TEXT NOT NULL,
            execution_status TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            is_archived INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await _createMemoryLogsTable(db);
        await _createUserPreferencesTable(db);
        await db.execute(
          'CREATE INDEX call_logs_timestamp_idx ON call_assistant_logs(call_timestamp)',
        );
        await db.execute(
          'CREATE INDEX location_logs_timestamp_idx ON location_tracking_logs(timestamp)',
        );
        await db.execute(
          'CREATE INDEX action_logs_timestamp_idx ON system_action_logs(timestamp)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createMemoryLogsTable(db);
        if (oldVersion < 3) await _createUserPreferencesTable(db);
      },
    );
    _database = opened;
    return opened;
  }

  Future<int> insertRecord(String table, Map<String, Object?> values) async {
    _validateTable(table);
    return (await database).insert(table, values);
  }

  Future<int> insertMemoryLog({
    required String interactionType,
    required String userInput,
    required String systemResponse,
    String? executedAction,
    required String executionStatus,
    DateTime? timestamp,
  }) async {
    return (await database).insert('memory_logs', {
      'interaction_type': interactionType,
      'user_input': userInput,
      'system_response': systemResponse,
      'executed_action': executedAction,
      'execution_status': executionStatus,
      'timestamp': (timestamp ?? DateTime.now().toUtc())
          .toUtc()
          .toIso8601String(),
    });
  }

  Future<void> saveUserPreference(String key, Object? value) async {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError.value(key, 'key', 'Preference key cannot be empty');
    }
    await (await database).insert('user_preferences', {
      'key': normalizedKey,
      'value': jsonEncode(value),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Object?> readUserPreference(String key) async {
    final rows = await (await database).query(
      'user_preferences',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.single['value']! as String) as Object?;
  }

  Future<List<Map<String, Object?>>> fetchMemoryLogs({int limit = 100}) async {
    if (limit < 1)
      throw ArgumentError.value(limit, 'limit', 'Must be positive');
    return (await database).query(
      'memory_logs',
      where: 'is_archived = 0',
      orderBy: 'julianday(timestamp) DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, Object?>>> fetchRelevantMemory(
    String query, {
    int limit = 6,
  }) async {
    if (limit < 1)
      throw ArgumentError.value(limit, 'limit', 'Must be positive');
    final terms = _memoryTerms(query);
    if (terms.isEmpty) return const [];

    final recent = await fetchMemoryLogs(limit: 100);
    final scored = <({int score, Map<String, Object?> row})>[];
    for (final row in recent) {
      final text = [
        row['user_input'],
        row['system_response'],
        row['executed_action'],
      ].whereType<String>().join(' ').toLowerCase();
      final score = terms.where(text.contains).length;
      if (score > 0) scored.add((score: score, row: row));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return (b.row['timestamp'] as String).compareTo(
        a.row['timestamp'] as String,
      );
    });
    return scored.take(limit).map((entry) => entry.row).toList();
  }

  Future<List<Map<String, Object?>>> fetchActiveRecords(String table) async {
    _validateTable(table);
    final timestampColumn = _timestampColumn(table);
    return (await database).query(
      table,
      where: 'is_archived = 0',
      orderBy: 'julianday($timestampColumn) DESC',
    );
  }

  Future<Map<String, List<Map<String, Object?>>>> fetchExpiredRecords({
    DateTime? now,
  }) async {
    final cutoff = (now ?? DateTime.now().toUtc())
        .toUtc()
        .subtract(const Duration(days: retentionDays))
        .toIso8601String();
    final db = await database;
    final result = <String, List<Map<String, Object?>>>{};
    for (final table in _recordTables) {
      final column = _timestampColumn(table);
      result[table] = await db.query(
        table,
        where: 'is_archived = 0 AND julianday($column) < julianday(?)',
        whereArgs: [cutoff],
        orderBy: '$column ASC',
      );
    }
    return result;
  }

  Future<Map<String, int>> activeRecordCounts() async {
    final db = await database;
    final result = <String, int>{};
    for (final table in _recordTables) {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM $table WHERE is_archived = 0',
      );
      result[table] = Sqflite.firstIntValue(rows) ?? 0;
    }
    return result;
  }

  Future<void> confirmArchivedRecords(Map<String, List<int>> recordIds) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final entry in recordIds.entries) {
        _validateTable(entry.key);
        for (final id in entry.value) {
          await transaction.update(
            entry.key,
            {'is_archived': 1},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    });
  }

  Future<void> purgeArchivedRecords(
    Map<String, List<int>> recordIds, {
    required bool userConfirmed,
  }) async {
    if (!userConfirmed) {
      throw StateError(
        'Explicit user confirmation is required to purge records',
      );
    }
    final db = await database;
    await db.transaction((transaction) async {
      for (final entry in recordIds.entries) {
        _validateTable(entry.key);
        for (final id in entry.value) {
          await transaction.delete(
            entry.key,
            where: 'id = ? AND is_archived = 1',
            whereArgs: [id],
          );
        }
      }
    });
  }

  Future<void> deleteExpiredRecords({
    required bool userConfirmed,
    DateTime? now,
  }) async {
    if (!userConfirmed) {
      throw StateError(
        'Explicit user confirmation is required to delete records',
      );
    }
    final expired = await fetchExpiredRecords(now: now);
    final db = await database;
    await db.transaction((transaction) async {
      for (final entry in expired.entries) {
        _validateTable(entry.key);
        for (final row in entry.value) {
          await transaction.delete(
            entry.key,
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
    });
  }

  static const List<String> _tables = [
    'call_assistant_logs',
    'location_tracking_logs',
    'system_action_logs',
  ];

  static const List<String> _recordTables = [..._tables, 'memory_logs'];

  void _validateTable(String table) {
    if (!_recordTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'Unsupported database table');
    }
  }

  String _timestampColumn(String table) =>
      table == 'call_assistant_logs' ? 'call_timestamp' : 'timestamp';

  static Future<void> _createMemoryLogsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE memory_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        interaction_type TEXT NOT NULL,
        user_input TEXT NOT NULL,
        system_response TEXT NOT NULL,
        executed_action TEXT,
        execution_status TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        is_archived INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX memory_logs_timestamp_idx ON memory_logs(timestamp)',
    );
  }

  static Future<void> _createUserPreferencesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE user_preferences (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Set<String> _memoryTerms(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((term) => term.length > 1)
      .toSet();
}
