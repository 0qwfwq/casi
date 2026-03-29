import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';
import 'weather_brief_service.dart';
import 'calendar_brief_service.dart';
import 'health_brief_service.dart';
import '../pills/d_calendar_pill.dart';

class MorningBriefPanel extends StatefulWidget {
  final VoidCallback onDismiss;
  final VoidCallback? onRefreshHealth;
  final WeatherBriefData? weatherData;
  final CalendarBriefData? calendarData;
  final HealthBriefData? healthData;
  final Map<DateTime, List<CalendarEvent>> launcherEvents;
  final String? ariaSuggestion;
  final bool ariaReady;
  final bool ariaGenerating;
  final String? ariaOutfitNarrative;
  final String? ariaWeatherNarrative;
  final bool ariaWeatherGenerating;
  final VoidCallback? onImportARIAModel;

  const MorningBriefPanel({
    super.key,
    required this.onDismiss,
    this.onRefreshHealth,
    this.weatherData,
    this.calendarData,
    this.healthData,
    this.launcherEvents = const {},
    this.ariaSuggestion,
    this.ariaReady = false,
    this.ariaGenerating = false,
    this.ariaOutfitNarrative,
    this.ariaWeatherNarrative,
    this.ariaWeatherGenerating = false,
    this.onImportARIAModel,
  });

  @override
  State<MorningBriefPanel> createState() => _MorningBriefPanelState();
}

