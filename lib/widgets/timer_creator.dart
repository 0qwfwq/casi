import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';
import 'alarm_creator.dart';

// Callback receives total seconds for the new timer.
typedef TimerCreatorSave = void Function(int totalSeconds);

class TimerCreator extends StatefulWidget {
  final TimerCreatorSave onSave;
  final VoidCallback onCancel;

  const TimerCreator({
    super.key,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<TimerCreator> createState() => _TimerCreatorState();
}

class _TimerCreatorState extends State<TimerCreator> {
  static const Color _cTimer = CASIColors.caution;

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
          children: [
            const Icon(Icons.hourglass_empty, color: _cTimer, size: 18),
            const SizedBox(width: 8),
            const Text(
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
              Container(
                height: 52,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: _cTimer.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
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
            _actionButton(
                "Cancel", Icons.close, CASIColors.textSecondary, widget.onCancel),
            _actionButton("Save", Icons.check, _cTimer, _save),
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

  Widget _actionButton(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
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
