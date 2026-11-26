// lib/app_database.dart
//
// Schema version: 11
//   v1 → v2: Episodes.isSubscribed added
//   v2 → v3: Episodes.isFinished added (true = fully listened)
//            Episodes.lastPositionMs added (millisecond precision resume point)
//   v3 → v4: Episodes.chaptersUrl added
//   v4 → v5: Episodes.lastPlayed added (timestamp of most recent playback)
//   v5 → v6: Episodes.markedForDownload added (queued for WiFi download)
//   v6 → v7: Podcasts.isSubscribed added (false = temporary preview feed)
//   v7 → v8: Podcasts.syncPaused added (true = skip background refresh)
//   v8 → v9: Podcasts.feedEtag, feedLastModified, feedHash, feedFailures
//            added (conditional refresh, "feed not loading" note);
//            episode indexes on (podcast_id, publish_date) and publish_date
//   v9 → v10: Episodes.isFavorite added
//   v10 → v11: feed validators cleared once (republished episodes merge)
//
// Regenerate after schema changes:
//   dart run build_runner build --delete-conflicting-outputs

import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'app_settings.dart';
import 'feed_items.dart';

part 'app_database.g.dart';

// ─── Tables ───────────────────────────────────────────────────────────────────

class Podcasts extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text()();
  TextColumn get imageUrl => text()();
  TextColumn get feedUrl => text()();
  TextColumn get author => text()();
  TextColumn get website => text().nullable()();
  DateTimeColumn get subscribedAt =>
      dateTime().withDefault(currentDateAndTime)();
  /// true = active subscription; false = temporary preview (not yet subscribed)
  BoolColumn get isSubscribed => boolean().withDefault(const Constant(true))();
  /// true = skip this feed during background auto-refresh (user manually paused sync)
  BoolColumn get syncPaused => boolean().withDefault(const Constant(false))();

  /// The feed's ETag and Last-Modified from the refresh that last parsed it,
  /// sent back so an unchanged feed answers 304 Not Modified.
  TextColumn get feedEtag => text().nullable()();
  TextColumn get feedLastModified => text().nullable()();
  /// Hash of the feed body last parsed (PodcastService.fetchFeed): a server
  /// that ignores the headers above but sends the same feed isn't parsed again.
  TextColumn get feedHash => text().nullable()();
  /// Refreshes in a row where this feed failed while others loaded, so the
  /// device was online: the podcast's page says the feed isn't loading.
  IntColumn get feedFailures => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

