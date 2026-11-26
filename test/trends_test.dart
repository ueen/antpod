import 'dart:async';

import 'package:antpod/discover_list.dart';
import 'package:antpod/l10n/app_localizations.dart';
import 'package:antpod/trends_country.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget app(Widget Function(BuildContext) body) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Builder(builder: body)),
    );

void main() {
  group('country search', () {
    List<String> hits(String q) =>
        trendsCountries.keys.where((c) => trendsCountryMatches(c, q)).toList();

    test('finds a country by its own name, its names in the app languages, or its code', () {
      expect(hits('deutsch'), ['de']);
      expect(hits('Allemagne'), ['de']);
      expect(hits('alemania'), ['de']);
      expect(hits('germany'), ['de']);
      expect(hits('CH'), contains('ch'));
      expect(hits('uk'), ['gb', 'ua']); // Ukraine starts with it too
      expect(hits('united k'), ['gb']);
    });

    test('ignores accents and hyphens, and matches word starts only', () {
      expect(hits('osterr'), ['at']);
      expect(hits('zelande'), ['nz']);
      expect(hits('arab'), unorderedEquals(['ae', 'sa']));
      // "land" ends many names but starts none of these.
      expect(hits('land'), isEmpty);
      expect(hits('xyz'), isEmpty);
      expect(hits('  '), hasLength(trendsCountries.length));
    });

    test('the default is the device region, not the app language', () {
      expect(deviceCountry(const [Locale('de', 'CH')]), 'ch');
      expect(deviceCountry(const [Locale('en'), Locale('fr', 'BE')]), 'be');
      expect(deviceCountry(const [Locale('fr')]), 'fr');
      expect(deviceCountry(const [Locale('it')]), 'it');
      expect(deviceCountry(const [Locale('ja')]), 'us');
    });
  });

  group('country sheet', () {
    late String? picked;

    Future<void> open(WidgetTester tester, String current) async {
      tallScreen(tester);
      picked = 'unset';
      await tester.pumpWidget(app((context) => TextButton(
            onPressed: () async => picked = await showTrendsCountrySheet(context, current),
            child: const Text('open'),
          )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('search narrows the list; Enter takes the first match', (tester) async {
      await open(tester, 'de');
      await tester.enterText(find.byKey(const ValueKey('country-search')), 'espa');
      await tester.pump();
      expect(find.byKey(const ValueKey('country-es')), findsOneWidget);
      expect(find.byKey(const ValueKey('country-de')), findsNothing);
      expect(find.byKey(const ValueKey('country-fr')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('country-search')), 'zzz');
      await tester.pump();
      expect(find.text('No results found.'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('country-search')), 'frank');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(picked, 'fr');
    });
  });

  group('trends page', () {
    late List<String> countries;
    late int refreshes;
    late Completer<void> refresh;
    late int appleOn;

    Future<void> pump(WidgetTester tester, {bool appleApi = true}) async {
      tallScreen(tester);
      countries = [];
      refreshes = 0;
      appleOn = 0;
      refresh = Completer<void>();
      await tester.pumpWidget(app((context) => DiscoverList(
            searchQuery: '', trending: const [], unifiedSearchResults: const [],
            loadingTrending: false, searchingPI: false,
            searchHasMore: false, loadingMoreSearch: false,
            cs: Theme.of(context).colorScheme,
            l10n: AppLocalizations.of(context)!,
            onOpen: (_) {},
            onRefresh: () {
              refreshes++;
              return refresh.future;
            },
            trendsCountry: 'de',
            onTrendsCountry: countries.add,
            appleApi: appleApi,
            onAppleApiOn: () => appleOn++,
            onLoadMore: () async {},
          )));
      await tester.pump();
    }

    testWidgets('the title names the country; tapping it picks another', (tester) async {
      await pump(tester);
      expect(find.text('Apple Trends (DE)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('trends-title')));
      await tester.pumpAndSettle();
      // The current one picked again changes nothing.
      await tester.tap(find.byKey(const ValueKey('country-de')));
      await tester.pumpAndSettle();
      expect(countries, isEmpty);

      await tester.tap(find.byKey(const ValueKey('trends-title')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('country-au')));
      await tester.pumpAndSettle();
      expect(countries, ['au']);
    });

    testWidgets('a full pull starts one refresh', (tester) async {
      await pump(tester);
      final g = await tester.startGesture(tester.getCenter(find.text('No trending podcasts available.')));
      for (var i = 0; i < 20; i++) {
        await g.moveBy(const Offset(0, 10));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(refreshes, 1);
      refresh.complete();
    });

    testWidgets('with Apple off, a note takes the trends\' place and turns it back on',
        (tester) async {
      await pump(tester, appleApi: false);
      expect(find.byKey(const ValueKey('trends-title')), findsNothing);
      expect(find.text('Apple Podcasts is off'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      expect(appleOn, 1);
    });
  });
}
