import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui; // Import dart:ui
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as p;
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../services/history_service.dart';
import '../services/subtitle_service.dart';
import '../models/subtitle_entry.dart';
import '../widgets/subtitle_overlay.dart';
import '../widgets/side_panel.dart';
import '../widgets/gesture_hud.dart';
import '../services/dictionary_service.dart';
import '../services/database_service.dart';
import '../services/subtitle_download_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final AssetEntity? videoFile;
  final String? videoPath;
  final int? initialPositionMs;

  const VideoPlayerScreen({
    super.key,
    this.videoFile,
    this.videoPath,
    this.initialPositionMs,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;

  // Stream Subscriptions
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<List<String>>? _subtitleSubscription;
  bool _isLoading = true;
  bool _showControls = true;
  bool _isLocked = false;
  bool _isMuted = false;
  double _playbackSpeed = 1.0;
  double _savedSpeed = 1.0;
  Timer? _hideTimer;

  final HistoryService _historyService = HistoryService();
  final SubtitleDownloadService _subtitleDownloadService =
      SubtitleDownloadService();

  // Gesture tracking
  double? _initialBrightness;
  double? _initialVolume;
  bool _isLongPressing = false;

  // Visual feedback
  String? _seekFeedback;
  Timer? _seekFeedbackTimer;
  double? _currentBrightness;
  double? _currentVolume;
  double _playerVolume = 1.0;
  bool _showBrightnessOverlay = false;
  bool _showVolumeOverlay = false;
  Timer? _overlayTimer;

  // Subtitles
  List<SubtitleEntry>? _subtitles;
  SubtitleEntry? _currentSubtitle;
  int _currentSubtitleIndex = 0;
  bool _subtitlesEnabled = false;
  String? _subtitleFileName;
  // Full path of the loaded external SRT, captured so it can be persisted
  // and restored across sessions. Null when using internal subtitles.
  String? _subtitleFilePath;
  double _subtitleTextSize = 18.0;
  bool _isLearningMode = false;
  String? _selectedWord;
  Duration _lastSubtitleSearchPosition = Duration.zero;
  bool _isCurrentSentenceSaved = false;

  // Horizontal Gesture Seeking
  bool _isSeeking = false;
  double _dragOffset = 0.0;
  Duration? _seekStartPosition;
  Duration? _seekTargetPosition;
  String _seekPreviewText = '';

  String? _resolvedVideoPath;
  // Captured once the video is opened; used as the key for per-video
  // persistence (resume position, volume, subtitle prefs).
  String? _currentVideoId;

  // Unified Subtitle State
  bool _useInternalSubtitles = true;
  String? _liveInternalCaption;
  String? _lastCapturedInternalCaption;

  // Resume playback state
  bool _initialSeekComplete = false;
  // Throttle progress writes triggered by the position stream.
  DateTime _lastProgressSaveAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _progressSaveInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    WakelockPlus.enable();
  }

  Future<void> _initializePlayer() async {
    File? file;
    if (widget.videoFile != null) {
      file = await widget.videoFile!.file;
    } else if (widget.videoPath != null) {
      file = File(widget.videoPath!);
    }

    if (file == null || !file.existsSync()) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Video file not found')));
      }
      return;
    }

    // Initialize MediaKit
    _player = Player();
    _controller = VideoController(_player);

    // 1. Position Listener
    _positionSubscription = _player.stream.position.listen((position) {
      if (mounted) {
        _updateSubtitle();
        setState(() {});
      }
      // Persist progress at most once per _progressSaveInterval so the
      // History strip reflects up-to-date watch percentage even if dispose
      // doesn't fire (e.g. app killed or backgrounded).
      if (_initialSeekComplete) {
        final now = DateTime.now();
        if (now.difference(_lastProgressSaveAt) >= _progressSaveInterval) {
          _lastProgressSaveAt = now;
          _saveProgress();
        }
      }
    });

    // 2. Duration Listener
    _durationSubscription = _player.stream.duration.listen((duration) {
      if (mounted) setState(() {});
    });

    // 3. Playing State Listener
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (mounted) setState(() {});
    });

    // 4. Subtitle Stream Listener (Dictionary Bridge)
    _subtitleSubscription = _player.stream.subtitle.listen((
      List<String> tracks,
    ) {
      if (mounted && _useInternalSubtitles) {
        if (tracks.isNotEmpty) {
          final text = tracks.first;
          if (_liveInternalCaption != text) {
            // Optimistically reset the bookmark to the unsaved state so it
            // never shows a stale "green" from the previous caption while
            // the async DB lookup is in flight. The check below will flip
            // it back to true iff this specific sentence is already saved.
            setState(() {
              _liveInternalCaption = text;
              _isCurrentSentenceSaved = false;
            });
            _checkIfSentenceSaved(text);
          }
        } else {
          if (_liveInternalCaption != null &&
              _liveInternalCaption!.isNotEmpty) {
            setState(() {
              _liveInternalCaption = "";
              _isCurrentSentenceSaved = false;
            });
          }
        }
      }
    });

    // 5. Completion Logic
    _player.stream.completed.listen((completed) {
      if (completed) {
        WakelockPlus.disable();
        if (mounted) _toggleControls();
      }
    });

    try {
      await _player.open(Media(file.path), play: false);

      final videoId = widget.videoFile?.id ?? widget.videoPath ?? 'unknown';
      _currentVideoId = videoId;

      // Restore volume (MediaKit uses 0-100)
      double? savedVolume = await _historyService.getVolume(videoId);
      if (savedVolume == null) {
        try {
          savedVolume = await VolumeController().getVolume();
        } catch (e) {
          savedVolume = 1.0;
        }
      }
      _playerVolume = savedVolume;
      await _player.setVolume(_playerVolume * 100);

      // Restore position
      int startPosition = 0;
      if (widget.initialPositionMs != null) {
        startPosition = widget.initialPositionMs!;
      } else {
        final saved = await _historyService.getProgress(videoId);
        startPosition = saved * 1000;
      }

      if (startPosition > 0) {
        // Wait until the player reports a valid duration before seeking,
        // otherwise the seek is dropped and playback starts at 0.
        try {
          await _player.stream.duration
              .firstWhere((d) => d > Duration.zero)
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          // Continue even if duration never arrived in time
        }

        // Clamp against known duration so we don't seek past the end
        final knownDuration = _player.state.duration;
        if (knownDuration > Duration.zero &&
            startPosition >= knownDuration.inMilliseconds) {
          startPosition = 0;
        }

        if (startPosition > 0) {
          await _player.seek(Duration(milliseconds: startPosition));
        }
      }

      _initialSeekComplete = true;

      // Save initial state (also bumps this video to the top of History)
      await _historyService.saveProgress(
        videoId,
        startPosition ~/ 1000,
        volume: _playerVolume,
      );

      await _player.play();

      // Restore previously persisted subtitle prefs for this video, falling
      // back to auto-discovery on first play.
      await _restoreOrLoadSubtitles();
      // Initialize dictionary
      await DictionaryService().initialize();

      setState(() {
        _resolvedVideoPath = file?.path;
        _isLoading = false;
        _currentVolume = _playerVolume;
      });
      _startHideTimer();
    } catch (e) {
      debugPrint('Error initializing player: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _startHideTimer();
      } else {
        _hideTimer?.cancel();
      }
    });
  }

  void _togglePlayPause() {
    setState(() {
      _player.playOrPause();
      if (!_player.state.playing) {
        // Paused
      } else {
        // Playing
        _startHideTimer();
      }
    });
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _player.setVolume(_isMuted ? 0.0 : _playerVolume * 100);
    });
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      if (_isLocked) {
        _showControls = false;
      } else {
        _showControls = true;
        _startHideTimer();
      }
    });
  }

  void _showSpeedDialog() {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    SidePanel.show(
      context: context,
      title: 'Playback Speed',
      children: speeds.map((speed) {
        final isSelected = _playbackSpeed == speed;
        return ListTile(
          title: Text(
            '${speed}x',
            style: TextStyle(
              color: isSelected ? const Color(0xFF00C853) : Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 15,
            ),
          ),
          trailing: isSelected
              ? const Icon(Icons.check, color: Color(0xFF00C853))
              : null,
          onTap: () {
            setState(() {
              _playbackSpeed = speed;
              _savedSpeed = speed;
              _player.setRate(speed);
            });
            Navigator.pop(context);
          },
        );
      }).toList(),
    );
  }

  void _showLearningModeMenu() {
    SidePanel.show(
      context: context,
      title: 'Learning Mode',
      children: [
        StatefulBuilder(
          builder: (context, setPanelState) {
            return SwitchListTile(
              secondary: Icon(
                _isLearningMode ? Icons.school : Icons.school_outlined,
                color: _isLearningMode ? const Color(0xFF00C853) : Colors.white,
              ),
              title: Text(
                _isLearningMode ? 'Learning Mode: ON' : 'Learning Mode: OFF',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              subtitle: const Text(
                'Tap words in subtitles for definitions',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              value: _isLearningMode,
              onChanged: (value) {
                setState(() => _isLearningMode = value);
                setPanelState(() {});
              },
              activeColor: const Color(0xFF00C853),
            );
          },
        ),
      ],
    );
  }

  void _handleDoubleTap(TapDownDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isRightSide = details.globalPosition.dx > screenWidth / 2;

    final currentPosition = _player.state.position;
    final seekDuration = isRightSide ? 10 : -10;
    final newPosition = currentPosition + Duration(seconds: seekDuration);

    _player.seek(newPosition);

    // Show feedback
    setState(() {
      _seekFeedback = isRightSide ? 'forward' : 'backward';
      _showControls = false;
    });

    _seekFeedbackTimer?.cancel();
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _seekFeedback = null);
      }
    });
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    if (_isLongPressing) return;
    setState(() {
      _isLongPressing = true;
      _savedSpeed = _playbackSpeed;
      _playbackSpeed = 2.0;
      _player.setRate(2.0);
    });
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    if (!_isLongPressing) return;
    setState(() {
      _isLongPressing = false;
      _playbackSpeed = _savedSpeed;
      _player.setRate(_savedSpeed);
    });
  }

  void _handleVerticalDragStart(DragStartDetails details) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLeftSide = details.globalPosition.dx < screenWidth / 2;

    if (isLeftSide) {
      // Brightness
      try {
        _initialBrightness = await ScreenBrightness().current;
        _currentBrightness = _initialBrightness;
      } catch (e) {
        _initialBrightness = 0.5;
        _currentBrightness = 0.5;
      }
      setState(() => _showBrightnessOverlay = true);
    } else {
      // Volume - use player volume, not system volume
      _initialVolume = _playerVolume;
      _currentVolume = _playerVolume;
      setState(() => _showVolumeOverlay = true);
    }

    // Hide main controls during gesture
    setState(() => _showControls = false);
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isLeftSide = details.globalPosition.dx < screenWidth / 2;

    // Sensitivity multiplier — without it a full-screen drag is required
    // for a 0→100% sweep, which feels sluggish. 2.5x means roughly 40% of
    // the screen height covers the full range.
    const sensitivity = 2.5;
    final delta = -details.delta.dy / screenHeight * sensitivity;

    if (isLeftSide && _initialBrightness != null) {
      // Brightness
      final newBrightness = (_initialBrightness! + delta).clamp(0.0, 1.0);
      try {
        await ScreenBrightness().setScreenBrightness(newBrightness);
        _initialBrightness = newBrightness;
        setState(() => _currentBrightness = newBrightness);
      } catch (e) {
        // Handle error
      }
    } else if (!isLeftSide && _initialVolume != null) {
      // Player volume
      final newVolume = (_initialVolume! + delta).clamp(0.0, 1.0);
      _playerVolume = newVolume;
      if (!_isMuted) {
        _player.setVolume(newVolume * 100);
      }
      _initialVolume = newVolume;
      setState(() => _currentVolume = newVolume);

      // Persist volume change immediately
      final videoId = widget.videoFile?.id ?? widget.videoPath ?? 'unknown';
      final position = _player.state.position.inSeconds;
      _historyService.saveProgress(videoId, position, volume: newVolume);
    }
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    // Conflict resolution: Only disable if locked
    if (_isLocked) return;

    setState(() {
      _isSeeking = true;
      _dragOffset = 0.0;
      _seekStartPosition = _player.state.position;
      _seekTargetPosition = _seekStartPosition;
      _seekPreviewText = '00:00';
      _showControls = false; // Hide controls while seeking
    });
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isSeeking || _seekStartPosition == null) return;

    // Conflict Fix: only precise horizontal movements
    if (details.primaryDelta == null) return;
    if (details.delta.dx.abs() < details.delta.dy.abs()) return;

    // Accumulate drag offset
    _dragOffset += details.primaryDelta!;

    // Sensitivity: 0.2 seconds per pixel
    final sensitivity = 0.2;
    final addedSeconds = _dragOffset * sensitivity;

    final startSeconds = _seekStartPosition!.inSeconds.toDouble();
    final newTargetSeconds = (startSeconds + addedSeconds).clamp(
      0.0,
      _player.state.duration.inSeconds.toDouble(),
    );

    final newTargetPosition = Duration(seconds: newTargetSeconds.toInt());
    final totalDuration = _player.state.duration;

    // Formatting
    final diff = newTargetPosition - _seekStartPosition!;
    final sign = diff.isNegative ? '-' : '+';
    final diffString = '$sign${_formatDuration(diff.abs())}';
    final currentString = _formatDuration(newTargetPosition);
    final totalString = _formatDuration(totalDuration);

    setState(() {
      _seekTargetPosition = newTargetPosition;
      _seekPreviewText = '$diffString\n$currentString / $totalString';
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (!_isSeeking || _seekTargetPosition == null) return;

    _player.seek(_seekTargetPosition!);

    setState(() {
      _isSeeking = false;
      _dragOffset = 0.0;
      _seekStartPosition = null;
      _seekTargetPosition = null;
    });
  }

  Widget _buildSeekOverlay() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black26, // Semi-transparent subtle background
          borderRadius: BorderRadius.circular(12),
        ),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5), // Blur effect
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                (_seekTargetPosition?.compareTo(
                              _seekStartPosition ?? Duration.zero,
                            ) ??
                            0) >=
                        0
                    ? Icons.fast_forward
                    : Icons.fast_rewind,
                color: Colors.white,
                size: 28, // Smaller icon
              ),
              const SizedBox(height: 4),
              Text(
                _seekPreviewText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14, // Smaller text
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    // Hide overlays after a delay
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showBrightnessOverlay = false;
          _showVolumeOverlay = false;
        });
      }
    });
  }

  Future<void> _loadSubtitles() async {
    try {
      File? videoFile;
      if (widget.videoFile != null) {
        videoFile = await widget.videoFile!.file;
      } else if (widget.videoPath != null) {
        videoFile = File(widget.videoPath!);
      }

      if (videoFile == null) return;

      // Auto-discover .srt file with same basename
      final videoPath = videoFile.path;
      final srtPath = videoPath.replaceAll(RegExp(r'\.\w+$'), '.srt');

      final srtFile = File(srtPath);
      if (await srtFile.exists()) {
        final subtitles = await SubtitleService.parseSRT(srtFile);
        final fileName = srtPath.split(Platform.pathSeparator).last;
        if (mounted) {
          setState(() {
            _subtitles = subtitles;
            _subtitleFileName = fileName;
            _subtitleFilePath = srtPath;
            _useInternalSubtitles = false;
            _subtitlesEnabled = true; // Auto-enable subtitles when loaded
          });
        }
      }
    } catch (e) {
      // Silently fail if subtitle loading fails
      debugPrint('Subtitle loading failed: $e');
    }
  }

  // Restore subtitle prefs persisted for this video, or fall back to the
  // existing auto-discover behavior the first time it's played. Either way
  // the resulting state is persisted so subsequent sessions are seamless.
  Future<void> _restoreOrLoadSubtitles() async {
    final id = _currentVideoId;
    final prefs = id != null
        ? await _historyService.getSubtitlePrefs(id)
        : null;

    if (prefs == null) {
      await _loadSubtitles();
      _persistSubtitlePrefs();
      return;
    }

    final enabled = prefs['enabled'] as bool? ?? false;
    final useInternal = prefs['useInternal'] as bool? ?? true;
    final srtPath = prefs['srtPath'] as String?;

    // External SRT was previously selected for this video.
    if (!useInternal && srtPath != null) {
      final srtFile = File(srtPath);
      if (await srtFile.exists()) {
        try {
          final subtitles = await SubtitleService.parseSRT(srtFile);
          if (mounted) {
            setState(() {
              _subtitles = subtitles;
              _subtitleFileName = srtPath.split(Platform.pathSeparator).last;
              _subtitleFilePath = srtPath;
              _useInternalSubtitles = false;
              _subtitlesEnabled = enabled;
            });
          }
          return;
        } catch (e) {
          debugPrint('Failed to parse saved subtitle: $e');
        }
      } else {
        debugPrint('Saved subtitle file missing: $srtPath');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saved subtitle file is missing. Please reselect.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
      // Missing or unreadable — fall back to auto-discover only if the user
      // had subtitles enabled, then re-persist whatever we ended up with.
      if (enabled) {
        await _loadSubtitles();
      }
      _persistSubtitlePrefs();
      return;
    }

    // Internal-track preference: just restore the binary choice and the
    // enabled flag. The player will surface its default internal track.
    if (mounted) {
      setState(() {
        _useInternalSubtitles = true;
        _subtitleFilePath = null;
        _subtitlesEnabled = enabled;
      });
    }
  }

  // Snapshot the current subtitle state and persist it for this video.
  void _persistSubtitlePrefs() {
    final id = _currentVideoId;
    if (id == null) return;
    _historyService.saveSubtitlePrefs(
      id,
      enabled: _subtitlesEnabled,
      useInternal: _useInternalSubtitles,
      srtPath: _useInternalSubtitles ? null : _subtitleFilePath,
    );
  }

  void _updateSubtitle() {
    if (_subtitles == null || _subtitles!.isEmpty) {
      return;
    }

    final position = _player.state.position;

    // Reset index if we jumped backwards
    if (position < _lastSubtitleSearchPosition) {
      _currentSubtitleIndex = 0;
    }
    _lastSubtitleSearchPosition = position;

    // Efficient index tracker - start from last known position
    for (int i = _currentSubtitleIndex; i < _subtitles!.length; i++) {
      final sub = _subtitles![i];
      if (position >= sub.start && position <= sub.end) {
        if (_currentSubtitle != sub) {
          // Optimistically clear the saved-state so the bookmark never
          // shows stale "green" while the async lookup runs. The check
          // below will set it back to true iff this exact sentence is
          // already in the database.
          setState(() {
            _currentSubtitle = sub;
            _currentSubtitleIndex = i;
            _isCurrentSentenceSaved = false;
          });
          _checkIfSentenceSaved(sub.text);
        }
        return;
      }
    }

    // Clear subtitle if no match
    if (_currentSubtitle != null) {
      setState(() {
        _currentSubtitle = null;
        _isCurrentSentenceSaved = false;
        // Don't reset index to 0, keep it for efficiency
      });
    }
  }

  Future<void> _checkIfSentenceSaved(String sentence) async {
    final isSaved = await DatabaseService().isSentenceSaved(sentence);
    if (mounted) {
      setState(() {
        _isCurrentSentenceSaved = isSaved;
      });
    }
  }

  Future<void> _handleSaveSentence(String sentence) async {
    final videoTitle =
        widget.videoFile?.title ??
        widget.videoPath?.split(Platform.pathSeparator).last ??
        'Unknown Video';

    File? videoFile;
    if (widget.videoFile != null) {
      videoFile = await widget.videoFile!.file;
    } else if (widget.videoPath != null) {
      videoFile = File(widget.videoPath!);
    }

    final videoPath = videoFile?.path;
    final timestampMs = _player.state.position.inMilliseconds;

    await DatabaseService().saveSentence(
      sentence: sentence,
      videoTitle: videoTitle,
      videoPath: videoPath,
      timestampMs: timestampMs,
    );

    if (mounted) {
      setState(() {
        _isCurrentSentenceSaved = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sentence Saved!'),
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFF00C853),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleCCButton() async {
    debugPrint('======= CC Button tapped =======');

    // Always show subtitle settings in side panel first
    SidePanel.show(
      context: context,
      title: 'Subtitle',
      children: [
        // Toggle between Built-in and External
        // Unified Subtitle List

        // 1. Embedded Subtitles Options (Dynamic)
        if (_player.state.tracks.subtitle.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              "Embedded Tracks",
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          ..._player.state.tracks.subtitle.map((track) {
            final isSelected =
                _useInternalSubtitles && _player.state.track.subtitle == track;
            return ListTile(
              leading: Icon(
                Icons.subtitles,
                color: isSelected ? const Color(0xFF00C853) : Colors.white,
              ),
              title: Text(
                track.title ?? track.language ?? 'Track ${track.id}',
                style: TextStyle(
                  color: isSelected ? const Color(0xFF00C853) : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check, color: Color(0xFF00C853), size: 18)
                  : null,
              onTap: () {
                setState(() {
                  _useInternalSubtitles = true;
                  _subtitles = null; // Clear external
                  _subtitleFileName = null;
                  _subtitleFilePath = null;
                  _currentSubtitle = null;
                  _subtitlesEnabled = true;

                  // Set track
                  _player.setSubtitleTrack(track);

                  _liveInternalCaption = null; // Ghost fix
                });
                _persistSubtitlePrefs();
                Navigator.pop(context);
              },
            );
          }).toList(),
          const Divider(color: Colors.white12, height: 1),
        ],

        // Option to disable internal subtitles if no track selected or specifically "None"
        ListTile(
          leading: const Icon(Icons.subtitles_off, color: Colors.white),
          title: const Text(
            "None (Internal)",
            style: TextStyle(color: Colors.white),
          ),
          onTap: () {
            _player.setSubtitleTrack(SubtitleTrack.no());
            setState(() {
              _liveInternalCaption = null;
            });
            Navigator.pop(context);
          },
        ),

        // 2. External File Option (if loaded)
        if (_subtitles != null && _subtitleFileName != null)
          ListTile(
            leading: Icon(
              Icons.description,
              color: !_useInternalSubtitles
                  ? const Color(0xFF00C853)
                  : Colors.white,
            ),
            title: Text(
              _subtitleFileName!,
              style: TextStyle(
                color: !_useInternalSubtitles
                    ? const Color(0xFF00C853)
                    : Colors.white,
                fontSize: 15,
                fontWeight: !_useInternalSubtitles
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: !_useInternalSubtitles
                ? const Icon(Icons.check, color: Color(0xFF00C853), size: 18)
                : IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 18,
                    ),
                    onPressed: () {
                      setState(() {
                        _subtitles = null;
                        _subtitleFileName = null;
                        _subtitleFilePath = null;
                        _useInternalSubtitles = true; // Revert to internal
                        _liveInternalCaption = null;
                      });
                      _persistSubtitlePrefs();
                      Navigator.pop(context);
                    },
                  ),
            onTap: () {
              setState(() {
                _useInternalSubtitles = false;
                _subtitlesEnabled = true;
                _liveInternalCaption = null; // Ghost fix
                _lastCapturedInternalCaption = null;
              });
              _persistSubtitlePrefs();
              Navigator.pop(context);
            },
          ),

        const Divider(color: Colors.white12, height: 1),

        // Select subtitle button (Always visible)
        ListTile(
          leading: const Icon(Icons.folder_open, color: Colors.white),
          title: const Text(
            'Select subtitle',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          onTap: () {
            setState(() {
              _useInternalSubtitles =
                  false; // Disable internal when loading external
              _liveInternalCaption = null; // Ghost fix
              _lastCapturedInternalCaption = null;
            });
            Navigator.pop(context);
            _loadSubtitleFile();
          },
        ),

        /*
        // Online subtitle button (Always visible)
        ListTile(
          leading: const Icon(Icons.public, color: Color(0xFF00C853)),
          title: const Text(
            'Online subtitle',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          onTap: () {
            Navigator.pop(context);
            _showOnlineSubtitleSearch();
          },
        ),
        */

        // Only show customization if subtitles are loaded
        if (_subtitles != null) ...[
          const Divider(color: Colors.white12, height: 1),

          // Customization section header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Customization',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          StatefulBuilder(
            builder: (context, setPanelState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Show/Hide toggle
                  SwitchListTile(
                    secondary: Icon(
                      _subtitlesEnabled
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: Colors.white,
                    ),
                    title: const Text(
                      'Show subtitles',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    value: _subtitlesEnabled,
                    onChanged: (value) {
                      setState(() => _subtitlesEnabled = value);
                      _persistSubtitlePrefs();
                      setPanelState(() {});
                    },
                    activeColor: const Color(0xFF00C853),
                  ),

                  // Text size control
                  ListTile(
                    leading: const Icon(Icons.text_fields, color: Colors.white),
                    title: const Text(
                      'Text size',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.remove,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _subtitleTextSize = (_subtitleTextSize - 2)
                                    .clamp(12.0, 32.0);
                              });
                              setPanelState(() {});
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Text(
                              _subtitleTextSize.toInt().toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _subtitleTextSize = (_subtitleTextSize + 2)
                                    .clamp(12.0, 32.0);
                              });
                              setPanelState(() {});
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Future<void> _loadSubtitleFile() async {
    debugPrint('_loadSubtitleFile() called');
    try {
      debugPrint('Calling FilePicker.platform.pickFiles...');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt'],
      );

      debugPrint('FilePicker result: $result, files: ${result?.files.length}');

      if (result != null && result.files.single.path != null) {
        final srtFile = File(result.files.single.path!);
        final fileName = result.files.single.name;
        final srtPath = srtFile.path;
        debugPrint('Loading subtitle: $fileName');
        final subtitles = await SubtitleService.parseSRT(srtFile);
        if (mounted) {
          setState(() {
            _subtitles = subtitles;
            _subtitlesEnabled = true;
            _subtitleFileName = fileName;
            _subtitleFilePath = srtPath;
            _useInternalSubtitles = false;
            _currentSubtitleIndex = 0;
            _currentSubtitle = null;
          });
          _persistSubtitlePrefs();
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Subtitle file selection failed: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  void _showOnlineSubtitleSearch() {
    final videoTitle =
        widget.videoFile?.title ??
        widget.videoPath?.split(Platform.pathSeparator).last.split('.').first ??
        '';

    SidePanel.show(
      context: context,
      title: 'Online Search',
      children: [
        OnlineSubtitleSearchContent(
          initialQuery: videoTitle,
          videoPath: _resolvedVideoPath ?? widget.videoPath,
          subtitleDownloadService: _subtitleDownloadService,
          onSubtitleDownloaded: (path) async {
            // Seamless player refresh
            if (mounted) {
              final subtitles = await SubtitleService.parseSRT(File(path));
              setState(() {
                _subtitles = subtitles;
                _subtitlesEnabled = true;
                _subtitleFileName = p.basename(path);
                _subtitleFilePath = path;
                _useInternalSubtitles = false;
                _currentSubtitleIndex = 0;
                _currentSubtitle = null;
              });
              _persistSubtitlePrefs();

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Subtitles synchronized successfully!'),
                  backgroundColor: Color(0xFF00C853),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        ),
      ],
    );
  }

  void _onWordTap(String word, String sentence) {
    debugPrint('Word tapped: $word');
    _player.pause();
    setState(() => _selectedWord = word);

    // Normalize word for consistency (Title Case)
    final normalizedWord =
        word[0].toUpperCase() + word.substring(1).toLowerCase();

    // Lookup definition (Service handles its own normalization for lookup)
    final definition = DictionaryService().lookup(word);

    // Save to history if found (Fire and forget)
    // Use normalizedWord so simple & capitalized versions map to same entry.
    // Persist the full subtitle line verbatim alongside the word.
    if (definition != null) {
      DatabaseService().upsertWord(
        normalizedWord,
        definition,
        sentence: sentence,
      );
    }

    // Show word definition in side panel
    SidePanel.show(
      context: context,
      title: normalizedWord,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (definition != null) ...[
                // Definition
                Text(
                  definition,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
              ] else
                Column(
                  children: [
                    const Icon(
                      Icons.search_off,
                      color: Colors.white54,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Definition not found',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Could not find a definition for "$word" in the local dictionary.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _onModalClose();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C853),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((_) => _onModalClose());
  }

  void _onModalClose() {
    _player.play();
    setState(() => _selectedWord = null);
  }

  void _onSentenceLongPress() {
    debugPrint('Sentence long press');
    // TODO: Implement sentence translation in Phase 4C
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    _overlayTimer?.cancel();
    _saveProgress();

    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    _subtitleSubscription?.cancel();

    _player.dispose();

    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _saveProgress() async {
    // Don't overwrite a previously saved position with ~0 if we exited
    // before the resume-seek had a chance to be applied.
    if (!_initialSeekComplete) return;

    final duration = _player.state.duration;
    if (duration != Duration.zero) {
      final position = _player.state.position.inSeconds;
      final videoId = widget.videoFile?.id ?? widget.videoPath ?? 'unknown';
      await _historyService.saveProgress(
        videoId,
        position,
        volume: _playerVolume,
      );
    }
  }

  void _toggleOrientation() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (isLandscape) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00C853)),
            )
          : GestureDetector(
              onTap: _toggleControls,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Video Layer - disable built-in controls
                  Center(
                    child: Video(
                      controller: _controller,
                      controls: NoVideoControls,
                      subtitleViewConfiguration: const SubtitleViewConfiguration(
                        visible:
                            false, // Hide native subtitles, use SubtitleOverlay instead
                      ),
                    ),
                  ),

                  // Middle Gesture Zone (60%)
                  Positioned(
                    top: MediaQuery.of(context).size.height * 0.2,
                    height: MediaQuery.of(context).size.height * 0.6,
                    left: 0,
                    right: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _toggleControls,
                      onDoubleTapDown: _handleDoubleTap,
                      onLongPressStart: _handleLongPressStart,
                      onLongPressEnd: _handleLongPressEnd,
                      onVerticalDragStart: _handleVerticalDragStart,
                      onVerticalDragUpdate: _handleVerticalDragUpdate,
                      onVerticalDragEnd: _handleVerticalDragEnd,
                      onHorizontalDragStart: _handleHorizontalDragStart,
                      onHorizontalDragUpdate: _handleHorizontalDragUpdate,
                      onHorizontalDragEnd: _handleHorizontalDragEnd,
                    ),
                  ),

                  // Visual Overlays
                  if (_seekFeedback != null) _buildSeekFeedback(),
                  if (_isSeeking) _buildSeekOverlay(),
                  if (_isLongPressing) _build2xSpeedIndicator(),
                  if (_showBrightnessOverlay)
                    GestureHud(
                      icon: Icons.wb_sunny_outlined,
                      value: _currentBrightness ?? 0.5,
                    ),
                  if (_showVolumeOverlay)
                    GestureHud(
                      icon: (_currentVolume ?? 0) <= 0
                          ? Icons.volume_off
                          : Icons.volume_up,
                      value: _currentVolume ?? 1.0,
                    ),

                  // Subtitles
                  if (_subtitlesEnabled)
                    SubtitleOverlay(
                      displayText: _useInternalSubtitles
                          ? _liveInternalCaption
                          : _currentSubtitle?.text,
                      fontSize: _subtitleTextSize,
                      isLearningMode: _isLearningMode,
                      selectedWord: _selectedWord,
                      onWordTap: _onWordTap,
                      onLongPress: _onSentenceLongPress,
                      onSaveSentence: _handleSaveSentence,
                      isSaved: _isCurrentSentenceSaved,
                    ),

                  // Controls Overlay
                  if (_showControls || _isLocked) _buildControls(),
                ],
              ),
            ),
    );
  }

  Widget _buildControls() {
    final position = _player.state.position;
    final duration = _player.state.duration;
    final isPlaying = _player.state.playing;

    return Stack(
      children: [
        // Background dim
        if (_showControls || _isLocked)
          IgnorePointer(child: Container(color: Colors.black45)),

        // Controls
        if (_showControls)
          SafeArea(
            child: Stack(
              children: [
                // Top bar
                if (!_isLocked)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Text(
                            widget.videoFile?.title ??
                                widget.videoPath
                                    ?.split(Platform.pathSeparator)
                                    .last ??
                                'Video',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _subtitlesEnabled
                                ? Icons.closed_caption
                                : Icons.closed_caption_outlined,
                            color: _subtitlesEnabled
                                ? const Color(0xFF00C853)
                                : Colors.white,
                          ),
                          onPressed: _handleCCButton,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                          ),
                          onPressed: _showLearningModeMenu,
                        ),
                      ],
                    ),
                  ),

                // Center - Play/Pause
                if (!_isLocked)
                  Center(
                    child: IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 48,
                      ),
                      onPressed: _togglePlayPause,
                    ),
                  ),

                // Right controls
                if (!_isLocked)
                  Positioned(
                    right: 16,
                    bottom: 100,
                    child: Column(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.screen_rotation,
                            color: Colors.white,
                          ),
                          onPressed: _toggleOrientation,
                        ),
                        const SizedBox(height: 16),
                        IconButton(
                          icon: Icon(
                            _isMuted ? Icons.volume_off : Icons.volume_up,
                            color: Colors.white,
                          ),
                          onPressed: _toggleMute,
                        ),
                      ],
                    ),
                  ),

                // Lock Button (Left Bottom)
                Positioned(
                  left: 16,
                  bottom: 100,
                  child: IconButton(
                    icon: Icon(
                      _isLocked ? Icons.lock : Icons.lock_open,
                      color: Colors.white,
                    ),
                    onPressed: _toggleLock,
                  ),
                ),

                // Bottom Seek Bar
                if (!_isLocked)
                  Positioned(
                    bottom: 40,
                    left: 0,
                    right: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text(
                                _formatDuration(position),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: position.inMilliseconds
                                      .toDouble()
                                      .clamp(
                                        0,
                                        duration.inMilliseconds.toDouble(),
                                      ),
                                  min: 0,
                                  max: duration.inMilliseconds.toDouble(),
                                  activeColor: const Color(0xFF00C853),
                                  inactiveColor: Colors.white24,
                                  onChanged: (value) {
                                    _player.seek(
                                      Duration(milliseconds: value.toInt()),
                                    );
                                  },
                                ),
                              ),
                              Text(
                                _formatDuration(duration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSeekFeedback() {
    final isForward = _seekFeedback == 'forward';
    return Positioned(
      left: isForward ? null : 40,
      right: isForward ? 40 : null,
      top: MediaQuery.of(context).size.height * 0.45,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color.fromARGB(100, 0, 0, 0),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isForward ? Icons.forward_10 : Icons.replay_10,
          color: Colors.white,
          size: 36,
        ),
      ),
    );
  }

  Widget _build2xSpeedIndicator() {
    return Positioned(
      top: 20,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF00C853),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            '2x',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class OnlineSubtitleSearchContent extends StatefulWidget {
  final String initialQuery;
  final String? videoPath;
  final SubtitleDownloadService subtitleDownloadService;
  final Function(String) onSubtitleDownloaded;

  const OnlineSubtitleSearchContent({
    super.key,
    required this.initialQuery,
    required this.videoPath,
    required this.subtitleDownloadService,
    required this.onSubtitleDownloaded,
  });

  @override
  State<OnlineSubtitleSearchContent> createState() =>
      _OnlineSubtitleSearchContentState();
}

class _OnlineSubtitleSearchContentState
    extends State<OnlineSubtitleSearchContent> {
  late TextEditingController _searchController;
  List<Map<String, dynamic>>? _results;
  bool _isSearching = false;
  double? _downloadProgress;

  String? _movieHash;
  bool _isCalculatingHash = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery);
    // Trigger auto-search after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSearch();
    });
  }

  Future<void> _initSearch() async {
    // 1. Calculate Hash first
    if (widget.videoPath != null) {
      setState(() => _isCalculatingHash = true);
      try {
        final hash = await SubtitleService.computeMovieHash(
          File(widget.videoPath!),
        );
        if (mounted) {
          setState(() {
            _movieHash = hash;
            _isCalculatingHash = false;
          });
          print('Computed MovieHash: $hash');
        }
      } catch (e) {
        print('Error computing hash: $e');
        if (mounted) setState(() => _isCalculatingHash = false);
      }
    }

    // 2. Perform search
    if (_searchController.text.isNotEmpty || _movieHash != null) {
      _performSearch();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty && _movieHash == null) return;

    setState(() {
      _isSearching = true;
      _results = null; // Clear previous results
    });

    debugPrint('Performing search for: $query (Hash: $_movieHash)');
    final items = await widget.subtitleDownloadService.searchSubtitles(
      query,
      movieHash: _movieHash,
    );

    if (mounted) {
      setState(() {
        _isSearching = false;
        _results = items ?? [];
      });
      debugPrint('Search completed. Results: ${_results?.length}');
    }
  }

  Future<void> _handleDownload(Map<String, dynamic> item) async {
    setState(() => _downloadProgress = -1);

    try {
      String? targetPath;
      if (widget.videoPath != null) {
        final dir = File(widget.videoPath!).parent.path;
        // USE ORIGINAL FILENAME from the search result exactly as requested
        String originalFileName =
            item['filename'] ?? 'subtitle_${item['id']}.srt';

        // Ensure it ends with .srt
        String finalName = originalFileName;
        if (!finalName.toLowerCase().endsWith('.srt')) {
          finalName = '$finalName.srt';
        }

        targetPath = p.join(dir, finalName);
      }

      if (targetPath == null)
        throw Exception('Local target path could not be determined.');

      debugPrint('Downloading subtitle ${item['id']} to $targetPath');
      // This will now throw a descriptive Exception if it fails
      await widget.subtitleDownloadService.downloadSubtitle(
        int.parse(item['id'].toString()),
        targetPath,
      );

      if (mounted) {
        Navigator.pop(context); // Close panel
        widget.onSubtitleDownloaded(targetPath);
      }
    } catch (e) {
      debugPrint('Download error: $e');
      if (mounted) {
        setState(() => _downloadProgress = null);

        final errorStr = e.toString();
        // Check if authentication is required (403 Forbidden)
        if (errorStr.contains('403') || errorStr.contains('Unauthorized')) {
          _showLoginDialog(onSuccess: () => _handleDownload(item));
          return;
        }

        // Show the ACTUAL error message from the API or System
        final displayError = errorStr.replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayError),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'LOGIN',
              textColor: Colors.white,
              onPressed: () =>
                  _showLoginDialog(onSuccess: () => _handleDownload(item)),
            ),
          ),
        );
      }
    }
  }

  void _showLoginDialog({required VoidCallback onSuccess}) {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    bool isLoggingIn = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'OpenSubtitles Login',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'A free OpenSubtitles.com account is required for downloads.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  labelStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                ),
                obscureText: true,
                style: const TextStyle(color: Colors.white),
              ),
              if (isLoggingIn)
                const Padding(
                  padding: EdgeInsets.only(top: 16.0),
                  child: CircularProgressIndicator(color: Color(0xFF00C853)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: isLoggingIn
                  ? null
                  : () async {
                      setDialogState(() => isLoggingIn = true);
                      final success = await widget.subtitleDownloadService
                          .login(
                            usernameController.text.trim(),
                            passwordController.text,
                          );
                      if (mounted) {
                        if (success) {
                          Navigator.pop(context);
                          onSuccess();
                        } else {
                          setDialogState(() => isLoggingIn = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Login failed. Please check your credentials.',
                              ),
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C853),
              ),
              child: const Text(
                'Login & Download',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search subtitles...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(
                        Icons.clear,
                        size: 18,
                        color: Colors.white54,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.search, color: Color(0xFF00C853)),
                    onPressed: _isSearching ? null : _performSearch,
                  ),
                ],
              ),
            ),
            onSubmitted: (_) => _performSearch(),
          ),

          if (_isCalculatingHash) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Computing file signature...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          if (_downloadProgress != null) ...[
            const Text(
              'Downloading...',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _downloadProgress == -1 ? null : _downloadProgress,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF00C853),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_isSearching)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(color: Color(0xFF00C853)),
              ),
            )
          else if (_results != null && _results!.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Icon(
                      Icons.search_off,
                      color: Colors.white38,
                      size: 40,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No results found',
                      style: TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Try a different movie name or broad search.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else if (_results == null &&
              !_isSearching &&
              (_searchController.text.isNotEmpty || _movieHash != null))
            Center(
              child: Column(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Search failed. Try again.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  TextButton(
                    onPressed: _performSearch,
                    child: const Text(
                      'RETRY',
                      style: TextStyle(color: Color(0xFF00C853)),
                    ),
                  ),
                ],
              ),
            )
          else if (_results != null)
            ..._results!.map(
              (item) => Card(
                color: Colors.white.withOpacity(0.05),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    item['filename'],
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'Language: ${item['language']} • Downloads: ${item['download_count']}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.download, color: Color(0xFF00C853)),
                    onPressed: () => _handleDownload(item),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
