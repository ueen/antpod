import 'dart:convert';
import 'dart:io';

import 'package:antpod/app_database.dart';
import 'package:antpod/backup.dart';
import 'package:antpod/feed_sync.dart';
import 'package:antpod/podcast_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _rss(String title, List<String> guids) => '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel>
<title>$title</title>
<description>About $title</description>
<itunes:image href="https://example.com/$title.jpg"/>
${[for (final g in guids) '<item><title>Episode $g</title><guid>$g</guid>'
    '<enclosure url="https://example.com/$g.mp3" type="audio/mpeg" length="1"/>'
    '<itunes:duration>1800</itunes:duration>'
    '<pubDate>Mon, 05 Jan 2026 10:00:00 GMT</pubDate></item>'].join('\n')}
</channel>
</rss>''';

const _keys = ['a_bool', 'an_int', 'a_double', 'a_string'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late HttpServer server;
  final feeds = <String, String>{};
  String url(String path) => 'http://127.0.0.1:${server.port}/$path';

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      final body = feeds[req.uri.path.substring(1)];
      req.response.statusCode = body == null ? 404 : 200;
      if (body != null) req.response.write(body);
      req.response.close();
    });
  });
  tearDownAll(() => server.close(force: true));

  late AppDatabase db;
  late SharedPreferences prefs;
  setUp(() async {
    feeds
      ..clear()
      ..['a'] = _rss('A', ['a1', 'a2', 'a3', 'a4'])
      ..['b'] = _rss('B', ['b1', 'b2'])
      ..['c'] = _rss('C', ['c1']);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() => db.close());

  Future<Episode> ep(AppDatabase d, String id) => d.getEpisode(id).then((e) => e!);

  /// A fresh phone: an empty database and no settings.
  Future<(AppDatabase, SharedPreferences)> newPhone() async {
    final d = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(d.close);
    SharedPreferences.setMockInitialValues({});
    return (d, await SharedPreferences.getInstance());
  }

  Map<String, Object?> backupOf(List<Map<String, Object?>> episodes,
          {List<Map<String, Object?>> podcasts = const []}) =>
      {
        'format': Backup.format,
        'version': Backup.version,
        'podcasts': podcasts,
        'episodes': episodes,
      };

  group('Backup', () {
    test('moves subscriptions, play state, favourites and settings', () async {
      await FeedSync.subscribeUrl(db, PodcastResult.feed(url('a')));
      await FeedSync.subscribeUrl(db, PodcastResult.feed(url('c')));
      await db.setPodcastSyncPaused(url('c'), true);
      await db.updatePlaybackPosition('a1', positionMs: 120000, durationMs: 1800000);
      await db.markFinished('a2');
      await db.setFavorite('a3', true);
      // A played episode of a feed only previewed, not subscribed.
      await FeedSync.loadPreview(db, PodcastResult.feed(url('b')));
      await db.updatePlaybackPosition('b1', positionMs: 30000, durationMs: 1800000);
      await prefs.setBool('a_bool', false);
      await prefs.setInt('an_int', 3);
      await prefs.setDouble('a_double', 1.5);
      await prefs.setString('a_string', 'x');
      await prefs.setString('not_a_setting', 'y');

      final text = await Backup.export(db, prefs, settingKeys: _keys);
      final json = jsonDecode(text) as Map;
      expect(json['settings'], {'a_bool': false, 'an_int': 3, 'a_double': 1.5, 'a_string': 'x'});
      expect((json['episodes'] as List).map((e) => e['id']),
          unorderedEquals(['a1', 'a2', 'a3', 'b1']));

      final (db2, prefs2) = await newPhone();
      final report = await Backup.import(db2, prefs2, text, settingKeys: _keys);
      expect(report, (subscribed: 2, failed: 0, episodes: 4));

      final subs = await db2.getAllPodcasts();
      expect(subs.map((p) => p.id), unorderedEquals([url('a'), url('c')]));
      expect(subs.firstWhere((p) => p.id == url('c')).syncPaused, isTrue);
      expect(subs.firstWhere((p) => p.id == url('a')).title, 'A');

      final a1 = await ep(db2, 'a1');
      expect(a1.lastPositionMs, 120000);
      expect(a1.isFinished, isFalse);
      expect(a1.lastPlayed, isNotNull);
      expect((await ep(db2, 'a2')).isFinished, isTrue);
      expect((await ep(db2, 'a3')).isFavorite, isTrue);
      expect((await ep(db2, 'a4')).lastPositionMs, 0);

      final b = await db2.getPodcast(url('b'));
      expect(b!.isSubscribed, isFalse);
      final b1 = await ep(db2, 'b1');
      expect(b1.lastPositionMs, 30000);
      expect(b1.isSubscribed, isFalse);

      expect(prefs2.getBool('a_bool'), isFalse);
      expect(prefs2.getInt('an_int'), 3);
      expect(prefs2.getDouble('a_double'), 1.5);
      expect(prefs2.getString('a_string'), 'x');
      expect(prefs2.getString('not_a_setting'), isNull);
    });

    test('of two play states the one played last wins; favourites add up', () async {
      await FeedSync.subscribeUrl(db, PodcastResult.feed(url('a')));
      await db.updatePlaybackPosition('a1', positionMs: 5000, durationMs: 0);
      await db.updatePlaybackPosition('a2', positionMs: 5000, durationMs: 0);
      await db.setFavorite('a3', true);
      final now = DateTime.now();
      String at(Duration d) => now.add(d).toUtc().toIso8601String();
      Map<String, Object?> e(String id, int pos, {String? lastPlayed, bool fav = false}) => {
            'id': id, 'feedUrl': url('a'), 'audioUrl': 'https://example.com/$id.mp3',
            'positionMs': pos, 'played': false, 'favorite': fav,
            if (lastPlayed != null) 'lastPlayed': lastPlayed,
          };

      final report = await Backup.import(db, prefs, jsonEncode(backupOf([
        e('a1', 60000, lastPlayed: at(const Duration(days: -1))), // older: kept
        e('a2', 60000, lastPlayed: at(const Duration(days: 1))), // newer: taken
        e('a3', 0), // no favourite in the backup: stays one
        e('a4', 0, fav: true),
      ])), settingKeys: _keys);

      expect(report.episodes, 2);
      expect((await ep(db, 'a1')).lastPositionMs, 5000);
      expect((await ep(db, 'a2')).lastPositionMs, 60000);
      expect((await ep(db, 'a3')).isFavorite, isTrue);
      expect((await ep(db, 'a4')).isFavorite, isTrue);
    });

    test('without a time, a play state only lands on an untouched episode', () async {
      await FeedSync.subscribeUrl(db, PodcastResult.feed(url('a')));
      await db.updatePlaybackPosition('a1', positionMs: 5000, durationMs: 0);
      Map<String, Object?> e(String id) =>
          {'id': id, 'feedUrl': url('a'), 'positionMs': 60000, 'played': true};
      await Backup.import(db, prefs, jsonEncode(backupOf([e('a1'), e('a2')])),
          settingKeys: _keys);
      expect((await ep(db, 'a1')).lastPositionMs, 5000);
      expect((await ep(db, 'a2')).isFinished, isTrue);
    });

    test('an episode whose guid changed is found by its audio URL', () async {
      await FeedSync.subscribeUrl(db, PodcastResult.feed(url('a')));
      await Backup.import(db, prefs, jsonEncode(backupOf([
        {'id': 'old-guid', 'feedUrl': url('a'), 'audioUrl': 'https://example.com/a2.mp3',
         'positionMs': 60000, 'lastPlayed': DateTime.now().toUtc().toIso8601String()},
      ])), settingKeys: _keys);
      expect((await ep(db, 'a2')).lastPositionMs, 60000);
      expect(await db.getEpisode('old-guid'), isNull);
    });

    test('an episode gone from its feed comes back from the backup', () async {
      await Backup.import(db, prefs, jsonEncode(backupOf(podcasts: [
        {'feedUrl': url('a'), 'title': 'A', 'subscribed': true},
      ], [
        {'id': 'gone', 'feedUrl': url('a'), 'audioUrl': 'https://example.com/gone.mp3',
         'title': 'Gone', 'publishDate': '2020-01-01T00:00:00.000Z',
         'durationSeconds': 600, 'positionMs': 0, 'played': true,
         'lastPlayed': DateTime.now().toUtc().toIso8601String()},
      ])), settingKeys: _keys);
      final gone = await ep(db, 'gone');
      expect(gone.title, 'Gone');
      expect(gone.podcastId, url('a'));
      expect(gone.isSubscribed, isTrue);
      expect(gone.isFinished, isTrue);
      expect(gone.durationSeconds, 600);
    });

    test('a feed that does not load is subscribed with what the backup knows', () async {
      final report = await Backup.import(db, prefs, jsonEncode(backupOf(podcasts: [
        {'feedUrl': url('missing'), 'title': 'Missing', 'imageUrl': 'https://x/i.jpg'},
      ], [])), settingKeys: _keys);
      expect(report, (subscribed: 1, failed: 1, episodes: 0));
      final pod = (await db.findSubscribed(url('missing')))!;
      expect(pod.title, 'Missing');
      expect(pod.imageUrl, 'https://x/i.jpg');
    });

    test('feeds already subscribed are left alone', () async {
      await FeedSync.subscribeUrl(db, PodcastResult.feed(url('a')));
      var calls = 0;
      final report = await Backup.import(db, prefs, jsonEncode(backupOf(podcasts: [
        {'feedUrl': url('a')},
        {'feedUrl': url('b')},
      ], [])), settingKeys: _keys, subscribe: (f) async {
        calls++;
        return true;
      });
      expect(calls, 1);
      expect(report.subscribed, 1);
    });

    test('rejects other files and newer versions', () async {
      Future<ImportReport> import(String text) =>
          Backup.import(db, prefs, text, settingKeys: _keys);
      await expectLater(import('not json'), throwsFormatException);
      await expectLater(import('[]'), throwsFormatException);
      await expectLater(import(jsonEncode({'format': 'other'})), throwsFormatException);
      await expectLater(
          import(jsonEncode({'format': Backup.format, 'version': Backup.version + 1})),
          throwsFormatException);
    });
  });

  group('Opml', () {
    test('build and parse round-trip', () async {
      await FeedSync.subscribeUrl(db, PodcastResult.feed(url('a')));
      await FeedSync.subscribeUrl(db, PodcastResult.feed(url('b')));
      final text = Opml.build(await db.getAllPodcasts(), now: DateTime.utc(2026, 11, 26, 9));
      expect(text, contains('<dateCreated>Thu, 26 Nov 2026 09:00:00 GMT</dateCreated>'));
      expect(Opml.parse(text), unorderedEquals([
        (url: url('a'), title: 'A'),
        (url: url('b'), title: 'B'),
      ]));
    });

    test('reads nested outlines, other schemes and spellings, each feed once', () {
      final feeds = Opml.parse('''<?xml version="1.0"?>
