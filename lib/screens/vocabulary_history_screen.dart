import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/database_service.dart';
import 'video_player_screen.dart';

class VocabularyHistoryScreen extends StatefulWidget {
  const VocabularyHistoryScreen({super.key});

  @override
  State<VocabularyHistoryScreen> createState() =>
      _VocabularyHistoryScreenState();
}

class _VocabularyHistoryScreenState extends State<VocabularyHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('History', style: TextStyle(color: Colors.white)),
          bottom: const TabBar(
            indicatorColor: Color(0xFF00C853),
            labelColor: Color(0xFF00C853),
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Words'),
              Tab(text: 'Phrases'),
            ],
          ),
        ),
        body: const TabBarView(children: [_WordsTab(), _PhrasesTab()]),
      ),
    );
  }
}

class _WordsTab extends StatelessWidget {
  const _WordsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: DatabaseService().onHistoryChanged,
      builder: (context, _) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: DatabaseService().getHistory(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white),
                ),
              );
            }

            final history = snapshot.data ?? [];

            if (history.isEmpty) {
              return _buildEmptyState(
                Icons.history,
                'No words in history yet.',
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.only(top: 8),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final item = history[index];
                return Card(
                  color: const Color(0xFF1E1E1E),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: ListTile(
                    title: Text(
                      item['word'].toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        item['definition'].toString(),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      onPressed: () => DatabaseService().deleteWord(item['id']),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _PhrasesTab extends StatelessWidget {
  const _PhrasesTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: DatabaseService().onSentencesChanged,
      builder: (context, _) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: DatabaseService().getSavedSentences(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white),
                ),
              );
            }

            final sentences = snapshot.data ?? [];

            if (sentences.isEmpty) {
              return _buildEmptyState(
                Icons.bookmark_border,
                'No saved phrases yet.',
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.only(top: 8),
              itemCount: sentences.length,
              itemBuilder: (context, index) {
                final item = sentences[index];
                final sentence = item['sentence'].toString();
                final timestampMs = item['timestamp_ms'] as int? ?? 0;
                final videoPath = item['video_path']?.toString();

                return Card(
                  color: const Color(0xFF1E1E1E),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (videoPath == null ||
                          videoPath.isEmpty ||
                          !File(videoPath).existsSync()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Video file not found or moved.'),
                            backgroundColor: Colors.redAccent,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VideoPlayerScreen(
                            videoPath: videoPath,
                            initialPositionMs: timestampMs,
                          ),
                        ),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          title: Text(
                            sentence,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item['video_title'].toString(),
                                    style: const TextStyle(
                                      color: Color(0xFF00C853),
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _formatTimestamp(timestampMs),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: sentence),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Copied to clipboard'),
                                      duration: Duration(seconds: 1),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.copy,
                                  size: 16,
                                  color: Colors.white70,
                                ),
                                label: const Text(
                                  'Copy',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => DatabaseService()
                                    .deleteSentence(item['id']),
                                icon: const Icon(
                                  Icons.delete,
                                  size: 16,
                                  color: Colors.redAccent,
                                ),
                                label: const Text(
                                  'Delete',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatTimestamp(int ms) {
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

Widget _buildEmptyState(IconData icon, String message) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 60, color: Colors.grey),
        const SizedBox(height: 16),
        Text(message, style: const TextStyle(color: Colors.grey, fontSize: 16)),
      ],
    ),
  );
}
