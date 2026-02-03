import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import '../models/subtitle_entry.dart';

class SubtitleService {
  /// Parse SRT file with automatic encoding detection
  static Future<List<SubtitleEntry>> parseSRT(File file) async {
    try {
      final bytes = await file.readAsBytes();
      String content;

      // Try UTF-8 first with malformed characters allowed
      try {
        content = utf8.decode(bytes, allowMalformed: true);
      } catch (e) {
        // Fallback to Latin-1 for older files
        content = latin1.decode(bytes);
      }

      return _parseContent(content);
    } catch (e) {
      throw Exception('Failed to parse SRT file: $e');
    }
  }

  static List<SubtitleEntry> _parseContent(String content) {
    final entries = <SubtitleEntry>[];
    final lines = content.split('\n');

    int i = 0;
    while (i < lines.length) {
      // Skip empty lines
      if (lines[i].trim().isEmpty) {
        i++;
        continue;
      }

      // Parse subtitle index
      final indexMatch = RegExp(r'^\d+$').firstMatch(lines[i].trim());
      if (indexMatch == null) {
        i++;
        continue;
      }
      final index = int.parse(lines[i].trim());
      i++;

      // Parse timecode line
      if (i >= lines.length) break;
      final timecodeMatch = RegExp(
        r'(\d{2}):(\d{2}):(\d{2}),(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2}),(\d{3})',
      ).firstMatch(lines[i]);

      if (timecodeMatch == null) {
        i++;
        continue;
      }

      final start = _parseTimestamp(
        timecodeMatch.group(1)!,
        timecodeMatch.group(2)!,
        timecodeMatch.group(3)!,
        timecodeMatch.group(4)!,
      );

      final end = _parseTimestamp(
        timecodeMatch.group(5)!,
        timecodeMatch.group(6)!,
        timecodeMatch.group(7)!,
        timecodeMatch.group(8)!,
      );
      i++;

      // Parse subtitle text (may be multiple lines)
      final textLines = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        textLines.add(lines[i].trim());
        i++;
      }

      if (textLines.isNotEmpty) {
        entries.add(
          SubtitleEntry(
            index: index,
            start: start,
            end: end,
            text: textLines.join('\n'),
          ),
        );
      }
    }

    return entries;
  }

  static Duration _parseTimestamp(
    String hours,
    String minutes,
    String seconds,
    String milliseconds,
  ) {
    return Duration(
      hours: int.parse(hours),
      minutes: int.parse(minutes),
      seconds: int.parse(seconds),
      milliseconds: int.parse(milliseconds),
    );
  }

  /// Compute OpenSubtitles MovieHash
  /// Algorithm: 64-bit sum of file size + first 64KB + last 64KB
  static Future<String> computeMovieHash(File file) async {
    final int fileSize = await file.length();
    int hash = fileSize;

    final raf = await file.open(mode: FileMode.read);
    try {
      // Read first 64KB
      final first64k = await raf.read(64 * 1024);
      final firstData = first64k.buffer.asByteData();
      for (int i = 0; i < first64k.length; i += 8) {
        if (i + 8 <= first64k.length) {
          hash += firstData.getUint64(i, Endian.little);
          hash &= 0xFFFFFFFFFFFFFFFF; // Keep it 64-bit
        }
      }

      // Read last 64KB
      final startLast64k = fileSize - 64 * 1024;
      await raf.setPosition(startLast64k > 0 ? startLast64k : 0);
      final last64k = await raf.read(64 * 1024);
      final lastData = last64k.buffer.asByteData();
      for (int i = 0; i < last64k.length; i += 8) {
        if (i + 8 <= last64k.length) {
          hash += lastData.getUint64(i, Endian.little);
          hash &= 0xFFFFFFFFFFFFFFFF; // Keep it 64-bit
        }
      }
    } finally {
      await raf.close();
    }

    return hash.toRadixString(16).padLeft(16, '0');
  }
}
