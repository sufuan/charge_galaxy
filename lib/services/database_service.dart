import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'vocabulary.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE vocabulary_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            word TEXT UNIQUE,
            definition TEXT,
            created_at INTEGER
          )
        ''');
      },
    );
  }

  // Fire and forget upsert
  Future<void> upsertWord(String word, String definition) async {
    try {
      final db = await database;
      // INSERT OR REPLACE Logic
      await db.rawInsert(
        'INSERT OR REPLACE INTO vocabulary_history (word, definition, created_at) VALUES (?, ?, ?)',
        [word, definition, DateTime.now().millisecondsSinceEpoch],
      );
      debugPrint('Saved to history: $word');
    } catch (e) {
      debugPrint('Error saving word: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    try {
      final db = await database;
      return await db.query('vocabulary_history', orderBy: 'created_at DESC');
    } catch (e) {
      debugPrint('Error fetching history: $e');
      return [];
    }
  }

  Future<void> deleteWord(int id) async {
    try {
      final db = await database;
      await db.delete('vocabulary_history', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('Error deleting word: $e');
    }
  }
}
