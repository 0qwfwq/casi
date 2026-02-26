import 'package:flutter/material.dart';

/// The specific content for the Clock version of the dynamic pill.
/// Contains mockups for Alarm, Stopwatch, and Timer.
class DClockPill extends StatelessWidget {
  const DClockPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min, // Keep it as wide as its children
      children: [
        _buildPillButton(
          icon: Icons.alarm,
          label: "Alarm",
          onTap: () {
            debugPrint("Alarm mockup tapped!");
          },
        ),
        const SizedBox(width: 8),
        _buildPillButton(
          icon: Icons.timer,
          label: "Stopwatch",
          onTap: () {
            debugPrint("Stopwatch mockup tapped!");
          },
        ),
        const SizedBox(width: 8),
        _buildPillButton(
          icon: Icons.hourglass_bottom,
          label: "Timer",
          onTap: () {
            debugPrint("Timer mockup tapped!");
          },
        ),
      ],
    );
  }

  // A helper method to keep the buttons visually consistent
  Widget _buildPillButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 24.0,
          semanticLabel: label,
        ),
      ),
    );
  }
}