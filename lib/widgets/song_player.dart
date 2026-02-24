import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SongPlayer extends StatefulWidget {
  const SongPlayer({super.key});

  @override
  State<SongPlayer> createState() => _SongPlayerState();
}

class _SongPlayerState extends State<SongPlayer> with WidgetsBindingObserver {
  // Channel to communicate with Android native code
  static const platform = MethodChannel('casi.launcher/media');

  bool _isPlaying = false;
  final String _songTitle = "System Media";
  final String _artist = "Controls active music app";
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkIfPlaying();
    
    // Periodically check if music is active to sync the play/pause icon
    // in case the user paused it from the notification shade or headphones.
    _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkIfPlaying());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkIfPlaying();
    }
  }

  Future<void> _checkIfPlaying() async {
    try {
      final bool isPlaying = await platform.invokeMethod('isPlaying');
      if (mounted && _isPlaying != isPlaying) {
        setState(() {
          _isPlaying = isPlaying;
        });
      }
    } on PlatformException catch (_) {
      // Ignore exceptions on platforms where this isn't hooked up yet
    }
  }

  Future<void> _togglePlayPause() async {
    // Optimistically update the UI for instant feedback
    setState(() {
      _isPlaying = !_isPlaying;
    });
    
    try {
      await platform.invokeMethod('playPause');
    } on PlatformException catch (e) {
      debugPrint("Failed to toggle media: '${e.message}'.");
    }
  }

  Future<void> _skipNext() async {
    try {
      await platform.invokeMethod('next');
    } on PlatformException catch (e) {
      debugPrint("Failed to skip next: '${e.message}'.");
    }
  }

  Future<void> _skipPrevious() async {
    try {
      await platform.invokeMethod('previous');
    } on PlatformException catch (e) {
      debugPrint("Failed to skip previous: '${e.message}'.");
    }
  }

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
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                // Album Art Placeholder / Icon
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: const Icon(
                    CupertinoIcons.music_note,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                
                // Song Info Column
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _songTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _artist,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                
                // Media Controls
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _skipPrevious,
                      icon: const Icon(CupertinoIcons.backward_fill, color: Colors.white, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _togglePlayPause,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: _skipNext,
                      icon: const Icon(CupertinoIcons.forward_fill, color: Colors.white, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}