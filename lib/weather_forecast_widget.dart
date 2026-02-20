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

class WeatherForecastWidget extends StatefulWidget {
  final List<DailyForecastData> forecastData;
  final List<HourlyForecastData> hourlyData;
  final String currentTemp;
  final String currentDescription;
  final IconData currentIcon;
  final Color currentIconColor;

  const WeatherForecastWidget({
    super.key, 
    this.forecastData = const [],
    this.hourlyData = const [],
    this.currentTemp = "--°C",
    this.currentDescription = "Unknown",
    this.currentIcon = CupertinoIcons.question,
    this.currentIconColor = Colors.white,
  });

  @override
  State<WeatherForecastWidget> createState() => _WeatherForecastWidgetState();
}

class _WeatherForecastWidgetState extends State<WeatherForecastWidget> {
  // Toggle state: true = shows horizontal hourly data, false = shows vertical 5-day data
  bool _showHourly = false; 

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(36),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.35), // Light frosty background
              borderRadius: BorderRadius.circular(36),
              border: Border.all(
                color: Colors.white.withOpacity(0.5),
                width: 1.5,
              ),
            ),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dynamic Header
                  _showHourly ? _buildHourlyHeader() : _buildDailyHeader(),
                  
                  const SizedBox(height: 24),
                  
                  // Forecast Content area
                  if (widget.forecastData.isEmpty || (widget.hourlyData.isEmpty && _showHourly))
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator(color: Colors.black54)),
                    )
                  else
                    _showHourly ? _buildHourlyContent() : _buildDailyContent(),
                  
                  const SizedBox(height: 28),
                  
                  // Bottom Action Buttons
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
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
            fontWeight: FontWeight.w700,
            color: Colors.black87,
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
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
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
                fontWeight: FontWeight.w600,
                color: Colors.black87,
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
                color: Colors.black87,
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
              color: Colors.black87,
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
            color: Colors.black87,
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
                fontWeight: FontWeight.w500, 
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        // Button 1: Toggle Hourly / Daily
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _showHourly = !_showHourly;
              });
            },
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(27),
              ),
              alignment: Alignment.center,
              child: Text(
                _showHourly ? "Show 5-Day\nForecast" : "Show Hourly\nWeather",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
        
        const SizedBox(width: 8),
        
        // Button 2: View More Details (matches the image reference styling)
        Expanded(
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(27),
              border: Border.all(
                color: Colors.white.withOpacity(0.6), 
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Custom layered Sun/Moon Sparkle Icon
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 1,
                        left: 0,
                        child: Icon(CupertinoIcons.sun_max_fill, color: Colors.amber.shade400, size: 16),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Icon(CupertinoIcons.moon_stars_fill, color: Colors.indigo.shade400, size: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "More Details",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      "View Full Breakdown",
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}