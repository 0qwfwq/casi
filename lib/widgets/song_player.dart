import 'dart:async';
import 'dart:typed_data'; 
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart'; // Added to open the active music app

class SongPlayer extends StatefulWidget {
  const SongPlayer({super.key});

  @override
  State<SongPlayer> createState() => _SongPlayerState();
}

class _SongPlayerState extends State<SongPlayer> with WidgetsBindingObserver {
  // Channel to communicate with Android native code
  static const platform = MethodChannel('casi.launcher/media');

  bool _isPlaying = false;
  
  // Variables to hold dynamic media data
  String _songTitle = "System Media";
  String _artist = "Controls active music app";
  Uint8List? _albumArt; 
  
  // --- New Functionality Data ---
  int _position = 0;
  int _duration = 0;
  String? _packageName; // Knows which app is playing (e.g., com.spotify.music)

  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncMediaState();
    
    // Fast periodic sync to keep the progress bar smooth
    _syncTimer = Timer.periodic(const Duration(seconds: 1), (_) => _syncMediaState());
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
      _syncMediaState();
    }
  }

  Future<void> _syncMediaState() async {
    try {
      final bool isPlaying = await platform.invokeMethod('isPlaying');
      
      // Request metadata map from the native side
      final Map<dynamic, dynamic>? metadata = await platform.invokeMethod('getMetadata');

      if (mounted) {
        setState(() {
          _isPlaying = isPlaying;
          
          if (metadata != null) {
            _songTitle = metadata['title'] as String? ?? "Unknown Title";
            _artist = metadata['artist'] as String? ?? "Unknown Artist";
            _albumArt = metadata['albumArt'] as Uint8List?;
            
            // Sync new progress and package data
            _position = metadata['position'] as int? ?? 0;
            _duration = metadata['duration'] as int? ?? 0;
            _packageName = metadata['packageName'] as String?;
          } else if (!isPlaying) {
             _songTitle = "System Media";
             _artist = "Controls active music app";
             _albumArt = null;
             _position = 0;
             _duration = 0;
             _packageName = null;
          }
        });
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to sync media state: '${e.message}'.");
    }
  }

  Future<void> _togglePlayPause() async {
    setState(() => _isPlaying = !_isPlaying);
    try {
      await platform.invokeMethod('playPause');
      _syncMediaState();
    } on PlatformException catch (_) {}
  }

  Future<void> _skipNext() async {
    try {
      await platform.invokeMethod('next');
      Future.delayed(const Duration(milliseconds: 300), _syncMediaState);
    } on PlatformException catch (_) {}
  }

  Future<void> _skipPrevious() async {
    try {
      await platform.invokeMethod('previous');
      Future.delayed(const Duration(milliseconds: 300), _syncMediaState);
    } on PlatformException catch (_) {}
  }

  // --- New Functionality: Tap to open the active music app ---
  void _openActiveMusicApp() {
    if (_packageName != null && _packageName!.isNotEmpty) {
      InstalledApps.startApp(_packageName!);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate progress for the progress bar (safeguard against division by zero)
    final double progress = (_duration > 0) ? (_position / _duration).clamp(0.0, 1.0) : 0.0;

    return Container(
      height: 70, 
      margin: const EdgeInsets.symmetric(horizontal: 40), 
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
          child: Stack(
            children: [
              // Main content container
              Container(
                color: Colors.white.withOpacity(0.2), 
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    // Tappable Area: Album Art & Text
                    Expanded(
                      child: GestureDetector(
                        onTap: _openActiveMusicApp, // Tap to open Spotify/Apple Music
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            // Album Art
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withOpacity(0.2)),
                                image: _albumArt != null 
                                    ? DecorationImage(
                                        image: MemoryImage(_albumArt!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: _albumArt == null 
                                  ? const Icon(CupertinoIcons.music_note, color: Colors.white, size: 20)
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            
                            // Song Info
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
                          ],
                        ),
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
              
              // --- New Functionality: Progress Bar ---
              Positioned(
                bottom: 0,
                left: 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2.5,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.6)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}