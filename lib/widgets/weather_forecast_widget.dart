import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class DailyForecastData {
  final String day;
  final IconData icon;
  final Color iconColor;
  final String temp;
  final String description;

  const DailyForecastData({
    required this.day,
    required this.icon,
    required this.iconColor,
    required this.temp,
    required this.description,
  });
}

class HourlyForecastData {
  final String time;
  final IconData icon;
  final Color iconColor;
  final String temp;

  const HourlyForecastData({
    required this.time,
    required this.icon,
    required this.iconColor,
    required this.temp,
  });
}

enum ForecastViewMode { daily, hourly, details }

class WeatherForecastWidget extends StatefulWidget {
  final List<DailyForecastData> forecastData;
  final List<HourlyForecastData> hourlyData;

  // Header Current Data
  final String currentTemp;
  final String currentDescription;
  final IconData currentIcon;
  final Color currentIconColor;

  // Detailed Data
  final String feelsLike;
  final String wind;
  final String precipitation;
  final String humidity;
  final String uvIndex;
  final String sunrise;

  const WeatherForecastWidget({
    super.key,
    this.forecastData = const [],
    this.hourlyData = const [],
    this.currentTemp = "--°C",
    this.currentDescription = "Unknown",
    this.currentIcon = CupertinoIcons.question,
    this.currentIconColor = Colors.white,
    this.feelsLike = "--°C",
    this.wind = "-- mph",
    this.precipitation = "--%",
    this.humidity = "--%",
    this.uvIndex = "--",
    this.sunrise = "--:-- AM",
  });

  @override
  State<WeatherForecastWidget> createState() => _WeatherForecastWidgetState();
}

class _WeatherForecastWidgetState extends State<WeatherForecastWidget> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  // Toggle between details and hourly on the "today" page
  ForecastViewMode _todayMode = ForecastViewMode.details;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! < -200 && _currentPage == 0) {
            setState(() => _currentPage = 1);
          } else if (details.primaryVelocity! > 200 && _currentPage == 1) {
            setState(() => _currentPage = 0);
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header changes based on current page
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _currentPage == 0
                  ? _buildCurrentWeatherHeader(key: const ValueKey('today_header'))
                  : _buildDailyHeader(key: const ValueKey('daily_header')),
            ),

            const SizedBox(height: 16),

            // Page content
            if (widget.forecastData.isEmpty && widget.hourlyData.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(color: Colors.white54)),
              )
            else
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: _currentPage == 0
                      ? KeyedSubtree(key: const ValueKey('today'), child: _buildTodayPage())
                      : KeyedSubtree(key: const ValueKey('daily'), child: _buildDailyPage()),
                ),
              ),

            const SizedBox(height: 12),

            // Page indicator dots
            _buildPageIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentWeatherHeader({Key? key}) {
    final bool isHourly = _todayMode == ForecastViewMode.hourly;

    return Row(
      key: key,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(widget.currentIcon, color: widget.currentIconColor, size: 22),
            const SizedBox(width: 8),
            Text(
              "${widget.currentDescription}, ${widget.currentTemp}",
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ],
        ),
        GestureDetector(
          onTap: () => setState(() => _todayMode = isHourly ? ForecastViewMode.details : ForecastViewMode.hourly),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isHourly ? CupertinoIcons.info_circle_fill : CupertinoIcons.clock_fill,
                  size: 12,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  isHourly ? "Details" : "Hourly",
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyHeader({Key? key}) {
    return Text(
      key: key,
      "5-Day Forecast",
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
    );
  }

  // --- Page content builders ---

  Widget _buildTodayPage() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 100),
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: <Widget>[
            ...previousChildren.map((child) => Positioned(top: 0, left: 0, right: 0, child: child)),
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: Container(
        key: ValueKey(_todayMode),
        child: _todayMode == ForecastViewMode.hourly ? _buildHourlyContent() : _buildDetailsContent(),
      ),
    );
  }

  Widget _buildDailyPage() {
    return _buildDailyContent();
  }

  // --- Content builders ---

  Widget _buildHourlyContent() {
    if (widget.hourlyData.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(color: Colors.white54)),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: widget.hourlyData.map((data) {
        return Column(
          children: [
            Text(data.time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
            const SizedBox(height: 10),
            Icon(data.icon, color: data.iconColor, size: 24),
            const SizedBox(height: 10),
            Text(data.temp, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildDailyContent() {
    if (widget.forecastData.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(color: Colors.white54)),
      );
    }
    return Column(
      children: widget.forecastData.asMap().entries.map((entry) {
        final index = entry.key;
        final data = entry.value;
        return Column(
          children: [
            _buildForecastRow(data.day, data.icon, data.iconColor, data.temp, data.description),
            if (index < widget.forecastData.length - 1)
              const SizedBox(height: 12),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildDetailsContent() {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            children: [
              Expanded(child: _buildDetailItem("Feels Like", widget.feelsLike)),
              Container(width: 1, color: Colors.white24),
              Expanded(child: _buildDetailItem("Wind", widget.wind)),
              Container(width: 1, color: Colors.white24),
              Expanded(child: _buildDetailItem("Precipitation", widget.precipitation)),
            ],
          ),
        ),
        const Divider(color: Colors.white24, height: 1, thickness: 1),
        IntrinsicHeight(
          child: Row(
            children: [
              Expanded(child: _buildDetailItem("Humidity", widget.humidity)),
              Container(width: 1, color: Colors.white24),
              Expanded(child: _buildDetailItem("UV Index", widget.uvIndex)),
              Container(width: 1, color: Colors.white24),
              Expanded(child: _buildDetailItem("Sunrise", widget.sunrise)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailItem(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildForecastRow(String day, IconData icon, Color iconColor, String temp, String desc) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(day, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
        ),
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 12),
        Text(temp, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(desc, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Colors.white70)),
          ),
        ),
      ],
    );
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(2, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 16 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
