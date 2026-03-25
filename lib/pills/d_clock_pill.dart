import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';

/// The specific content for the Clock version of the dynamic pill.
/// Features a focal-display pattern (big time at top) across all tabs,
/// swipe-to-delete rows, and multi-day chip selection for alarms.
class DClockPill extends StatelessWidget {
  // --- Alarm State ---
  final bool isAlarmMode;
  final bool isAlarmRinging;
  final List<String> activeAlarms;
  final int? selectedIndex;
  final List<String> selectedDays;

  // --- Stopwatch State (unchanged) ---
  final bool isStopwatchMode;
  final bool isStopwatchRunning;
  final String stopwatchTime;
  final List<String> stopwatchLaps;

  // --- Timer State ---
  final bool isTimerMode;
  final bool isCreatingTimer;
  final bool isEditingTimer;
  final List<String> savedTimersTimes;
  final List<bool> savedTimersRunning;
  final List<bool> savedTimersAtStart;
  final int? selectedTimerIndex;

  // --- Scroller Initial Values ---
  final int? initialHour;
  final int? initialMinute;
  final String initialAmPm;
  final int? initialTimerHour;
  final int? initialTimerMinute;
  final int? initialTimerSecond;

  // --- Tab Callbacks ---
  final VoidCallback onAlarmTapped;
  final VoidCallback? onStopwatchTapped;
  final VoidCallback? onTimerTapped;

  // --- Alarm Callbacks ---
  final ValueChanged<int>? onAlarmRowTapped;
  final VoidCallback? onAddNewAlarmTapped;
  final VoidCallback? onEditSelectedAlarm;
  final VoidCallback? onSaveAlarmTapped;
  final VoidCallback? onCancelAlarmTapped;
  final ValueChanged<int>? onDeleteAlarm;
  final ValueChanged<List<String>>? onDaysChanged;

  // --- Stopwatch Callbacks (unchanged) ---
  final VoidCallback? onStopwatchToggle;
  final VoidCallback? onStopwatchLap;
  final VoidCallback? onStopwatchReset;

  // --- Timer Callbacks ---
  final ValueChanged<int>? onTimerRowTapped;
  final ValueChanged<int>? onLongPressTimer;
  final VoidCallback? onAddNewTimerTapped;
  final VoidCallback? onSaveTimerTapped;
  final VoidCallback? onCancelTimerTapped;
  final ValueChanged<int>? onDeleteTimer;
  final ValueChanged<int>? onToggleTimer;
  final VoidCallback? onTimerReset;

  // --- Ringing Callbacks (unchanged) ---
  final VoidCallback? onSnoozeRinging;
  final VoidCallback? onCancelRinging;

  // --- Scroller Callbacks ---
  final ValueChanged<int>? onHourChanged;
  final ValueChanged<int>? onMinuteChanged;
  final ValueChanged<String>? onAmPmChanged;
  final ValueChanged<int>? onTimerHourChanged;
  final ValueChanged<int>? onTimerMinuteChanged;
  final ValueChanged<int>? onTimerSecondChanged;

  // --- Constants ---
  static const double _fixedPillWidth = 272.0;
  // CASI Design System semantic colors
  static const Color _cAlarm = CASIColors.confirm;      // #4FD17A — success/positive
  static const Color _cTimer = CASIColors.caution;       // #F7874F — warnings/attention
  static const Color _cStopwatch = CASIColors.accentPrimary; // #4F8EF7 — primary accent

