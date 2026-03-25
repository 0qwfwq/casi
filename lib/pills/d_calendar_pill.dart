import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';

/// A data model representing a calendar event with a title and optional description.
class CalendarEvent {
  final String title;
  final String description;

  const CalendarEvent({
    required this.title,
    this.description = '',
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
  };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
  );
}

/// The specific content for the Calendar version of the dynamic pill.
/// Displays a paginated monthly calendar, highlights the current day,
/// and allows date selection. It smoothly transitions into an Events List.
class DCalendarPill extends StatefulWidget {
  final DateTime focusedDay;
  final bool isViewingEvents;
  final Map<DateTime, List<CalendarEvent>> events;
  final ValueChanged<DateTime> onDateSelected;
  final int? selectedEventIndex;
  final ValueChanged<int>? onEventSelected;
  
  // Action Callbacks
  final VoidCallback? onAddEvent;
  final VoidCallback? onViewEvents;
  final VoidCallback? onDeleteEvent;
  final VoidCallback? onCloseEvents;

  const DCalendarPill({
    super.key,
    required this.focusedDay,
    this.isViewingEvents = false,
    this.events = const {},
    required this.onDateSelected,
    this.selectedEventIndex,
    this.onEventSelected,
    this.onAddEvent,
    this.onViewEvents,
    this.onDeleteEvent,
    this.onCloseEvents,
  });

  @override
  State<DCalendarPill> createState() => _DCalendarPillState();
}

class _DCalendarPillState extends State<DCalendarPill> {
  // Increased width to 272.0 to perfectly fit 7 items of 32px + 6 gaps of 4px + 24px padding
  static const double _fixedPillWidth = 272.0;
  
  late DateTime _displayMonth;

  @override
  void initState() {
    super.initState();
    // Initialize the calendar view to the currently focused day's month
    _displayMonth = DateTime(widget.focusedDay.year, widget.focusedDay.month);
  }

  void _prevMonth() {
    setState(() {
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 100),
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
      child: widget.isViewingEvents
          ? _buildEventsList(key: const ValueKey('events_list'))
          : _buildCalendarGrid(key: const ValueKey('calendar_grid')),
    );
  }

