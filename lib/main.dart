import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/diagnostics/app_log.dart';
import 'core/audio/noise_reduction.dart';
import 'core/ffi/native_core_ffi.dart';
import 'core/platform/native_debug_log_channel.dart';
import 'core/preferences/debug_log_settings_store.dart';
import 'ui/pages/session_stage.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final debugLoggingEnabled = await DebugLogSettingsStore().load();
  AppLog.setEnabled(debugLoggingEnabled);
  NativeDebugLogChannel.start();
  _installGlobalErrorLogging();
  NativeCoreFfi.initialize();
  await NoiseReductionSettings.load();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const DawnMeshApp());
}

void _installGlobalErrorLogging() {
  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    AppLog.error('DawnFlutter', details.exceptionAsString(), details.stack);
    previousFlutterHandler?.call(details);
  };

  final previousPlatformHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.error('DawnRuntime', '$error', stack);
    return previousPlatformHandler?.call(error, stack) ?? false;
  };
}

/// Root Application Widget for DawnMesh.
class DawnMeshApp extends StatefulWidget {
  const DawnMeshApp({super.key});

  @override
  State<DawnMeshApp> createState() => _DawnMeshAppState();
}

class _DawnMeshAppState extends State<DawnMeshApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _toggleTheme() {
    setState(() {
      if (_themeMode == ThemeMode.light) {
        _themeMode = ThemeMode.dark;
      } else if (_themeMode == ThemeMode.dark) {
        _themeMode = ThemeMode.light;
      } else {
        // From system to dark
        _themeMode = ThemeMode.dark;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '曙光之声',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) {
          final isNight =
              _themeMode == ThemeMode.dark ||
              (_themeMode == ThemeMode.system &&
                  MediaQuery.of(context).platformBrightness == Brightness.dark);
          return SessionStage(isNight: isNight, onToggleTheme: _toggleTheme);
        },
      ),
    );
  }
}
