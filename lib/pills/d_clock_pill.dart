import 'dart:ui';
import 'package:flutter/material.dart';

/// The specific content for the Clock version of the dynamic pill.
/// Redesigned with a spacious Glassmorphic aesthetic, internal tabs,
/// and self-contained controls to match the Calendar pill.
class DClockPill extends StatelessWidget {
  final bool isAlarmMode;
  final bool isViewingAlarms;
  final bool isAlarmRinging;
  
  final bool isStopwatchMode; 
  final bool isStopwatchRunning;
  final String stopwatchTime; 
  final List<String> stopwatchLaps; 
  
  final bool isTimerMode; 
  final bool isCreatingTimer;
  final bool isEditingTimer;
  final String timerTime;
  
  final List<String> savedTimersTimes;
  final List<bool> savedTimersRunning;
  final int? selectedTimerIndex;
  
  final List<String> activeAlarms;
  final int? selectedIndex;
  
  final int? initialHour; 
  final int? initialMinute; 
  final String initialAmPm;
  final String initialDay;
  final int? initialTimerHour; 
  final int? initialTimerMinute; 
  final int? initialTimerSecond; 

  final VoidCallback onAlarmTapped;
  final VoidCallback? onStopwatchTapped; 
  final VoidCallback? onTimerTapped; 

  // --- Clock Actions ---
  final VoidCallback? onStopwatchToggle;
  final VoidCallback? onStopwatchLap;
  final VoidCallback? onStopwatchReset;
  final VoidCallback? onTimerStop;

  final ValueChanged<int>? onSelectAlarm;
  final ValueChanged<int>? onSelectTimer;
  final ValueChanged<int>? onToggleTimer; 
  final ValueChanged<int>? onEditTimer;   
  final ValueChanged<int>? onEditAlarmTapped;
  final VoidCallback? onCancelAlarmTapped; 

  // --- Ringing Actions ---
  final VoidCallback? onSnoozeRinging;
  final VoidCallback? onCancelRinging;

  // --- Scroller Callbacks ---
  final ValueChanged<int>? onHourChanged;
  final ValueChanged<int>? onMinuteChanged;
  final ValueChanged<String>? onAmPmChanged;
  final ValueChanged<String>? onDayChanged;
  final ValueChanged<int>? onTimerHourChanged;
  final ValueChanged<int>? onTimerMinuteChanged;
  final ValueChanged<int>? onTimerSecondChanged;

  // --- View Actions ---
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
  static const double _fixedPillWidth = 272.0; 

  // Premium Color Palette
  static const Color _cAlarm = Color(0xFF00E676); 
  static const Color _cTimer = Color(0xFFFFAB00); 
  static const Color _cStopwatch = Color(0xFF40C4FF); 

