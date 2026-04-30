import 'package:flutter/material.dart';

/// Centered Heads-Up Display used while the user adjusts brightness or
/// volume with a vertical drag gesture.
///
/// Renders a pill-shaped capsule with a dark "empty" track and a solid
/// white fill that rises from the bottom in proportion to [value].
/// The [icon] sits in the center of the capsule. The integer percentage
/// is shown beneath it.
class GestureHud extends StatelessWidget {
  final IconData icon;
  // Current value in the range [0.0, 1.0].
  final double value;
  // Pill capsule dimensions.
  final double pillWidth;
  final double pillHeight;

  const GestureHud({
    super.key,
    required this.icon,
    required this.value,
    this.pillWidth = 44,
    this.pillHeight = 170,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    final percentage = (clamped * 100).round();

    // Once the white fill rises past the midpoint, a white icon would
    // disappear into it. Switch to the dark capsule color for legibility.
    final iconOnWhite = clamped > 0.5;

    // Center.fill via Positioned.fill at the call-site is unnecessary —
    // a plain Center widget centers itself in any parent (Stack, Scaffold
    // body, etc.) in both portrait and landscape orientations.
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pill capsule
            SizedBox(
              width: pillWidth,
              height: pillHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(pillWidth / 2),
                child: Stack(
                  children: [
                    // Dark (empty) background fills the whole pill
                    Container(color: const Color(0xCC3A3A3A)),
                    // White (filled) portion grows from the bottom
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: pillHeight * clamped,
                        color: Colors.white,
                      ),
                    ),
                    // Icon centered inside the pill
                    Center(
                      child: Icon(
                        icon,
                        size: 18,
                        color: iconOnWhite
                            ? const Color(0xFF3A3A3A)
                            : Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Numeric value
            Text(
              '$percentage',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w300,
                fontFamily: 'Roboto',
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
