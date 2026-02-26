import 'dart:async'; 
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:casi/widgets/weather_forecast_widget.dart';

class ScreenDock extends StatefulWidget {
  final bool isDragging;
  final bool isAlarmMode; 
  final bool isAlarmRinging; 
  final bool isViewingAlarms; 
  final bool hasSelectedAlarm; 
  final String? initialAmPm; // Added to support Edit mode auto-setting
  final String? initialDay; // Added to support Edit mode auto-setting
  final void Function(AppInfo)? onRemove;
  final void Function(AppInfo)? onUninstall;
  final VoidCallback? onSnooze;
  final VoidCallback? onCancel;
  final VoidCallback? onEditAlarm;
  final VoidCallback? onDeleteAlarm;
  final ValueChanged<String>? onAmPmChanged;
  final ValueChanged<String>? onDayChanged; // Track day changes
  
  final Widget? activePill;

  const ScreenDock({
    super.key,
    this.isDragging = false,
    this.isAlarmMode = false,
    this.isAlarmRinging = false,
    this.isViewingAlarms = false,
    this.hasSelectedAlarm = false,
    this.initialAmPm,
    this.initialDay,
    this.onRemove,
    this.onUninstall,
    this.onSnooze,
    this.onCancel,
    this.onEditAlarm,
    this.onDeleteAlarm,
    this.onAmPmChanged,
    this.onDayChanged,
    this.activePill,
  });

  @override
  State<ScreenDock> createState() => _ScreenDockState();
}

class _ScreenDockState extends State<ScreenDock> with WidgetsBindingObserver {
  // Weather State
  int? _temperature;
  int? _weatherCode;
  
  // Data lists for the widget
  List<DailyForecastData> _forecastData = [];
  List<HourlyForecastData> _hourlyData = [];
  
  // Current Weather Info passed to Widget
  String _currentDescription = "Unknown";
  IconData _currentIcon = CupertinoIcons.question;
  Color _currentIconColor = Colors.white;

  // Detailed Data passed to Widget
  String _feelsLike = "--°C";
  String _wind = "-- mph";
  String _precipitation = "--%";
  String _humidity = "--%";
  String _uvIndex = "--";
  String _sunrise = "--:-- AM";

  bool _isLoadingWeather = false;
  bool _showForecast = false;
  