<opml version="1.0"><head/><body>
  <outline text="Folder">
    <outline text="One" xmlUrl="https://example.com/one"/>
    <outline title="Two" text="ignored" xmlurl="feed://example.com/two"/>
  </outline>
  <outline text="One again" xmlUrl="https://example.com/one/"/>
  <outline text="Three" xmlUrl="itpc://example.com/three"/>
  <outline xmlUrl="feed:https://example.com/four"/>
  <outline text="Not a feed" xmlUrl="mailto:someone@example.com"/>
  <outline text="A folder, no feed"/>
</body></opml>''');
      expect(feeds, [
        (url: 'https://example.com/one', title: 'One'),
        (url: 'https://example.com/two', title: 'Two'),
        (url: 'https://example.com/three', title: 'Three'),
        (url: 'https://example.com/four', title: 'example.com'),
      ]);
    });

    test('rejects what is not OPML', () {
      expect(() => Opml.parse('just text'), throwsFormatException);
      expect(() => Opml.parse('<rss><channel/></rss>'), throwsFormatException);
    });

    test('import subscribes the feeds not subscribed yet', () async {
      await FeedSync.subscribeUrl(db, PodcastResult.feed(url('a')));
      final text = '<opml><body>'
          '<outline text="A" xmlUrl="${url('a')}"/>'
          '<outline text="B" xmlUrl="${url('b')}"/>'
          '<outline text="Missing" xmlUrl="${url('missing')}"/>'
          '</body></opml>';
      final progress = <int>[];
      final report = await Opml.import(db, text, onProgress: (done, _) => progress.add(done));
      expect(report, (subscribed: 2, failed: 1, episodes: 0));
      expect(progress, unorderedEquals([1, 2]));
      expect((await db.getAllPodcasts()).map((p) => p.title),
          unorderedEquals(['A', 'B', 'Missing']));
      expect((await db.select(db.episodes).get()).where((e) => e.podcastId == url('b')),
          hasLength(2));
    });
  });
}
