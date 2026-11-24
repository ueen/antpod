import 'package:app_links/app_links.dart';
import 'package:audio_service/audio_service.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_database.dart';
import 'audio_handler.dart';
import 'download_provider.dart';
import 'download_service.dart';
import 'home_screen.dart';
import 'l10n/app_localizations.dart';
import 'player_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fire all slow one-time inits in parallel — AudioService.init alone can
  // take 1–2 s on first launch (spawns a background isolate).
  // The launch link is read up front so HomeScreen opens straight into it.
  final linkFuture = AppLinks()
      .getInitialLink()
      .then<Uri?>((uri) => uri, onError: (_) => null);
  final spFuture = SharedPreferences.getInstance();
  final dlFuture = DownloadService.init();
  final audioFuture = AudioService.init(
    builder: () => AntPodAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'de.ueen.antpod.channel.audio',
      androidNotificationChannelName: 'AntPod Audio',
      androidNotificationChannelDescription: 'Podcast playback controls',
      androidNotificationIcon: 'drawable/ic_notification',
      androidNotificationOngoing: true,
    ),
  );
  await spFuture;
  await dlFuture;
  audioHandler = await audioFuture;
  final initialLink = await linkFuture;

  final db = AppDatabase();
  runApp(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider(create: (_) => PlayerProvider(db)),
        ChangeNotifierProvider(create: (_) => DownloadProvider(db)),
      ],
      child: AntPodApp(initialLink: initialLink),
    ),
  );
}

class AntPodApp extends StatelessWidget {
  final Uri? initialLink;
  const AntPodApp({super.key, this.initialLink});

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
          home: HomeScreen(initialLink: initialLink),
        );
      },
    );
  }
}