  Widget _buildEventsList({Key? key}) {
    // Normalize date to ignore time specifics when fetching from map
    final normalizedFocused = DateTime(widget.focusedDay.year, widget.focusedDay.month, widget.focusedDay.day);
    final dayEvents = widget.events[normalizedFocused] ?? [];
    
    // Dynamically size based on number of events and if they have descriptions
    double listHeight = 0.0;
    if (dayEvents.isEmpty) {
      listHeight = 40.0;
    } else {
      for (var e in dayEvents) {
        listHeight += e.description.isNotEmpty ? 60.0 : 44.0;
      }
    }
    // Added extra height buffer to accommodate the new action button row
    final double totalHeight = (listHeight + 110.0).clamp(150.0, 360.0);

    const List<String> monthNames = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun", 
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];

    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 120),
      width: _fixedPillWidth,
      height: totalHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.event, color: CASIColors.accentPrimary, size: 16),
              const SizedBox(width: 6),
              Text(
                "${monthNames[widget.focusedDay.month - 1]} ${widget.focusedDay.day}, ${widget.focusedDay.year}",
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: dayEvents.isEmpty
                ? const Center(
                    child: Text("No events", style: TextStyle(color: CASIColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500))
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: dayEvents.length,
                    itemBuilder: (context, index) {
                      final event = dayEvents[index];
                      final isSelected = widget.selectedEventIndex == index;
                      
                      return GestureDetector(
                        onTap: () => widget.onEventSelected?.call(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          height: event.description.isNotEmpty ? 52 : 36,
                          margin: const EdgeInsets.symmetric(vertical: 4.0),
                          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: isSelected ? CASIColors.alert.withValues(alpha:0.3) : CASIColors.alert.withValues(alpha:0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? CASIColors.alert : CASIColors.alert.withValues(alpha:0.4), 
                              width: isSelected ? 2 : 1
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                event.title,
                                style: const TextStyle(color: CASIColors.alert, fontSize: 13, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (event.description.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  event.description,
                                  style: TextStyle(color: CASIColors.alert.withValues(alpha:0.7), fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ]
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          // --- ACTION BUTTONS (Events List) ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              InkWell(
                onTap: widget.onCloseEvents,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: CASIColors.glassDivider, borderRadius: BorderRadius.circular(20)),
                  child: const Row(
                    children: [
                      Icon(Icons.arrow_back, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text("Back", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: widget.onAddEvent,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: CASIColors.confirm.withValues(alpha:0.2), borderRadius: BorderRadius.circular(20)),
                  child: const Row(
                    children: [
                      Icon(Icons.add, color: CASIColors.confirm, size: 16),
                      SizedBox(width: 4),
                      Text("Add", style: TextStyle(color: CASIColors.confirm, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: widget.selectedEventIndex != null ? widget.onDeleteEvent : null,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: widget.selectedEventIndex != null ? CASIColors.alert.withValues(alpha:0.2) : CASIColors.glassCard, 
                    borderRadius: BorderRadius.circular(20)
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: widget.selectedEventIndex != null ? CASIColors.alert : CASIColors.textTertiary, size: 16),
                      const SizedBox(width: 4),
                      Text("Delete", style: TextStyle(color: widget.selectedEventIndex != null ? CASIColors.alert : CASIColors.textTertiary, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid({Key? key}) {
    final now = DateTime.now();
    
    const List<String> monthNames = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun", 
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    const List<String> weekdays = ["M", "T", "W", "T", "F", "S", "S"];

    int daysInMonth = DateTime(_displayMonth.year, _displayMonth.month + 1, 0).day;
    int firstDayOfWeek = DateTime(_displayMonth.year, _displayMonth.month, 1).weekday;
    int emptySlots = firstDayOfWeek - 1;

    final normalizedFocused = DateTime(widget.focusedDay.year, widget.focusedDay.month, widget.focusedDay.day);
    final hasEventsForFocusedDay = widget.events[normalizedFocused]?.isNotEmpty ?? false;

    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 120),
      width: _fixedPillWidth,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // --- HEADER: Month/Year & Pagination ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _prevMonth,
                child: const Icon(Icons.chevron_left, color: Colors.white, size: 22),
              ),
              Text(
                "${monthNames[_displayMonth.month - 1]} ${_displayMonth.year}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              GestureDetector(
                onTap: _nextMonth,
                child: const Icon(Icons.chevron_right, color: Colors.white, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // --- WEEKDAYS HEADER ---
          Row(
            // Changed from spaceAround to spaceBetween to align perfectly with the Wrap's internal spacing
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: weekdays.map((day) => SizedBox(
              width: 32,
              child: Text(
                day,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CASIColors.textSecondary, 
                  fontSize: 12, 
                  fontWeight: FontWeight.bold
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 8),

          // --- CALENDAR GRID ---
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(emptySlots + daysInMonth, (index) {
              if (index < emptySlots) {
                return const SizedBox(width: 32, height: 32);
              }
              
              int day = index - emptySlots + 1;
              bool isToday = day == now.day && _displayMonth.month == now.month && _displayMonth.year == now.year;
              bool isSelected = day == widget.focusedDay.day && _displayMonth.month == widget.focusedDay.month && _displayMonth.year == widget.focusedDay.year;
              
              final normalizedDay = DateTime(_displayMonth.year, _displayMonth.month, day);
              bool hasEvents = widget.events[normalizedDay]?.isNotEmpty ?? false;

              return GestureDetector(
                onTap: () => widget.onDateSelected(normalizedDay),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isToday 
                        ? CASIColors.accentPrimary 
                        : (isSelected 
                            ? Colors.white.withValues(alpha:0.2) 
                            : (hasEvents ? CASIColors.alert.withValues(alpha:0.15) : Colors.transparent)),
                    borderRadius: BorderRadius.circular(8),
                    border: hasEvents ? Border.all(color: CASIColors.alert.withValues(alpha:0.8), width: 1.5) : null,
                  ),
                  child: Text(
                    '$day',
                    style: TextStyle(
                      color: hasEvents ? CASIColors.alert : (isToday || isSelected ? Colors.white : CASIColors.textSecondary),
                      fontSize: 14,
                      fontWeight: isToday || isSelected || hasEvents ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16), 

          // --- ACTION BUTTONS (Calendar Grid) ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              InkWell(
                onTap: hasEventsForFocusedDay ? widget.onViewEvents : null,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: hasEventsForFocusedDay ? CASIColors.accentPrimary.withValues(alpha:0.2) : CASIColors.glassCard,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_note, color: hasEventsForFocusedDay ? CASIColors.accentPrimary : CASIColors.textTertiary, size: 18),
                      const SizedBox(width: 6),
                      Text("View", style: TextStyle(color: hasEventsForFocusedDay ? CASIColors.accentPrimary : CASIColors.textTertiary, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: widget.onAddEvent,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: CASIColors.confirm.withValues(alpha:0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.add, color: CASIColors.confirm, size: 18),
                      SizedBox(width: 6),
                      Text("Add", style: TextStyle(color: CASIColors.confirm, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}