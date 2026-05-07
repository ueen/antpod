import 'package:audio_service/audio_service.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_database.dart';
import 'audio_handler.dart';
import 'download_provider.dart';
import 'download_service.dart';
import 'home_screen.dart';
import 'l10n/app_localizations.dart';
import 'player_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DownloadService.init();
  DownloadService.registerCallback();

  audioHandler = await AudioService.init(
    builder: () => AntPodAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'de.ueen.antpod.channel.audio',
      androidNotificationChannelName: 'AntPod Audio',
      androidNotificationOngoing: true,
    ),
  );

  final db = AppDatabase();
  runApp(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider(create: (_) => PlayerProvider(db)),
        ChangeNotifierProvider(create: (_) => DownloadProvider(db)),
      ],
      child: const AntPodApp(),
    ),
  );
}

class AntPodApp extends StatelessWidget {
  const AntPodApp({super.key});

  static const _seed = Color(0xFF8B5E3C);

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final lightScheme =
            lightDynamic ?? ColorScheme.fromSeed(seedColor: _seed);
        final darkScheme = darkDynamic ??
            ColorScheme.fromSeed(
                seedColor: _seed, brightness: Brightness.dark);

        return MaterialApp(
          title: 'AntPod',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
          darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
          themeMode: ThemeMode.system,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        );
      },
    );
  }
}
