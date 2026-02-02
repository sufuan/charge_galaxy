import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

class MediaService {
  Future<List<AssetEntity>> fetchVideos() async {
    // Request permissions
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    debugPrint('Permission State: $ps, isAuth: ${ps.isAuth}');
    if (!ps.isAuth) {
      // Handle permission denied
      debugPrint('Permission denied or not authorized.');
      return [];
    }

    // Get video albums
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
    );

    debugPrint('Found ${albums.length} albums.');

    if (albums.isEmpty) {
      debugPrint('No albums found.');
      return [];
    }

    // Get videos from the "Recent" album (usually the first one)
    final List<AssetEntity> videos = await albums[0].getAssetListRange(
      start: 0,
      end: 1000, // Fetch first 1000 videos
    );

    debugPrint('Found ${videos.length} videos in first album.');

    return videos;
  }
}