  const DClockPill({
    super.key,
    this.isAlarmMode = false,
    this.isAlarmRinging = false,
    this.activeAlarms = const [],
    this.selectedIndex,
    this.selectedDays = const [],
    this.isStopwatchMode = false,
    this.isStopwatchRunning = false,
    this.stopwatchTime = "00:00.00",
    this.stopwatchLaps = const [],
    this.isTimerMode = false,
    this.isCreatingTimer = false,
    this.isEditingTimer = false,
    this.savedTimersTimes = const [],
    this.savedTimersRunning = const [],
    this.savedTimersAtStart = const [],
    this.selectedTimerIndex,
    this.initialHour,
    this.initialMinute,
    this.initialAmPm = 'AM',
    this.initialTimerHour,
    this.initialTimerMinute,
    this.initialTimerSecond,
    required this.onAlarmTapped,
    this.onStopwatchTapped,
    this.onTimerTapped,
    this.onAlarmRowTapped,
    this.onAddNewAlarmTapped,
    this.onEditSelectedAlarm,
    this.onSaveAlarmTapped,
    this.onCancelAlarmTapped,
    this.onDeleteAlarm,
    this.onDaysChanged,
    this.onStopwatchToggle,
    this.onStopwatchLap,
    this.onStopwatchReset,
    this.onTimerRowTapped,
    this.onLongPressTimer,
    this.onAddNewTimerTapped,
    this.onSaveTimerTapped,
    this.onCancelTimerTapped,
    this.onDeleteTimer,
    this.onToggleTimer,
    this.onTimerReset,
    this.onSnoozeRinging,
    this.onCancelRinging,
    this.onHourChanged,
    this.onMinuteChanged,
    this.onAmPmChanged,
    this.onTimerHourChanged,
    this.onTimerMinuteChanged,
    this.onTimerSecondChanged,
  });

