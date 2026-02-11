import 'dart:async';
import 'dart:math' as math;
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:oc_liquid_glass/oc_liquid_glass.dart';

class StatusIconsCapsule extends StatefulWidget {
  final double opacity;

  const StatusIconsCapsule({super.key, this.opacity = 1.0});

  @override
  State<StatusIconsCapsule> createState() => _StatusIconsCapsuleState();
}

class _StatusIconsCapsuleState extends State<StatusIconsCapsule> with SingleTickerProviderStateMixin {
  final Battery _battery = Battery();
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.full;
  late Timer _timer;
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isWifiConnected = false;
  late AnimationController _wiggleController;

  @override
  void initState() {
    super.initState();
    _wiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _initBattery();
    _initConnectivity();
    // Poll every minute to ensure level is accurate even if state doesn't change
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _getBatteryLevel());
  }

  void _initBattery() {
    _getBatteryLevel();
    _battery.batteryState.then((state) {
      if (mounted) {
        setState(() => _batteryState = state);
        _updateWiggle();
      }
    });
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((BatteryState state) {
      if (mounted) {
        setState(() => _batteryState = state);
        _getBatteryLevel(); // Update level immediately on state change
        _updateWiggle();
      }
    });
  }

  void _updateWiggle() {
    if (_batteryState == BatteryState.charging) {
      if (!_wiggleController.isAnimating) {
        _wiggleController.repeat(reverse: true);
      }
    } else {
      _wiggleController.stop();
      _wiggleController.reset();
    }
  }

  Future<void> _initConnectivity() async {
    final connectivity = Connectivity();
    // Check initial status
    final results = await connectivity.checkConnectivity();
    if (mounted) {
      setState(() => _isWifiConnected = results.contains(ConnectivityResult.wifi));
    }
    // Listen for changes
    _connectivitySubscription = connectivity.onConnectivityChanged.listen((results) {
      if (mounted) {
        setState(() => _isWifiConnected = results.contains(ConnectivityResult.wifi));
      }
    });
  }

  Future<void> _getBatteryLevel() async {
    try {
      final int level = await _battery.batteryLevel;
      if (mounted) {
        setState(() => _batteryLevel = level);
      }
    } catch (e) {
      debugPrint("Error getting battery level: $e");
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _batteryStateSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _wiggleController.dispose();
    super.dispose();
  }

  Color _getBatteryColor() {
    if (_batteryLevel > 70) return Colors.greenAccent;
    if (_batteryLevel > 30) return Colors.yellowAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _wiggleController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _batteryState == BatteryState.charging
              ? 0.05 * math.sin(_wiggleController.value * 2 * math.pi)
              : 0,
          child: child,
        );
      },
      child: _GlassCapsule(
        opacity: widget.opacity,
        color: _getBatteryColor(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "$_batteryLevel%",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(width: 12),
              Icon(_isWifiConnected ? Icons.wifi : Icons.wifi_off, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCapsule extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double opacity;
  
  const _GlassCapsule({required this.child, this.color, this.opacity = 1.0});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(30)),
      child: Stack(
        children: [
          Positioned.fill(
            child: OCLiquidGlass(
              color: (color ?? Colors.white).withValues(alpha: 0.2 * opacity),
              child: const SizedBox(),
            ),
          ),
          Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(30)),
              border: Border.all(
                color: (color ?? Colors.white).withValues(alpha: 0.2 * opacity),
                width: 1.5,
              ),
            ),
            child: Opacity(
              opacity: opacity,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}