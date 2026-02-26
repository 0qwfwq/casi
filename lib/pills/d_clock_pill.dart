import 'package:flutter/material.dart';

/// The specific content for the Clock version of the dynamic pill.
/// Contains mockups for Alarm, Stopwatch, and Timer.
class DClockPill extends StatelessWidget {
  final bool isAlarmMode;
  final bool isViewingAlarms;
  final bool isAlarmRinging;
  final List<String> activeAlarms;
  final VoidCallback onAlarmTapped;
  final ValueChanged<int>? onDeleteAlarm;
  final ValueChanged<int>? onHourChanged;
  final ValueChanged<int>? onMinuteChanged;

  const DClockPill({
    super.key,
    this.isAlarmMode = false,
    this.isViewingAlarms = false,
    this.isAlarmRinging = false,
    this.activeAlarms = const [],
    required this.onAlarmTapped,
    this.onDeleteAlarm,
    this.onHourChanged,
    this.onMinuteChanged,
  });

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
          : isViewingAlarms 
              ? _buildAlarmsList(key: const ValueKey('alarms_list'))
              : isAlarmMode 
                  ? _buildTimeScrollers(key: const ValueKey('scrollers'))
                  : _buildActionButtons(key: const ValueKey('buttons')),
    );
  }

  // --- NEW: Ringing State ---
  Widget _buildRingingState({Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_active, color: Colors.white, size: 28),
          SizedBox(width: 12),
          Text(
            "Wake Up!",
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // --- NEW: Alarms List Expandable ---
  Widget _buildAlarmsList({Key? key}) {
    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 300),
      width: 200,
      // Grow pill height based on alarms
      height: activeAlarms.isEmpty ? 60 : (activeAlarms.length * 50.0).clamp(50.0, 150.0),
      child: activeAlarms.isEmpty
          ? const Center(
              child: Text("No active alarms", style: TextStyle(color: Colors.white70)),
            )
          : ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: activeAlarms.length,
              itemBuilder: (context, index) {
                return Dismissible(
                  key: ValueKey(activeAlarms[index] + index.toString()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16.0),
                    color: Colors.redAccent.withOpacity(0.8),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => onDeleteAlarm?.call(index),
                  child: Container(
                    height: 50,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          activeAlarms[index],
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        const Icon(Icons.alarm_on, color: Colors.greenAccent, size: 20),
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
    return Row(
      key: key,
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
          onTap: () {
            debugPrint("Stopwatch mockup tapped!");
          },
        ),
        const SizedBox(width: 8),
        _buildPillButton(
          icon: Icons.hourglass_bottom,
          label: "Timer",
          onTap: () {
            debugPrint("Timer mockup tapped!");
          },
        ),
      ],
    );
  }

  // --- Alarm Mode: Time Scrollers ---
  Widget _buildTimeScrollers({Key? key}) {
    return Row(
      key: key,
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
    );
  }

  Widget _buildNumberScroller(int count, bool isHour) {
    return SizedBox(
      width: 40,
      height: 48,
      child: ListWheelScrollView.useDelegate(
        itemExtent: 30,
        physics: const FixedExtentScrollPhysics(),
        overAndUnderCenterOpacity: 0.3,
        onSelectedItemChanged: (index) {
          int val = isHour ? index + 1 : index;
          if (isHour) {
            onHourChanged?.call(val);
          } else {
            onMinuteChanged?.call(val);
          }
        },
        childDelegate: ListWheelChildLoopingListDelegate(
          children: List.generate(count, (index) {
            // Hours are 1-12, minutes are 0-59
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

  // A helper method to keep the buttons visually consistent
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