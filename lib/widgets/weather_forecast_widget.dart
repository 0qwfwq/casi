import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';

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
  final String uv;

  const HourlyForecastData({
    required this.time,
    required this.icon,
    required this.iconColor,
    required this.temp,
    this.uv = "--",
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
  final String visibility;
  final String location;
  final DateTime? lastUpdated;
  final bool isRefreshing;
  final VoidCallback? onRefresh;

  const WeatherForecastWidget({
    super.key,
    this.forecastData = const [],
    this.hourlyData = const [],
    this.currentTemp = "--°",
    this.currentDescription = "Unknown",
    this.currentIcon = CupertinoIcons.question,
    this.currentIconColor = Colors.white,
    this.feelsLike = "--°",
    this.wind = "-- mph",
    this.precipitation = "--%",
    this.humidity = "--%",
    this.uvIndex = "--",
    this.sunrise = "--:-- AM",
    this.visibility = "-- mi",
    this.location = "My Location",
    this.lastUpdated,
    this.isRefreshing = false,
    this.onRefresh,
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
                child: Center(child: CircularProgressIndicator(color: CASIColors.textSecondary)),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.location,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      "${widget.currentDescription} • ${_formatLastUpdated(widget.lastUpdated)}",
                      style: const TextStyle(fontSize: 12, color: CASIColors.textSecondary, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.isRefreshing ? null : widget.onRefresh,
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: Center(
                        child: widget.isRefreshing
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CupertinoActivityIndicator(color: CASIColors.textSecondary, radius: 6),
                              )
                            : const Icon(CupertinoIcons.refresh_thin, size: 14, color: CASIColors.textSecondary),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Weather icon in a circle (top-right). Tap to toggle Details ↔ Hourly.
        GestureDetector(
          onTap: () => setState(() => _todayMode = isHourly ? ForecastViewMode.details : ForecastViewMode.hourly),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CASIColors.glassCard,
              border: Border.all(color: CASIColors.textTertiary.withValues(alpha: 0.4), width: 1),
            ),
            child: Center(
              child: Icon(
                isHourly ? CupertinoIcons.clock_fill : widget.currentIcon,
                color: isHourly ? Colors.white : widget.currentIconColor,
                size: 30,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatLastUpdated(DateTime? t) {
    if (t == null) return '--:-- --';
    final h24 = t.hour;
    final hour12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    final mm = t.minute.toString().padLeft(2, '0');
    final hh = hour12.toString().padLeft(2, '0');
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    return '$hh:$mm $ampm';
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
        child: Center(child: CircularProgressIndicator(color: CASIColors.textSecondary)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: widget.hourlyData.map((data) {
          return Column(
            children: [
              Text(data.time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
              const SizedBox(height: 10),
              Icon(data.icon, color: data.iconColor, size: 24),
              const SizedBox(height: 10),
              Text(data.temp, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 6),
              Text(
                "UV ${data.uv}",
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: CASIColors.textSecondary),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDailyContent() {
    if (widget.forecastData.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(color: CASIColors.textSecondary)),
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
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: 2x2 grid of weather details
          Expanded(
            flex: 5,
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildDetailItem(CupertinoIcons.wind, "Wind", widget.wind, const Color(0xFFB8D4E8))),
                    Expanded(child: _buildDetailItem(CupertinoIcons.eye_fill, "Visibility", widget.visibility, const Color(0xFFB8D4E8))),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildDetailItem(CupertinoIcons.drop_fill, "Humidity", widget.humidity, const Color(0xFF6BD4E8))),
                    Expanded(child: _buildDetailItem(CupertinoIcons.cloud_rain_fill, "Precip", widget.precipitation, const Color(0xFF7EB6FF))),
                  ],
                ),
              ],
            ),
          ),
          // Right: large temperature
          Expanded(
            flex: 4,
            child: _buildBigTemperature(),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String title, String value, Color iconColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: CASIColors.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                value,
                style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBigTemperature() {
    final match = RegExp(r'^(-?\d+)').firstMatch(widget.currentTemp);
    final number = match?.group(1) ?? widget.currentTemp;
    final unit = widget.currentTemp.substring(number.length);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          number,
          style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w300, color: Colors.white, height: 1.0),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            unit,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white, height: 1.0),
          ),
        ),
      ],
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
            child: Text(desc, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: CASIColors.textSecondary)),
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
            color: isActive ? Colors.white : CASIColors.textTertiary,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
