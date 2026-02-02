import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

class VideoListItem extends StatelessWidget {
  final AssetEntity video;
  final VoidCallback? onTap;

  const VideoListItem({super.key, required this.video, this.onTap});

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes;
    final remainingSeconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb > 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                height: 68,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildThumbnail(video),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(179, 0, 0, 0),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          _formatDuration(video.duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title ?? 'Unknown',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Meta Info Row
                  FutureBuilder<int?>(
                    future: video.file.then((f) => f?.length()),
                    builder: (context, snapshot) {
                      final size = _formatSize(snapshot.data);
                      // Assuming height is resolution for now as simplified check
                      final resolution = video.height >= 2160
                          ? '4k'
                          : '${video.height}p';

                      return Text(
                        '$resolution | $size',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 6),
                  // Tags
                  Builder(
                    builder: (context) {
                      // Extract last folder name from path, e.g. "DCIM/Camera/" -> "Camera"
                      String folderName = 'Unknown';
                      final path = video.relativePath;
                      if (path != null) {
                        // Remove trailing slash if exists
                        final cleanPath = path.endsWith('/')
                            ? path.substring(0, path.length - 1)
                            : path;
                        final parts = cleanPath.split('/');
                        if (parts.isNotEmpty) {
                          folderName = parts.last;
                        }
                      }

                      return Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF333333),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.folder_open,
                                  size: 10,
                                  color: Colors.white70,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  folderName,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            // More menu
            const Icon(Icons.more_vert, color: Colors.white54, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(AssetEntity video) {
    return FutureBuilder<Uint8List?>(
      future: video.thumbnailData,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(snapshot.data!, fit: BoxFit.cover);
        }
        return Container(
          color: const Color(0xFF1A1A1A),
          child: const Center(
            child: Icon(
              Icons.play_circle_outline,
              color: Colors.white24,
              size: 24,
            ),
          ),
        );
      },
    );
  }
}
