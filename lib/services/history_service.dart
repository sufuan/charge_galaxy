import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryService extends ChangeNotifier {
  static const String _historyListKey = 'history_list';
  static const String _progressPrefix = 'video_progress_';
  static const String _volumePrefix = 'video_volume_';
  static const String _subtitlePrefsPrefix = 'subtitle_prefs_';

  // Singleton so all listeners share the same instance.
  HistoryService._internal();
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;

  // Save progress and update history list logic
  Future<void> saveProgress(
    String videoId,
    int positionInSeconds, {
    double? volume,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Save Position
    await prefs.setInt('$_progressPrefix$videoId', positionInSeconds);

    // 2. Save Volume if provided
    if (volume != null) {
      await prefs.setDouble('$_volumePrefix$videoId', volume);
    }

    // 3. Update History List (Move to top)
    List<String> history = prefs.getStringList(_historyListKey) ?? [];
    history.remove(videoId);
    history.insert(0, videoId);

    if (history.length > 50) {
      history = history.sublist(0, 50);
    }

    await prefs.setStringList(_historyListKey, history);

    // Notify listeners (e.g. HomeScreen) so the History strip refreshes
    // immediately, without depending on Navigator.pop callbacks.
    notifyListeners();
  }

  // Get saved progress for a specific video
  Future<int> getProgress(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_progressPrefix$videoId') ?? 0;
  }

  // Get saved volume for a specific video
  Future<double?> getVolume(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('$_volumePrefix$videoId');
  }

  // Get list of video IDs in history order
  Future<List<String>> getHistoryIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_historyListKey) ?? [];
  }

  // Persist subtitle preferences (source + enabled state) for a video.
  Future<void> saveSubtitlePrefs(
    String videoId, {
    required bool enabled,
    required bool useInternal,
    String? srtPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode({
      'enabled': enabled,
      'useInternal': useInternal,
      'srtPath': srtPath,
    });
    await prefs.setString('$_subtitlePrefsPrefix$videoId', encoded);
  }

  // Returns the saved subtitle preferences map for [videoId], or null if
  // none has been stored yet. Shape: { 'enabled': bool, 'useInternal': bool,
  // 'srtPath': String? }.
  Future<Map<String, dynamic>?> getSubtitlePrefs(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_subtitlePrefsPrefix$videoId');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Corrupt entry — treat as absent.
    }
    return null;
  }
}
