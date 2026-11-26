import 'package:antpod/app_database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _feed = 'https://example.com/feed.xml';

EpisodesCompanion _rss(String id, {int durationSeconds = 1800, String? title}) =>
    EpisodesCompanion.insert(
      id: id,
      podcastId: _feed,
      podcastTitle: 'Podcast',
      podcastImageUrl: '',
      title: title ?? 'Episode $id',
      description: '',
      audioUrl: 'https://example.com/$id.mp3',
      durationSeconds: Value(durationSeconds),
      publishDate: DateTime(2026, 1, 1),
    );

void main() {
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

    test('a save in the last minute never marks it played', () async {
      await db.insertEpisodes([_rss('a')]);
      await db.updatePlaybackPosition('a',
          positionMs: 1790000, durationMs: 1800000);
      expect((await ep('a')).isFinished, isFalse);
    });

    test('a finished episode near its end stays finished', () async {
      await db.insertEpisodes([_rss('a')]);
      await db.markFinished('a');
      await db.updatePlaybackPosition('a',
          positionMs: 1790000, durationMs: 1800000);
      expect((await ep('a')).isFinished, isTrue);
    });

    test('a save before the last minute un-marks it', () async {
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
}
