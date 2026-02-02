import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

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
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE vocabulary_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            word TEXT UNIQUE,
            definition TEXT,
            created_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE saved_sentences (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sentence TEXT UNIQUE,
            video_title TEXT,
            video_path TEXT,
            timestamp_ms INTEGER,
            created_at INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE saved_sentences (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sentence TEXT UNIQUE,
              video_title TEXT,
              video_path TEXT,
              timestamp_ms INTEGER,
              created_at INTEGER
            )
          ''');
        }
        if (oldVersion < 3) {
          // Check if columns exist before adding (safer for distributed dev)
          try {
            await db.execute(
              'ALTER TABLE saved_sentences ADD COLUMN video_path TEXT',
            );
            await db.execute(
              'ALTER TABLE saved_sentences ADD COLUMN timestamp_ms INTEGER',
            );
          } catch (e) {
            debugPrint('Columns might already exist: $e');
          }
        }
      },
    );
  }

  // Streams to notify listeners of changes
  final _historyStreamController = StreamController<void>.broadcast();
  Stream<void> get onHistoryChanged => _historyStreamController.stream;

  final _sentencesStreamController = StreamController<void>.broadcast();
  Stream<void> get onSentencesChanged => _sentencesStreamController.stream;

  // Fire and forget upsert
  Future<void> upsertWord(String word, String definition) async {
    try {
      final db = await database;
      // INSERT OR REPLACE Logic
      await db.rawInsert(
        'INSERT OR REPLACE INTO vocabulary_history (word, definition, created_at) VALUES (?, ?, ?)',
        [word, definition, DateTime.now().millisecondsSinceEpoch],
      );
      _historyStreamController.add(null);
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
      _historyStreamController.add(null);
    } catch (e) {
      debugPrint('Error deleting word: $e');
    }
  }

  // --- Saved Sentences ---

  Future<void> saveSentence({
    required String sentence,
    required String? videoTitle,
    required String? videoPath,
    required int timestampMs,
  }) async {
    try {
      final db = await database;
      await db.rawInsert(
        'INSERT OR REPLACE INTO saved_sentences (sentence, video_title, video_path, timestamp_ms, created_at) VALUES (?, ?, ?, ?, ?)',
        [
          sentence,
          videoTitle ?? 'Unknown Video',
          videoPath ?? '',
          timestampMs,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      _sentencesStreamController.add(null);
      debugPrint('Saved sentence at $timestampMs ms: $sentence');
    } catch (e) {
      debugPrint('Error saving sentence: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getSavedSentences() async {
    try {
      final db = await database;
      return await db.query('saved_sentences', orderBy: 'created_at DESC');
    } catch (e) {
      debugPrint('Error fetching sentences: $e');
      return [];
    }
  }

  Future<void> deleteSentence(int id) async {
    try {
      final db = await database;
      await db.delete('saved_sentences', where: 'id = ?', whereArgs: [id]);
      _sentencesStreamController.add(null);
    } catch (e) {
      debugPrint('Error deleting sentence: $e');
    }
  }

  Future<bool> isSentenceSaved(String sentence) async {
    try {
      final db = await database;
      final results = await db.query(
        'saved_sentences',
        where: 'sentence = ?',
        whereArgs: [sentence],
      );
      return results.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _historyStreamController.close();
    _sentencesStreamController.close();
  }
}
