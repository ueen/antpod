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

  /// The sheet, opened over an 800×600 screen (the test default).
  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(
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

  testWidgets('the switches write their settings', (tester) async {
    await openSheet(tester);
    expect(settings.markPlayedNearEnd, isTrue);
    expect(settings.deletePlayedDownloads, isTrue);

    await tester.tap(find.text('Played in the last minute'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete played downloads'));
    await tester.pumpAndSettle();

    expect(settings.markPlayedNearEnd, isFalse);
    expect(settings.deletePlayedDownloads, isFalse);
    expect(prefs.getBool(AppSettings.keyMarkPlayedNearEnd), isFalse);
    expect(prefs.getBool(AppSettings.keyDeletePlayedDownloads), isFalse);
  });

  testWidgets('import & export come last; Android-only tiles stay hidden here',
      (tester) async {
    await openSheet(tester);
    await tester.drag(find.text('Settings'), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Import subscriptions (OPML)'), 100,
        scrollable: find.byType(Scrollable).last);

    final order = [
      'Playback', 'Downloads', 'Import & export', 'Export backup',
      'Import backup', 'Export subscriptions (OPML)', 'Import subscriptions (OPML)',
    ].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
    expect(order, orderedEquals([...order]..sort()));

    // The test host isn't Android: no wallpaper colours, no Files app.
    expect(find.text('Material You'), findsNothing);
    expect(find.text('Downloads folder'), findsNothing);
  });
}
