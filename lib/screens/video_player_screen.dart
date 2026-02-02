import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../services/history_service.dart';
import '../services/subtitle_service.dart';
import '../models/subtitle_entry.dart';
import '../widgets/subtitle_overlay.dart';
import '../widgets/side_panel.dart';
import '../services/dictionary_service.dart';
import '../services/database_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final AssetEntity videoFile;

  const VideoPlayerScreen({super.key, required this.videoFile});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _showControls = true;
  bool _isLocked = false;
  bool _isMuted = false;
  double _playbackSpeed = 1.0;
  double _savedSpeed = 1.0;
  Timer? _hideTimer;

  final HistoryService _historyService = HistoryService();

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
  double _subtitleTextSize = 18.0;
  bool _isLearningMode = false;
  String? _selectedWord;
  Duration _lastSubtitleSearchPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    WakelockPlus.enable();
  }

  Future<void> _initializePlayer() async {
    final file = await widget.videoFile.file;
    if (file == null) {
      setState(() => _isLoading = false);
      return;
    }

    _controller = VideoPlayerController.file(file);
    await _controller!.initialize();

    // Restore progress
    final savedPosition = await _historyService.getProgress(
      widget.videoFile.id,
    );
    if (savedPosition > 0 &&
        savedPosition < _controller!.value.duration.inSeconds) {
      await _controller!.seekTo(Duration(seconds: savedPosition));
    }

    _controller!.play();
    _controller!.addListener(_videoListener);
    _controller!.setVolume(_playerVolume);

    // Save to history immediately when video starts
    await _historyService.saveProgress(widget.videoFile.id, savedPosition);

    // Load subtitles
    await _loadSubtitles();

    // Initialize dictionary
    await DictionaryService().initialize();

    setState(() => _isLoading = false);
    _startHideTimer();
  }

  void _videoListener() {
    if (mounted) {
      _updateSubtitle();
      setState(() {});
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_isLocked) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_isLocked) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
        _startHideTimer();
      }
    });
  }

  void _toggleMute() {
    if (_controller == null) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : _playerVolume);
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
              _controller?.setPlaybackSpeed(speed);
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
    if (_controller == null) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final isRightSide = details.globalPosition.dx > screenWidth / 2;

    final currentPosition = _controller!.value.position;
    final seekDuration = isRightSide ? 10 : -10;
    final newPosition = currentPosition + Duration(seconds: seekDuration);

    _controller!.seekTo(newPosition);

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
    if (_controller == null || _isLongPressing) return;
    setState(() {
      _isLongPressing = true;
      _savedSpeed = _playbackSpeed;
      _playbackSpeed = 2.0;
      _controller?.setPlaybackSpeed(2.0);
    });
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    if (_controller == null || !_isLongPressing) return;
    setState(() {
      _isLongPressing = false;
      _playbackSpeed = _savedSpeed;
      _controller?.setPlaybackSpeed(_savedSpeed);
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

    final delta = -details.delta.dy / screenHeight;

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
        _controller?.setVolume(newVolume);
      }
      _initialVolume = newVolume;
      setState(() => _currentVolume = newVolume);
    }
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
      final videoFile = await widget.videoFile.file;
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
            _subtitlesEnabled = true; // Auto-enable subtitles when loaded
          });
        }
      }
    } catch (e) {
      // Silently fail if subtitle loading fails
      debugPrint('Subtitle loading failed: $e');
    }
  }

  void _updateSubtitle() {
    if (_subtitles == null || _subtitles!.isEmpty || _controller == null) {
      return;
    }

    final position = _controller!.value.position;

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
          setState(() {
            _currentSubtitle = sub;
            _currentSubtitleIndex = i;
          });
        }
        return;
      }
    }

    // Clear subtitle if no match
    if (_currentSubtitle != null) {
      setState(() {
        _currentSubtitle = null;
        // Don't reset index to 0, keep it for efficiency
      });
    }
  }

  Future<void> _handleCCButton() async {
    debugPrint('======= CC Button tapped =======');
    debugPrint(
      '_subtitles: ${_subtitles != null}, length: ${_subtitles?.length}',
    );

    if (_subtitles == null) {
      // Load subtitle file
      debugPrint('Opening file picker...');
      await _loadSubtitleFile();
    } else {
      // Show subtitle settings in side panel
      SidePanel.show(
        context: context,
        title: 'Subtitle',
        children: [
          // Current subtitle file
          if (_subtitleFileName != null)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.subtitles, color: Colors.white70, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _subtitleFileName!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 18,
                    ),
                    onPressed: () {
                      setState(() {
                        _subtitles = null;
                        _subtitleFileName = null;
                        _subtitlesEnabled = false;
                      });
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),

          // Select files button
          ListTile(
            leading: const Icon(Icons.folder_open, color: Colors.white),
            title: const Text(
              'Select files',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
            onTap: () {
              Navigator.pop(context);
              _loadSubtitleFile();
            },
          ),

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
      );
    }
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
        debugPrint('Loading subtitle: $fileName');
        final subtitles = await SubtitleService.parseSRT(srtFile);
        if (mounted) {
          setState(() {
            _subtitles = subtitles;
            _subtitlesEnabled = true;
            _subtitleFileName = fileName;
            _currentSubtitleIndex = 0;
            _currentSubtitle = null;
          });
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Subtitle file selection failed: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  void _onWordTap(String word) {
    debugPrint('Word tapped: $word');
    _controller?.pause();
    setState(() => _selectedWord = word);

    // Normalize word for consistency (Title Case)
    final normalizedWord =
        word[0].toUpperCase() + word.substring(1).toLowerCase();

    // Lookup definition (Service handles its own normalization for lookup)
    final definition = DictionaryService().lookup(word);

    // Save to history if found (Fire and forget)
    // Use normalizedWord so simple & capitalized versions map to same entry
    if (definition != null) {
      DatabaseService().upsertWord(normalizedWord, definition);
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
    _controller?.play();
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
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _saveProgress() async {
    if (_controller != null && _controller!.value.isInitialized) {
      final position = _controller!.value.position.inSeconds;
      await _historyService.saveProgress(widget.videoFile.id, position);
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
          : _controller != null && _controller!.value.isInitialized
          ? GestureDetector(
              onTap: _toggleControls,
              onDoubleTapDown: _handleDoubleTap,
              onLongPressStart: _handleLongPressStart,
              onLongPressEnd: _handleLongPressEnd,
              onVerticalDragStart: _handleVerticalDragStart,
              onVerticalDragUpdate: _handleVerticalDragUpdate,
              onVerticalDragEnd: _handleVerticalDragEnd,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Video
                  Center(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                  ),

                  // Seek feedback overlay
                  if (_seekFeedback != null) _buildSeekFeedback(),

                  // 2x speed indicator
                  if (_isLongPressing) _build2xSpeedIndicator(),

                  // Brightness overlay
                  if (_showBrightnessOverlay) _buildBrightnessOverlay(),

                  // Volume overlay
                  if (_showVolumeOverlay) _buildVolumeOverlay(),

                  // Subtitle overlay
                  if (_subtitlesEnabled && _currentSubtitle != null)
                    SubtitleOverlay(
                      currentSubtitle: _currentSubtitle,
                      fontSize: _subtitleTextSize,
                      isLearningMode: _isLearningMode,
                      selectedWord: _selectedWord,
                      onWordTap: _onWordTap,
                      onLongPress: _onSentenceLongPress,
                    ),

                  // Controls overlay
                  if (_showControls || _isLocked) _buildControls(),
                ],
              ),
            )
          : const Center(
              child: Text(
                'Error loading video',
                style: TextStyle(color: Colors.white),
              ),
            ),
    );
  }

  Widget _buildControls() {
    final position = _controller?.value.position ?? Duration.zero;
    final duration = _controller?.value.duration ?? Duration.zero;
    final isPlaying = _controller?.value.isPlaying ?? false;

    return Container(
      color: const Color.fromARGB(128, 0, 0, 0),
      child: SafeArea(
        child: Stack(
          children: [
            // Top bar
            if (!_isLocked)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black54, Colors.transparent],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.videoFile.title ?? 'Video',
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
                        icon: const Icon(Icons.headphones, color: Colors.white),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.playlist_play,
                          color: Colors.white,
                        ),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        onPressed: _showLearningModeMenu,
                      ),
                    ],
                  ),
                ),
              ),

            // Left controls
            Positioned(
              left: 12,
              top: MediaQuery.of(context).size.height * 0.3,
              child: Column(
                children: [
                  IconButton(
                    icon: Icon(
                      _isMuted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: _toggleMute,
                  ),
                  const SizedBox(height: 16),
                  IconButton(
                    icon: Icon(
                      _isLocked ? Icons.lock : Icons.lock_open,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: _toggleLock,
                  ),
                ],
              ),
            ),

            // Right controls
            if (!_isLocked)
              Positioned(
                right: 12,
                top: MediaQuery.of(context).size.height * 0.3,
                child: IconButton(
                  icon: const Icon(
                    Icons.screen_rotation,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: _toggleOrientation,
                ),
              ),

            // Bottom controls
            if (!_isLocked)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black54],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Seek bar
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
                              value: position.inMilliseconds.toDouble(),
                              max: duration.inMilliseconds.toDouble(),
                              activeColor: const Color(0xFF00C853),
                              inactiveColor: Colors.white24,
                              onChanged: (value) {
                                _controller?.seekTo(
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
                      // Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: Icon(
                              isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                              color: Colors.white,
                              size: 40,
                            ),
                            onPressed: _togglePlayPause,
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.skip_previous,
                              color: Colors.white54,
                              size: 32,
                            ),
                            onPressed: null,
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.skip_next,
                              color: Colors.white54,
                              size: 32,
                            ),
                            onPressed: null,
                          ),
                          TextButton(
                            onPressed: _showSpeedDialog,
                            child: const Text(
                              'Speed',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.picture_in_picture_alt,
                              color: Colors.white,
                              size: 24,
                            ),
                            onPressed: () {},
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

  Widget _buildBrightnessOverlay() {
    return Positioned(
      left: 30,
      top: MediaQuery.of(context).size.height * 0.25,
      bottom: MediaQuery.of(context).size.height * 0.25,
      child: Container(
        width: 50,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color.fromARGB(179, 0, 0, 0),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.brightness_6, color: Colors.white, size: 24),
            const SizedBox(height: 8),
            Expanded(
              child: RotatedBox(
                quarterTurns: -1,
                child: LinearProgressIndicator(
                  value: _currentBrightness ?? 0.5,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF00C853),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${((_currentBrightness ?? 0.5) * 100).toInt()}%',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeOverlay() {
    return Positioned(
      right: 30,
      top: MediaQuery.of(context).size.height * 0.25,
      bottom: MediaQuery.of(context).size.height * 0.25,
      child: Container(
        width: 50,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color.fromARGB(179, 0, 0, 0),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _currentVolume == 0 ? Icons.volume_off : Icons.volume_up,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RotatedBox(
                quarterTurns: -1,
                child: LinearProgressIndicator(
                  value: _currentVolume ?? 1.0,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF00C853),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${((_currentVolume ?? 1.0) * 100).toInt()}%',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
