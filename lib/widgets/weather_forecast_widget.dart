import 'dart:ui';
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

  // Configuration
  final ForecastViewMode initialViewMode;

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
    this.initialViewMode = ForecastViewMode.daily, // Defaults to daily, overridden by ScreenDock
  });

  @override
  State<WeatherForecastWidget> createState() => _WeatherForecastWidgetState();
}

class _WeatherForecastWidgetState extends State<WeatherForecastWidget> {
  late ForecastViewMode _viewMode; 

  @override
  void initState() {
    super.initState();
    // Set the initial mode based on what the parent passes in
    _viewMode = widget.initialViewMode;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dynamic Header
            _viewMode == ForecastViewMode.daily ? _buildDailyHeader() : _buildCurrentWeatherHeader(),
            
            const SizedBox(height: 24),
            
            // Forecast Content area
            if (widget.forecastData.isEmpty || (widget.hourlyData.isEmpty && _viewMode == ForecastViewMode.hourly))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(color: Colors.white54)),
              )
            else
              // Smooth crossfade AND smooth resize when switching between Daily/Hourly/Details
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  // This layout builder prevents the height from "snapping" after the fade completes
                  layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                    return Stack(
                      alignment: Alignment.topCenter,
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        ...previousChildren.map((Widget child) {
                          return Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: child,
                          );
                        }),
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
                  child: Container(
                    key: ValueKey(_viewMode),
                    child: _buildActiveContent(),
                  ),
                ),
              ),
            
            const SizedBox(height: 28),
            
            // Bottom Action Buttons
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentWeatherHeader() {
    final bool isHourly = _viewMode == ForecastViewMode.hourly;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left side: Icon and description
        Row(
          children: [
            Icon(widget.currentIcon, color: widget.currentIconColor, size: 24),
            const SizedBox(width: 10),
            Text(
              "${widget.currentDescription}, ${widget.currentTemp}",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
        
        // Right side: Hourly/Details Pill toggle (Across from the temp, above precipitation)
        GestureDetector(
          onTap: () => setState(() => _viewMode = isHourly ? ForecastViewMode.details : ForecastViewMode.hourly),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withOpacity(0.4), 
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isHourly ? CupertinoIcons.info_circle_fill : CupertinoIcons.clock_fill, 
                  size: 12, 
                  color: Colors.white
                ),
                const SizedBox(width: 4),
                Text(
                  isHourly ? "Details" : "Hourly",
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyHeader() {
    return const Text(
      "5-Day Forecast",
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );
  }

  Widget _buildActiveContent() {
    switch (_viewMode) {
      case ForecastViewMode.daily:
        return _buildDailyContent();
      case ForecastViewMode.hourly:
        return _buildHourlyContent();
      case ForecastViewMode.details:
        return _buildDetailsContent();
    }
  }

  Widget _buildHourlyContent() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: widget.hourlyData.map((data) {
        return Column(
          children: [
            Text(
              data.time,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Icon(data.icon, color: data.iconColor, size: 28),
            const SizedBox(height: 12),
            Text(
              data.temp,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildDailyContent() {
    return Column(
      children: widget.forecastData.asMap().entries.map((entry) {
        final index = entry.key;
        final data = entry.value;
        return Column(
          children: [
            _buildForecastRow(data.day, data.icon, data.iconColor, data.temp, data.description),
            if (index < widget.forecastData.length - 1)
              const SizedBox(height: 16),
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
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildForecastRow(String day, IconData icon, Color iconColor, String temp, String desc) {
    return Row(
      children: [
        // Day of the week
        SizedBox(
          width: 45,
          child: Text(
            day,
            style: const TextStyle(
              fontSize: 16, 
              fontWeight: FontWeight.w500, 
              color: Colors.white,
            ),
          ),
        ),
        
        // Weather Icon
        Icon(icon, color: iconColor, size: 26),
        const SizedBox(width: 16),
        
        // Temperature High/Low
        Text(
          temp,
          style: const TextStyle(
            fontSize: 16, 
            fontWeight: FontWeight.w500, 
            color: Colors.white,
          ),
        ),
        
        // Weather Description (Pushed to the right)
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              desc,
              style: const TextStyle(
                fontSize: 15, 
                fontWeight: FontWeight.w400, 
                color: Colors.white70,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    // Both 'details' and 'hourly' fall under the "Today's Weather" category conceptually
    final bool isToday = _viewMode == ForecastViewMode.details || _viewMode == ForecastViewMode.hourly;
    final bool isDaily = _viewMode == ForecastViewMode.daily;

    return Row(
      children: [
        // Primary Button (Left) - Today's Weather
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _viewMode = ForecastViewMode.details),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: isToday ? Colors.white.withOpacity(0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: Colors.white.withOpacity(0.4), 
                  width: 1.2,
                ),
              ),
              alignment: Alignment.center,
              child: const Text(
                "Today's Weather",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Secondary Button (Right) - 5-Day Forecast
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _viewMode = ForecastViewMode.daily),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: isDaily ? Colors.white.withOpacity(0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: Colors.white.withOpacity(0.4), 
                  width: 1.2,
                ),
              ),
              alignment: Alignment.center,
              child: const Text(
                "5-Day Forecast",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}