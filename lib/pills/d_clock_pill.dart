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
  final bool isViewingTimers;
  final bool isCreatingTimer;
  final String timerTime;
  
  final List<String> savedTimersTimes;
  final List<bool> savedTimersRunning;
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

  // --- Inline Action Callbacks ---
  final VoidCallback? onViewAlarmsTapped;
  final VoidCallback? onAddNewAlarmTapped;
  final VoidCallback? onSaveAlarmTapped;
  final ValueChanged<int>? onDeleteAlarm;

  final VoidCallback? onViewTimersTapped;
  final VoidCallback? onAddNewTimerTapped;
  final VoidCallback? onCancelTimerTapped;
  final VoidCallback? onSaveTimerTapped;
  final ValueChanged<int>? onDeleteTimer;

  // --- STRICT UNIFORM WIDTH ---
  // A slightly narrower fixed width guarantees perfect centering 
  // with safe breathing room from the side Dock buttons.
  static const double _fixedPillWidth = 160.0;

  const DClockPill({
    super.key,
    this.isAlarmMode = false,
    this.isViewingAlarms = false,
    this.isAlarmRinging = false,
    this.isStopwatchMode = false,
    this.stopwatchTime = "00:00.00",
    this.stopwatchLaps = const [],
    this.isTimerMode = false,
    this.isViewingTimers = false,
    this.isCreatingTimer = false,
    this.timerTime = "00:00",
    this.savedTimersTimes = const [],
    this.savedTimersRunning = const [],
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
    this.onViewAlarmsTapped,
    this.onAddNewAlarmTapped,
    this.onSaveAlarmTapped,
    this.onDeleteAlarm,
    this.onViewTimersTapped,
    this.onAddNewTimerTapped,
    this.onCancelTimerTapped,
    this.onSaveTimerTapped,
    this.onDeleteTimer,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: isAlarmRinging 
          ? _buildRingingState(key: const ValueKey('ringing'))
          : isTimerMode
              ? (isCreatingTimer
                  ? _buildTimerScrollers(key: const ValueKey('timer_scrollers'))
                  : isViewingTimers
                      ? _buildTimersList(key: const ValueKey('timers_list'))
                      : selectedTimerIndex != null
                          ? _buildTimerRunningState(key: const ValueKey('timer_running'))
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

  // --- Ringing State (Urgent Red Glow) ---
  Widget _buildRingingState({Key? key}) {
    return Container(
      key: key,
      width: _fixedPillWidth,
      height: 60, 
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.2),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.redAccent.withOpacity(0.8), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.redAccent.withOpacity(0.4), blurRadius: 12, spreadRadius: 2)
        ],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_active, color: Colors.white, size: 24),
          SizedBox(width: 8),
          Text(
            "Wake Up!",
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // --- Timer Running (and Paused) View ---
  Widget _buildTimerRunningState({Key? key}) {
    bool isRunning = (selectedTimerIndex != null && selectedTimerIndex! < savedTimersRunning.length) 
        ? savedTimersRunning[selectedTimerIndex!] 
        : false;

    return Container(
      key: key,
      width: _fixedPillWidth,
      height: 100, 
      alignment: Alignment.center,
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_bottom, color: isRunning ? Colors.orangeAccent : Colors.white54, size: 18),
              const SizedBox(width: 8),
              Text(
                timerTime,
                style: TextStyle(
                  color: isRunning ? Colors.orangeAccent : Colors.white,
                  fontSize: 26, 
                  fontWeight: FontWeight.bold,
                  shadows: isRunning ? [BoxShadow(color: Colors.orangeAccent.withOpacity(0.5), blurRadius: 10)] : null,
                  fontFeatures: const [FontFeature.tabularFigures()]
                ),
              ),
            ],
          ),
          Container(
            height: 1,
            width: 120,
            color: Colors.white.withOpacity(0.05),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.list, color: Colors.white54, size: 26),
                onPressed: onViewTimersTapped,
                tooltip: "View Timers",
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 26),
                onPressed: () {
                  if (selectedTimerIndex != null) onDeleteTimer?.call(selectedTimerIndex!);
                },
                tooltip: "Delete Timer",
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Timers List Expandable ---
  Widget _buildTimersList({Key? key}) {
    final double listHeight = savedTimersTimes.isEmpty ? 40.0 : (savedTimersTimes.length * 56.0);
    final double totalHeight = (listHeight + 60.0).clamp(100.0, 240.0);

    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 300),
      width: _fixedPillWidth,
      height: totalHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Column(
        children: [
          Expanded(
            child: savedTimersTimes.isEmpty
                ? const Center(
                    child: Text("No saved timers", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w500)),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: savedTimersTimes.length,
                    itemBuilder: (context, index) {
                      final isSelected = selectedTimerIndex == index;
                      final isRunning = savedTimersRunning[index];
                      
                      return GestureDetector(
                        onTap: () => onSelectTimer?.call(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 48,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 10.0),
                          margin: const EdgeInsets.symmetric(vertical: 2.0),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white.withOpacity(0.15) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSelected ? Colors.orangeAccent.withOpacity(0.5) : Colors.transparent, width: 1),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                savedTimersTimes[index], 
                                style: TextStyle(
                                  color: isSelected ? Colors.orangeAccent : Colors.white, 
                                  fontSize: 16, 
                                  fontWeight: FontWeight.bold,
                                  fontFeatures: const [FontFeature.tabularFigures()]
                                ),
                              ),
                              Icon(
                                isRunning ? Icons.play_circle_fill : Icons.pause_circle_filled, 
                                color: isSelected ? Colors.orangeAccent : Colors.white54, 
                                size: 20
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: onAddNewTimerTapped,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, color: Colors.orangeAccent, size: 18),
                  SizedBox(width: 6),
                  Text("New Timer", style: TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Timer HH:MM:SS Scrollers ---
  Widget _buildTimerScrollers({Key? key}) {
    return Container(
      key: key,
      width: _fixedPillWidth,
      height: 110, 
      alignment: Alignment.center,
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 140, // Reduced to fit safely inside 160.0
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTimerNumberScroller(24, initialTimerHour ?? 0, onTimerHourChanged),
                    const Padding(padding: EdgeInsets.only(right: 4.0), child: Text("h", style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600))),
                    _buildTimerNumberScroller(60, initialTimerMinute ?? 5, onTimerMinuteChanged),
                    const Padding(padding: EdgeInsets.only(right: 4.0), child: Text("m", style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600))),
                    _buildTimerNumberScroller(60, initialTimerSecond ?? 0, onTimerSecondChanged),
                    const Text("s", style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            width: 120, // Clean separation line
            color: Colors.white.withOpacity(0.05),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 26), 
                onPressed: onCancelTimerTapped,
              ),
              IconButton(
                icon: const Icon(Icons.play_circle_fill, color: Colors.orangeAccent, size: 26), 
                onPressed: onSaveTimerTapped,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimerNumberScroller(int count, int initialVal, ValueChanged<int>? onChanged) {
    return SizedBox(
      width: 32,
      height: 48,
      child: ListWheelScrollView.useDelegate(
        controller: FixedExtentScrollController(initialItem: initialVal),
        itemExtent: 28,
        physics: const FixedExtentScrollPhysics(),
        overAndUnderCenterOpacity: 0.4,
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
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()]
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
      width: _fixedPillWidth,
      height: stopwatchLaps.isEmpty ? 60 : (stopwatchLaps.length * 40.0 + 50.0).clamp(60.0, 168.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined, color: Colors.lightBlueAccent, size: 20),
              const SizedBox(width: 6),
              Text(
                stopwatchTime,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()] 
                ),
              ),
            ],
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
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Lap ${stopwatchLaps.length - index}", style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500)),
                        Text(stopwatchLaps[index], style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 14, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
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
    final double listHeight = activeAlarms.isEmpty ? 40.0 : (activeAlarms.length * 56.0);
    final double totalHeight = (listHeight + 60.0).clamp(100.0, 240.0);

    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 300),
      width: _fixedPillWidth,
      height: totalHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Column(
        children: [
          Expanded(
            child: activeAlarms.isEmpty
                ? const Center(
                    child: Text("No active alarms", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w500)),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: activeAlarms.length,
                    itemBuilder: (context, index) {
                      final isSelected = selectedIndex == index;
                      final parts = activeAlarms[index].split(' ');
                      String day = parts.isNotEmpty ? parts[0] : '';
                      String time = parts.length > 1 ? parts[1] : '';
                      String ampm = parts.length > 2 ? parts[2] : '';
                      if (parts.length == 2) {
                         day = 'Daily';
                         time = parts[0];
                         ampm = parts[1];
                      }

                      return GestureDetector(
                        onTap: () => onSelectAlarm?.call(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 48,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          margin: const EdgeInsets.symmetric(vertical: 2.0),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white.withOpacity(0.15) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSelected ? Colors.greenAccent.withOpacity(0.5) : Colors.transparent, width: 1),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.greenAccent.withOpacity(0.2) : Colors.white24,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(day, style: TextStyle(color: isSelected ? Colors.greenAccent : Colors.white, fontSize: 9, fontWeight: FontWeight.bold))
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(time, style: TextStyle(color: isSelected ? Colors.greenAccent : Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 2),
                                    Text(ampm, style: TextStyle(color: isSelected ? Colors.greenAccent.withOpacity(0.8) : Colors.white54, fontSize: 10, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: onAddNewAlarmTapped,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.greenAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, color: Colors.greenAccent, size: 18),
                  SizedBox(width: 6),
                  Text("New Alarm", style: TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Normal Mode: Main Action Buttons ---
  Widget _buildActionButtons({Key? key}) {
    return Container(
      key: key,
      width: _fixedPillWidth, 
      height: 60, 
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildPillButton(icon: Icons.alarm, color: Colors.greenAccent, label: "Alarm", onTap: onAlarmTapped),
          _buildPillButton(icon: Icons.timer, color: Colors.lightBlueAccent, label: "Stopwatch", onTap: onStopwatchTapped ?? () {}),
          _buildPillButton(icon: Icons.hourglass_bottom, color: Colors.orangeAccent, label: "Timer", onTap: onTimerTapped ?? () {}),
        ],
      ),
    );
  }

  // --- Alarm Mode: Time Scrollers ---
  Widget _buildTimeScrollers({Key? key}) {
    return Container(
      key: key,
      width: _fixedPillWidth,
      height: 110, 
      alignment: Alignment.center,
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 100,
                  height: 34,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildNumberScroller(12, true), 
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4.0),
                      child: Text(":", style: TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    _buildNumberScroller(60, false),
                  ],
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            width: 120, // Clean separation line
            color: Colors.white.withOpacity(0.05),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.list, color: Colors.white54, size: 26),
                onPressed: onViewAlarmsTapped,
                tooltip: "View Alarms",
              ),
              IconButton(
                icon: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 26),
                onPressed: onSaveAlarmTapped,
                tooltip: "Save Alarm",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNumberScroller(int count, bool isHour) {
    int initialVal = isHour ? (initialHour ?? 1) : (initialMinute ?? 0);
    int initialIndex = isHour ? initialVal - 1 : initialVal;

    return SizedBox(
      width: 36,
      height: 48,
      child: ListWheelScrollView.useDelegate(
        controller: FixedExtentScrollController(initialItem: initialIndex),
        itemExtent: 28,
        physics: const FixedExtentScrollPhysics(),
        overAndUnderCenterOpacity: 0.4,
        onSelectedItemChanged: (index) {
          int actualIndex = index % count;
          int val = isHour ? actualIndex + 1 : actualIndex;
          if (isHour) onHourChanged?.call(val);
          else onMinuteChanged?.call(val);
        },
        childDelegate: ListWheelChildLoopingListDelegate(
          children: List.generate(count, (index) {
            int val = isHour ? index + 1 : index;
            return Center(
              child: Text(
                val.toString().padLeft(2, '0'),
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildPillButton({required IconData icon, required Color color, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.05))),
        child: Icon(icon, color: color, size: 22.0, semanticLabel: label),
      ),
    );
  }
}