  const DClockPill({
    super.key,
    this.isAlarmMode = false,
    this.isViewingAlarms = false,
    this.isAlarmRinging = false,
    this.isStopwatchMode = false,
    this.isStopwatchRunning = false,
    this.stopwatchTime = "00:00.00",
    this.stopwatchLaps = const [],
    this.isTimerMode = false,
    this.isCreatingTimer = false,
    this.isEditingTimer = false,
    this.timerTime = "00:00",
    this.savedTimersTimes = const [],
    this.savedTimersRunning = const [],
    this.selectedTimerIndex,
    this.activeAlarms = const [],
    this.selectedIndex,
    this.initialHour,
    this.initialMinute,
    this.initialAmPm = 'AM',
    this.initialDay = 'Mon',
    this.initialTimerHour,
    this.initialTimerMinute,
    this.initialTimerSecond,
    required this.onAlarmTapped,
    this.onStopwatchTapped,
    this.onTimerTapped,
    this.onStopwatchToggle,
    this.onStopwatchLap,
    this.onStopwatchReset,
    this.onTimerStop,
    this.onSelectAlarm,
    this.onSelectTimer,
    this.onToggleTimer,
    this.onEditTimer,
    this.onEditAlarmTapped,
    this.onCancelAlarmTapped,
    this.onSnoozeRinging,
    this.onCancelRinging,
    this.onHourChanged,
    this.onMinuteChanged,
    this.onAmPmChanged,
    this.onDayChanged,
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

  double _getDesiredHeight() {
    if (isAlarmRinging) return 76.0; // Shrinks down perfectly for the swipe slider
    
    double baseHeight = 130.0; 
    double selectionPadding = 0.0; 
    
    if (isStopwatchMode) {
      double lapsHeight = stopwatchLaps.isEmpty ? 0 : stopwatchLaps.length * 40.0;
      return (baseHeight + 110.0 + lapsHeight).clamp(260.0, 420.0);
    } else if (isTimerMode) {
      if (isCreatingTimer) return 320.0; 
      if (selectedTimerIndex != null) selectionPadding = 50.0; 
      double listHeight = savedTimersTimes.isEmpty ? 60 : savedTimersTimes.length * 62.0;
      return (baseHeight + 40.0 + listHeight + selectionPadding).clamp(220.0, 420.0);
    } else {
      // Alarm Mode
      if (isAlarmMode) return 320.0; 
      if (selectedIndex != null) selectionPadding = 50.0; 
      double listHeight = activeAlarms.isEmpty ? 60 : activeAlarms.length * 58.0;
      return (baseHeight + 40.0 + listHeight + selectionPadding).clamp(220.0, 420.0);
    }
  }

  double _getDesiredWidth() {
    return _fixedPillWidth; // Slider needs full pill width
  }

  @override
  Widget build(BuildContext context) {
    if (isAlarmRinging) {
      return _RingingSlider(
        key: const ValueKey('ringing_slider'),
        ringColor: Colors.white, // Changed to a clean, simple white glow
        onSnooze: onSnoozeRinging,
        onCancel: onCancelRinging,
      );
    }

    Widget content;
    if (isStopwatchMode) {
      content = _buildStopwatchState(key: const ValueKey('stopwatch'));
    } else if (isTimerMode) {
      if (isCreatingTimer) {
        content = _buildTimerScrollers(key: const ValueKey('timer_scrollers'));
      } else {
        content = _buildTimersList(key: const ValueKey('timers_list'));
      }
    } else {
      if (isAlarmMode) {
        content = _buildAlarmScrollers(key: const ValueKey('alarm_scrollers'));
      } else {
        content = _buildAlarmsList(key: const ValueKey('alarms_list'));
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutQuart,
      width: _getDesiredWidth(),
      height: _getDesiredHeight(),
      padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 8.0), 
      child: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: content,
            ),
          ),
          _buildTabBar(),
        ],
      ),
    );
  }

  // --- Bottom Tab Bar ---
  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 0.0), 
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center, 
        children: [
          _buildTabItem(Icons.alarm, (!isStopwatchMode && !isTimerMode), _cAlarm, onAlarmTapped),
          const SizedBox(width: 20), 
          _buildTabItem(Icons.timer_outlined, isStopwatchMode, _cStopwatch, onStopwatchTapped ?? () {}),
          const SizedBox(width: 20), 
          _buildTabItem(Icons.hourglass_bottom, isTimerMode, _cTimer, onTimerTapped ?? () {}),
        ],
      ),
    );
  }

  Widget _buildTabItem(IconData icon, bool isActive, Color activeColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.2) : Colors.transparent,
          shape: BoxShape.circle, 
        ),
        child: Icon(icon, color: isActive ? activeColor : Colors.white54, size: 22),
      ),
    );
  }

  // --- Alarms List View ---
  Widget _buildAlarmsList({Key? key}) {
    return SingleChildScrollView(
      key: key,
      physics: const BouncingScrollPhysics(), 
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 32), 
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.alarm, color: _cAlarm, size: 16),
                  const SizedBox(width: 6),
                  const Text("Alarms", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
              GestureDetector(
                onTap: onAddNewAlarmTapped,
                child: Container(
                  width: 32,
                  alignment: Alignment.centerRight,
                  child: const Icon(Icons.add, color: _cAlarm, size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (activeAlarms.isEmpty)
            const SizedBox(
              height: 80, 
              child: Center(child: Text("No active alarms", style: TextStyle(color: Colors.white54, fontSize: 13)))
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(), 
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
                    height: 52,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected ? _cAlarm.withOpacity(0.15) : Colors.white12,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isSelected ? _cAlarm.withOpacity(0.5) : Colors.transparent),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44, 
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(day, style: TextStyle(color: isSelected ? _cAlarm : Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Text(time, style: TextStyle(color: isSelected ? _cAlarm : Colors.white, fontSize: 24, fontWeight: isSelected ? FontWeight.w500 : FontWeight.w300, fontFeatures: const [FontFeature.tabularFigures()])),
                        const SizedBox(width: 4),
                        Text(ampm, style: TextStyle(color: isSelected ? _cAlarm.withOpacity(0.8) : Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => onEditAlarmTapped?.call(index),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0), 
                            child: Icon(Icons.edit, color: isSelected ? _cAlarm.withOpacity(0.7) : Colors.white38, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          if (selectedIndex != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildActionButton("Delete Selected", Icons.delete, Colors.redAccent, () => onDeleteAlarm?.call(selectedIndex!)),
              ],
            ),
          ]
        ],
      ),
    );
  }

  // --- Alarm Scrollers View ---
  Widget _buildAlarmScrollers({Key? key}) {
    return SingleChildScrollView(
      key: key,
      physics: const NeverScrollableScrollPhysics(), 
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_alarm, color: _cAlarm, size: 16),
              const SizedBox(width: 6),
              const Text("Edit Alarm", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 44, 
                  decoration: BoxDecoration(
                    color: _cAlarm.withOpacity(0.15), 
                    borderRadius: BorderRadius.circular(12)
                  )
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStringScroller(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Daily'], initialDay, onDayChanged, 55),
                    const SizedBox(width: 8),
                    _buildNumberScroller(12, true, 40),
                    const Text(":", style: TextStyle(color: Colors.white54, fontSize: 24, fontWeight: FontWeight.bold)),
                    _buildNumberScroller(60, false, 40),
                    const SizedBox(width: 8),
                    _buildStringScroller(['AM', 'PM'], initialAmPm, onAmPmChanged, 45),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton("Cancel", Icons.close, Colors.white54, onCancelAlarmTapped ?? onViewAlarmsTapped),
              _buildActionButton("Save", Icons.check, _cAlarm, onSaveAlarmTapped),
            ],
          ),
        ],
      ),
    );
  }

  // --- Stopwatch View ---
  Widget _buildStopwatchState({Key? key}) {
    return SingleChildScrollView(
      key: key,
      physics: const BouncingScrollPhysics(), 
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined, color: _cStopwatch, size: 16),
              const SizedBox(width: 6),
              const Text("Stopwatch", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                stopwatchTime.substring(0, 5), 
                style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w200, fontFeatures: [FontFeature.tabularFigures()]),
              ),
              Text(
                stopwatchTime.substring(5), 
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 20, fontWeight: FontWeight.w300, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(isStopwatchRunning ? "Stop" : "Start", isStopwatchRunning ? Icons.pause : Icons.play_arrow, _cStopwatch, onStopwatchToggle),
              if (isStopwatchRunning)
                _buildActionButton("Lap", Icons.flag, Colors.white54, onStopwatchLap)
              else if (stopwatchTime != "00:00.00")
                _buildActionButton("Reset", Icons.refresh, Colors.redAccent, onStopwatchReset),
            ],
          ),
          if (stopwatchLaps.isNotEmpty) ...[
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(), 
              padding: EdgeInsets.zero,
              itemCount: stopwatchLaps.length,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Lap ${stopwatchLaps.length - index}", style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
                      Text(stopwatchLaps[index], style: const TextStyle(color: _cStopwatch, fontSize: 16, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                );
              },
            ),
          ]
        ],
      ),
    );
  }

  // --- Timers List View ---
  Widget _buildTimersList({Key? key}) {
    return SingleChildScrollView(
      key: key,
      physics: const BouncingScrollPhysics(), 
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 32),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.hourglass_bottom, color: _cTimer, size: 16),
                  const SizedBox(width: 6),
                  const Text("Timers", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
              GestureDetector(
                onTap: onAddNewTimerTapped,
                child: Container(
                  width: 32,
                  alignment: Alignment.centerRight,
                  child: const Icon(Icons.add, color: _cTimer, size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (savedTimersTimes.isEmpty)
            const SizedBox(
              height: 80, 
              child: Center(child: Text("No saved timers", style: TextStyle(color: Colors.white54, fontSize: 13)))
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(), 
              padding: EdgeInsets.zero,
              itemCount: savedTimersTimes.length,
              itemBuilder: (context, index) {
                final isSelected = selectedTimerIndex == index;
                final isRunning = savedTimersRunning[index];
                
                return GestureDetector(
                  onTap: () => onSelectTimer?.call(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 56,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected ? _cTimer.withOpacity(0.15) : Colors.white12,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isSelected ? _cTimer.withOpacity(0.5) : Colors.transparent),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => onToggleTimer?.call(index),
                          child: Icon(isRunning ? Icons.pause_circle_filled : Icons.play_circle_fill, color: isSelected ? _cTimer : Colors.white70, size: 32),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            savedTimersTimes[index], 
                            style: TextStyle(color: isSelected ? _cTimer : Colors.white, fontSize: 24, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w300, fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => onEditTimer?.call(index),
                          child: Icon(Icons.edit, color: isSelected ? _cTimer.withOpacity(0.7) : Colors.white38, size: 20),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          if (selectedTimerIndex != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildActionButton("Delete Selected", Icons.delete, Colors.redAccent, () => onDeleteTimer?.call(selectedTimerIndex!)),
              ],
            ),
          ]
        ],
      ),
    );
  }

  // --- Timer Scrollers View ---
  Widget _buildTimerScrollers({Key? key}) {
    return SingleChildScrollView(
      key: key,
      physics: const NeverScrollableScrollPhysics(), 
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hourglass_empty, color: _cTimer, size: 16),
              const SizedBox(width: 6),
              Text(isEditingTimer ? "Edit Timer" : "New Timer", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 44, 
                  width: 200, 
                  decoration: BoxDecoration(color: _cTimer.withOpacity(0.15), borderRadius: BorderRadius.circular(12))
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTimerNumberScroller(24, initialTimerHour ?? 0, onTimerHourChanged, "h"),
                    const SizedBox(width: 16),
                    _buildTimerNumberScroller(60, initialTimerMinute ?? 5, onTimerMinuteChanged, "m"),
                    const SizedBox(width: 16),
                    _buildTimerNumberScroller(60, initialTimerSecond ?? 0, onTimerSecondChanged, "s"),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton("Cancel", Icons.close, Colors.white54, onCancelTimerTapped),
              _buildActionButton("Save", Icons.check, _cTimer, onSaveTimerTapped),
            ],
          ),
        ],
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _buildStringScroller(List<String> items, String initialItem, ValueChanged<String>? onChanged, double width) {
    int initialIndex = items.indexOf(initialItem);
    if (initialIndex < 0) initialIndex = 0;
    
    return SizedBox(
      width: width,
      height: 120, 
      child: ListWheelScrollView.useDelegate(
        controller: FixedExtentScrollController(initialItem: initialIndex),
        itemExtent: 36,
        physics: const FixedExtentScrollPhysics(),
        perspective: 0.005,
        squeeze: 1.15,
        useMagnifier: true,
        magnification: 1.25,
        overAndUnderCenterOpacity: 0.3,
        onSelectedItemChanged: (index) => onChanged?.call(items[index]),
        childDelegate: ListWheelChildLoopingListDelegate(
          children: items.map((item) => Center(
            child: Text(item, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildNumberScroller(int count, bool isHour, double width) {
    int initialVal = isHour ? (initialHour ?? 1) : (initialMinute ?? 0);
    int initialIndex = isHour ? initialVal - 1 : initialVal;

    return SizedBox(
      width: width,
      height: 120,
      child: ListWheelScrollView.useDelegate(
        controller: FixedExtentScrollController(initialItem: initialIndex),
        itemExtent: 36,
        physics: const FixedExtentScrollPhysics(),
        perspective: 0.005,
        squeeze: 1.15,
        useMagnifier: true,
        magnification: 1.25,
        overAndUnderCenterOpacity: 0.3,
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
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w400, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildTimerNumberScroller(int count, int initialVal, ValueChanged<int>? onChanged, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 40,
          height: 120,
          child: ListWheelScrollView.useDelegate(
            controller: FixedExtentScrollController(initialItem: initialVal),
            itemExtent: 36,
            physics: const FixedExtentScrollPhysics(),
            perspective: 0.005,
            squeeze: 1.15,
            useMagnifier: true,
            magnification: 1.25,
            overAndUnderCenterOpacity: 0.3,
            onSelectedItemChanged: (index) => onChanged?.call(index % count),
            childDelegate: ListWheelChildLoopingListDelegate(
              children: List.generate(count, (index) {
                return Center(
                  child: Text(
                    index.toString().padLeft(2, '0'),
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w400, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                );
              }),
            ),
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: onTap != null ? color.withOpacity(0.2) : Colors.white12,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: onTap != null ? color : Colors.white30, size: 16),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: onTap != null ? color : Colors.white30, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// --- Interactive Ringing Slider ---
class _RingingSlider extends StatefulWidget {
  final VoidCallback? onSnooze;
  final VoidCallback? onCancel;
  final Color ringColor;

  const _RingingSlider({
    Key? key,
    this.onSnooze,
    this.onCancel,
    required this.ringColor,
  }) : super(key: key);

  @override
  State<_RingingSlider> createState() => _RingingSliderState();
}

class _RingingSliderState extends State<_RingingSlider> with TickerProviderStateMixin {
  double _dragOffset = 0.0;
  late AnimationController _pulseController;
  late AnimationController _snapController;
  late Animation<double> _snapAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _snapController.addListener(() {
      setState(() {
        _dragOffset = _snapAnimation.value;
      });
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _snapController.dispose();
    super.dispose();
  }

  void _onDragEnd(DragEndDetails details) {
    final double maxDrag = 90.0;
    if (_dragOffset > maxDrag * 0.7) {
      widget.onCancel?.call(); // Stop
    } else if (_dragOffset < -maxDrag * 0.7) {
      widget.onSnooze?.call(); // Snooze
    } else {
      // Snap back to center
      _snapAnimation = Tween<double>(begin: _dragOffset, end: 0.0).animate(
        CurvedAnimation(parent: _snapController, curve: Curves.easeOutBack)
      );
      _snapController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double maxDrag = 90.0;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = _pulseController.value;
        return Container(
          width: DClockPill._fixedPillWidth, // 272
          height: 76.0,
          decoration: BoxDecoration(
            color: widget.ringColor.withOpacity(0.1 + (pulse * 0.05)),
            borderRadius: BorderRadius.circular(38),
            border: Border.all(color: widget.ringColor.withOpacity(0.3 + (pulse * 0.2)), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1 + (pulse * 0.1)),
                blurRadius: 10 + (pulse * 4),
                spreadRadius: 1,
              )
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Left side (Snooze text fades as you swipe)
              Positioned(
                left: 20,
                child: Opacity(
                  opacity: (_dragOffset < 0) ? 1.0 : 0.4,
                  child: const Row(
                    children: [
                      Icon(Icons.chevron_left, color: Colors.white, size: 24),
                      SizedBox(width: 4),
                      Text("Snooze", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ),
              ),
              // Right side (Stop text fades as you swipe)
              Positioned(
                right: 20,
                child: Opacity(
                  opacity: (_dragOffset > 0) ? 1.0 : 0.4,
                  child: const Row(
                    children: [
                      Text("Stop", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right, color: Colors.white, size: 24),
                    ],
                  ),
                ),
              ),
              // Draggable Thumb
              Positioned(
                left: DClockPill._fixedPillWidth / 2 - 28 + _dragOffset,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    if (_snapController.isAnimating) _snapController.stop();
                    setState(() {
                      _dragOffset += details.delta.dx;
                      _dragOffset = _dragOffset.clamp(-maxDrag, maxDrag);
                    });
                  },
                  onHorizontalDragEnd: _onDragEnd,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        )
                      ],
                    ),
                    child: const Icon(Icons.notifications_active_rounded, color: Colors.black87, size: 28),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}