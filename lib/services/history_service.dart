import 'package:shared_preferences/shared_preferences.dart';

class HistoryService {
  static const String _historyListKey = 'history_list';
  static const String _progressPrefix = 'video_progress_';

  // Save progress and update history list logic
  Future<void> saveProgress(String videoId, int positionInSeconds) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Save Position
    await prefs.setInt('$_progressPrefix$videoId', positionInSeconds);

    // 2. Update History List (Move to top)
    List<String> history = prefs.getStringList(_historyListKey) ?? [];

    // Remove if exists (to re-add at top)
    history.remove(videoId);

    // Add to top
    history.insert(0, videoId);

    // Optional: Limit history size (e.g. 50 items)
    if (history.length > 50) {
      history = history.sublist(0, 50);
    }

    await prefs.setStringList(_historyListKey, history);
  }

  // Get saved progress for a specific video
  Future<int> getProgress(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_progressPrefix$videoId') ?? 0;
  }

  // Get list of video IDs in history order
  Future<List<String>> getHistoryIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_historyListKey) ?? [];
  }
}
