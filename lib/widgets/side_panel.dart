import 'package:flutter/material.dart';

class SidePanel extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final VoidCallback? onBack;

  const SidePanel({
    super.key,
    required this.title,
    required this.children,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final orientation = MediaQuery.of(context).orientation;

    // Portrait: slide from bottom, Landscape: slide from right
    final isPortrait = orientation == Orientation.portrait;
    final panelWidth = isPortrait ? screenWidth : screenWidth * 0.5;

    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Transparent overlay - tap to close
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(color: Colors.transparent),
              ),
            ),
            // Side panel
            Positioned(
              left: isPortrait ? 0 : null,
              right: isPortrait ? 0 : 0,
              top: isPortrait ? null : 0,
              bottom: 0,
              width: isPortrait ? null : panelWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: isPortrait ? screenHeight * 0.7 : double.infinity,
                ),
                child: GestureDetector(
                  onTap: () {}, // Prevent closing when tapping panel
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: isPortrait
                            ? Alignment.bottomCenter
                            : Alignment.centerRight,
                        end: isPortrait
                            ? Alignment.topCenter
                            : Alignment.centerLeft,
                        colors: [
                          const Color(0xFF1A1A1A).withOpacity(0.95),
                          const Color(0xFF1A1A1A).withOpacity(0.85),
                        ],
                      ),
                      borderRadius: isPortrait
                          ? const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.white.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              if (onBack != null)
                                GestureDetector(
                                  onTap: onBack ?? () => Navigator.pop(context),
                                  child: const Icon(
                                    Icons.arrow_back,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              if (onBack != null) const SizedBox(width: 12),
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Content
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            children: children,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required List<Widget> children,
    VoidCallback? onBack,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Material(
          type: MaterialType.transparency,
          child: SidePanel(title: title, children: children, onBack: onBack),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final orientation = MediaQuery.of(context).orientation;
        final isPortrait = orientation == Orientation.portrait;

        // Portrait: slide up from bottom, Landscape: slide left from right
        final begin = isPortrait
            ? const Offset(0.0, 1.0)
            : const Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;

        var tween = Tween(
          begin: begin,
          end: end,
        ).chain(CurveTween(curve: curve));

        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }
}
