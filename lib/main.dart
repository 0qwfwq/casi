import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'design_system.dart';
import 'screens/home_info_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge: transparent status bar AND navigation bar (section 13.2)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Enable edge-to-edge rendering
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Build the Inter-based text theme (section 3)
    final textTheme = GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme,
    );

    return MaterialApp(
      title: 'CASI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        // Section 13.1: Force dark mode, use CASI background
        scaffoldBackgroundColor: CASIColors.bgPrimary,
        colorScheme: const ColorScheme.dark(
          primary: CASIColors.accentPrimary,
          secondary: CASIColors.accentSecondary,
          tertiary: CASIColors.accentTertiary,
          surface: CASIColors.bgPrimary,
          error: CASIColors.error,
          onPrimary: CASIColors.textPrimary,
          onSecondary: CASIColors.textPrimary,
          onSurface: CASIColors.textPrimary,
          onError: CASIColors.textPrimary,
        ),
        textTheme: textTheme,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
