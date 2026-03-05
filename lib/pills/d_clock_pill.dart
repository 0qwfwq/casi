import 'dart:ui';
import 'package:flutter/material.dart';

/// The specific content for the Clock version of the dynamic pill.
/// Contains functionality for Alarm, Stopwatch, and Timer mockups.
class DClockPill extends StatelessWidget {
  final bool isAlarmMode;
  final bool isViewingAlarms;
  final bool isAlarmRinging;
  
  final bool isStopwatchMode; 
  final String stopwatchTime; 
  final List<String> stopwatchLaps; 
  
  final bool isTimerMode; 
  final bool isTimerRunning;
  final bool isViewingTimers;
  final bool isCreatingTimer;
  final String timerTime;
  final List<int> savedTimers;
  final int? selectedTimerIndex;
  
  final List<String> activeAlarms;
  final int? selectedIndex;
  
  final int? initialHour; 
  final int? initialMinute; 
  final int? initialTimerHour; 
  final int? initialTimerMinute; 
  final int? initialTimerSecond; 

  final VoidCallback onAlarmTapped;
  final VoidCallback? onStopwatchTapped; 
  final VoidCallback? onTimerTapped; 

  final ValueChanged<int>? onSelectAlarm;
  final ValueChanged<int>? onSelectTimer;

  final ValueChanged<int>? onHourChanged;
  final ValueChanged<int>? onMinuteChanged;
  final ValueChanged<int>? onTimerHourChanged;
  final ValueChanged<int>? onTimerMinuteChanged;
  final ValueChanged<int>? onTimerSecondChanged;

  const DClockPill({
    super.key,
    this.isAlarmMode = false,
    this.isViewingAlarms = false,
    this.isAlarmRinging = false,
    this.isStopwatchMode = false,
    this.stopwatchTime = "00:00.00",
    this.stopwatchLaps = const [],
    this.isTimerMode = false,
    this.isTimerRunning = false,
    this.isViewingTimers = false,
    this.isCreatingTimer = false,
    this.timerTime = "00:00",
    this.savedTimers = const [],
    this.selectedTimerIndex,
    this.activeAlarms = const [],
    this.selectedIndex,
    this.initialHour,
    this.initialMinute,
    this.initialTimerHour,
    this.initialTimerMinute,
    this.initialTimerSecond,
    required this.onAlarmTapped,
    this.onStopwatchTapped,
    this.onTimerTapped,
    this.onSelectAlarm,
    this.onSelectTimer,
    this.onHourChanged,
    this.onMinuteChanged,
    this.onTimerHourChanged,
    this.onTimerMinuteChanged,
    this.onTimerSecondChanged,
  });

  String _formatTimerTime(int totalSeconds) {
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    int s = totalSeconds % 60;
    if (h > 0) {
      return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    } else {
      return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: isAlarmRinging 
          ? _buildRingingState(key: const ValueKey('ringing'))
          : isTimerMode
              ? (isTimerRunning
                  ? _buildTimerRunningState(key: const ValueKey('timer_running'))
                  : isCreatingTimer
                      ? _buildTimerScrollers(key: const ValueKey('timer_scrollers'))
                      : isViewingTimers
                          ? _buildTimersList(key: const ValueKey('timers_list'))
                          : _buildActionButtons(key: const ValueKey('buttons')))
              : isStopwatchMode
                  ? _buildStopwatchState(key: const ValueKey('stopwatch'))
                  : isViewingAlarms 
                      ? _buildAlarmsList(key: const ValueKey('alarms_list'))
                      : isAlarmMode 
                          ? _buildTimeScrollers(key: const ValueKey('scrollers'))
                          : _buildActionButtons(key: const ValueKey('buttons')),
    );
  }

