import 'dart:io';
import 'package:dio/dio.dart';
import 'package:archive/archive.dart';

class SubtitleDownloadService {
  final Dio _dio;

  SubtitleDownloadService()
    : _dio = Dio(
        BaseOptions(
          baseUrl: 'https://api.opensubtitles.com/api/v1/',
          headers: {
            'Api-Key': 'LxxJYH8wmnx1kTpTrr2J35qGiIWyL5oa',
            'User-Agent': 'AntigravityPlayer_v1',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

  /// Search for subtitles by query (filename or title) or MovieHash
  Future<List<Map<String, dynamic>>?> searchSubtitles(
    String query, {
    String? movieHash,
  }) async {
    try {
      final cleanedQuery = _cleanQuery(query);
      print('Searching for: "$cleanedQuery" (Hash: ${movieHash ?? "N/A"})');

      List<Map<String, dynamic>> allResults = [];
      Set<String> seenFileIds = {};

      // Helper to add results with deduplication
      void addResults(List<Map<String, dynamic>>? newResults) {
        if (newResults == null) return;
        for (var item in newResults) {
          final id = item['id']?.toString();
          if (id != null && !seenFileIds.contains(id)) {
            seenFileIds.add(id);
            allResults.add(item);
          }
        }
      }

      // STAGE 1: Search by MovieHash (Exact Match) - English
      if (movieHash != null) {
        try {
          print('Requesting by Hash (EN)...');
          final hashResponse = await _dio.get(
            'subtitles',
            queryParameters: {'moviehash': movieHash, 'languages': 'en'},
          );
          addResults(_processResponse(hashResponse));
        } catch (e) {
          print('Hash search error: $e');
        }
      }

      // STAGE 2: Search by Query (Text Match) - English
      if (cleanedQuery.isNotEmpty) {
        try {
          print('Requesting by Query (EN)...');
          final queryResponse = await _dio.get(
            'subtitles',
            queryParameters: {'query': cleanedQuery, 'languages': 'en'},
          );
          addResults(_processResponse(queryResponse));
        } catch (e) {
          print('Query search error: $e');
        }
      }

      // STAGE 3: Fallback if still empty (broaden languages)
      if (allResults.isEmpty) {
        print('No English results, broadening to all languages...');

        // Try Hash again (All Languages)
        if (movieHash != null) {
          try {
            final hashFallback = await _dio.get(
              'subtitles',
              queryParameters: {'moviehash': movieHash},
            );
            addResults(_processResponse(hashFallback));
          } catch (e) {
            print('Hash fallback error: $e');
          }
        }

        // Try Query again (All Languages)
        if (cleanedQuery.isNotEmpty) {
          try {
            final queryFallback = await _dio.get(
              'subtitles',
              queryParameters: {'query': cleanedQuery},
            );
            addResults(_processResponse(queryFallback));
          } catch (e) {
            print('Query fallback error: $e');
          }
        }
      }

      print('Total unique results found: ${allResults.length}');
      return allResults;
    } catch (e) {
      if (e is DioException) {
        print('DioError searching subtitles: ${e.type} - ${e.message}');
        print('Response: ${e.response?.data}');
      } else {
        print('Error searching subtitles: $e');
      }
      return null;
    }
  }

  List<Map<String, dynamic>>? _processResponse(Response response) {
    try {
      if (response.statusCode == 200) {
        final dynamic responseData = response.data;
        if (responseData is! Map) {
          print('API error: Response is not a map: $responseData');
          return [];
        }

        final List<dynamic> data = responseData['data'] ?? [];
        final List<Map<String, dynamic>> results = [];

        for (var item in data) {
          try {
            final attributes = item['attributes'];
            if (attributes == null) continue;

            final List<dynamic>? files = attributes['files'] as List<dynamic>?;
            if (files == null || files.isEmpty) continue;

            final firstFile = files[0];
            final fileId = firstFile['file_id'];
            if (fileId == null) continue;

            results.add({
              'id': fileId,
              'filename':
                  attributes['release'] ??
                  firstFile['file_name'] ??
                  'Subtitle #$fileId',
              'language': attributes['language'] ?? 'en',
              'download_count': attributes['download_count'] ?? 0,
            });
          } catch (e) {
            print('Error parsing subtitle item: $e');
          }
        }
        return results;
      }
    } catch (e) {
      print('Core error in _processResponse: $e');
    }
    return null;
  }

  /// Download and decompress a subtitle file
  Future<bool> downloadSubtitle(int fileId, String targetPath) async {
    try {
      // 1. Get temporary download link
      final linkResponse = await _dio.post(
        'download',
        data: {'file_id': fileId},
      );

      if (linkResponse.statusCode == 200) {
        final String downloadLink = linkResponse.data['link'];
        final String fileName = linkResponse.data['file_name'];

        // 2. Download the bytes
        final response = await _dio.get<List<int>>(
          downloadLink,
          options: Options(responseType: ResponseType.bytes),
        );

        if (response.statusCode == 200 && response.data != null) {
          List<int> srtBytes = response.data!;

          // 3. Decompress if it's GZipped
          if (fileName.endsWith('.gz') || _isGzipped(srtBytes)) {
            srtBytes = GZipDecoder().decodeBytes(srtBytes);
          }

          // 4. Save to target path
          final file = File(targetPath);
          await file.writeAsBytes(srtBytes);
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Error downloading subtitle: $e');
      return false;
    }
  }

  bool _isGzipped(List<int> bytes) {
    if (bytes.length < 2) return false;
    // GZip magic number: 0x1F 0x8B
    return bytes[0] == 0x1F && bytes[1] == 0x8B;
  }

  String _cleanQuery(String query) {
    // 1. Remove common video extensions
    String cleaned = query.replaceAll(
      RegExp(r'\.(mp4|mkv|avi|mov|flv|wmv|mpg|mpeg)$', caseSensitive: false),
      '',
    );

    // 2. Replace dots, underscores, and dashes with spaces
    cleaned = cleaned.replaceAll(RegExp(r'[._\-]'), ' ');

    // 3. Remove extra spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    return cleaned;
  }
}
