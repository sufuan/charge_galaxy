import 'package:flutter/material.dart';
import 'home_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(), // Video Tab
    const Center(
      child: Text('Music', style: TextStyle(color: Colors.white)),
    ),
    const Center(
      child: Text('Game', style: TextStyle(color: Colors.white)),
    ),
    const Center(
      child: Text('Me', style: TextStyle(color: Colors.white)),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.play_circle_filled),
              label: 'VIDEO',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.music_note),
              label: 'MUSIC',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.videogame_asset),
              label: 'GAME',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'ME'),
          ],
          selectedFontSize: 10,
          unselectedFontSize: 10,
          iconSize: 24,
        ),
      ),
    );
  }
}