  // --- Ringing State ---
  Widget _buildRingingState({Key? key}) {
    return Container(
      key: key,
      width: 160, 
      height: 60, 
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_active, color: Colors.white, size: 28),
          SizedBox(width: 8),
          Text(
            "Wake Up!",
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // --- Timer Running View ---
  Widget _buildTimerRunningState({Key? key}) {
    return Container(
      key: key,
      width: 160,
      height: 60,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text(
        timerTime,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 32, 
          fontWeight: FontWeight.bold,
          fontFeatures: [FontFeature.tabularFigures()]
        ),
      ),
    );
  }

  // --- Timers List Expandable ---
  Widget _buildTimersList({Key? key}) {
    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 300),
      width: 160, 
      height: savedTimers.isEmpty ? 60 : (savedTimers.length * 56.0).clamp(60.0, 168.0),
      child: savedTimers.isEmpty
          ? const Center(
              child: Text("No saved timers", style: TextStyle(color: Colors.white70)),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              itemCount: savedTimers.length,
              itemBuilder: (context, index) {
                final isSelected = selectedTimerIndex == index;
                return GestureDetector(
                  onTap: () => onSelectTimer?.call(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 48,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.white54 : Colors.transparent, 
                        width: 1
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatTimerTime(savedTimers[index]),
                          style: TextStyle(
                            color: isSelected ? Colors.orangeAccent : Colors.white, 
                            fontSize: 18, 
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()]
                          ),
                        ),
                        Icon(
                          Icons.hourglass_bottom, 
                          color: isSelected ? Colors.orangeAccent : Colors.white70, 
                          size: 20
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  // --- Timer HH:MM:SS Scrollers ---
  Widget _buildTimerScrollers({Key? key}) {
    return Container(
      key: key,
      width: 160, 
      height: 60, 
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTimerNumberScroller(24, initialTimerHour ?? 0, onTimerHourChanged),
          const Text(":", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          _buildTimerNumberScroller(60, initialTimerMinute ?? 5, onTimerMinuteChanged),
          const Text(":", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          _buildTimerNumberScroller(60, initialTimerSecond ?? 0, onTimerSecondChanged),
        ],
      ),
    );
  }

  Widget _buildTimerNumberScroller(int count, int initialVal, ValueChanged<int>? onChanged) {
    return SizedBox(
      width: 36,
      height: 48,
      child: ListWheelScrollView.useDelegate(
        controller: FixedExtentScrollController(initialItem: initialVal),
        itemExtent: 30,
        physics: const FixedExtentScrollPhysics(),
        overAndUnderCenterOpacity: 0.3,
        onSelectedItemChanged: (index) {
          onChanged?.call(index % count);
        },
        childDelegate: ListWheelChildLoopingListDelegate(
          children: List.generate(count, (index) {
            return Center(
              child: Text(
                index.toString().padLeft(2, '0'),
                style: const TextStyle(
                  color: Colors.white, 
                  fontSize: 18, 
                  fontWeight: FontWeight.w600
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // --- Stopwatch Running View ---
  Widget _buildStopwatchState({Key? key}) {
    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 300),
      width: 160,
      height: stopwatchLaps.isEmpty ? 60 : (stopwatchLaps.length * 40.0 + 50.0).clamp(60.0, 168.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            stopwatchTime,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()] 
            ),
          ),
          if (stopwatchLaps.isNotEmpty) ...[
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: stopwatchLaps.length,
                itemBuilder: (context, index) {
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Lap ${stopwatchLaps.length - index}",
                          style: const TextStyle(color: Colors.white54, fontSize: 14),
                        ),
                        Text(
                          stopwatchLaps[index],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontFeatures: [FontFeature.tabularFigures()]
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ]
        ],
      ),
    );
  }

  // --- Alarms List Expandable ---
  Widget _buildAlarmsList({Key? key}) {
    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 300),
      width: 160, 
      height: activeAlarms.isEmpty ? 60 : (activeAlarms.length * 56.0).clamp(60.0, 168.0),
      child: activeAlarms.isEmpty
          ? const Center(
              child: Text("No active alarms", style: TextStyle(color: Colors.white70)),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              itemCount: activeAlarms.length,
              itemBuilder: (context, index) {
                final isSelected = selectedIndex == index;
                return GestureDetector(
                  onTap: () => onSelectAlarm?.call(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 48,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.white54 : Colors.transparent, 
                        width: 1
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Text(
                              activeAlarms[index],
                              style: TextStyle(
                                color: isSelected ? Colors.greenAccent : Colors.white, 
                                fontSize: 16, 
                                fontWeight: FontWeight.w600
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.alarm_on, 
                          color: isSelected ? Colors.greenAccent : Colors.white70, 
                          size: 20
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  // --- Normal Mode: 3 Buttons ---
  Widget _buildActionButtons({Key? key}) {
    return Container(
      key: key,
      width: 160, 
      height: 60, 
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPillButton(
            icon: Icons.alarm,
            label: "Alarm",
            onTap: onAlarmTapped,
          ),
          const SizedBox(width: 8),
          _buildPillButton(
            icon: Icons.timer,
            label: "Stopwatch",
            onTap: onStopwatchTapped ?? () {}, 
          ),
          const SizedBox(width: 8),
          _buildPillButton(
            icon: Icons.hourglass_bottom,
            label: "Timer",
            onTap: onTimerTapped ?? () {}, 
          ),
        ],
      ),
    );
  }

  // --- Alarm Mode: Time Scrollers ---
  Widget _buildTimeScrollers({Key? key}) {
    return Container(
      key: key,
      width: 160, 
      height: 60, 
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 8),
          _buildNumberScroller(12, true), // Hours 1-12
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.0),
            child: Text(
              ":",
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          _buildNumberScroller(60, false), // Minutes 00-59
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildNumberScroller(int count, bool isHour) {
    int initialVal = isHour ? (initialHour ?? 1) : (initialMinute ?? 0);
    int initialIndex = isHour ? initialVal - 1 : initialVal;

    return SizedBox(
      width: 40,
      height: 48,
      child: ListWheelScrollView.useDelegate(
        controller: FixedExtentScrollController(initialItem: initialIndex),
        itemExtent: 30,
        physics: const FixedExtentScrollPhysics(),
        overAndUnderCenterOpacity: 0.3,
        onSelectedItemChanged: (index) {
          int actualIndex = index % count;
          int val = isHour ? actualIndex + 1 : actualIndex;
          if (isHour) {
            onHourChanged?.call(val);
          } else {
            onMinuteChanged?.call(val);
          }
        },
        childDelegate: ListWheelChildLoopingListDelegate(
          children: List.generate(count, (index) {
            int val = isHour ? index + 1 : index;
            String text = val.toString().padLeft(2, '0');
            return Center(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white, 
                  fontSize: 20, 
                  fontWeight: FontWeight.w600
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

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