  double _getDesiredHeight() {
    if (isAlarmRinging) return 120.0;

    if (isStopwatchMode) {
      double lapsHeight = stopwatchLaps.isEmpty ? 0 : stopwatchLaps.length * 40.0;
      return (240.0 + lapsHeight).clamp(260.0, 420.0);
    } else if (isTimerMode) {
      if (isCreatingTimer) return 310.0;
      if (savedTimersTimes.isEmpty) return 220.0;
      double focalHeight = selectedTimerIndex != null ? 100.0 : 0.0;
      double listHeight = savedTimersTimes.length * 48.0;
      return (160.0 + focalHeight + listHeight).clamp(280.0, 420.0);
    } else {
      // Alarm
      if (isAlarmMode) return 340.0;
      if (activeAlarms.isEmpty) return 220.0;
      double focalHeight = selectedIndex != null ? 110.0 : 24.0;
      double listHeight = activeAlarms.length * 48.0;
      return (150.0 + focalHeight + listHeight).clamp(260.0, 420.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isAlarmRinging) {
      return _RingingSlider(
        key: const ValueKey('ringing_slider'),
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
        content = _buildTimerView(key: const ValueKey('timer_view'));
      }
    } else {
      if (isAlarmMode) {
        content = _buildAlarmScrollers(key: const ValueKey('alarm_scrollers'));
      } else {
        content = _buildAlarmView(key: const ValueKey('alarm_view'));
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      width: _fixedPillWidth,
      height: _getDesiredHeight(),
      padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 8.0),
      child: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 100),
              child: content,
            ),
          ),
          _buildTabBar(),
        ],
      ),
    );
  }

  // =====================================================================
  // TAB BAR (unchanged)
  // =====================================================================

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
        duration: const Duration(milliseconds: 100),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isActive ? activeColor.withValues(alpha:0.2) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: isActive ? activeColor : CASIColors.textSecondary, size: 22),
      ),
    );
  }

  // =====================================================================
  // ALARM VIEW — Focal Display + Compact Swipeable List
  // =====================================================================

  Widget _buildAlarmView({Key? key}) {
    String? focalTime;
    String? focalDay;
    if (selectedIndex != null && selectedIndex! < activeAlarms.length) {
      final parts = activeAlarms[selectedIndex!].split(' ');
      if (parts.length == 3) {
        focalDay = parts[0];
        focalTime = "${parts[1]} ${parts[2]}";
      } else if (parts.length == 2) {
        focalDay = 'Daily';
        focalTime = "${parts[0]} ${parts[1]}";
      }
    }

    return SingleChildScrollView(
      key: key,
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
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

          // Focal Display Area
          if (activeAlarms.isEmpty)
            _buildFocalTimeDisplay("No Alarms", isEmpty: true)
          else if (focalTime != null) ...[
            _buildFocalTimeDisplay(focalTime, subtitle: focalDay, color: _cAlarm),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton("Delete", Icons.delete, CASIColors.alert, () => onDeleteAlarm?.call(selectedIndex!)),
                _buildActionButton("Edit", Icons.edit, _cAlarm, onEditSelectedAlarm),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text("Tap an alarm to manage", style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13)),
            ),

          if (activeAlarms.isNotEmpty) ...[
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: activeAlarms.length,
              itemBuilder: (context, index) {
                final isSelected = selectedIndex == index;
                final parts = activeAlarms[index].split(' ');
                String day, time, ampm;
                if (parts.length == 3) {
                  day = parts[0];
                  time = parts[1];
                  ampm = parts[2];
                } else {
                  day = 'Daily';
                  time = parts.isNotEmpty ? parts[0] : '';
                  ampm = parts.length > 1 ? parts[1] : '';
                }

                return Dismissible(
                  key: ValueKey('alarm_${activeAlarms[index]}_$index'),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => onDeleteAlarm?.call(index),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: CASIColors.alert.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete, color: CASIColors.alert, size: 20),
                  ),
                  child: GestureDetector(
                    onTap: () => onAlarmRowTapped?.call(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      height: 44,
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? _cAlarm.withValues(alpha: 0.15) : CASIColors.glassCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? _cAlarm.withValues(alpha: 0.5) : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            child: Text(day, style: TextStyle(color: isSelected ? _cAlarm : CASIColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Text(time, style: TextStyle(color: isSelected ? _cAlarm : Colors.white, fontSize: 20, fontWeight: FontWeight.w400, fontFeatures: const [FontFeature.tabularFigures()])),
                          const SizedBox(width: 4),
                          Text(ampm, style: TextStyle(color: isSelected ? _cAlarm.withValues(alpha: 0.8) : CASIColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // =====================================================================
  // ALARM SCROLLERS — Day Chips + Time Wheels
  // =====================================================================

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
              Text(
                selectedIndex != null ? "Edit Alarm" : "New Alarm",
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDayChips(),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: _cAlarm.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildNumberScroller(12, true, 40),
                    const Text(":", style: TextStyle(color: CASIColors.textSecondary, fontSize: 24, fontWeight: FontWeight.bold)),
                    _buildNumberScroller(60, false, 40),
                    const SizedBox(width: 8),
                    _buildStringScroller(['AM', 'PM'], initialAmPm, onAmPmChanged, 45),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton("Cancel", Icons.close, CASIColors.textSecondary, onCancelAlarmTapped),
              _buildActionButton("Save", Icons.check, _cAlarm, onSaveAlarmTapped),
            ],
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // STOPWATCH VIEW (unchanged)
  // =====================================================================

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
                style: TextStyle(color: Colors.white.withValues(alpha:0.6), fontSize: 20, fontWeight: FontWeight.w300, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(isStopwatchRunning ? "Stop" : "Start", isStopwatchRunning ? Icons.pause : Icons.play_arrow, _cStopwatch, onStopwatchToggle),
              if (isStopwatchRunning)
                _buildActionButton("Lap", Icons.flag, CASIColors.textSecondary, onStopwatchLap)
              else if (stopwatchTime != "00:00.00")
                _buildActionButton("Reset", Icons.refresh, CASIColors.alert, onStopwatchReset),
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
                  decoration: BoxDecoration(color: CASIColors.glassCard, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Lap ${stopwatchLaps.length - index}", style: const TextStyle(color: CASIColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
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

  // =====================================================================
  // TIMER VIEW — Focal Display + Compact Swipeable List
  // =====================================================================

  Widget _buildTimerView({Key? key}) {
    String? focusedTime;
    bool focusedRunning = false;
    bool focusedAtStart = true;

    if (selectedTimerIndex != null && selectedTimerIndex! < savedTimersTimes.length) {
      focusedTime = savedTimersTimes[selectedTimerIndex!];
      focusedRunning = savedTimersRunning[selectedTimerIndex!];
      focusedAtStart = savedTimersAtStart[selectedTimerIndex!];
    }

    return SingleChildScrollView(
      key: key,
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 32),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.hourglass_bottom, color: _cTimer, size: 16),
                  const SizedBox(width: 6),
                  const Text("Timer", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
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

          // Focal Display
          if (savedTimersTimes.isEmpty)
            _buildFocalTimeDisplay("No Timers", isEmpty: true)
          else if (focusedTime != null) ...[
            _buildFocalTimeDisplay(focusedTime, color: _cTimer),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  focusedRunning ? "Pause" : (focusedAtStart ? "Start" : "Resume"),
                  focusedRunning ? Icons.pause : Icons.play_arrow,
                  _cTimer,
                  () => onToggleTimer?.call(selectedTimerIndex!),
                ),
                if (!focusedRunning && !focusedAtStart)
                  _buildActionButton("Reset", Icons.refresh, CASIColors.alert, onTimerReset),
              ],
            ),
          ],

          if (savedTimersTimes.isNotEmpty) ...[
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: savedTimersTimes.length,
              itemBuilder: (context, index) {
                final isSelected = selectedTimerIndex == index;
                final isRunning = savedTimersRunning[index];

                return Dismissible(
                  key: ValueKey('timer_${index}_${savedTimersTimes[index]}'),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => onDeleteTimer?.call(index),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: CASIColors.alert.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete, color: CASIColors.alert, size: 20),
                  ),
                  child: GestureDetector(
                    onTap: () => onTimerRowTapped?.call(index),
                    onLongPress: () => onLongPressTimer?.call(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      height: 44,
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? _cTimer.withValues(alpha: 0.15) : CASIColors.glassCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? _cTimer.withValues(alpha: 0.5) : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => onToggleTimer?.call(index),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                              child: Icon(
                                isRunning ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                color: isSelected ? _cTimer : CASIColors.textSecondary,
                                size: 24,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            savedTimersTimes[index],
                            style: TextStyle(
                              color: isSelected ? _cTimer : Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w400,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // =====================================================================
  // TIMER SCROLLERS — H:M:S Wheels
  // =====================================================================

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
                  decoration: BoxDecoration(color: _cTimer.withValues(alpha:0.15), borderRadius: BorderRadius.circular(12)),
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
              _buildActionButton("Cancel", Icons.close, CASIColors.textSecondary, onCancelTimerTapped),
              _buildActionButton(
                isEditingTimer ? "Save" : "Start",
                isEditingTimer ? Icons.check : Icons.play_arrow,
                _cTimer,
                onSaveTimerTapped,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // SHARED HELPERS
  // =====================================================================

  Widget _buildFocalTimeDisplay(String time, {String? subtitle, Color color = Colors.white, bool isEmpty = false}) {
    if (isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(time, style: TextStyle(color: CASIColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w400)),
      );
    }
    return Column(
      children: [
        Text(
          time,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 44,
            fontWeight: FontWeight.w200,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  Widget _buildDayChips() {
    const allDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final bool allSelected = allDays.every((d) => selectedDays.contains(d));

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () {
            if (allSelected) {
              onDaysChanged?.call([]);
            } else {
              onDaysChanged?.call(List.from(allDays));
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 36,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: allSelected ? _cAlarm.withValues(alpha: 0.25) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: allSelected ? _cAlarm.withValues(alpha: 0.6) : CASIColors.glassDivider,
              ),
            ),
            child: Text(
              "All",
              style: TextStyle(
                color: allSelected ? Colors.white : CASIColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        ...List.generate(7, (i) {
          final isSelected = selectedDays.contains(allDays[i]);
          return Padding(
            padding: EdgeInsets.only(left: i > 0 ? 3 : 0),
            child: GestureDetector(
              onTap: () {
                final newDays = List<String>.from(selectedDays);
                if (isSelected) {
                  newDays.remove(allDays[i]);
                } else {
                  newDays.add(allDays[i]);
                }
                onDaysChanged?.call(newDays);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? _cAlarm.withValues(alpha: 0.25) : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? _cAlarm.withValues(alpha: 0.6) : CASIColors.glassDivider,
                  ),
                ),
                child: Text(
                  dayLabels[i],
                  style: TextStyle(
                    color: isSelected ? Colors.white : CASIColors.textTertiary,
                    fontSize: 12,
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

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: onTap != null ? color.withValues(alpha:0.2) : CASIColors.glassCard,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: onTap != null ? color : CASIColors.textTertiary, size: 16),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: onTap != null ? color : CASIColors.textTertiary, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  // SCROLLER HELPERS (unchanged)
  // =====================================================================

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
          if (isHour) {
            onHourChanged?.call(val);
          } else {
            onMinuteChanged?.call(val);
          }
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
        Text(label, style: const TextStyle(color: CASIColors.textSecondary, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// =====================================================================
// RINGING SLIDER (unchanged)
// =====================================================================

class _RingingSlider extends StatefulWidget {
  final VoidCallback? onSnooze;
  final VoidCallback? onCancel;

  const _RingingSlider({
    super.key,
    this.onSnooze,
    this.onCancel,
  });

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
    final double trackWidth = DClockPill._fixedPillWidth - (CASISpacing.md * 2);
    final double maxDrag = (trackWidth - 56) / 2;
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
    final double trackWidth = DClockPill._fixedPillWidth - (CASISpacing.md * 2);
    final double maxDrag = (trackWidth - 56) / 2;
    final double normalizedDrag = (maxDrag > 0) ? (_dragOffset / maxDrag).clamp(-1.0, 1.0) : 0.0;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = _pulseController.value;
        return Container(
          width: DClockPill._fixedPillWidth,
          height: 120.0,
          padding: const EdgeInsets.all(CASISpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Ringing label with subtle pulse
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_active_rounded,
                    color: CASIColors.alert.withValues(alpha: 0.6 + (pulse * 0.4)),
                    size: CASIIcons.small,
                  ),
                  const SizedBox(width: CASISpacing.sm),
                  Text(
                    "Alarm Ringing",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7 + (pulse * 0.3)),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Slide track — glass-on-glass
              Container(
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: CASIElevation.base.bgAlpha),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.04),
                    width: 1.0,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Snooze label (left) — fades in as you drag left
                    Positioned(
                      left: CASISpacing.md,
                      child: Opacity(
                        opacity: normalizedDrag < 0 ? (-normalizedDrag).clamp(0.3, 1.0) : 0.3,
                        child: const Text(
                          "Snooze",
                          style: TextStyle(
                            color: CASIColors.accentPrimary,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    // Stop label (right) — fades in as you drag right
                    Positioned(
                      right: CASISpacing.md,
                      child: Opacity(
                        opacity: normalizedDrag > 0 ? normalizedDrag.clamp(0.3, 1.0) : 0.3,
                        child: const Text(
                          "Stop",
                          style: TextStyle(
                            color: CASIColors.alert,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    // Draggable thumb — glass circle
                    Positioned(
                      left: (trackWidth - 44) / 2 + _dragOffset,
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
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: CASIElevation.raised.bgAlpha),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: CASIElevation.raised.borderAlpha),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.chevron_left_rounded,
                            color: CASIColors.textSecondary,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
