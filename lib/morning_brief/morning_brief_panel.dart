import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'weather_brief_service.dart';

class MorningBriefPanel extends StatefulWidget {
  final VoidCallback onDismiss;
  final WeatherBriefData? weatherData;

  const MorningBriefPanel({
    super.key,
    required this.onDismiss,
    this.weatherData,
  });

  @override
  State<MorningBriefPanel> createState() => _MorningBriefPanelState();
}

class _MorningBriefPanelState extends State<MorningBriefPanel> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

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

  IconData _conditionIcon(String condition) {
    switch (condition) {
      case 'Clear':
        return CupertinoIcons.sun_max_fill;
      case 'Cloudy':
        return CupertinoIcons.cloud_fill;
      case 'Rainy':
        return CupertinoIcons.cloud_rain_fill;
      case 'Snowy':
        return CupertinoIcons.snow;
      case 'Stormy':
        return CupertinoIcons.cloud_bolt_fill;
      case 'Foggy':
        return CupertinoIcons.cloud_fog_fill;
      default:
        return CupertinoIcons.sun_max_fill;
    }
  }

  Color _conditionColor(String condition) {
    switch (condition) {
      case 'Clear':
        return Colors.orange.shade300;
      case 'Cloudy':
        return Colors.blueGrey.shade200;
      case 'Rainy':
        return Colors.blue.shade300;
      case 'Snowy':
        return Colors.lightBlue.shade100;
      case 'Stormy':
        return Colors.deepPurple.shade300;
      case 'Foggy':
        return Colors.grey.shade400;
      default:
        return Colors.orange.shade300;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = screenWidth - 64;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            width: panelWidth,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha:0.2),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha:0.15),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              children: [
                Column(
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
                        ],
                      ),
                    ),
                    _buildPageIndicator(),
                    const SizedBox(height: 12),
                  ],
                ),
                // Dismiss button
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: widget.onDismiss,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha:0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white54,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
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
      children: List.generate(2, (index) {
        final isActive = _currentPage == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.white30,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  Widget _buildGreetingPage() {
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
              color: Colors.white.withValues(alpha:0.6),
              fontSize: 14,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Swipe to see your day',
                style: TextStyle(
                  color: Colors.white.withValues(alpha:0.4),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withValues(alpha:0.4),
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
            style: TextStyle(color: Colors.white54, fontSize: 14),
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
            // Clothing suggestion
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha:0.15),
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
                              color: Colors.white.withValues(alpha:0.5),
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
            // Clothing row
            Row(
              children: [
                Icon(
                  Icons.checkroom,
                  color: Colors.white.withValues(alpha:0.5),
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    weather.clothingSuggestion,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha:0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Weather summary
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha:0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                weather.weatherSummary,
                style: TextStyle(
                  color: Colors.white.withValues(alpha:0.6),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w400,
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
}
