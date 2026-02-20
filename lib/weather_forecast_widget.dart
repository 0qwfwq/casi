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
  ForecastViewMode _viewMode = ForecastViewMode.daily; 

  @override
  Widget build(BuildContext context) {
    // We removed the glass and sizing containers from here! 
    // The ScreenDock now provides a single seamless glass container that wraps this.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dynamic Header
            _viewMode == ForecastViewMode.daily ? _buildDailyHeader() : _buildHourlyHeader(),
            
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

  Widget _buildHourlyHeader() {
    return Row(
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
    String leftText;
    ForecastViewMode leftMode;
    String rightTitle;
    String rightSubtitle;
    ForecastViewMode rightMode;

    if (_viewMode == ForecastViewMode.daily) {
      leftText = "Show Hourly\nWeather";
      leftMode = ForecastViewMode.hourly;
      rightTitle = "More Details";
      rightSubtitle = "View Full Breakdown";
      rightMode = ForecastViewMode.details;
    } else if (_viewMode == ForecastViewMode.hourly) {
      leftText = "Show Daily\nWeather";
      leftMode = ForecastViewMode.daily;
      rightTitle = "More Details";
      rightSubtitle = "View Full Breakdown";
      rightMode = ForecastViewMode.details;
    } else {
      leftText = "Show Daily\nWeather";
      leftMode = ForecastViewMode.daily;
      rightTitle = "View Hourly";
      rightSubtitle = "";
      rightMode = ForecastViewMode.hourly;
    }

    return Row(
      children: [
        // Primary Button (Left) - Glass filled
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _viewMode = leftMode),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2), // Matches glass theme nicely
                borderRadius: BorderRadius.circular(25),
              ),
              alignment: Alignment.center,
              child: Text(
                leftText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
        
        const SizedBox(width: 8),
        
        // Secondary Transparent Outline Button (Right)
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _viewMode = rightMode),
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: Colors.white.withOpacity(0.4), 
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (rightSubtitle.isNotEmpty) _buildSparkleIcon(),
                  if (rightSubtitle.isNotEmpty) const SizedBox(width: 8),
                  
                  if (rightSubtitle.isNotEmpty)
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rightTitle,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          rightSubtitle,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      rightTitle,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  
                  if (rightSubtitle.isEmpty) const SizedBox(width: 8),
                  if (rightSubtitle.isEmpty) _buildSparkleIcon(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSparkleIcon() {
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        children: [
          Positioned(
            top: 1,
            left: 0,
            child: Icon(CupertinoIcons.sun_max_fill, color: Colors.amber.shade300, size: 16),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Icon(CupertinoIcons.moon_stars_fill, color: Colors.indigo.shade200, size: 14),
          ),
        ],
      ),
    );
  }
}