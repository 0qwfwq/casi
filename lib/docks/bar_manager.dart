import 'dart:ui';
import 'package:flutter/material.dart';
import 'song_bar.dart';

class BarManager extends StatefulWidget {
  const BarManager({super.key});

  @override
  State<BarManager> createState() => _BarManagerState();
}

class _BarManagerState extends State<BarManager> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70, // Fixed height to keep the pill shape consistent
      margin: const EdgeInsets.symmetric(horizontal: 40), // Matches the ScreenDock padding
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(35),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
          child: Container(
            color: Colors.white.withOpacity(0.2), // Unified glass overlay
            child: const SongBar(),
          ),
        ),
      ),
    );
  }
}