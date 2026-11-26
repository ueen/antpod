import 'dart:io';

import 'package:antpod/app_database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _feed = 'https://example.com/feed.xml';

EpisodesCompanion _rss(String id,
        {int durationSeconds = 1800, String? title, DateTime? date}) =>
    EpisodesCompanion.insert(
      id: id,
      podcastId: _feed,
      podcastTitle: 'Podcast',
      podcastImageUrl: '',
      title: title ?? 'Episode $id',
      description: '',
      audioUrl: 'https://example.com/$id.mp3',
      durationSeconds: Value(durationSeconds),
      publishDate: Value(date ?? DateTime(2026, 1, 1)),
    );

void main() {
  // Each test opens its own in-memory database (and the migration test two
  // on one file, one after the other).
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.insertPodcast(PodcastsCompanion.insert(
      id: _feed, title: 'Podcast', description: '', imageUrl: '',
      feedUrl: _feed, author: '',
    ));
  });
  tearDown(() => db.close());

  Future<Episode> ep(String id) =>
      (db.select(db.episodes)..where((e) => e.id.equals(id))).getSingle();

  group('insertEpisodes', () {
    test('an unplayed episode takes the feed duration on refresh', () async {
      await db.insertEpisodes([_rss('a', durationSeconds: 1800)]);
      await db.insertEpisodes([_rss('a', durationSeconds: 1900)]);
      expect((await ep('a')).durationSeconds, 1900);
    });

    test('a played episode keeps the duration from playback', () async {
      await db.insertEpisodes([_rss('a', durationSeconds: 1800)]);
      await db.updatePlaybackPosition('a',
          positionMs: 60000, durationMs: 1834000);
      await db.insertEpisodes([_rss('a', durationSeconds: 0, title: 'New')]);

      final e = await ep('a');
      expect(e.durationSeconds, 1834);
      expect(e.title, 'New', reason: 'other feed columns still update');
      expect(e.lastPositionMs, 60000, reason: 'refresh leaves the position');
    });

    test('after a reset the feed duration applies again', () async {
      await db.insertEpisodes([_rss('a', durationSeconds: 1800)]);
      await db.updatePlaybackPosition('a',
          positionMs: 60000, durationMs: 1834000);
      await db.markUnfinished('a');
      await db.insertEpisodes([_rss('a', durationSeconds: 1800)]);
      expect((await ep('a')).durationSeconds, 1800);
    });

    test('refresh keeps download and finished state', () async {
      await db.insertEpisodes([_rss('a')]);
      await db.updateEpisodeDownload('a', true, '/x/a.mp3', 'task');
      await db.markFinished('a');
      await db.insertEpisodes([_rss('a')]);

      final e = await ep('a');
      expect(e.isDownloaded, isTrue);
      expect(e.localPath, '/x/a.mp3');
      expect(e.isFinished, isTrue);
    });
  });

  group('updatePlaybackPosition', () {
    test('saves ms and seconds and the real duration', () async {
      await db.insertEpisodes([_rss('a', durationSeconds: 0)]);
      await db.updatePlaybackPosition('a',
          positionMs: 125500, durationMs: 3600000);

      final e = await ep('a');
      expect(e.lastPositionMs, 125500);
      expect(e.playbackPositionSeconds, 125);
      expect(e.durationSeconds, 3600);
      expect(e.lastPlayed, isNotNull);
    });

    test('an unknown duration (0) leaves the stored one', () async {
      await db.insertEpisodes([_rss('a', durationSeconds: 1800)]);
      await db.updatePlaybackPosition('a', positionMs: 1000, durationMs: 0);
      expect((await ep('a')).durationSeconds, 1800);
    });

    test('a save in the last 100 s never marks it played', () async {
      await db.insertEpisodes([_rss('a')]);
      await db.updatePlaybackPosition('a',
          positionMs: 1790000, durationMs: 1800000);
      expect((await ep('a')).isFinished, isFalse);
    });

    test('a finished episode near its end stays finished', () async {
      await db.insertEpisodes([_rss('a')]);
      await db.markFinished('a');
      await db.updatePlaybackPosition('a',
          positionMs: 1710000, durationMs: 1800000); // 90 s before the end
      expect((await ep('a')).isFinished, isTrue);
    });

    test('a save before the last 100 s un-marks it', () async {
      await db.insertEpisodes([_rss('a')]);
      await db.markFinished('a');
      await db.updatePlaybackPosition('a',
          positionMs: 60000, durationMs: 1800000);
      expect((await ep('a')).isFinished, isFalse);
    });
  });

  test('markUnfinished resets the position', () async {
    await db.insertEpisodes([_rss('a')]);
    await db.updatePlaybackPosition('a', positionMs: 60000, durationMs: 1800000);
    await db.markUnfinished('a');

    final e = await ep('a');
    expect(e.lastPositionMs, 0);
    expect(e.playbackPositionSeconds, 0);
    expect(e.lastPlayed, isNull);
    expect(e.isFinished, isFalse);
  });

  Future<Podcast> pod() => db.getPodcast(_feed).then((p) => p!);

  group('list streams', () {
    test("a list's episode is the stored one without its show notes", () async {
      await db.insertEpisodes([
        _rss('a').copyWith(
          description: const Value('<p>01:00 Intro</p>'),
          isSubscribed: const Value(true),
          chaptersUrl: const Value('https://example.com/a.json'),
        ),
      ]);
      await db.updatePlaybackPosition('a', positionMs: 5000, durationMs: 1800000);
      final stored = (await db.getEpisode('a'))!;
      expect(stored.description, '<p>01:00 Intro</p>');
      expect(stored.lastPlayed, isNotNull);

      final listed = [stored.copyWith(description: '')];
      expect(await db.watchAllFeedEpisodes().first, listed);
      expect(await db.watchEpisodesForPodcast(_feed).first, listed);
    });

    test('each list has its episodes, newest first', () async {
      EpisodesCompanion at(String id, int day, {bool subscribed = true,
              bool downloaded = false, bool marked = false}) =>
          _rss(id).copyWith(
            publishDate: Value(DateTime(2026, 1, day)),
            isSubscribed: Value(subscribed),
            isDownloaded: Value(downloaded),
            markedForDownload: Value(marked),
          );
      await db.insertEpisodes([
        at('old', 1),
        at('new', 3, marked: true),
        at('mid', 2, subscribed: false, downloaded: true),
        at('temp', 4, subscribed: false),
        _rss('other').copyWith(podcastId: const Value('elsewhere'),
            isSubscribed: const Value(true),
            publishDate: Value(DateTime(2025, 12, 1))),
      ]);
      Future<List<String>> ids(Stream<List<Episode>> s) =>
          s.first.then((l) => [for (final e in l) e.id]);

      expect(await ids(db.watchAllFeedEpisodes()), ['new', 'mid', 'old', 'other']);
      expect(await ids(db.watchEpisodesForPodcast(_feed)), ['temp', 'new', 'mid', 'old']);
      expect(await ids(db.watchDownloadedOrMarkedEpisodes()), ['new', 'mid']);
    });
  });

  group('favourites', () {
    test('set and watched, and listed in the home feed even when temp', () async {
      await db.insertEpisodes([
        _rss('a').copyWith(isSubscribed: const Value(false)),
      ]);
      final seen = db.watchFavorite('a').take(2).toList();
      await Future<void>.delayed(Duration.zero);
      await db.setFavorite('a', true);
      expect(await seen, [false, true]);
      expect([for (final e in await db.watchAllFeedEpisodes().first) e.id], ['a']);
    });

    test('a temp favourite outlasts the stale cleanup', () async {
      final old = DateTime.now().subtract(const Duration(days: 30));
      await db.insertEpisodes([
        for (final id in ['fav', 'plain'])
          _rss(id).copyWith(
            isSubscribed: const Value(false),
            isFinished: const Value(true),
            lastPlayed: Value(old),
            publishDate: Value(old),
          ),
      ]);
      await (db.update(db.podcasts)..where((p) => p.id.equals(_feed)))
          .write(const PodcastsCompanion(isSubscribed: Value(false)));
      await db.setFavorite('fav', true);

      await db.cleanupStaleTempEpisodes();
      final left = await db.select(db.episodes).get();
      expect([for (final e in left) e.id], ['fav']);
      expect(await db.select(db.podcasts).get(), hasLength(1),
          reason: 'the feed stays for its favourite');
    });

    test('unsubscribe & delete keeps favourites, as a temp feed', () async {
      await db.insertEpisodes([
        for (final id in ['fav', 'plain'])
          _rss(id).copyWith(isSubscribed: const Value(true)),
      ]);
      await db.setFavorite('fav', true);

      await db.deletePodcast(_feed);
      final left = await db.select(db.episodes).get();
      expect([for (final e in left) e.id], ['fav']);
      expect(left.single.isSubscribed, isFalse);
      final pod = await db.select(db.podcasts).getSingle();
      expect(pod.isSubscribed, isFalse);
    });

    test('without favourites the podcast goes whole', () async {
      await db.insertEpisodes([_rss('a').copyWith(isSubscribed: const Value(true))]);
      await db.deletePodcast(_feed);
      expect(await db.select(db.episodes).get(), isEmpty);
      expect(await db.select(db.podcasts).get(), isEmpty);
    });

    test("a favourite's played download isn't deleted", () async {
      final old = DateTime.now().subtract(const Duration(days: 5));
      await db.insertEpisodes([
        for (final id in ['fav', 'plain'])
          _rss(id).copyWith(
            isSubscribed: const Value(true),
            isFinished: const Value(true),
            isDownloaded: const Value(true),
            lastPlayed: Value(old),
          ),
      ]);
      await db.setFavorite('fav', true);

      await db.deleteFinishedDownloads();
      expect((await ep('fav')).isDownloaded, isTrue);
      expect((await ep('plain')).isDownloaded, isFalse);
    });

    test('a removed temp episode is no favourite any more', () async {
      await db.insertEpisodes([
        _rss('a').copyWith(isSubscribed: const Value(false)),
      ]);
      await db.setFavorite('a', true);
      await db.resetTempEpisode('a');
      expect((await ep('a')).isFavorite, isFalse);
    });
  });

  group('saveFeedRefresh', () {
    test('writes episodes and podcast columns together', () async {
      await db.saveFeedRefresh([_rss('a')], {
        _feed: const PodcastsCompanion(
            imageUrl: Value('https://example.com/new.jpg'),
            feedEtag: Value('"v1"'),
            feedHash: Value('1:abc')),
      });
      expect((await ep('a')).title, 'Episode a');
      final p = await pod();
      expect(p.imageUrl, 'https://example.com/new.jpg');
      expect(p.feedEtag, '"v1"');
      expect(p.feedHash, '1:abc');
      expect(p.title, 'Podcast', reason: 'absent columns stay');
    });

    test('skips a podcast unsubscribed while its feed loaded', () async {
      await db.deletePodcast(_feed);
      await db.saveFeedRefresh([_rss('a')],
          {_feed: const PodcastsCompanion(feedEtag: Value('"v1"'))});
      expect(await db.getEpisode('a'), isNull);
      expect(await db.getPodcast(_feed), isNull);
    });

    test('nothing to write is fine', () async {
      await db.saveFeedRefresh(const [], {_feed: const PodcastsCompanion()});
      expect((await pod()).feedEtag, isNull);
    });

    // The feed's oldest item, so the republished one is inside its span.
    final older = _rss('z', date: DateTime(2025, 12));
    Future<void> refresh(List<EpisodesCompanion> feed) =>
        db.saveFeedRefresh(feed, const {});
    Future<void> set(String id, EpisodesCompanion c) =>
        (db.update(db.episodes)..where((e) => e.id.equals(id))).write(c);
    final republished =
        _rss('b', title: ' kingdom  come 1', date: DateTime(2026, 1, 1, 12));

    test('a republished episode in use stays off the feed until finished',
        () async {
      await refresh([older, _rss('a', title: 'Kingdom Come 1')]);
      await set('a', EpisodesCompanion(
          lastPositionMs: const Value(600000),
          lastPlayed: Value(DateTime(2026, 1, 2)),
          isFavorite: const Value(true),
          isDownloaded: const Value(true),
          localPath: const Value('/files/a.mp3')));
      await refresh([older, republished]);

      var a = await ep('a');
      expect(a.isSubscribed, isFalse, reason: 'a temp episode now');
      expect(a.isFavorite, isFalse, reason: 'the mark moved');
      expect(a.lastPositionMs, 600000);
      var b = await ep('b');
      expect(b.isFavorite, isTrue);
      expect(b.lastPositionMs, 0);
      expect(b.isFinished, isFalse);

      await refresh([older, republished]);
      a = await ep('a');
      expect(a.lastPositionMs, 600000, reason: 'a refresh leaves it be');

      await db.markFinished('a');
      expect(await db.getEpisode('a'), isNull, reason: 'it folded in');
      b = await ep('b');
      expect(b.isFinished, isTrue);
      expect(b.lastPositionMs, 600000);
      expect(b.isDownloaded, isTrue);
      expect(b.localPath, '/files/a.mp3');
    });

    test('a finished one folds in at once', () async {
      await refresh([older, _rss('a', title: 'Kingdom Come 1')]);
      await db.markFinished('a');
      await refresh([older, republished]);
      expect(await db.getEpisode('a'), isNull);
      expect((await ep('b')).isFinished, isTrue);
    });

    test('an untouched one goes, and its WiFi mark moves', () async {
      await refresh([older, _rss('a', title: 'Kingdom Come 1')]);
      await set('a', const EpisodesCompanion(markedForDownload: Value(true)));
      await refresh([older, republished]);
      expect(await db.getEpisode('a'), isNull);
      expect((await ep('b')).markedForDownload, isTrue);
    });

    test('same audio under a new guid and title: one episode', () async {
      await refresh([older, _rss('a')]);
      await db.markFinished('a');
      await refresh([
        older,
        _rss('b', title: 'Episode a (fixed typo)', date: DateTime(2026, 2))
            .copyWith(audioUrl: const Value('https://example.com/a.mp3')),
      ]);
      expect(await db.getEpisode('a'), isNull);
      expect((await ep('b')).isFinished, isTrue);
    });

    test('a temp episode finished folds into its twin in the feed', () async {
      await refresh([older, republished]);
      await db.insertTempEpisodes([
        _rss('stub', title: 'Kingdom Come 1')
            .copyWith(isSubscribed: const Value(false)),
      ]);
      await db.markPlayedByUser('stub');
      expect(await db.getEpisode('stub'), isNull);
      expect((await ep('b')).isFinished, isTrue);
    });

    test('an undated item keeps the date it was first seen', () async {
      final undated = _rss('u').copyWith(publishDate: const Value.absent());
      await refresh([older, undated]);
      final first = (await ep('u')).publishDate;
      expect(DateTime.now().difference(first).inMinutes, 0);
      await set('u', EpisodesCompanion(publishDate: Value(DateTime(2026, 1))));
      await refresh([older, undated]);
      expect((await ep('u')).publishDate, DateTime(2026, 1));
    });

    test('same title, but older than the feed or another day: stays', () async {
      await db.saveFeedRefresh([
        _rss('old', title: 'News').copyWith(
            publishDate: Value(DateTime(2025, 12, 31, 18))),
        _rss('other', title: 'News').copyWith(
            publishDate: Value(DateTime(2026, 1, 5))),
      ], const {});
      await db.saveFeedRefresh([
        _rss('b', title: 'News'),
        _rss('c').copyWith(publishDate: Value(DateTime(2026, 1, 10))),
      ], const {});
      expect(await db.getEpisode('old'), isNotNull);
      expect(await db.getEpisode('other'), isNotNull);
    });
  });

  test('the failing note shows after three failed refreshes', () async {
    final failing = <bool>[];
    final sub = db.watchFeedFailing(_feed).listen(failing.add);
    for (var i = 0; i < AppDatabase.feedFailingAfter; i++) {
      await db.countFeedFailures([_feed]);
    }
    await pumpEventQueue();
    expect((await pod()).feedFailures, AppDatabase.feedFailingAfter);
    expect(failing.last, isTrue);

    await db.saveFeedRefresh(
        const [], {_feed: const PodcastsCompanion(feedFailures: Value(0))});
    await pumpEventQueue();
    expect(failing, [false, true, false]);
    await sub.cancel();
  });

  test('subscribing starts the feed over: no validators, no failures', () async {
    await db.saveFeedRefresh(const [], {
      _feed: const PodcastsCompanion(
          feedEtag: Value('"v1"'), feedLastModified: Value('Mon'),
          feedHash: Value('1:abc'), feedFailures: Value(5)),
    });
    await db.subscribePodcast(
        PodcastsCompanion.insert(
            id: _feed, title: 'Podcast', description: '', imageUrl: '',
            feedUrl: _feed, author: ''),
        [_rss('a')]);
    final p = await pod();
    expect([p.feedEtag, p.feedLastModified, p.feedHash], [null, null, null]);
    expect(p.feedFailures, 0);
  });

  test('a v8 database gets the feed columns, episode indexes and favourites', () async {
    final dir = Directory.systemTemp.createTempSync('antpod-migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/v8.db');

    // Today's schema taken back to v8.
    final old = AppDatabase.forTesting(NativeDatabase(file));
    await old.customStatement('DROP INDEX episodes_podcast_date');
    await old.customStatement('DROP INDEX episodes_publish_date');
    for (final col in ['feed_etag', 'feed_last_modified', 'feed_hash', 'feed_failures']) {
      await old.customStatement('ALTER TABLE podcasts DROP COLUMN $col');
    }
    await old.customStatement('ALTER TABLE episodes DROP COLUMN is_favorite');
    await old.customStatement(
        "INSERT INTO podcasts (id, title, description, image_url, feed_url, author) "
        "VALUES ('$_feed', 'Podcast', '', '', '$_feed', '')");
    await old.customStatement('PRAGMA user_version = 8');
    await old.close();

    final migrated = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(migrated.close);
    final p = (await migrated.getPodcast(_feed))!;
    expect(p.feedFailures, 0);
    expect(p.feedEtag, isNull);
    final indexes = await migrated
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name LIKE 'episodes_%'")
        .map((r) => r.read<String>('name'))
        .get();
    expect(indexes.toSet(), {'episodes_podcast_date', 'episodes_publish_date'});
    await migrated.insertEpisodes([_rss('a')]);
    expect((await migrated.getEpisode('a'))!.isFavorite, isFalse,
        reason: 'v10 added is_favorite');
  });

  test('a v10 database loads every feed in full once', () async {
    final dir = Directory.systemTemp.createTempSync('antpod-migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/v10.db');
    final old = AppDatabase.forTesting(NativeDatabase(file));
    await old.customStatement(
        "INSERT INTO podcasts (id, title, description, image_url, feed_url, "
        "author, feed_etag, feed_last_modified, feed_hash) VALUES ('$_feed', "
        "'Podcast', '', '', '$_feed', '', '\"v1\"', 'Mon', '1:abc')");
    await old.customStatement('PRAGMA user_version = 10');
    await old.close();

    final migrated = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(migrated.close);
    final p = (await migrated.getPodcast(_feed))!;
    expect([p.feedEtag, p.feedLastModified, p.feedHash], [null, null, null]);
  });
}