  Timer? _hourlySyncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWeather();
    _scheduleTopOfHourWeatherSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hourlySyncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndFetchWeather();
    }
  }

  @override
  void didUpdateWidget(covariant ScreenDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Force weather widget to close if alarm mode opens
    if (widget.isAlarmMode && _showForecast) {
      setState(() => _showForecast = false);
    }
  }

  // --- Weather Logic ---
  Future<void> _initWeather() async {
    final prefs = await SharedPreferences.getInstance();
    
    final String? cachedWeatherJson = prefs.getString('weather_json_cache');
    if (cachedWeatherJson != null) {
      try {
        final data = jsonDecode(cachedWeatherJson);
        _parseWeatherData(data);
      } catch (e) {
        debugPrint("Cache parse error: $e");
      }
    } else {
      if (mounted) {
        setState(() {
          _temperature = prefs.getInt('last_temperature');
          _weatherCode = prefs.getInt('last_weather_code');
          _currentDescription = _getWeatherDescription(_weatherCode);
          _currentIcon = _getWeatherIcon(_weatherCode, true);
          _currentIconColor = _getWeatherIconColor(_weatherCode, true);
        });
      }
    }

    _checkAndFetchWeather();
  }

  void _scheduleTopOfHourWeatherSync() {
    final now = DateTime.now();
    DateTime nextHour = DateTime(now.year, now.month, now.day, now.hour + 1, 0, 2);
    Duration durationUntilNextHour = nextHour.difference(now);
    
    _hourlySyncTimer?.cancel();
    _hourlySyncTimer = Timer(durationUntilNextHour, () {
      _fetchWeather();
      _scheduleTopOfHourWeatherSync(); 
    });
  }

  Future<void> _checkAndFetchWeather() async {
    final prefs = await SharedPreferences.getInstance();
    final lastFetchMs = prefs.getInt('last_fetch_time_ms') ?? 0;
    final lastFetch = DateTime.fromMillisecondsSinceEpoch(lastFetchMs);
    final now = DateTime.now();
    
    bool crossedHour = now.hour != lastFetch.hour || now.day != lastFetch.day || now.month != lastFetch.month || now.year != lastFetch.year;
    
    if (now.difference(lastFetch).inMinutes > 30 || _temperature == null || crossedHour) {
      _fetchWeather();
    }
    
    _scheduleTopOfHourWeatherSync();
  }

  void _parseWeatherData(Map<String, dynamic> data) {
    final current = data['current'];
    final temp = (current['temperature_2m'] as num).round();
    final code = (current['weathercode'] as num).toInt();
    final currentIsDay = (current['is_day'] as num).toInt() == 1;
    
    final String currentDesc = _getWeatherDescription(code);
    final IconData curIcon = _getWeatherIcon(code, currentIsDay);
    final Color curIconColor = _getWeatherIconColor(code, currentIsDay);

    final feelsLikeNum = (current['apparent_temperature'] as num).round();
    final humidityNum = (current['relative_humidity_2m'] as num).round();
    final windSpeedNum = (current['wind_speed_10m'] as num).round();
    final windDirDegrees = (current['wind_direction_10m'] as num).toInt();
    final String windDir = _getWindDirection(windDirDegrees);
    
    final double uvIndexRaw = (data['daily']['uv_index_max'][0] as num).toDouble();
    final String uvIndexStr = "${uvIndexRaw.round()} (${_getUvDescription(uvIndexRaw)})";
    
    final String sunriseIso = data['daily']['sunrise'][0] as String;
    final String sunriseTime = _formatTime(sunriseIso);

    List<DailyForecastData> dailyList = [];
    if (data['daily'] != null) {
      final daily = data['daily'];
      final times = daily['time'] as List;
      final codes = daily['weathercode'] as List;
      final maxs = daily['temperature_2m_max'] as List;
      final mins = daily['temperature_2m_min'] as List;

      for (int i = 0; i < times.length && i < 5; i++) {
        DateTime date = DateTime.parse(times[i]);
        int dCode = (codes[i] as num).toInt();
        int dMax = (maxs[i] as num).round();
        int dMin = (mins[i] as num).round();

        dailyList.add(DailyForecastData(
          day: _getDayName(date.weekday),
          icon: _getWeatherIcon(dCode, true), 
          iconColor: _getWeatherIconColor(dCode, true),
          temp: "$dMax°/$dMin°",
          description: _getWeatherDescription(dCode),
        ));
      }
    }

    List<HourlyForecastData> hourlyList = [];
    int precipProbNum = 0;

    if (data['hourly'] != null) {
      final hourly = data['hourly'];
      final times = hourly['time'] as List;
      final codes = hourly['weathercode'] as List;
      final temps = hourly['temperature_2m'] as List;
      final isDays = hourly['is_day'] as List;
      final precipProbs = hourly['precipitation_probability'] as List;

      DateTime now = DateTime.now();
      int currentIndex = 0;
      for (int i = 0; i < times.length; i++) {
        DateTime t = DateTime.parse(times[i]);
        if (t.isAfter(now) || (t.hour == now.hour && t.day == now.day)) {
          currentIndex = i;
          break;
        }
      }

      precipProbNum = (precipProbs[currentIndex] as num).round();

      for (int i = currentIndex; i < currentIndex + 6 && i < times.length; i++) {
        DateTime t = DateTime.parse(times[i]);
        int hCode = (codes[i] as num).toInt();
        int hTemp = (temps[i] as num).round();
        bool hIsDay = (isDays[i] as num).toInt() == 1;

        hourlyList.add(HourlyForecastData(
          time: _getFormattedHour(t),
          icon: _getWeatherIcon(hCode, hIsDay),
          iconColor: _getWeatherIconColor(hCode, hIsDay),
          temp: "$hTemp°C",
        ));
      }
    }

    if (mounted) {
      setState(() {
        _temperature = temp;
        _weatherCode = code;
        _currentDescription = currentDesc;
        _currentIcon = curIcon;
        _currentIconColor = curIconColor;
        
        _feelsLike = "$feelsLikeNum°C";
        _humidity = "$humidityNum%";
        _wind = "$windSpeedNum mph $windDir";
        _precipitation = "$precipProbNum%";
        _uvIndex = uvIndexStr;
        _sunrise = sunriseTime;

        _forecastData = dailyList;
        _hourlyData = hourlyList;
      });
    }
  }

  Future<void> _fetchWeather() async {
    if (_isLoadingWeather) return;
    if (mounted) setState(() => _isLoadingWeather = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {}
      
      position ??= await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);

      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=${position.latitude}&longitude=${position.longitude}'
          '&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weathercode,wind_speed_10m,wind_direction_10m'
          '&hourly=temperature_2m,weathercode,is_day,precipitation_probability'
          '&daily=weathercode,temperature_2m_max,temperature_2m_min,sunrise,uv_index_max'
          '&wind_speed_unit=mph&timezone=auto');
      
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('weather_json_cache', response.body);
        await prefs.setInt('last_fetch_time_ms', DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt('last_temperature', (data['current']['temperature_2m'] as num).round());
        await prefs.setInt('last_weather_code', (data['current']['weathercode'] as num).toInt());

        _parseWeatherData(data);
      }
    } catch (e) {
      debugPrint("Error fetching weather: $e");
    } finally {
      if (mounted) setState(() => _isLoadingWeather = false);
    }
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  String _getFormattedHour(DateTime time) {
    int hour = time.hour;
    if (hour == 0) return "12 AM";
    if (hour < 12) return "$hour AM";
    if (hour == 12) return "12 PM";
    return "${hour - 12} PM";
  }

  String _formatTime(String isoTime) {
    DateTime time = DateTime.parse(isoTime);
    int hour = time.hour;
    int minute = time.minute;
    String ampm = hour >= 12 ? "PM" : "AM";
    hour = hour % 12;
    if (hour == 0) hour = 12;
    String minuteStr = minute.toString().padLeft(2, '0');
    return "$hour:$minuteStr $ampm";
  }

  String _getWindDirection(int degrees) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    int index = ((degrees + 22.5) % 360 / 45).floor();
    return directions[index];
  }

  String _getUvDescription(double uv) {
    if (uv < 3) return "Low";
    if (uv < 6) return "Moderate";
    if (uv < 8) return "High";
    if (uv < 11) return "Very High";
    return "Extreme";
  }

  String _getWeatherDescription(int? code) {
    if (code == null) return "Unknown";
    if (code == 0) return "Clear";
    if (code >= 1 && code <= 3) return "Cloudy";
    if (code >= 45 && code <= 48) return "Fog";
    if (code >= 51 && code <= 67) return "Rain";
    if (code >= 71 && code <= 77) return "Snow";
    if (code >= 80 && code <= 82) return "Showers";
    if (code >= 95 && code <= 99) return "Storm";
    return "Clear";
  }

  IconData _getWeatherIcon(int? code, [bool isDay = true]) {
    if (code == null) return CupertinoIcons.question;
    if (code == 0) return isDay ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_stars_fill;
    if (code >= 1 && code <= 3) return isDay ? CupertinoIcons.cloud_sun_fill : CupertinoIcons.cloud_moon_fill;
    if (code >= 45 && code <= 48) return CupertinoIcons.cloud_fog_fill;
    if (code >= 51 && code <= 67) return CupertinoIcons.cloud_rain_fill;
    if (code >= 71 && code <= 77) return CupertinoIcons.snow;
    if (code >= 80 && code <= 82) return CupertinoIcons.cloud_heavyrain_fill;
    if (code >= 95 && code <= 99) return CupertinoIcons.cloud_bolt_fill;
    return isDay ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_stars_fill;
  }

  Color _getWeatherIconColor(int? code, [bool isDay = true]) {
    if (code == 0) return isDay ? Colors.orange.shade300 : Colors.indigo.shade300;
    if (code != null && code >= 1 && code <= 3) return isDay ? Colors.white : Colors.indigo.shade200;
    return Colors.white; 
  }

  void _launchBrowser() {
    launchUrl(Uri.parse('https://google.com'), mode: LaunchMode.externalApplication);
  }

  Future<void> _launchAssistantApp() async {
    final List<String> assistantPackages = [
      'com.google.android.apps.bard',
      'com.google.android.googlequicksearchbox',
      'com.amazon.dee.app',
      'com.samsung.android.bixby.agent',
    ];

    try {
      for (String pkg in assistantPackages) {
        bool? isInstalled = await InstalledApps.isAppInstalled(pkg);
        if (isInstalled == true) {
          InstalledApps.startApp(pkg); 
          return;
        }
      }
    } catch (e) {
      debugPrint("Error launching assistant app: $e");
    }
  }

  // --- Scroller Widgets for Alarm Mode ---
  
  Widget _buildAmPmScroller({Key? key}) {
    final ampm = ['AM', 'PM'];
    final int initialIndex = ampm.indexOf(widget.initialAmPm ?? 'AM');
    
    return ListWheelScrollView.useDelegate(
      key: key,
      controller: FixedExtentScrollController(initialItem: initialIndex != -1 ? initialIndex : 0),
      itemExtent: 26,
      physics: const FixedExtentScrollPhysics(),
      overAndUnderCenterOpacity: 0.3,
      onSelectedItemChanged: (index) => widget.onAmPmChanged?.call(ampm[index]),
      childDelegate: ListWheelChildListDelegate(
        children: ampm.map((e) => Center(
          child: Text(e, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))
        )).toList(),
      ),
    );
  }

  Widget _buildDayScroller({Key? key}) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final int initialIndex = days.indexOf(widget.initialDay ?? 'Mon');
    
    return ListWheelScrollView.useDelegate(
      key: key,
      controller: FixedExtentScrollController(initialItem: initialIndex != -1 ? initialIndex : 0),
      itemExtent: 26,
      physics: const FixedExtentScrollPhysics(),
      overAndUnderCenterOpacity: 0.3,
      // Modulo prevents out-of-bounds error on infinite loop lists
      onSelectedItemChanged: (index) => widget.onDayChanged?.call(days[index % 7]),
      childDelegate: ListWheelChildLoopingListDelegate(
        children: days.map((e) => Center(
          child: Text(e, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))
        )).toList(),
      ),
    );
  }

  // --- UI Build Helpers ---

  Widget _buildWeatherButton({Key? key}) {
    return InkWell(
      key: key,
      onTap: () {
        _checkAndFetchWeather();
        setState(() => _showForecast = true);
      },
      borderRadius: BorderRadius.circular(30),
      child: Center(
        child: Icon(_currentIcon, color: _currentIconColor, size: 24),
      ),
    );
  }

  Widget _buildWebButton({Key? key}) {
    return InkWell(
      key: key,
      onTap: _launchBrowser,
      onLongPress: _launchAssistantApp, 
      borderRadius: BorderRadius.circular(30),
      child: const Center(
        child: Icon(CupertinoIcons.globe, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildRemoveTarget({Key? key}) {
    return DragTarget<AppInfo>(
      key: key,
      onAcceptWithDetails: (details) => widget.onRemove?.call(details.data),
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isHovered ? Colors.red.withOpacity(0.6) : Colors.transparent,
            borderRadius: BorderRadius.circular(32),
          ),
          child: const Center(
            child: Icon(CupertinoIcons.clear_circled, color: Colors.white, size: 24),
          ),
        );
      },
    );
  }

  Widget _buildUninstallTarget({Key? key}) {
    return DragTarget<AppInfo>(
      key: key,
      onAcceptWithDetails: (details) => widget.onUninstall?.call(details.data),
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isHovered ? Colors.orange.withOpacity(0.6) : Colors.transparent,
            borderRadius: BorderRadius.circular(32),
          ),
          child: const Center(
            child: Icon(CupertinoIcons.delete, color: Colors.white, size: 24),
          ),
        );
      },
    );
  }

  Widget _buildSnoozeButton({Key? key}) {
    return InkWell(
      key: key,
      onTap: widget.onSnooze,
      borderRadius: BorderRadius.circular(30),
      child: const Center(
        child: Icon(Icons.snooze, color: Colors.orangeAccent, size: 28),
      ),
    );
  }

  Widget _buildCancelButton({Key? key}) {
    return InkWell(
      key: key,
      onTap: widget.onCancel,
      borderRadius: BorderRadius.circular(30),
      child: const Center(
        child: Icon(Icons.close, color: Colors.redAccent, size: 28),
      ),
    );
  }

  Widget _buildEditAlarmButton({Key? key}) {
    return InkWell(
      key: key,
      onTap: widget.hasSelectedAlarm ? widget.onEditAlarm : null,
      borderRadius: BorderRadius.circular(30),
      child: Center(
        child: Icon(Icons.edit, color: widget.hasSelectedAlarm ? Colors.blueAccent : Colors.white30, size: 28),
      ),
    );
  }

  Widget _buildDeleteAlarmButton({Key? key}) {
    return InkWell(
      key: key,
      onTap: widget.hasSelectedAlarm ? widget.onDeleteAlarm : null,
      borderRadius: BorderRadius.circular(30),
      child: Center(
        child: Icon(Icons.delete, color: widget.hasSelectedAlarm ? Colors.redAccent : Colors.white30, size: 28),
      ),
    );
  }

  Widget _buildRightGlassCircle() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32.0),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(31.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
          child: Container(
            color: Colors.white.withOpacity(0.2),
            child: Material(
              color: Colors.transparent,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: widget.isAlarmRinging
                    ? _buildSnoozeButton(key: const ValueKey('snooze'))
                    : widget.isViewingAlarms
                        ? _buildDeleteAlarmButton(key: const ValueKey('delete_alarm'))
                        : widget.isAlarmMode 
                            ? _buildAmPmScroller(key: const ValueKey('ampm'))
                            : (widget.isDragging ? _buildUninstallTarget(key: const ValueKey('uninstall')) : _buildWebButton(key: const ValueKey('web'))),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeftGlassArea(BuildContext context, double maxWidth) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32.0),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(31.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
          child: Container(
            color: Colors.white.withOpacity(0.2), 
            child: AnimatedSize(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutQuart,
              alignment: Alignment.bottomLeft,
              clipBehavior: Clip.antiAlias, 
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation),
                      alignment: Alignment.bottomLeft,
                      child: child,
                    ),
                  );
                },
                layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                  return Stack(
                    alignment: Alignment.bottomLeft,
                    clipBehavior: Clip.none, 
                    children: <Widget>[
                      ...previousChildren.map((Widget child) {
                        return Positioned(
                          bottom: 0,
                          left: 0,
                          child: child,
                        );
                      }),
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                child: (_showForecast && !widget.isDragging && !widget.isAlarmMode && !widget.isAlarmRinging && !widget.isViewingAlarms)
                    ? TapRegion(
                        key: const ValueKey('forecast_widget'),
                        onTapOutside: (event) {
                          setState(() {
                            _showForecast = false;
                          });
                        },
                        child: SizedBox(
                          width: maxWidth,
                          child: WeatherForecastWidget(
                            initialViewMode: ForecastViewMode.details, 
                            forecastData: _forecastData,
                            hourlyData: _hourlyData,
                            currentTemp: "${_temperature ?? '--'}°C",
                            currentDescription: _currentDescription,
                            currentIcon: _currentIcon,
                            currentIconColor: _currentIconColor,
                            feelsLike: _feelsLike,
                            wind: _wind,
                            precipitation: _precipitation,
                            humidity: _humidity,
                            uvIndex: _uvIndex,
                            sunrise: _sunrise,
                          ),
                        ),
                      )
                    : SizedBox(
                        key: ValueKey('left_circle_${widget.isDragging}_${widget.isAlarmMode}_${widget.isAlarmRinging}_${widget.isViewingAlarms}'),
                        width: 60.0,
                        height: 60.0,
                        child: Material(
                          color: Colors.transparent,
                          child: widget.isAlarmRinging
                              ? _buildCancelButton(key: const ValueKey('cancel'))
                              : widget.isViewingAlarms
                                  ? _buildEditAlarmButton(key: const ValueKey('edit_alarm'))
                                  : widget.isAlarmMode 
                                      ? _buildDayScroller(key: const ValueKey('day'))
                                      : (widget.isDragging ? _buildRemoveTarget(key: const ValueKey('remove')) : _buildWeatherButton(key: const ValueKey('weather'))),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double maxWidth = screenWidth - 80.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(40.0, 0, 40.0, 40.0),
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          alignment: Alignment.bottomLeft,
          clipBehavior: Clip.none,
          children: [
            // Middle Pill - Reordered to render UNDER the side circles during swipe out!
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedOpacity(
                opacity: (_showForecast && !widget.isDragging && !widget.isAlarmMode && !widget.isAlarmRinging && !widget.isViewingAlarms) ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 350),
                child: IgnorePointer(
                  ignoring: (_showForecast && !widget.isDragging && !widget.isAlarmMode && !widget.isAlarmRinging && !widget.isViewingAlarms),
                  child: SizedBox(
                    height: 60,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) {
                          return SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.5),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: animation, 
                              curve: Curves.easeOutQuart
                            )),
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        },
                        child: widget.activePill != null
                            ? KeyedSubtree(
                                key: const ValueKey('active_pill'),
                                child: widget.activePill!,
                              )
                            : const SizedBox.shrink(key: ValueKey('empty_pill')),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Right Circle
            Align(
              alignment: Alignment.bottomRight,
              child: AnimatedOpacity(
                opacity: (_showForecast && !widget.isDragging && !widget.isAlarmMode && !widget.isAlarmRinging && !widget.isViewingAlarms) ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 350), 
                child: IgnorePointer(
                  ignoring: (_showForecast && !widget.isDragging && !widget.isAlarmMode && !widget.isAlarmRinging && !widget.isViewingAlarms),
                  child: _buildRightGlassCircle(),
                ),
              ),
            ),

            // Left Circle
            _buildLeftGlassArea(context, maxWidth),
          ],
        ),
      ),
    );
  }
}