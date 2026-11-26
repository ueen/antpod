import 'package:antpod/feed_state.dart';
import 'package:antpod/home_toolbar.dart';
import 'package:antpod/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int logoTaps, infoTaps;

  Future<void> pumpToolbar(WidgetTester tester) async {
    logoTaps = 0;
    infoTaps = 0;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: HomeToolbar(
              inPodcast: false, discoverSearch: false, episodeSearch: false,
              searchOpen: false, searchCtrl: TextEditingController(),
              filter: const FilterState(), filterChipsVisible: false,
              l10n: AppLocalizations.of(context)!,
              cs: Theme.of(context).colorScheme,
              onBack: () {}, onSearchChanged: (_) {}, onClearSearch: () {},
              onSearchOpen: () {}, onPlusPressed: () {}, onFilterToggle: () {},
              onLogoTap: () => logoTaps++,
              onInfoPressed: () => infoTaps++,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the logo and wordmark take taps across the full bar height',
      (tester) async {
    await pumpToolbar(tester);
    final brand = tester.getRect(find.byKey(const ValueKey('brand-tap')));
    // The bar is 56 high, less its 0.5 px bottom border.
    expect(brand.height, closeTo(56, 0.5));

    final word = tester.getRect(find.text('AntPod'));
    final spots = [
      Offset(brand.left + 2, brand.center.dy),  // the margin left of the logo
      Offset(word.left - 4, brand.center.dy),   // the gap between logo and wordmark
      Offset(word.center.dx, brand.top + 2),    // above the wordmark
      Offset(brand.left + 24, brand.bottom - 2), // below the logo
    ];
    for (final spot in spots) {
      await tester.tapAt(spot);
      await tester.pumpAndSettle();
    }
    expect(logoTaps, spots.length);
    expect(infoTaps, 0);
  });

  testWidgets('the guide icon next to the wordmark keeps its own taps',
      (tester) async {
    await pumpToolbar(tester);
    await tester.tap(find.byIcon(Icons.info_rounded));
    await tester.pumpAndSettle();
    expect(infoTaps, 1);
    expect(logoTaps, 0);
  });
}