class _MorningBriefPanelState extends State<MorningBriefPanel> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  static const int _totalPages = 4;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _getDateString() {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    ];
    final now = DateTime.now();
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  IconData _conditionIcon(String condition) => switch (condition) {
    'Clear' => CupertinoIcons.sun_max_fill,
    'Cloudy' => CupertinoIcons.cloud_fill,
    'Rainy' => CupertinoIcons.cloud_rain_fill,
    'Snowy' => CupertinoIcons.snow,
    'Stormy' => CupertinoIcons.cloud_bolt_fill,
    'Foggy' => CupertinoIcons.cloud_fog_fill,
    _ => CupertinoIcons.sun_max_fill,
  };

  Color _conditionColor(String condition) => switch (condition) {
    'Clear' => CASIColors.caution,           // Warm orange
    'Cloudy' => CASIColors.textSecondary,     // Muted
    'Rainy' => CASIColors.accentPrimary,      // Pulse Blue
    'Snowy' => CASIColors.accentTertiary,     // Teal
    'Stormy' => CASIColors.accentSecondary,   // Pulse Purple
    'Foggy' => CASIColors.textSecondary,      // Muted
    _ => CASIColors.caution,
  };

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = screenWidth - 64;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CASIGlass.cornerSheet),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: CASIGlass.blurSheet, sigmaY: CASIGlass.blurSheet),
          child: Container(
            width: panelWidth,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: CASIGlass.tintSheet),
              borderRadius: BorderRadius.circular(CASIGlass.cornerSheet),
              border: Border.all(
                color: Colors.white.withValues(alpha: CASIElevation.float_.borderAlpha),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                // Swipe up to dismiss (like weather widget)
                if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
                  widget.onDismiss();
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: _panelHeight,
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: (page) {
                        setState(() => _currentPage = page);
                      },
                      children: [
                        _buildGreetingPage(),
                        _buildWeatherPage(),
                        _buildCalendarPage(),
                        _buildHealthPage(),
                      ],
                    ),
                  ),
                  _buildPageIndicator(),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double get _panelHeight => 200.0;

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_totalPages, (index) {
        final isActive = _currentPage == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : CASIColors.textTertiary,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  Widget _buildGreetingPage() {
    final suggestion = widget.ariaSuggestion;
    return Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _getGreeting(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _getDateString(),
                style: TextStyle(
                  color: CASIColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 16),
              // ARIA-generated encouragement (streams word-by-word)
              if (suggestion != null && widget.ariaReady)
                Text(
                  suggestion,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: CASIColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w300,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                )
              else if (widget.ariaGenerating)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: CASIColors.accentPrimary,
                  ),
                )
              else if (!widget.ariaReady)
                GestureDetector(
                  onTap: widget.onImportARIAModel,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: CASIColors.textTertiary,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Set up ARIA',
                        style: TextStyle(
                          color: CASIColors.textTertiary,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Swipe to see your day',
                    style: TextStyle(
                      color: CASIColors.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: CASIColors.textTertiary,
                    size: 10,
                  ),
                ],
              ),
            ],
          ),
        );
  }

  Widget _buildWeatherPage() {
    final weather = widget.weatherData;
    if (weather == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Weather data is loading...',
            style: TextStyle(color: CASIColors.textSecondary, fontSize: 14),
          ),
        ),
      );
    }

    final icon = _conditionIcon(weather.overallCondition);
    final iconColor = _conditionColor(weather.overallCondition);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${weather.highTemp.round()}°',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                          Text(
                            ' / ${weather.lowTemp.round()}°C',
                            style: TextStyle(
                              color: CASIColors.textTertiary,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        weather.overallCondition,
                        style: TextStyle(
                          color: iconColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  Icons.checkroom,
                  color: CASIColors.textTertiary,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.ariaOutfitNarrative ?? weather.clothingSuggestion,
                    style: TextStyle(
                      color: CASIColors.textSecondary,
                      fontSize: 12,
                      fontWeight: widget.ariaOutfitNarrative != null
                          ? FontWeight.w300
                          : FontWeight.w400,
                      fontStyle: widget.ariaOutfitNarrative != null
                          ? FontStyle.italic
                          : FontStyle.normal,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CASIColors.glassCard,
                borderRadius: BorderRadius.circular(14),
              ),
              child: widget.ariaWeatherGenerating && widget.ariaWeatherNarrative == null
                  ? Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: CASIColors.accentPrimary,
                        ),
                      ),
                    )
                  : Text(
                      widget.ariaWeatherNarrative ?? weather.weatherSummary,
                      style: TextStyle(
                        color: CASIColors.textSecondary,
                        fontSize: 11.5,
                        fontWeight: widget.ariaWeatherNarrative != null
                            ? FontWeight.w300
                            : FontWeight.w400,
                        fontStyle: widget.ariaWeatherNarrative != null
                            ? FontStyle.italic
                            : FontStyle.normal,
                        height: 1.5,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Panel 3: Calendar Events ────────────────────────────────────────────

  /// Collects today's launcher-created events as DeviceCalendarEvent objects.
  List<DeviceCalendarEvent> _todayLauncherEvents() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final launcherEvts = widget.launcherEvents[today] ?? [];
    return launcherEvts.map((e) => DeviceCalendarEvent(
      title: e.title,
      begin: 0,
      end: 0,
      allDay: true,
      description: e.description,
    )).toList();
  }

  Widget _buildCalendarPage() {
    final calData = widget.calendarData;
    final launcherEvts = _todayLauncherEvents();

    // No permission and no launcher events
    if (calData != null && !calData.hasPermission && launcherEvts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_month_outlined,
              color: CASIColors.textTertiary,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              'Allow calendar access to see\nyour events here',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CASIColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => CalendarBriefService.requestPermission(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: CASIColors.glassCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: CASIColors.glassDivider,
                  ),
                ),
                child: const Text(
                  'Grant Permission',
                  style: TextStyle(
                    color: CASIColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Loading (but still show launcher events if available)
    if (calData == null && launcherEvts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Loading calendar...',
            style: TextStyle(color: CASIColors.textSecondary, fontSize: 14),
          ),
        ),
      );
    }

    // Combine device calendar events with launcher events
    final deviceEvents = calData?.events ?? [];
    final events = [...deviceEvents, ...launcherEvts];

    // No events today from either source
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_available,
              color: CASIColors.confirm,
              size: 32,
            ),
            const SizedBox(height: 12),
            const Text(
              'No events today',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your schedule is clear',
              style: TextStyle(
                color: CASIColors.textTertiary,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                color: CASIColors.accentPrimary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                "Today's Schedule",
                style: TextStyle(
                  color: CASIColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${events.length} event${events.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: CASIColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              itemCount: events.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final event = events[index];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: CASIColors.glassCard,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 3,
                        height: 32,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: CASIColors.accentPrimary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  event.timeString,
                                  style: TextStyle(
                                    color: CASIColors.textTertiary,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                if (event.location.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.location_on,
                                    color: CASIColors.textTertiary,
                                    size: 10,
                                  ),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      event.location,
                                      style: TextStyle(
                                        color: CASIColors.textTertiary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Panel 4: Health & Fitness ───────────────────────────────────────────

  Widget _buildHealthPage() {
    final health = widget.healthData;

    // Health Connect not available
    if (health != null && !health.available) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border,
              color: CASIColors.textTertiary,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              'Health Connect is required\nto view your fitness data',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CASIColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                await HealthBriefService.requestPermissions();
                widget.onRefreshHealth?.call();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: CASIColors.glassCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: CASIColors.glassDivider,
                  ),
                ),
                child: const Text(
                  'Set Up Health',
                  style: TextStyle(
                    color: CASIColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Loading
    if (health == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Loading health data...',
            style: TextStyle(color: CASIColors.textSecondary, fontSize: 14),
          ),
        ),
      );
    }

    // Show health data
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.favorite_rounded,
                color: CASIColors.alert,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                "Today's Activity",
                style: TextStyle(
                  color: CASIColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Row 1: Steps & Sleep
          Row(
            children: [
              Expanded(
                child: _buildHealthRow(
                  icon: Icons.directions_walk,
                  iconColor: CASIColors.confirm,
                  label: 'Steps',
                  value: health.stepsString,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildHealthRow(
                  icon: Icons.bedtime_outlined,
                  iconColor: CASIColors.accentSecondary,
                  label: 'Sleep',
                  value: health.sleepString,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 2: Calories & Active
          Row(
            children: [
              Expanded(
                child: _buildHealthRow(
                  icon: Icons.local_fire_department,
                  iconColor: CASIColors.caution,
                  label: 'Calories',
                  value: health.caloriesString,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildHealthRow(
                  icon: Icons.timer_outlined,
                  iconColor: CASIColors.accentTertiary,
                  label: 'Active',
                  value: health.activeTimeString,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 3: Distance + Refresh
          Row(
            children: [
              Expanded(
                child: _buildHealthRow(
                  icon: Icons.straighten,
                  iconColor: CASIColors.accentTertiary,
                  label: 'Distance',
                  value: health.distanceString,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onRefreshHealth,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: CASIColors.glassCard,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.refresh_rounded,
                    color: CASIColors.textTertiary,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHealthRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: CASIColors.glassCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: CASIColors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
