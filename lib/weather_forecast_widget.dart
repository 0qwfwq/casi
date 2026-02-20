import 'dart:ui';
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

class WeatherForecastWidget extends StatelessWidget {
  final List<DailyForecastData> forecastData;

  const WeatherForecastWidget({super.key, this.forecastData = const []});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(36),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.35), // Light frosty background
            borderRadius: BorderRadius.circular(36),
            border: Border.all(
              color: Colors.white.withOpacity(0.5),
              width: 1.5,
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                const Text(
                  "5-Day Forecast",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Forecast Rows
                if (forecastData.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  ...forecastData.asMap().entries.map((entry) {
                    final index = entry.key;
                    final data = entry.value;
                    return Column(
                      children: [
                        _buildForecastRow(data.day, data.icon, data.iconColor, data.temp, data.description),
                        if (index < forecastData.length - 1)
                          const SizedBox(height: 14),
                      ],
                    );
                  }),
                
                const SizedBox(height: 28),
                
                // Bottom Action Buttons
                _buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForecastRow(String day, IconData icon, Color iconColor, String temp, String desc) {
    return Column(
      children: [
        Row(
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
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        // Button 1: Show Hourly Weather
        Expanded(
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(27),
            ),
            alignment: Alignment.center,
            child: const Text(
              "Show Hourly\nWeather",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
                height: 1.2,
              ),
            ),
          ),
        ),
        
        const SizedBox(width: 8),
        
        // Button 2: View More Details
        Expanded(
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(27),
              border: Border.all(
                color: Colors.white.withOpacity(0.6), 
                width: 1.2,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Center(
                  child: Text(
                    "View More Details",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}