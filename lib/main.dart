import 'package:app_links/app_links.dart';
import 'package:audio_service/audio_service.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_binding.dart';
import 'app_database.dart';
import 'app_settings.dart';
import 'audio_handler.dart';
import 'download_provider.dart';
import 'download_service.dart';
import 'home_screen.dart';
import 'l10n/app_localizations.dart';
import 'player_provider.dart';

Future<void> main() async {
  AppBinding(); // before anything asks for a binding

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
  final prefs = await spFuture;
  await dlFuture;
  audioHandler = await audioFuture;
  final initialLink = await linkFuture;

  final db = AppDatabase();
  final settings = AppSettings(prefs);
  runApp(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(create: (_) => PlayerProvider(db, settings)),
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

  /// AntPod's own colors: Material's scheme from the seed, its near-blacks
  /// turned reddish brown, and one highlight, a mellow orange (HCT hue 60,
  /// chroma 44): the mini player's elements (inversePrimary), and as
  /// tertiary the favorite heart, the current episode's ring, the seek bar
  /// and the swipe to played. With Material You the wallpaper's take over.
  static ColorScheme _antScheme(Brightness brightness) {
    final s = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    if (brightness == Brightness.light) {
      return s.copyWith(
        onSurface: const Color(0xFF451806), // titles, wordmark
        inverseSurface: const Color(0xFF582614), // mini player
        inversePrimary: const Color(0xFFFAA65A), // tone 75 on it
        tertiary: const Color(0xFFAC661F), // tone 50, 4:1 on the sheets
        // Tone 85: a step deeper than the peach of the swipe to unplayed.
        tertiaryContainer: const Color(0xFFFFCA9F),
        onTertiaryContainer: const Color(0xFF6C3A00),
      );
    }
    // The same hue at chroma 10 for the dark backgrounds.
    return s.copyWith(
      surface: const Color(0xFF1E100B),
      surfaceDim: const Color(0xFF1E100B),
      surfaceBright: const Color(0xFF47352F),
      surfaceContainerLowest: const Color(0xFF180B07),
      surfaceContainerLow: const Color(0xFF271813),
      surfaceContainer: const Color(0xFF2B1C17),
      surfaceContainerHigh: const Color(0xFF362621),
      surfaceContainerHighest: const Color(0xFF42312B),
      // The mini player as in light mode: on cream the bright orange would
      // fade (1.5:1), on the brown it's 6.3:1, and the card still stands out
      // from the page. Snackbars share the background, hence their text.
      inverseSurface: const Color(0xFF582614),
      onInverseSurface: const Color(0xFFFEEEE4),
      inversePrimary: const Color(0xFFFAA65A),
      tertiary: const Color(0xFFFAA65A),
      tertiaryContainer: const Color(0xFF6C3A00), // tone 30
      onTertiaryContainer: const Color(0xFFFFDCC1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final materialYou = context.select<AppSettings, bool>((s) => s.materialYou);
    final themeMode = context.select<AppSettings, ThemeMode>((s) => s.themeMode);
    final language = context.select<AppSettings, String?>((s) => s.language);
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // Material You: the wallpaper's colors where the system has them
        // (Android 12+), otherwise AntPod's brown.
        final lightScheme = (materialYou ? lightDynamic : null) ??
            _antScheme(Brightness.light);
        final darkScheme = (materialYou ? darkDynamic : null) ??
            _antScheme(Brightness.dark);

        return MaterialApp(
          title: 'AntPod',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
          darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
          themeMode: themeMode,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          // The language picked in the settings; none (or one this version
          // doesn't have, from a newer backup) follows the phone, as it
          // changes, in English if the app hasn't the phone's.
          locale: AppLocalizations.supportedLocales
              .where((l) => l.languageCode == language).firstOrNull,
          localeListResolutionCallback: (phone, _) =>
              appLocale(null, phone ?? const []),
          home: HomeScreen(initialLink: initialLink),
        );
      },
    );
  }
}
