import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../services/history_service.dart';
import '../widgets/history_item.dart';
import '../widgets/video_list_item.dart';
import 'video_player_screen.dart';
import 'video_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<AssetEntity> _videos = [];
  List<AssetEntity> _historyVideos = [];
  List<AssetPathEntity> _folders = [];
  bool _isLoading = true;
  final HistoryService _historyService = HistoryService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchVideos();
    });
  }

  Future<void> _fetchVideos() async {
    setState(() => _isLoading = true);
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth && ps != PermissionState.limited) {
        setState(() => _isLoading = false);
        return;
      }

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.video,
      );

      // Store folders
      setState(() {
        _folders = albums;
      });

      if (albums.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      // Fetch Recent videos (index 0)
      final videos = await albums[0].getAssetListRange(start: 0, end: 1000);

      // Load History
      await _loadHistory(videos);

      setState(() {
        _videos = videos;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadHistory(List<AssetEntity> availableVideos) async {
    final historyIds = await _historyService.getHistoryIds();
    final historyVideos = <AssetEntity>[];

    for (final id in historyIds) {
      try {
        final video = availableVideos.firstWhere((v) => v.id == id);
        historyVideos.add(video);
      } catch (e) {
        // Video missing
      }
    }
    setState(() => _historyVideos = historyVideos);
  }

  void _navigateToPlayer(AssetEntity video) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(videoFile: video),
      ),
    );
    _loadHistory(_videos);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          titleSpacing: 16,
          title: Row(
            children: [
              const Text(
                'Charged Galaxy',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  fontFamily: 'Roboto', // Default sans
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37), // Goldish
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'VIP',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          actions: const [],
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              // History Section
              if (_historyVideos.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'History',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Icon(
                              Icons.delete_outline,
                              color: Colors.white54,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 90, // Height for history items
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: _historyVideos.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 0),
                          itemBuilder: (context, index) {
                            return HistoryItem(
                              video: _historyVideos[index],
                              onTap: () =>
                                  _navigateToPlayer(_historyVideos[index]),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),

              // Sticky Tab Bar
              SliverPersistentHeader(
                delegate: _SliverTabBarDelegate(
                  const TabBar(
                    indicatorColor: Color(0xFF00C853),
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelColor: Color(0xFF00C853),
                    unselectedLabelColor: Colors.white,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    unselectedLabelStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    tabs: [
                      Tab(text: 'Video'),
                      Tab(text: 'Folder'),
                      Tab(text: 'Playlist'),
                    ],
                  ),
                  color: Colors.black,
                ),
                pinned: true,
              ),
            ];
          },
          body: TabBarView(
            children: [
              _buildVideoList(),
              _buildFolderList(),
              _buildPlaylistPlaceholder(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00C853)),
      );
    }

    // Grouping by date could be added here, currently single list for "Jan" etc.
    // For now, simpler implementation: Just a header "Jan" then items.

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _videos.length + 1, // +1 for Header
      itemBuilder: (context, index) {
        if (index == 0) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Jan', // Hardcoded for now, dynamic date grouping would be next step
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }
        return VideoListItem(
          video: _videos[index - 1],
          onTap: () => _navigateToPlayer(_videos[index - 1]),
        );
      },
    );
  }

  Widget _buildFolderList() {
    if (_folders.isEmpty) {
      return const Center(
        child: Text('No folders', style: TextStyle(color: Colors.white54)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _folders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final folder = _folders[index];
        return FutureBuilder<int>(
          future: folder.assetCountAsync,
          builder: (context, snapshot) {
            return InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoListScreen(folder: folder),
                  ),
                );
              },
              child: Row(
                children: [
                  const Icon(Icons.folder, color: Color(0xFF00C853), size: 48),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folder.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      Text(
                        '${snapshot.data ?? 0} videos',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaylistPlaceholder() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.playlist_play, size: 64, color: Colors.white24),
          SizedBox(height: 16),
          Text('No Playlists', style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  final Color color;

  _SliverTabBarDelegate(this._tabBar, {required this.color});

  @override
  double get minExtent => _tabBar.preferredSize.height + 1; // +1 for border if needed
  @override
  double get maxExtent => _tabBar.preferredSize.height + 1;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: color,
      child: Column(
        children: [
          _tabBar,
          // Bottom border line
          Container(height: 1, color: Colors.white10),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
  }
}
