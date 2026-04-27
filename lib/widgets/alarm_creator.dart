import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';

// Callback receiving the new alarm label (e.g. "Mon 8:30 AM", "Daily 8:30 AM")
// for a single alarm, or a list of labels if multiple days were selected.
typedef AlarmCreatorSave = void Function(List<String> labels);

class AlarmCreator extends StatefulWidget {
  final AlarmCreatorSave onSave;
  final VoidCallback onCancel;
  // Source the cancel/save buttons and the time-row highlight refract.
  final Widget backgroundWidget;

  const AlarmCreator({
    super.key,
    required this.onSave,
    required this.onCancel,
    required this.backgroundWidget,
  });

  @override
  State<AlarmCreator> createState() => _AlarmCreatorState();
}

class _AlarmCreatorState extends State<AlarmCreator> {
  static const List<String> _allDays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];
  static const List<String> _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  int _hour = 8;
  int _minute = 0;
  String _ampm = 'AM';
  late List<String> _selectedDays;

  @override
  void initState() {
    super.initState();
    final today = _allDays[DateTime.now().weekday - 1];
    _selectedDays = [today];
  }

  void _save() {
    final timeStr = "$_hour:${_minute.toString().padLeft(2, '0')} $_ampm";
    final labels = <String>[];
    if (_selectedDays.length == 7) {
      labels.add("Daily $timeStr");
    } else {
      for (final day in _selectedDays) {
        labels.add("$day $timeStr");
      }
    }
    if (labels.isNotEmpty) widget.onSave(labels);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.add_alarm, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              "New Alarm",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildDayChips(),
        const SizedBox(height: 20),
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
                  _NumberWheel(
                    count: 12,
                    offset: 1,
                    initial: _hour,
                    width: 56,
                    fontSize: 28,
                    onChanged: (v) => _hour = v,
                  ),
                  const Text(
                    ":",
                    style: TextStyle(
                      color: CASIColors.textSecondary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  _NumberWheel(
                    count: 60,
                    offset: 0,
                    initial: _minute,
                    width: 56,
                    fontSize: 28,
                    onChanged: (v) => _minute = v,
                  ),
                  const SizedBox(width: 12),
                  _StringWheel(
                    items: const ['AM', 'PM'],
                    initial: _ampm,
                    width: 56,
                    onChanged: (v) => _ampm = v,
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

  Widget _buildDayChips() {
    final bool allSelected =
        _allDays.every((d) => _selectedDays.contains(d));

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              if (allSelected) {
                _selectedDays = [];
              } else {
                _selectedDays = List.from(_allDays);
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 40,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: allSelected
                  ? Colors.white.withValues(alpha: 0.22)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: allSelected
                    ? Colors.white.withValues(alpha: 0.55)
                    : CASIColors.glassDivider,
              ),
            ),
            child: Text(
              "All",
              style: TextStyle(
                color:
                    allSelected ? Colors.white : CASIColors.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        ...List.generate(7, (i) {
          final day = _allDays[i];
          final isSelected = _selectedDays.contains(day);
          return Padding(
            padding: EdgeInsets.only(left: i > 0 ? 4 : 0),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  final newDays = List<String>.from(_selectedDays);
                  if (isSelected) {
                    newDays.remove(day);
                  } else {
                    newDays.add(day);
                  }
                  _selectedDays = newDays;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.55)
                        : CASIColors.glassDivider,
                  ),
                ),
                child: Text(
                  _dayLabels[i],
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : CASIColors.textTertiary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// Shared wheel-scroller primitives used by both creators.

class _NumberWheel extends StatelessWidget {
  final int count;
  final int offset; // e.g. 1 for hours (1..12), 0 for minutes (0..59)
  final int initial;
  final double width;
  final double fontSize;
  final ValueChanged<int> onChanged;

  const _NumberWheel({
    required this.count,
    required this.offset,
    required this.initial,
    required this.width,
    required this.fontSize,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final initialIndex = (initial - offset).clamp(0, count - 1);
    return SizedBox(
      width: width,
      height: 140,
      child: ListWheelScrollView.useDelegate(
        controller: FixedExtentScrollController(initialItem: initialIndex),
        itemExtent: 40,
        physics: const FixedExtentScrollPhysics(),
        perspective: 0.005,
        squeeze: 1.15,
        useMagnifier: true,
        magnification: 1.25,
        overAndUnderCenterOpacity: 0.3,
        onSelectedItemChanged: (index) {
          onChanged((index % count) + offset);
        },
        childDelegate: ListWheelChildLoopingListDelegate(
          children: List.generate(count, (index) {
            final val = index + offset;
            return Center(
              child: Text(
                val.toString().padLeft(2, '0'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w400,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _StringWheel extends StatelessWidget {
  final List<String> items;
  final String initial;
  final double width;
  final ValueChanged<String> onChanged;

  const _StringWheel({
    required this.items,
    required this.initial,
    required this.width,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    int initialIndex = items.indexOf(initial);
    if (initialIndex < 0) initialIndex = 0;
    return SizedBox(
      width: width,
      height: 140,
      child: ListWheelScrollView.useDelegate(
        controller: FixedExtentScrollController(initialItem: initialIndex),
        itemExtent: 40,
        physics: const FixedExtentScrollPhysics(),
        perspective: 0.005,
        squeeze: 1.15,
        useMagnifier: true,
        magnification: 1.25,
        overAndUnderCenterOpacity: 0.3,
        onSelectedItemChanged: (index) => onChanged(items[index]),
        childDelegate: ListWheelChildLoopingListDelegate(
          children: items
              .map((item) => Center(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// Exported for timer_creator.dart so both can share the wheels.
class AlarmCreatorWheels {
  static Widget number({
    required int count,
    required int offset,
    required int initial,
    required double width,
    required double fontSize,
    required ValueChanged<int> onChanged,
  }) =>
      _NumberWheel(
        count: count,
        offset: offset,
        initial: initial,
        width: width,
        fontSize: fontSize,
        onChanged: onChanged,
      );
}