// A podcast's page and most per-feed queries filter by podcast_id; the lists
// sort by publish_date.
@TableIndex(name: 'episodes_podcast_date', columns: {#podcastId, #publishDate})
@TableIndex(name: 'episodes_publish_date', columns: {#publishDate})
class Episodes extends Table {
  TextColumn get id => text()();
  TextColumn get podcastId => text()();
  TextColumn get podcastTitle => text()();
  TextColumn get podcastImageUrl => text()();
  TextColumn get title => text()();
  TextColumn get description => text()();
  TextColumn get audioUrl => text()();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  /// When the feed dates it; an undated item's first sighting (a feed's
  /// later refreshes leave it be, see PodcastService.fetchFeed).
  DateTimeColumn get publishDate => dateTime().clientDefault(DateTime.now)();
  BoolColumn get isDownloaded => boolean().withDefault(const Constant(false))();
  TextColumn get localPath => text().nullable()();
  TextColumn get downloadTaskId => text().nullable()();

  /// Resume position in milliseconds (high precision).
  /// 0 = never started.
  IntColumn get lastPositionMs => integer().withDefault(const Constant(0))();

  /// Derived convenience: position in full seconds (for display).
  /// Kept for backward compat with older code paths.
  IntColumn get playbackPositionSeconds =>
      integer().withDefault(const Constant(0))();

  /// true once the episode has been played to completion
  /// (position >= 95 % of duration, or explicitly marked).
  BoolColumn get isFinished => boolean().withDefault(const Constant(false))();

  /// true  = from a subscribed podcast
  /// false = temporary Discover episode (deleted after playback)
  BoolColumn get isSubscribed => boolean().withDefault(const Constant(true))();

  /// Where the feed's chapters are: the podcast:chapters JSON file, or a
  /// data: URI of the same JSON made from inline Podlove chapters.
  TextColumn get chaptersUrl => text().nullable()();

  /// Timestamp of the most recent playback interaction.
  /// Null if the episode has never been played.
  DateTimeColumn get lastPlayed => dateTime().nullable()();

  /// true = queued to download the next time WiFi is available.
  BoolColumn get markedForDownload =>
      boolean().withDefault(const Constant(false))();

  /// Marked as a favourite: kept, temp or not, until unmarked; its download
  /// isn't deleted once played.
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── Stream helpers ───────────────────────────────────────────────────────────

// Structural equality for episode lists: propagates changes to fields that affect
// filtering or display. Position changes count too, except for [liveId], the
// episode the player is on: its 5-second saves would rebuild every list while
// it plays, and its tile shows the live player position anyway.
bool _episodeListEqual(List<Episode> a, List<Episode> b, String? liveId) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    final x = a[i]; final y = b[i];
    if (x.id != y.id ||
        x.isFinished != y.isFinished ||
        x.isDownloaded != y.isDownloaded ||
        x.markedForDownload != y.markedForDownload ||
        x.isFavorite != y.isFavorite ||
        x.durationSeconds != y.durationSeconds ||
        x.localPath != y.localPath ||
        (x.lastPositionMs != y.lastPositionMs && x.id != liveId)) {
      return false;
    }
  }
  return true;
}

// Podcast lists compare equal unless something on screen changed: a refresh
// that only stores a feed's validators doesn't rebuild the grid.
bool _samePodcastList(List<Podcast> a, List<Podcast> b) {
  if (a.length != b.length) return false;
  Podcast shown(Podcast p) => p.copyWith(
      feedEtag: const Value(null), feedLastModified: const Value(null),
      feedHash: const Value(null), feedFailures: 0);
  for (int i = 0; i < a.length; i++) {
    if (shown(a[i]) != shown(b[i])) return false;
  }
  return true;
}

// ─── Database ─────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [Podcasts, Episodes])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'antpod'));

  /// Over any executor, e.g. `NativeDatabase.memory()` in tests.
  AppDatabase.forTesting(super.e);

  /// The episode the player is on, set by PlayerProvider. List streams skip
  /// its position-only changes while it plays; every other position change
  /// (the final save when the player stops or switches episode, mark as
  /// unplayed) reaches the lists, so progress bars never go stale.
  String? livePositionEpisodeId;

  bool _sameEpisodeList(List<Episode> a, List<Episode> b) =>
      _episodeListEqual(a, b, livePositionEpisodeId);

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(episodes, episodes.isSubscribed);
      }
      if (from < 3) {
        await m.addColumn(episodes, episodes.isFinished);
        await m.addColumn(episodes, episodes.lastPositionMs);
      }
      if (from < 4) {
        await m.database.customStatement(
            'ALTER TABLE episodes ADD COLUMN chapters_url TEXT');
      }
      if (from < 5) {
        await m.database.customStatement(
            'ALTER TABLE episodes ADD COLUMN last_played INTEGER');
      }
      if (from < 6) {
        await m.database.customStatement(
            'ALTER TABLE episodes ADD COLUMN marked_for_download INTEGER NOT NULL DEFAULT 0');
      }
      if (from < 7) {
        await m.database.customStatement(
            'ALTER TABLE podcasts ADD COLUMN is_subscribed INTEGER NOT NULL DEFAULT 1');
      }
      if (from < 8) {
        await m.database.customStatement(
            'ALTER TABLE podcasts ADD COLUMN sync_paused INTEGER NOT NULL DEFAULT 0');
      }
      if (from < 9) {
        for (final col in ['feed_etag', 'feed_last_modified', 'feed_hash']) {
          await m.database.customStatement(
              'ALTER TABLE podcasts ADD COLUMN $col TEXT');
        }
        await m.database.customStatement(
            'ALTER TABLE podcasts ADD COLUMN feed_failures INTEGER NOT NULL DEFAULT 0');
        await m.createIndex(episodesPodcastDate);
        await m.createIndex(episodesPublishDate);
      }
      if (from < 10) {
        await m.database.customStatement(
            'ALTER TABLE episodes ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0');
      }
      if (from < 11) {
        // Every feed loads in full once, so republished episodes already
        // listed twice merge (saveFeedRefresh).
        await m.database.customStatement('UPDATE podcasts SET feed_etag = NULL, '
            'feed_last_modified = NULL, feed_hash = NULL');
      }
    },
  );

  // ── Podcasts ──────────────────────────────────────────────────────────────

  Stream<List<Podcast>> watchAllPodcasts() =>
      (select(podcasts)
            ..where((p) => p.isSubscribed.equals(true))
            ..orderBy([(p) => OrderingTerm.asc(p.title)]))
          .watch()
          .distinct(_samePodcastList);

  Future<List<Podcast>> getAllPodcasts() =>
      (select(podcasts)..where((p) => p.isSubscribed.equals(true))).get();

  Future<Podcast?> getPodcast(String id) =>
      (select(podcasts)..where((p) => p.id.equals(id))).getSingleOrNull();

  /// The subscribed podcast for [feed]: by id, by feed URL, or by the feed
  /// with protocol, "www." and trailing slashes ignored (share links drop them).
  Future<Podcast?> findSubscribed(String feed) async {
    final all = await getAllPodcasts();
    final norm = normFeed(feed);
    return all.where((p) => p.id == feed || p.feedUrl == feed).firstOrNull ??
        all.where((p) => normFeed(p.feedUrl) == norm).firstOrNull;
  }

  /// A feed URL reduced for comparison: no protocol, leading "www." or
  /// trailing slashes.
  static String normFeed(String url) => url
      .replaceFirst(RegExp(r'^https?://'), '')
      .replaceFirst(RegExp(r'^www\.'), '')
      .replaceFirst(RegExp(r'/+$'), '');

  /// Between a podcast id and a guid in a [scopedId]: XML 1.0 can't carry
  /// it, so no guid or feed URL has it.
  static const _scope = '\u001f';

  /// The id of [podcastId]'s episode [guid] when another podcast's feed
  /// had that guid first (see [_ownIds]).
  static String scopedId(String podcastId, String guid) =>
      '$podcastId$_scope$guid';

  /// The feed's own guid of the episode stored as [id].
  static String guidOf(String id) {
    final i = id.indexOf(_scope);
    return i < 0 ? id : id.substring(i + 1);
  }

  /// [eps] under the ids they're stored as. An episode's id is its feed's
  /// guid, unless another podcast has a row under it already (a network's
  /// feeds sharing a trailer or a promo, a feed copied from another): then
  /// it's scoped to its own podcast ([scopedId]) and both are kept. The feed
  /// that had it first keeps the bare guid; a scoped one stays scoped. A
  /// preview of a subscribed feed (another id, the same URL) is that feed.
  Future<List<EpisodesCompanion>> _ownIds(List<EpisodesCompanion> eps) async {
    if (eps.isEmpty) return eps;
    final keys = {
      for (final e in eps) ...[
        guidOf(e.id.value),
        scopedId(e.podcastId.value, guidOf(e.id.value)),
      ],
    }.toList();
    final owner = <String, String>{};
    for (var i = 0; i < keys.length; i += 500) {
      final q = selectOnly(episodes)
        ..addColumns([episodes.id, episodes.podcastId])
        ..where(episodes.id.isIn(keys.skip(i).take(500)));
      for (final r in await q.get()) {
        owner[r.read(episodes.id)!] = r.read(episodes.podcastId)!;
      }
    }
    Map<String, String>? feedOf;
    Future<bool> same(String a, String b) async {
      if (a == b) return true;
      final feeds = feedOf ??= {
        for (final p in await select(podcasts).get()) p.id: normFeed(p.feedUrl),
      };
      return (feeds[a] ?? normFeed(a)) == (feeds[b] ?? normFeed(b));
    }

    final claimed = <String, String>{};
    final out = <EpisodesCompanion>[];
    for (final e in eps) {
      final pod = e.podcastId.value;
      final guid = guidOf(e.id.value);
      final own = scopedId(pod, guid);
      final holder = owner[guid] ?? claimed[guid];
      final scoped = owner.containsKey(own) ||
          (holder != null && !await same(holder, pod));
      if (!scoped) claimed[guid] = pod;
      final id = scoped ? own : guid;
      out.add(id == e.id.value ? e : e.copyWith(id: Value(id)));
    }
    return out;
  }

  /// [podcastId]'s episode with the feed guid [guid] (or its stored id): its
  /// own [scopedId] row, else the bare one if it's that feed's.
  Future<Episode?> episodeOf(String podcastId, String guid) async {
    final g = guidOf(guid);
    final rows = await (select(episodes)
          ..where((e) => e.id.isIn([g, scopedId(podcastId, g)])))
        .get();
    final scoped = rows.where((r) => r.id != g).firstOrNull;
    if (scoped != null) return scoped;
    final bare = rows.firstOrNull;
    if (bare == null || bare.podcastId == podcastId) return bare;
    final a = await getPodcast(bare.podcastId);
    final b = await getPodcast(podcastId);
    return normFeed(a?.feedUrl ?? bare.podcastId) ==
            normFeed(b?.feedUrl ?? podcastId)
        ? bare
        : null;
  }

  /// Downloads the feed's audio isn't anymore: the same guid, other audio
  /// (a re-cut, a fixed upload, new ads) at another URL and of another
  /// length (not [sameAudio]). Never started, the file goes and the episode
  /// is marked to download again, on WiFi. A started one keeps its file, to
  /// be finished on the audio its position is in; the one in the player
  /// keeps its file and its old URL and length, so a later refresh looks
  /// again. A new URL alone (a tracking prefix) changes nothing.
  Future<List<EpisodesCompanion>> _dropReplacedAudio(
      List<EpisodesCompanion> eps) async {
    final byId = {for (final e in eps) e.id.value: e};
    final ids = byId.keys.toList();
    final rows = <Episode>[];
    for (var i = 0; i < ids.length; i += 500) {
      rows.addAll(await (select(episodes)
            ..where((e) =>
                e.id.isIn(ids.skip(i).take(500)) & e.isDownloaded.equals(true)))
          .get());
    }
    final stale = <String>[];
    for (final old in rows) {
      final now = byId[old.id]!;
      final url = now.audioUrl.present ? now.audioUrl.value : '';
      final length = now.durationSeconds.present ? now.durationSeconds.value : 0;
      if (old.lastPlayed != null || old.lastPositionMs > 0 || old.isFinished) {
        continue;
      }
      if (url.isEmpty || url == old.audioUrl) continue;
      if (old.durationSeconds <= 0 ||
          length <= 0 ||
          sameAudio(old.durationSeconds, length)) {
        continue;
      }
      if (old.id == livePositionEpisodeId) {
        byId[old.id] = now.copyWith(
            audioUrl: Value(old.audioUrl),
            durationSeconds: Value(old.durationSeconds));
        continue;
      }
      if (old.localPath != null) {
        final f = File(old.localPath!);
        if (f.existsSync()) f.deleteSync();
      }
      stale.add(old.id);
    }
    if (stale.isNotEmpty) {
      await (update(episodes)..where((e) => e.id.isIn(stale))).write(
        const EpisodesCompanion(
          isDownloaded: Value(false),
          localPath: Value(null),
          downloadTaskId: Value(null),
          markedForDownload: Value(true),
        ),
      );
    }
    return [for (final e in eps) byId[e.id.value]!];
  }

  Future<void> insertPodcast(PodcastsCompanion pod) =>
      into(podcasts).insertOnConflictUpdate(pod);

  /// Insert a temporary preview podcast. Uses insertOrIgnore so a real
  /// subscription is never downgraded to isSubscribed=false.
  Future<void> insertTempPodcast(PodcastsCompanion pod) =>
      into(podcasts).insert(
        pod.copyWith(isSubscribed: const Value(false)),
        mode: InsertMode.insertOrIgnore,
      );

  /// Unsubscribe & delete: the podcast, its episodes and their downloads go.
  /// Favourites stay, as a temp feed without downloads, until unmarked.
  Future<void> deletePodcast(String id) async {
    // Fetch the podcast first so we can delete episodes by feedUrl (the canonical
    // podcastId used in episodes) even if id was historically an iTunes ID.
    final pod = await (select(podcasts)..where((p) => p.id.equals(id))).getSingleOrNull();
    final feedUrl = pod?.feedUrl ?? id;
    Expression<bool> ofPodcast($EpisodesTable e) =>
        e.podcastId.equals(feedUrl) | e.podcastId.equals(id);

    final eps = await (select(episodes)
          ..where((e) => ofPodcast(e))
          ..where((e) => e.isDownloaded.equals(true)))
        .get();
    for (final ep in eps) {
      if (ep.localPath != null) {
        final f = File(ep.localPath!);
        try { if (f.existsSync()) f.deleteSync(); } catch (_) {}
      }
    }
    final keepFavorites = pod != null &&
        await (select(episodes)
                  ..where((e) => ofPodcast(e) & e.isFavorite.equals(true))
                  ..limit(1))
                .getSingleOrNull() !=
            null;
    await transaction(() async {
      await (delete(episodes)
            ..where((e) => ofPodcast(e) & e.isFavorite.equals(false)))
          .go();
      if (keepFavorites) {
        await (update(episodes)..where((e) => ofPodcast(e))).write(
            EpisodesCompanion(
                podcastId: Value(feedUrl),
                isSubscribed: const Value(false),
                isDownloaded: const Value(false),
                localPath: const Value(null),
                downloadTaskId: const Value(null),
                markedForDownload: const Value(false)));
        await (delete(podcasts)..where((p) => p.id.equals(id))).go();
        await into(podcasts).insertOnConflictUpdate(pod.toCompanion(true).copyWith(
              id: Value(feedUrl),
              isSubscribed: const Value(false),
              syncPaused: const Value(false),
            ));
      } else {
        await (delete(episodes)..where((e) => ofPodcast(e))).go();
        await (delete(podcasts)..where((p) => p.id.equals(id))).go();
      }
    });
  }

  // ── Episodes ──────────────────────────────────────────────────────────────

  /// Subscribed episodes and actively used temp ones (downloaded, started):
  /// the home feed before its filters.
  Stream<List<Episode>> watchAllFeedEpisodes() => _watchList(_inFeed);

  Stream<List<Episode>> watchEpisodesForPodcast(String podcastId) =>
      _watchList(episodes.podcastId.equals(podcastId));

  /// Episodes that are downloaded OR queued for WiFi download.
  /// Used when the user taps "Show marked for download" in the downloaded filter.
  Stream<List<Episode>> watchDownloadedOrMarkedEpisodes() => _watchList(
      (episodes.isDownloaded.equals(true) | episodes.markedForDownload.equals(true)) &
          _inFeed);

  Expression<bool> get _inFeed =>
      episodes.isSubscribed.equals(true) |
      episodes.isDownloaded.equals(true) |
      episodes.isFavorite.equals(true) |
      episodes.lastPositionMs.isBiggerThanValue(0);

  /// Every column but the show notes: kilobytes of HTML per episode that no
  /// list shows, read again by every list on every episode write.
  late final List<GeneratedColumn> _listColumns = [
    for (final c in episodes.$columns)
      if (c.$name != episodes.description.$name) c,
  ];

  /// Episodes matching [where], newest first, without their show notes: a
  /// list's Episode has description ''. What needs the notes (the player)
  /// reads the episode itself, see [getEpisode] and [watchEpisode].
  Stream<List<Episode>> _watchList(Expression<bool> where) {
    final query = selectOnly(episodes)
      ..addColumns(_listColumns)
      ..where(where)
      ..orderBy([OrderingTerm.desc(episodes.publishDate)]);
    return query
        .watch()
        .map((rows) => [
              for (final r in rows)
                episodes.map({...r.rawData.data, 'episodes.description': ''},
                    tablePrefix: 'episodes'),
            ])
        .distinct(_sameEpisodeList);
  }

  /// Upsert feed episodes: a row that's already there takes the feed's
  /// columns, except its duration once it was played. updatePlaybackPosition
  /// wrote the audio's own duration then, and RSS durations are often
  /// rounded, wrong or 0. Ids as [_ownIds] keeps them; returns them, in order.
  Future<List<String>> insertEpisodes(List<EpisodesCompanion> eps) =>
      transaction(() async {
        final own = await _ownIds(eps);
        await batch((b) => _upsertEpisodes(b, own));
        return [for (final e in own) e.id.value];
      });

  void _upsertEpisodes(Batch b, Iterable<EpisodesCompanion> eps) {
    for (final e in eps) {
      b.insert(
        episodes,
        e,
        onConflict:
            DoUpdate<$EpisodesTable, Episode>.withExcluded((old, excluded) {
          final cols = e.toColumns(true)..remove('id');
          if (cols.containsKey('duration_seconds')) {
            cols['duration_seconds'] = CaseWhenExpression<int>(
              cases: [
                CaseWhen(
                  old.lastPlayed.isNotNull() &
                      old.durationSeconds.isBiggerThanValue(0),
                  then: old.durationSeconds,
                ),
              ],
              orElse: excluded.durationSeconds,
            );
          }
          return RawValuesInsertable<Episode>(cols);
        }),
      );
    }
  }

  /// Saves what refreshing some subscribed feeds found, in one transaction so
  /// the lists update once: their [episodes] (upserted like [insertEpisodes])
  /// and each podcast's new columns in [podcastUpdates] (cover, validators,
  /// failure count), by podcast id. A podcast unsubscribed while its feed
  /// loaded is skipped, so its episodes don't come back as subscribed.
  Future<void> saveFeedRefresh(List<EpisodesCompanion> episodes,
      Map<String, PodcastsCompanion> podcastUpdates) async {
    final updates = {
      for (final MapEntry(key: id, value: update) in podcastUpdates.entries)
        if (update.toColumns(false).isNotEmpty) id: update,
    };
    if (episodes.isEmpty && updates.isEmpty) return;
    await transaction(() async {
      final live = {for (final p in await getAllPodcasts()) p.id};
      final own = await _dropReplacedAudio(await _ownIds([
        for (final e in episodes)
          if (live.contains(e.podcastId.value)) e,
      ]));
      final feeds = <String, List<EpisodesCompanion>>{};
      for (final e in own) {
        feeds.putIfAbsent(e.podcastId.value, () => []).add(e);
      }
      await batch((b) {
        _upsertEpisodes(b, feeds.values.expand((f) => f));
        for (final MapEntry(key: id, value: update) in updates.entries) {
          if (live.contains(id)) {
            b.update(podcasts, update, where: (p) => p.id.equals(id));
          }
        }
      });
      for (final MapEntry(key: id, value: feed) in feeds.entries) {
        await _mergeRepublished(id, feed);
      }
    });
  }

  /// Episodes a feed has under another guid now (see twinOf): Legion's
  /// guid is the mp3's URL, and a re-upload got a new one; a host moved, a
  /// guid-less item's title was fixed, a feed listed one twice (see
  /// distinctItems), an Apple search stub. Rows the feed no longer has, from
  /// within its span: one that aged out of a feed keeping just its latest
  /// isn't republished, even under the same title (news). See [_foldInto].
  Future<void> _mergeRepublished(
      String podcastId, List<EpisodesCompanion> feed) async {
    final facts = [for (final e in feed) itemFacts(e)];
    final dates = [for (final f in facts) if (f.date != null) f.date!];
    final oldest = dates.isEmpty
        ? null
        : dates.reduce((a, b) => a.isBefore(b) ? a : b)
            .subtract(const Duration(days: 1));
    final gone = await (select(episodes)
          ..where((e) =>
              e.podcastId.equals(podcastId) &
              (oldest == null
                  ? const Constant(true)
                  : e.publishDate.isBiggerOrEqualValue(oldest)) &
              e.id.isNotIn(facts.map((f) => f.id))))
        .get();
    for (final old in gone) {
      final twin = twinOf(rowFacts(old), facts);
      final now = twin == null ? null : await getEpisode(twin);
      if (now != null) await _foldInto(old, now);
    }
  }

  /// [old], the same episode as the feed's [now] under another guid:
  /// - Busy (in the player, downloading), or started on audio that isn't
  ///   [sameAudio] (an edit): kept as a temp episode, off the feed, to be
  ///   finished on its own audio; then it folds in (markFinished), or a
  ///   later refresh folds it ([foldOffFeedTwins]), or the temp rules take it.
  /// - Else [now] takes its played state (position, finished), unless [now]
  ///   was played since on its own, and its file; [old] goes.
  /// A favourite or WiFi mark moves to [now] either way. [done]: [old] was
  /// just finished in the player, which closes.
  Future<void> _foldInto(Episode old, Episode now, {bool done = false}) async {
    if (old.isFavorite && !now.isFavorite) await setFavorite(now.id, true);
    // A finished download keeps its task id.
    bool downloading(Episode e) => e.downloadTaskId != null && !e.isDownloaded;
    final busy = old.id == livePositionEpisodeId || downloading(old);
    final started =
        !old.isFinished && (old.isDownloaded || old.lastPositionMs > 0);
    if (!done &&
        (busy ||
            (started && !sameAudio(old.durationSeconds, now.durationSeconds)))) {
      if (old.isSubscribed || old.isFavorite) {
        await (update(episodes)..where((e) => e.id.equals(old.id))).write(
            const EpisodesCompanion(
                isSubscribed: Value(false), isFavorite: Value(false)));
      }
      return;
    }
    final played = old.isFinished || old.lastPositionMs > 0;
    final nowPlayed = now.lastPlayed != null || now.lastPositionMs > 0;
    final takePlayed = played &&
        (!nowPlayed ||
            (old.lastPlayed != null &&
                now.lastPlayed != null &&
                old.lastPlayed!.isAfter(now.lastPlayed!)));
    final free = !now.isDownloaded && !downloading(now);
    final takeFile = old.isDownloaded && free;
    if (old.isDownloaded && !takeFile && old.localPath != null) {
      final f = File(old.localPath!);
      if (f.existsSync()) f.deleteSync();
    }
    await (update(episodes)..where((e) => e.id.equals(now.id)))
        .write(EpisodesCompanion(
      isFinished: takePlayed ? Value(old.isFinished) : const Value.absent(),
      lastPositionMs:
          takePlayed ? Value(old.lastPositionMs) : const Value.absent(),
      playbackPositionSeconds: takePlayed
          ? Value(old.playbackPositionSeconds)
          : const Value.absent(),
      lastPlayed: takePlayed ? Value(old.lastPlayed) : const Value.absent(),
      isDownloaded: takeFile ? const Value(true) : const Value.absent(),
      localPath: takeFile ? Value(old.localPath) : const Value.absent(),
      markedForDownload: old.markedForDownload && free && !old.isFinished
          ? const Value(true)
          : const Value.absent(),
    ));
    await (delete(episodes)..where((e) => e.id.equals(old.id))).go();
  }

  /// The off-feed copies subscribed podcasts keep of episodes their feeds
  /// have under another guid ([_foldInto] left them in use) fold in once
  /// they're free. A refresh runs this even when no feed changed: an
  /// unchanged feed isn't parsed, so nothing else would look again.
  Future<void> foldOffFeedTwins([String? podcastId]) => transaction(() async {
        final subscribed = [
          for (final p in await getAllPodcasts())
            if (podcastId == null || p.id == podcastId) p.id,
        ];
        if (subscribed.isEmpty) return;
        final off = await (select(episodes)
              ..where((e) =>
                  e.isSubscribed.equals(false) &
                  e.podcastId.isIn(subscribed)))
            .get();
        final byPodcast = <String, List<Episode>>{};
        for (final e in off) {
          byPodcast.putIfAbsent(e.podcastId, () => []).add(e);
        }
        for (final MapEntry(key: id, value: olds) in byPodcast.entries) {
          final rows = await (select(episodes)
                ..where((e) =>
                    e.podcastId.equals(id) & e.isSubscribed.equals(true)))
              .get();
          final facts = rows.map(rowFacts).toList();
          for (final old in olds) {
            final twin = twinOf(rowFacts(old), facts);
            final now = twin == null ? null : await getEpisode(twin);
            if (now != null) await _foldInto(old, now);
          }
        }
      });

  /// A temp episode just finished, the off-feed copy of one its subscribed
  /// feed has under another guid (or a search stub): it folds into that
  /// one, so it isn't new there and isn't listed twice. Whether it did.
  Future<bool> _foldIntoTwin(String id) async {
    final old = await getEpisode(id);
    if (old == null || old.isSubscribed) return false;
    final rows = await (select(episodes)
          ..where((e) =>
              e.podcastId.equals(old.podcastId) &
              e.isSubscribed.equals(true)))
        .get();
    final twin = twinOf(rowFacts(old), rows.map(rowFacts));
    if (twin == null) return false;
    await _foldInto(old, rows.firstWhere((r) => r.id == twin), done: true);
    await cleanupTempFeedIfDone(old.podcastId);
    return true;
  }

  /// Counts one more failed refresh for each podcast in [ids].
  Future<void> countFeedFailures(List<String> ids) =>
      (update(podcasts)..where((p) => p.id.isIn(ids))).write(
          PodcastsCompanion.custom(
              feedFailures: podcasts.feedFailures + const Constant(1)));

  /// Failed refreshes in a row (while others loaded) before a podcast's page
  /// says its feed isn't loading: one bad refresh is just a server hiccup.
  static const feedFailingAfter = 3;

  /// Whether [podcastId]'s feed has failed [feedFailingAfter] refreshes in a row.
  Stream<bool> watchFeedFailing(String podcastId) =>
      (select(podcasts)..where((p) => p.id.equals(podcastId)))
          .watchSingleOrNull()
          .map((p) => (p?.feedFailures ?? 0) >= feedFailingAfter)
          .distinct();

  /// A row that's already there (subscribed, played, downloaded) is kept,
  /// except for its chapters link: a fresh one from the feed wins, and none
  /// (search results carry none) leaves the old one. Ids as [_ownIds] keeps
  /// them; returns them, in order.
  Future<List<String>> insertTempEpisodes(List<EpisodesCompanion> eps) =>
      transaction(() async {
        final own = await _ownIds(eps);
        await batch((b) => b.insertAll(
              episodes,
              own.map((e) => e.copyWith(isSubscribed: const Value(false))).toList(),
              onConflict: DoUpdate<$EpisodesTable, Episode>.withExcluded(
                  (old, excluded) => EpisodesCompanion.custom(
                      chaptersUrl:
                          coalesce([excluded.chaptersUrl, old.chaptersUrl]))),
            ));
        return [for (final e in own) e.id.value];
      });

  /// Only promotes temp episodes that were played, finished or downloaded to
  /// subscribed. Other temp episodes (Apple search results, preview inserts)
  /// are left alone so they don't appear as duplicates alongside the real RSS
  /// episodes.
  Future<void> markEpisodesSubscribed(String podcastId) =>
      (update(episodes)
            ..where((e) =>
                e.podcastId.equals(podcastId) &
                (e.lastPositionMs.isBiggerThanValue(0) |
                    e.isFinished.equals(true) |
                    e.isDownloaded.equals(true))))
          .write(const EpisodesCompanion(isSubscribed: Value(true)));

  /// Match Apple episode stubs (id prefix 'apple-') to the real RSS episodes
  /// for the same feed by title. Migrates playback progress to the RSS episode,
  /// then deletes the stubs. Call after inserting RSS episodes for a feed.
  /// Returns {appleId → rssGuid} for every stub that was resolved.
  Future<Map<String, String>> migrateAppleEpisodeStubs(String podcastId) async {
    final stubs = await (select(episodes)
          ..where((e) => e.podcastId.equals(podcastId) & e.id.like('apple-%')))
        .get();
    if (stubs.isEmpty) return {};

    final rssEps = await (select(episodes)
          ..where((e) => e.podcastId.equals(podcastId) & e.id.like('apple-%').not()))
        .get();

    final migrated = <String, String>{};
    for (final stub in stubs) {
      final stubTitle = stub.title.toLowerCase().trim();
      final match = rssEps.where(
        (e) => e.title.toLowerCase().trim() == stubTitle,
      ).firstOrNull;
      if (match != null) {
        if (stub.lastPositionMs > match.lastPositionMs) {
          await updatePlaybackPosition(match.id,
              positionMs: stub.lastPositionMs,
              durationMs: stub.durationSeconds * 1000);
        }
        if (stub.isFinished && !match.isFinished) await markFinished(match.id);
        if (stub.isFavorite && !match.isFavorite) await setFavorite(match.id, true);
        migrated[stub.id] = match.id;
      }
      await (delete(episodes)..where((e) => e.id.equals(stub.id))).go();
    }
    return migrated;
  }

  /// Subscribe to [podcast] with its freshly fetched [rssEpisodes] (already
  /// tagged subscribed), in one transaction so episode watchers see a single
  /// change: an open preview list updates in place instead of emptying and
  /// refilling. Preview rows share the RSS ids and are simply upserted;
  /// played/finished temp rows are promoted; Apple search stubs hand their
  /// progress to the matching RSS episode and go; other unplayed temp rows
  /// that aren't in the feed are dropped.
  /// Without [rssEpisodes] (feed fetch failed) the preview's rows are all we
  /// have of the feed, so they're promoted and stubs wait for a later fetch.
  /// Returns {appleStubId → rssGuid} like [migrateAppleEpisodeStubs].
  Future<Map<String, String>> subscribePodcast(
      PodcastsCompanion podcast, List<EpisodesCompanion> rssEpisodes) {
    final id = podcast.id.value;
    return transaction(() async {
      // A fresh start for the refresh: a preview or a previously finished
      // feed's validators may not match the episodes kept.
      await insertPodcast(podcast.copyWith(
        feedEtag: const Value(null),
        feedLastModified: const Value(null),
        feedHash: const Value(null),
        feedFailures: const Value(0),
      ));
      await markEpisodesSubscribed(id);
      if (rssEpisodes.isEmpty) {
        await (update(episodes)
              ..where((e) => e.podcastId.equals(id) & e.id.like('apple-%').not()))
            .write(const EpisodesCompanion(isSubscribed: Value(true)));
        return const <String, String>{};
      }
      final own = await _dropReplacedAudio(await _ownIds(rssEpisodes));
      await batch((b) => _upsertEpisodes(b, own));
      final migrated = await migrateAppleEpisodeStubs(id);
      final inFeed = {for (final e in own) e.id.value};
      final leftovers = await (select(episodes)
            ..where((e) =>
                e.podcastId.equals(id) &
                e.isSubscribed.equals(false) &
                e.lastPositionMs.equals(0) &
                e.isFinished.equals(false) &
                e.isDownloaded.equals(false)))
          .get();
      final stale = [for (final e in leftovers) if (!inFeed.contains(e.id)) e.id];
      if (stale.isNotEmpty) {
        await (delete(episodes)..where((e) => e.id.isIn(stale))).go();
      }
      return migrated;
    });
  }

  /// Save the resume position (ms + seconds). It never marks the episode as
  /// played: only a pause in the last 100 s or the natural end does that
  /// (PlayerProvider), so the periodic saves can't close the player early.
  /// A save before the last 100 s un-marks it: it's being listened again.
  Future<void> updatePlaybackPosition(
    String id, {
    required int positionMs,
    required int durationMs,
  }) async {
    final posSeconds = positionMs ~/ 1000;
    final nearEnd = durationMs > 0 && positionMs >= durationMs - AppSettings.nearEnd.inMilliseconds;

    await (update(episodes)..where((e) => e.id.equals(id))).write(
      EpisodesCompanion(
        lastPositionMs: Value(positionMs),
        playbackPositionSeconds: Value(posSeconds),
        isFinished: nearEnd ? const Value.absent() : const Value(false),
        lastPlayed: Value(DateTime.now()),
        // Keep durationSeconds in sync with actual audio — RSS values are often
        // rounded or wrong, causing the progress bar to exceed 100%.
        durationSeconds: durationMs > 0 ? Value(durationMs ~/ 1000) : const Value.absent(),
      ),
    );
  }

  /// Explicitly mark episode as finished (e.g. after natural completion).
  /// Also clears any pending WiFi download queue — no point downloading
  /// something the user has already listened to.
  /// A temp episode with a twin in its subscribed feed folds into it
  /// (see [_foldIntoTwin]).
  Future<void> markFinished(String id) async {
    await (update(episodes)..where((e) => e.id.equals(id))).write(
      EpisodesCompanion(
        isFinished: const Value(true),
        lastPlayed: Value(DateTime.now()),
        markedForDownload: const Value(false),
      ),
    );
    await _foldIntoTwin(id);
  }

  /// Whether [id] is a favourite, as it changes; false once it's gone.
  Stream<bool> watchFavorite(String id) {
    final q = selectOnly(episodes)
      ..addColumns([episodes.isFavorite])
      ..where(episodes.id.equals(id));
    return q
        .map((r) => r.read(episodes.isFavorite) ?? false)
        .watchSingleOrNull()
        .map((v) => v ?? false)
        .distinct();
  }

  Future<void> setFavorite(String id, bool favorite) =>
      (update(episodes)..where((e) => e.id.equals(id)))
          .write(EpisodesCompanion(isFavorite: Value(favorite)));

  /// Episodes with something worth keeping: a position, played, a favourite.
  Future<List<Episode>> getEpisodesWithState() => (select(episodes)
        ..where((e) =>
            e.lastPositionMs.isBiggerThanValue(0) |
            e.isFinished.equals(true) |
            e.isFavorite.equals(true)))
      .get();

  /// [podcastId]'s episode with [audioUrl]: the same episode when its guid
  /// changed.
  Future<Episode?> findEpisodeByAudio(String podcastId, String audioUrl) =>
      (select(episodes)
            ..where((e) => e.podcastId.equals(podcastId) & e.audioUrl.equals(audioUrl))
            ..limit(1))
          .getSingleOrNull();

  /// A backup's play state, as it was: unlike [updatePlaybackPosition] the
  /// time it was last played stays the backup's, so the newer of two merged
  /// states can still be told.
  Future<void> restorePlayState(
    String id, {
    required int positionMs,
    required bool finished,
    required DateTime? lastPlayed,
    int durationSeconds = 0,
  }) =>
      (update(episodes)..where((e) => e.id.equals(id))).write(EpisodesCompanion(
        lastPositionMs: Value(positionMs),
        playbackPositionSeconds: Value(positionMs ~/ 1000),
        isFinished: Value(finished),
        lastPlayed: Value(lastPlayed),
        durationSeconds:
            durationSeconds > 0 ? Value(durationSeconds) : const Value.absent(),
        markedForDownload: finished ? const Value(false) : const Value.absent(),
      ));

  /// Explicitly mark episode as unfinished (reset).
  Future<void> markUnfinished(String id) =>
      (update(episodes)..where((e) => e.id.equals(id))).write(
        const EpisodesCompanion(
          isFinished: Value(false),
          lastPositionMs: Value(0),
          playbackPositionSeconds: Value(0),
          lastPlayed: Value(null),
        ),
      );

  Future<void> updateEpisodeDownload(
      String id, bool downloaded, String? path, String? taskId) =>
      (update(episodes)..where((e) => e.id.equals(id))).write(
        EpisodesCompanion(
          isDownloaded: Value(downloaded),
          localPath: Value(path),
          downloadTaskId: Value(taskId),
          // Clear the WiFi queue mark once an actual download starts/completes
          markedForDownload: const Value(false),
        ),
      );

  Future<void> markForDownload(String id) =>
      (update(episodes)..where((e) => e.id.equals(id))).write(
        const EpisodesCompanion(markedForDownload: Value(true)),
      );

  /// Re-queue a single episode after its download failed mid-session.
  /// Clears the stale taskId and sets markedForDownload so the dotted bar
  /// appears immediately without requiring an app restart.
  Future<void> requeueEpisodeForDownload(String id) =>
      (update(episodes)..where((e) => e.id.equals(id))).write(
        const EpisodesCompanion(
          downloadTaskId: Value(null),
          markedForDownload: Value(true),
        ),
      );

  Future<void> clearMarkedForDownload(String id) =>
      (update(episodes)..where((e) => e.id.equals(id))).write(
        const EpisodesCompanion(markedForDownload: Value(false)),
      );

  /// Episodes with a download task that hasn't completed yet (as recorded
  /// here; DownloadProvider.restore() checks the task's real state).
  Future<List<Episode>> getPendingDownloads() =>
      (select(episodes)
            ..where((e) =>
                e.downloadTaskId.isNotNull() & e.isDownloaded.equals(false)))
          .get();

  Future<List<Episode>> getMarkedForDownloadEpisodes() =>
      (select(episodes)
            ..where((e) => e.markedForDownload.equals(true))
            ..orderBy([(e) => OrderingTerm.desc(e.publishDate)]))
          .get();

  Stream<int> watchMarkedForDownloadCount() {
    final count = episodes.id.count();
    return (selectOnly(episodes)
          ..addColumns([count])
          ..where(episodes.markedForDownload.equals(true)))
        .watchSingle()
        .map((row) => row.read(count) ?? 0)
        .distinct();
  }

  Stream<int> watchDownloadedEpisodeCount() {
    final count = episodes.id.count();
    return (selectOnly(episodes)
          ..addColumns([count])
          ..where(episodes.isDownloaded.equals(true)))
        .watchSingle()
        .map((row) => row.read(count) ?? 0)
        .distinct();
  }

  /// User-initiated "delete download": removes the file, and for a temp
  /// episode lets its preview feed go once nothing in it is left to keep.
  Future<void> deleteDownload(String id) async {
    final ep = await (select(episodes)..where((e) => e.id.equals(id)))
        .getSingleOrNull();
    if (ep == null) return;
    if (ep.localPath != null) {
      final f = File(ep.localPath!);
      if (f.existsSync()) f.deleteSync();
    }
    await (update(episodes)..where((e) => e.id.equals(id))).write(
      const EpisodesCompanion(
        isDownloaded: Value(false),
        localPath: Value(null),
        downloadTaskId: Value(null),
      ),
    );
    if (!ep.isSubscribed) await cleanupTempFeedIfDone(ep.podcastId);
  }

  /// Delete local files of episodes finished more than 2 days ago, temp ones
  /// included (those stay in history until their feed's week is up, see
  /// cleanupStaleTempEpisodes). Favourites keep theirs.
  Future<void> deleteFinishedDownloads() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 2));
    final finished = await (select(episodes)
          ..where((e) =>
              e.isFinished.equals(true) &
              e.isDownloaded.equals(true) &
              e.isFavorite.equals(false) &
              e.lastPlayed.isSmallerThanValue(cutoff)))
        .get();
    if (finished.isEmpty) return;
    for (final ep in finished) {
      if (ep.localPath != null) {
        final f = File(ep.localPath!);
        if (f.existsSync()) f.deleteSync();
      }
    }
    final ids = finished.map((e) => e.id).toList();
    await (update(episodes)..where((e) => e.id.isIn(ids))).write(
      const EpisodesCompanion(
        isDownloaded: Value(false),
        localPath: Value(null),
        downloadTaskId: Value(null),
      ),
    );
  }

  /// Delete stale temp episodes and orphaned podcasts.
  ///
  /// A temp feed that was played goes once nothing in it is in use any more
  /// (see [_tempFeedInUse]): a week after its last play.
  /// Played episodes: removed 7 days after last playback.
  /// Never-started episodes: removed if publish date is >7 days old.
  /// In-progress episodes (started but not finished) and favourites are
  /// always kept, and so is [keepId] (the loaded episode, e.g. an old one just
  /// opened from a link).
  /// With [keepPlayedDownloads] (auto-delete switched off in the settings) a
  /// played episode stays as long as it's downloaded.
  Future<void> cleanupStaleTempEpisodes(
      {String? keepId, bool keepPlayedDownloads = false}) async {
    final cutoff = DateTime.now().subtract(_tempWeek);

    // Feeds first, while their played episodes still say when they were
    // last played.
    final tempPods = await (select(podcasts)
          ..where((p) => p.isSubscribed.equals(false)))
        .get();
    for (final pod in tempPods) {
      final eps = await (select(episodes)
            ..where((e) => e.podcastId.equals(pod.id)))
          .get();
      if (eps.isNotEmpty) {
        if (_tempFeedInUse(eps, keepId: keepId)) continue;
        // Never played, only browsed: its episodes age out below, and the
        // feed with the last of them.
        if (eps.every((e) => e.lastPlayed == null)) continue;
      }
      await _purgeTempFeed(pod.id, eps);
    }

    final stale = await (select(episodes)
          ..where((e) =>
              e.isSubscribed.equals(false) &
              e.isFavorite.equals(false) &
              (keepId == null ? const Constant(true) : e.id.equals(keepId).not()) &
              (
                // Played: wait 7 days from last playback before removing
                (e.isFinished.equals(true) &
                    (keepPlayedDownloads
                        ? e.isDownloaded.equals(false)
                        : const Constant(true)) &
                    e.lastPlayed.isSmallerThanValue(cutoff)) |
                // Never started: no play mark and old content. Downloaded
                // ones stay — the user fetched them to listen later.
                (e.lastPositionMs.equals(0) &
                    e.isFinished.equals(false) &
                    e.isDownloaded.equals(false) &
                    e.publishDate.isSmallerThanValue(cutoff))
              )))
        .get();

    if (stale.isNotEmpty) {
      for (final ep in stale) {
        if (ep.localPath != null) {
          final f = File(ep.localPath!);
          if (f.existsSync()) f.deleteSync();
        }
      }
      final ids = stale.map((e) => e.id).toList();
      await (delete(episodes)..where((e) => e.id.isIn(ids))).go();
    }

    // Feeds whose last episodes just aged out.
    for (final pod in tempPods) {
      final left = await (select(episodes)
            ..where((e) => e.podcastId.equals(pod.id))
            ..limit(1))
          .get();
      if (left.isEmpty) {
        await (delete(podcasts)..where((p) => p.id.equals(pod.id))).go();
      }
    }
  }

  static const _tempWeek = Duration(days: 7);

  /// Podcasts whose episode list is on screen (EpisodeFeed): their temp feed
  /// isn't purged from under it; the startup cleanup takes it later.
  final openFeeds = <String>[];

  /// Whether something in a temp feed is still in use: an episode loaded in
  /// the player ([keepId]), a favourite, downloaded or on its way, in
  /// progress, or played within the past week.
  static bool _tempFeedInUse(List<Episode> eps, {String? keepId}) {
    final cutoff = DateTime.now().subtract(_tempWeek);
    return eps.any((e) =>
        e.id == keepId ||
        e.isFavorite ||
        e.isDownloaded ||
        e.markedForDownload ||
        e.downloadTaskId != null ||
        (e.lastPositionMs > 0 && !e.isFinished) ||
        (e.lastPlayed?.isAfter(cutoff) ?? false));
  }

  /// Delete a temp podcast with all its episodes and their files.
  Future<void> _purgeTempFeed(String podcastId, List<Episode> eps) async {
    for (final ep in eps) {
      if (ep.localPath != null) {
        final f = File(ep.localPath!);
        if (f.existsSync()) f.deleteSync();
      }
    }
    if (eps.isNotEmpty) {
      final ids = eps.map((e) => e.id).toList();
      await (delete(episodes)..where((e) => e.id.isIn(ids))).go();
    }
    await (delete(podcasts)..where((p) => p.id.equals(podcastId))).go();
  }

  /// Mark as played from the menu. A temp episode is deleted instead, and
  /// its feed with it when nothing else in it is in use; a favourite stays.
  Future<void> markPlayedByUser(String id) async {
    final ep = await getEpisode(id);
    if (ep == null) return;
    if (ep.isSubscribed || ep.isFavorite) return markFinished(id);
    await markFinished(id); // folds into a twin in its feed, if it has one
    await cleanupTempEpisode(id);
  }

  Future<void> cleanupTempEpisode(String id) async {
    final ep = await (select(episodes)..where((e) => e.id.equals(id)))
        .getSingleOrNull();
    if (ep == null) return;
    if (!ep.isSubscribed) {
      if (ep.localPath != null) {
        final f = File(ep.localPath!);
        if (f.existsSync()) f.deleteSync();
      }
      await (delete(episodes)..where((e) => e.id.equals(id))).go();
      await cleanupTempFeedIfDone(ep.podcastId);
    }
  }

  /// Remove a temp episode (swipe or menu): its play state, download and
  /// favourite mark go, as if it had never been played. The row stays, so its
  /// preview feed still lists it; the home feed, which shows temp episodes
  /// only while they're in use, drops it. The startup cleanup deletes the row
  /// once it's stale.
  Future<void> resetTempEpisode(String id) async {
    final ep = await (select(episodes)..where((e) => e.id.equals(id)))
        .getSingleOrNull();
    if (ep == null || ep.isSubscribed) return;
    if (ep.localPath != null) {
      final f = File(ep.localPath!);
      if (f.existsSync()) f.deleteSync();
    }
    await (update(episodes)..where((e) => e.id.equals(id))).write(
      const EpisodesCompanion(
        isFinished: Value(false),
        lastPositionMs: Value(0),
        playbackPositionSeconds: Value(0),
        lastPlayed: Value(null),
        isDownloaded: Value(false),
        localPath: Value(null),
        downloadTaskId: Value(null),
        markedForDownload: Value(false),
        isFavorite: Value(false),
      ),
    );
  }

  /// Delete a temp podcast and all its episodes right away if nothing in it
  /// is in use ([_tempFeedInUse]) and its list isn't open. Called after a
  /// temp episode is marked as played or its download is deleted.
  Future<void> cleanupTempFeedIfDone(String podcastId) async {
    if (openFeeds.contains(podcastId)) return;
    final pod = await (select(podcasts)
          ..where((p) => p.id.equals(podcastId)))
        .getSingleOrNull();
    if (pod == null || pod.isSubscribed) return;

    final eps = await (select(episodes)
          ..where((e) => e.podcastId.equals(podcastId)))
        .get();
    if (_tempFeedInUse(eps)) return;
    await _purgeTempFeed(podcastId, eps);
  }

  /// Something left to finish: downloaded, or started but not finished. The
  /// unsubscribe sheet offers "finish episodes" only when an episode passes.
  static bool isKeepWorthy(Episode e) =>
      e.isDownloaded || (e.lastPositionMs > 0 && !e.isFinished);

  /// Whether the unsubscribed feed [podcastId] still has episodes to finish
  /// (the [isKeepWorthy] test): its header then says it's being finished.
  Stream<bool> watchHasEpisodesToFinish(String podcastId) =>
      (select(episodes)
            ..where((e) =>
                e.podcastId.equals(podcastId) &
                e.isSubscribed.equals(false) &
                (e.isDownloaded.equals(true) |
                    (e.lastPositionMs.isBiggerThanValue(0) &
                        e.isFinished.equals(false))))
            ..limit(1))
          .watch()
          .map((rows) => rows.isNotEmpty)
          .distinct();

  /// Unsubscribe, finish episodes: the podcast and all its episodes become
  /// temp, with play state, downloads and the list itself untouched. Only the
  /// flags change; the usual temp cleanup takes the feed once it's played out.
  Future<void> demoteToTempFeed(Podcast pod) {
    final feedUrl = pod.feedUrl;
    return transaction(() async {
      await (update(episodes)
            ..where((e) => e.podcastId.equals(pod.id) | e.podcastId.equals(feedUrl)))
          .write(EpisodesCompanion(
              podcastId: Value(feedUrl),
              isSubscribed: const Value(false),
              markedForDownload: const Value(false)));
      // Re-key on feedUrl (legacy rows may use an iTunes id) as a temp feed.
      await (delete(podcasts)..where((p) => p.id.equals(pod.id))).go();
      await into(podcasts).insertOnConflictUpdate(pod.toCompanion(true).copyWith(
            id: Value(feedUrl),
            isSubscribed: const Value(false),
            syncPaused: const Value(false),
          ));
    });
  }

  Future<void> setPodcastSyncPaused(String id, bool paused) =>
      (update(podcasts)..where((p) => p.id.equals(id)))
          .write(PodcastsCompanion(syncPaused: Value(paused)));

  Future<Episode?> getEpisode(String id) =>
      (select(episodes)..where((e) => e.id.equals(id))).getSingleOrNull();

  Stream<Episode?> watchEpisode(String id) =>
      (select(episodes)..where((e) => e.id.equals(id))).watchSingleOrNull();
}
