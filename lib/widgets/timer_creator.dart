import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';
import 'alarm_creator.dart';

// Callback receives total seconds for the new timer.
typedef TimerCreatorSave = void Function(int totalSeconds);

class TimerCreator extends StatefulWidget {
  final TimerCreatorSave onSave;
  final VoidCallback onCancel;
  // Source the cancel/save buttons and the time-row highlight refract.
  final Widget backgroundWidget;

  const TimerCreator({
    super.key,
    required this.onSave,
    required this.onCancel,
    required this.backgroundWidget,
  });

  @override
  State<TimerCreator> createState() => _TimerCreatorState();
}

class _TimerCreatorState extends State<TimerCreator> {
  int _hour = 0;
  int _minute = 5;
  int _second = 0;

  void _save() {
    final total = _hour * 3600 + _minute * 60 + _second;
    if (total > 0) widget.onSave(total);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.hourglass_empty, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              "New Timer",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: LiquidGlassSurface.pill(
                  backgroundWidget: widget.backgroundWidget,
                  cornerRadius: 16,
                  height: 52,
                  child: const SizedBox.expand(),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _labeledWheel(
                    wheel: AlarmCreatorWheels.number(
                      count: 24,
                      offset: 0,
                      initial: _hour,
                      width: 52,
                      fontSize: 26,
                      onChanged: (v) => _hour = v,
                    ),
                    label: "h",
                  ),
                  const SizedBox(width: 14),
                  _labeledWheel(
                    wheel: AlarmCreatorWheels.number(
                      count: 60,
                      offset: 0,
                      initial: _minute,
                      width: 52,
                      fontSize: 26,
                      onChanged: (v) => _minute = v,
                    ),
                    label: "m",
                  ),
                  const SizedBox(width: 14),
                  _labeledWheel(
                    wheel: AlarmCreatorWheels.number(
                      count: 60,
                      offset: 0,
                      initial: _second,
                      width: 52,
                      fontSize: 26,
                      onChanged: (v) => _second = v,
                    ),
                    label: "s",
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _actionButton("Cancel", Icons.close, widget.onCancel),
            _actionButton("Save", Icons.check, _save),
          ],
        ),
      ],
    );
  }

  Widget _labeledWheel({required Widget wheel, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        wheel,
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: CASIColors.textSecondary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlassSurface.pill(
        backgroundWidget: widget.backgroundWidget,
        cornerRadius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
