import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class DictionaryService {
  static final DictionaryService _instance = DictionaryService._internal();
  factory DictionaryService() => _instance;
  DictionaryService._internal();

  Map<String, String>? _dictionary;
  bool _isLoading = false;

  Future<void> initialize() async {
    if (_dictionary != null || _isLoading) return;

    _isLoading = true;
    try {
      debugPrint('Loading dictionary...');
      final jsonString = await rootBundle.loadString('assets/dictionary.json');

      // Use compute to parse in background isolate
      _dictionary = await compute(_parseDictionary, jsonString);

      debugPrint('Dictionary loaded: ${_dictionary!.length} words');
    } catch (e) {
      debugPrint('Failed to load dictionary: $e');
      _dictionary = {};
    } finally {
      _isLoading = false;
    }
  }

  // Static top-level function for compute
  static Map<String, String> _parseDictionary(String jsonString) {
    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      final Map<String, String> dict = {};

      for (final item in jsonList) {
        if (item is Map<String, dynamic>) {
          final en = item['en']?.toString().toLowerCase();
          final bn = item['bn']?.toString();

          if (en != null && bn != null) {
            dict[en] = bn;
          }
        }
      }
      return dict;
    } catch (e) {
      debugPrint('Error parsing dictionary JSON: $e');
      return {};
    }
  }

  String? lookup(String word) {
    if (_dictionary == null) return null;

    // Normalize: remove trailing punctuation, lowercase
    // Keep internal apostrophes (e.g., "don't") but remove surrounding punctuation
    final cleanWord = word.trim().toLowerCase().replaceAll(
      RegExp(r'[^\w\s\x27]'),
      '',
    );
    return _dictionary![cleanWord];
  }
}
