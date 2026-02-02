class SubtitleEntry {
  final int index;
  final Duration start;
  final Duration end;
  final String text;

  SubtitleEntry({
    required this.index,
    required this.start,
    required this.end,
    required this.text,
  });

  @override
  String toString() {
    return 'SubtitleEntry(index: $index, start: $start, end: $end, text: $text)';
  }
}
