import 'package:antpod/app_settings.dart';
import 'package:antpod/l10n/app_localizations.dart';
import 'package:antpod/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    settings = AppSettings(prefs);
  });

  /// A screen tall enough that the sheet shows every tile at once.
  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// The sheet, opened over an 800×600 screen (the test default).
  Future<void> openSheet(WidgetTester tester, {Locale? locale}) async {
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showSettingsSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  double sheetHeight(WidgetTester tester) =>
      tester.getSize(find.byType(ListView)).height;

  testWidgets('opens part way up and extends to full height when scrolled',
      (tester) async {
    await openSheet(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(sheetHeight(tester), closeTo(600 * 0.6, 1));

    await tester.drag(find.text('Settings'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(sheetHeight(tester), closeTo(600, 1));
  });

  testWidgets('the theme segments write the theme', (tester) async {
    await openSheet(tester);
    expect(settings.themeMode, ThemeMode.system);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);
    expect(prefs.getString(AppSettings.keyTheme), 'dark');

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(AppSettings(prefs).themeMode, ThemeMode.light);
  });

  testWidgets('the theme row fits a narrow phone in every language',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final locale in AppLocalizations.supportedLocales) {
      await openSheet(tester, locale: locale);
      expect(tester.takeException(), isNull, reason: '$locale');
      Navigator.of(tester.element(find.byType(ListView))).pop();
      await tester.pumpAndSettle();
    }
  });

  test('a resume rewinds only after a long pause, and only when on', () {
    expect(settings.rewindOnResume, isTrue);
    expect(settings.resumeRewind(const Duration(minutes: 4)), Duration.zero);
    expect(settings.resumeRewind(const Duration(minutes: 5)),
        AppSettings.resumeRewindBy);
    settings.rewindOnResume = false;
    expect(settings.resumeRewind(const Duration(days: 1)), Duration.zero);
  });

  testWidgets('the switches write their settings', (tester) async {
    tallScreen(tester);
    await openSheet(tester);
    expect(settings.rewindOnResume, isTrue);
    expect(settings.markPlayedNearEnd, isTrue);
    expect(settings.deletePlayedDownloads, isTrue);
    expect(settings.appleApi, isTrue);

    await tester.tap(find.text('Rewind on resume'));
    await tester.pumpAndSettle();
    expect(settings.rewindOnResume, isFalse);
    expect(prefs.getBool(AppSettings.keyRewindOnResume), isFalse);

    await tester.tap(find.text('Played near the end'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete played downloads'));
    await tester.pumpAndSettle();

    expect(settings.markPlayedNearEnd, isFalse);
    expect(settings.deletePlayedDownloads, isFalse);
    expect(prefs.getBool(AppSettings.keyMarkPlayedNearEnd), isFalse);
    expect(prefs.getBool(AppSettings.keyDeletePlayedDownloads), isFalse);

    await tester.tap(find.text('Apple Podcasts'));
    await tester.pumpAndSettle();
    expect(settings.appleApi, isFalse);
    expect(prefs.getBool(AppSettings.keyAppleApi), isFalse);
  });

  testWidgets('import & export come last; Android-only tiles stay hidden here',
      (tester) async {
    tallScreen(tester);
    await openSheet(tester);

    final order = [
      'Appearance', 'Theme', 'Playback', 'Rewind on resume', 'Played near the end',
      'Downloads', 'Delete played downloads', 'Privacy', 'Apple Podcasts',
      'Import & export', 'Export backup',
      'Import backup', 'Export subscriptions (OPML)', 'Import subscriptions (OPML)',
    ].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
    expect(order, orderedEquals([...order]..sort()));

    // The test host isn't Android: no wallpaper colours, no Files app.
    expect(find.text('Material You'), findsNothing);
    expect(find.text('Downloads folder'), findsNothing);
  });
}
