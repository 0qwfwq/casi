import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:oc_liquid_glass/oc_liquid_glass.dart';

class StatusIconsCapsule extends StatefulWidget {
  final double opacity;

  const StatusIconsCapsule({super.key, this.opacity = 1.0});

  @override
  State<StatusIconsCapsule> createState() => _StatusIconsCapsuleState();
}

class _StatusIconsCapsuleState extends State<StatusIconsCapsule> {
  final Battery _battery = Battery();
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.full;
  late Timer _timer;
  StreamSubscription<BatteryState>? _batteryStateSubscription;

  @override
  void initState() {
    super.initState();
    _initBattery();
    // Poll every minute to ensure level is accurate even if state doesn't change
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _getBatteryLevel());
  }

  void _initBattery() {
    _getBatteryLevel();
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((BatteryState state) {
      if (mounted) {
        setState(() => _batteryState = state);
        _getBatteryLevel(); // Update level immediately on state change
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
    super.dispose();
  }

  Color _getBatteryColor() {
    if (_batteryLevel > 70) return Colors.greenAccent;
    if (_batteryLevel > 30) return Colors.yellowAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    return _GlassCapsule(
      opacity: widget.opacity,
      color: _getBatteryColor(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "$_batteryLevel%",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(width: 12),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 16),
            ),
          ],
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
    return Stack(
      children: [
        if (opacity > 0)
          Positioned.fill(
            child: OCLiquidGlass(
              borderRadius: 30,
              color: (color ?? Colors.white).withValues(alpha: 0.2 * opacity),
              child: const SizedBox(),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: (color ?? Colors.white).withValues(alpha: 0.1 * opacity),
            borderRadius: BorderRadius.circular(30),
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
    );
  }
}