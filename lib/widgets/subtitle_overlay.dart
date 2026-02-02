import 'package:flutter/material.dart';
import '../models/subtitle_entry.dart';

class SubtitleOverlay extends StatelessWidget {
  final SubtitleEntry? currentSubtitle;
  final double fontSize;
  final bool isLearningMode;
  final String? selectedWord;
  final Function(String)? onWordTap;
  final VoidCallback? onLongPress;

  const SubtitleOverlay({
    super.key,
    this.currentSubtitle,
    this.fontSize = 18.0,
    this.isLearningMode = false,
    this.selectedWord,
    this.onWordTap,
    this.onLongPress,
  });

  List<String> _tokenizeSubtitle(String text) {
    final normalized = text.replaceAll('\n', ' ');
    return normalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  }

  String _cleanWord(String word) {
    // Remove leading/trailing punctuation but keep internal apostrophes
    return word.replaceAll(RegExp(r"^[.,!?;:()]+|[.,!?;:()]+$"), '');
  }

  @override
  Widget build(BuildContext context) {
    if (currentSubtitle == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 80, // Above controls
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          margin: const EdgeInsets.symmetric(horizontal: 32),
          child: isLearningMode
              ? _buildInteractiveSubtitle()
              : _buildStandardSubtitle(),
        ),
      ),
    );
  }

  Widget _buildInteractiveSubtitle() {
    final words = _tokenizeSubtitle(currentSubtitle!.text);

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 2,
      children: words.map((word) {
        final cleaned = _cleanWord(word);
        final isSelected = cleaned.toLowerCase() == selectedWord?.toLowerCase();

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: cleaned.isNotEmpty ? () => onWordTap?.call(cleaned) : null,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.green.withOpacity(0.4)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              word,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                height: 1.4,
                shadows: [
                  Shadow(
                    offset: const Offset(0, 1),
                    blurRadius: 3.0,
                    color: Colors.black.withOpacity(0.8),
                  ),
                  Shadow(
                    offset: const Offset(0, -1),
                    blurRadius: 3.0,
                    color: Colors.black.withOpacity(0.8),
                  ),
                  Shadow(
                    offset: const Offset(1, 0),
                    blurRadius: 3.0,
                    color: Colors.black.withOpacity(0.8),
                  ),
                  Shadow(
                    offset: const Offset(-1, 0),
                    blurRadius: 3.0,
                    color: Colors.black.withOpacity(0.8),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStandardSubtitle() {
    return Text(
      currentSubtitle!.text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        height: 1.4,
        shadows: [
          Shadow(
            offset: const Offset(0, 1),
            blurRadius: 3.0,
            color: Colors.black.withOpacity(0.8),
          ),
          Shadow(
            offset: const Offset(0, -1),
            blurRadius: 3.0,
            color: Colors.black.withOpacity(0.8),
          ),
          Shadow(
            offset: const Offset(1, 0),
            blurRadius: 3.0,
            color: Colors.black.withOpacity(0.8),
          ),
          Shadow(
            offset: const Offset(-1, 0),
            blurRadius: 3.0,
            color: Colors.black.withOpacity(0.8),
          ),
        ],
      ),
    );
  }
}
