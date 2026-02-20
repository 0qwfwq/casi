import 'dart:ui';
import 'package:flutter/material.dart';

class WeatherForecastWidget extends StatelessWidget {
  const WeatherForecastWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.35), // Light frosty background
            borderRadius: BorderRadius.circular(32),
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
                _buildForecastRow("Fri", Icons.wb_cloudy, Colors.white, "4°/0°", "Partly Cloudy"),
                const SizedBox(height: 14),
                _buildForecastRow("Sat", Icons.ac_unit, Colors.white, "1°/-2°", "Snow Flurries"),
                const SizedBox(height: 14),
                _buildForecastRow("Sun", Icons.wb_sunny, Colors.amber, "3°/-1°", "Sunny", hasDividerBelow: true),
                const SizedBox(height: 14),
                _buildForecastRow("Mon", Icons.cloud, Colors.white, "5°/1°", "Cloudy", hasDividerBelow: true),
                const SizedBox(height: 14),
                _buildForecastRow("Tue", Icons.cloudy_snowing, Colors.white, "2°/-1°", "Rain/Snow"),
                
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

  Widget _buildForecastRow(String day, IconData icon, Color iconColor, String temp, String desc, {bool hasDividerBelow = false}) {
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
        
        // Optional Divider
        if (hasDividerBelow) ...[
          const SizedBox(height: 14),
          const Divider(color: Colors.black12, height: 1, thickness: 1),
        ],
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