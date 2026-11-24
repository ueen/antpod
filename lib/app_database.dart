// lib/app_database.dart
//
// Schema version: 7
//   v1 → v2: Episodes.isSubscribed added
//   v2 → v3: Episodes.isFinished added (true = fully listened)
//            Episodes.lastPositionMs added (millisecond precision resume point)
//   v3 → v4: Episodes.chaptersUrl added
//   v4 → v5: Episodes.lastPlayed added (timestamp of most recent playback)
//   v5 → v6: Episodes.markedForDownload added (queued for WiFi download)
//   v6 → v7: Podcasts.isSubscribed added (false = temporary preview feed)
//
// Regenerate after schema changes:
//   dart run build_runner build --delete-conflicting-outputs

import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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

  @override
  Set<Column> get primaryKey => {id};
}

class Episodes extends Table {
  TextColumn get id => text()();
  TextColumn get podcastId => text()();
  TextColumn get podcastTitle => text()();
  TextColumn get podcastImageUrl => text()();
  TextColumn get title => text()();
  TextColumn get description => text()();
  TextColumn get audioUrl => text()();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  DateTimeColumn get publishDate => dateTime()();
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

  /// URL of the PodcastIndex chapters JSON file, if the episode has chapters.
  TextColumn get chaptersUrl => text().nullable()();

  /// Timestamp of the most recent playback interaction.
  /// Null if the episode has never been played.
  DateTimeColumn get lastPlayed => dateTime().nullable()();

  /// true = queued to download the next time WiFi is available.
  BoolColumn get markedForDownload =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── Stream helpers ───────────────────────────────────────────────────────────

// Structural equality for episode lists: propagates changes to fields that affect
// filtering or display, but ignores lastPositionMs / playbackPositionSeconds so
// the 5-second position-save writes don't trigger downstream rebuilds.
bool _episodeListEqual(List<Episode> a, List<Episode> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    final x = a[i]; final y = b[i];
    if (x.id != y.id ||
        x.isFinished != y.isFinished ||
        x.isDownloaded != y.isDownloaded ||
        x.markedForDownload != y.markedForDownload ||
        x.durationSeconds != y.durationSeconds ||
        x.localPath != y.localPath) return false;
  }
  return true;
}

// ─── Database ─────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [Podcasts, Episodes])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'antpod'));

  @override
  int get schemaVersion => 7;

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
    },
  );

  // ── Podcasts ──────────────────────────────────────────────────────────────

  Stream<List<Podcast>> watchAllPodcasts() =>
      (select(podcasts)
            ..where((p) => p.isSubscribed.equals(true))
            ..orderBy([(p) => OrderingTerm.asc(p.title)]))
          .watch();

  Future<List<Podcast>> getAllPodcasts() =>
      (select(podcasts)..where((p) => p.isSubscribed.equals(true))).get();

  Future<void> insertPodcast(PodcastsCompanion pod) =>
      into(podcasts).insertOnConflictUpdate(pod);

  /// Insert a temporary preview podcast. Uses insertOrIgnore so a real
  /// subscription is never downgraded to isSubscribed=false.
  Future<void> insertTempPodcast(PodcastsCompanion pod) =>
      into(podcasts).insert(
        pod.copyWith(isSubscribed: const Value(false)),
        mode: InsertMode.insertOrIgnore,
      );

  Future<void> deletePodcast(String id) async {
    // Fetch the podcast first so we can delete episodes by feedUrl (the canonical
    // podcastId used in episodes) even if id was historically an iTunes ID.
    final pod = await (select(podcasts)..where((p) => p.id.equals(id))).getSingleOrNull();
    final feedUrl = pod?.feedUrl ?? id;

    final eps = await (select(episodes)
          ..where((e) => e.podcastId.equals(feedUrl) | e.podcastId.equals(id))
          ..where((e) => e.isDownloaded.equals(true)))
        .get();
    for (final ep in eps) {
      if (ep.localPath != null) {
        final f = File(ep.localPath!);
        try { if (f.existsSync()) f.deleteSync(); } catch (_) {}
      }
    }
    await (delete(episodes)
          ..where((e) => e.podcastId.equals(feedUrl) | e.podcastId.equals(id)))
        .go();
    await (delete(podcasts)..where((p) => p.id.equals(id))).go();
  }

  // ── Episodes ──────────────────────────────────────────────────────────────

  /// Default feed: subscribed or actively-used temp episodes, not yet finished.
  Stream<List<Episode>> watchUnfinishedEpisodes({bool downloadedOnly = false}) {
    return (select(episodes)
          ..where((e) {
            final base = e.isFinished.equals(false) &
                (e.isSubscribed.equals(true) |
                 e.isDownloaded.equals(true) |
                 e.lastPositionMs.isBiggerThanValue(0));
            return downloadedOnly ? base & e.isDownloaded.equals(true) : base;
          })
          ..orderBy([(e) => OrderingTerm.desc(e.publishDate)]))
        .watch();
  }

  /// All subscribed + actively-used temp episodes (no finished filter).
  Stream<List<Episode>> watchAllFeedEpisodes({bool downloadedOnly = false}) {
    return (select(episodes)
          ..where((e) {
            final base = e.isSubscribed.equals(true) |
                e.isDownloaded.equals(true) |
                e.lastPositionMs.isBiggerThanValue(0);
            return downloadedOnly ? base & e.isDownloaded.equals(true) : base;
          })
          ..orderBy([(e) => OrderingTerm.desc(e.publishDate)]))
        .watch()
        .distinct(_episodeListEqual);
  }

  /// Finished/played episodes (history view). Includes temp episodes still within
  /// the 7-day cleanup window so they appear in history until automatically removed.
  Stream<List<Episode>> watchFinishedEpisodes({bool downloadedOnly = false}) {
    return (select(episodes)
          ..where((e) {
            final base = e.isFinished.equals(true);
            return downloadedOnly ? base & e.isDownloaded.equals(true) : base;
          })
          ..orderBy([(e) => OrderingTerm.desc(e.publishDate)]))
        .watch();
  }

  /// All subscribed episodes (for "show all" filter — kept for podcast filter screen).
  Stream<List<Episode>> watchAllSubscribedEpisodes() =>
      (select(episodes)
            ..where((e) => e.isSubscribed.equals(true))
            ..orderBy([(e) => OrderingTerm.desc(e.publishDate)]))
          .watch();

  Stream<List<Episode>> watchEpisodesForPodcast(String podcastId) =>
      (select(episodes)
            ..where((e) => e.podcastId.equals(podcastId))
            ..orderBy([(e) => OrderingTerm.desc(e.publishDate)]))
          .watch()
          .distinct(_episodeListEqual);

  Future<void> insertEpisode(EpisodesCompanion ep) =>
      into(episodes).insertOnConflictUpdate(ep);

  Future<void> insertEpisodes(List<EpisodesCompanion> eps) =>
      batch((b) => b.insertAllOnConflictUpdate(episodes, eps));

  Future<void> insertTempEpisode(EpisodesCompanion ep) =>
      into(episodes).insertOnConflictUpdate(
        ep.copyWith(isSubscribed: const Value(false)),
      );

  Future<void> insertTempEpisodes(List<EpisodesCompanion> eps) =>
      batch((b) => b.insertAll(
        episodes,
        eps.map((e) => e.copyWith(isSubscribed: const Value(false))).toList(),
        mode: InsertMode.insertOrIgnore,
      ));

  /// Only promotes temp episodes that were actually played/finished to subscribed.
  /// Unplayed temp episodes (Apple search results, preview inserts) are left alone
  /// so they don't appear as duplicates alongside the real RSS episodes.
  Future<void> markEpisodesSubscribed(String podcastId) =>
      (update(episodes)
            ..where((e) =>
                e.podcastId.equals(podcastId) &
                (e.lastPositionMs.isBiggerThanValue(0) | e.isFinished.equals(true))))
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
        migrated[stub.id] = match.id;
      }
      await (delete(episodes)..where((e) => e.id.equals(stub.id))).go();
    }
    return migrated;
  }

  /// Delete unplayed, undownloaded temp episodes for a feed before subscribing,
  /// so Apple search-result stubs don't accumulate as orphaned rows.
  Future<void> deleteUnplayedTempEpisodes(String podcastId) =>
      (delete(episodes)
            ..where((e) =>
                e.podcastId.equals(podcastId) &
                e.isSubscribed.equals(false) &
                e.lastPositionMs.equals(0) &
                e.isFinished.equals(false) &
                e.isDownloaded.equals(false)))
          .go();

  /// Save resume position (ms + seconds) and optionally mark finished.
  Future<void> updatePlaybackPosition(
    String id, {
    required int positionMs,
    required int durationMs,
  }) async {
    final posSeconds = positionMs ~/ 1000;
    // Consider finished if within last 60 seconds of total duration
    final finished = durationMs > 0 && positionMs >= durationMs - 60000;

    await (update(episodes)..where((e) => e.id.equals(id))).write(
      EpisodesCompanion(
        lastPositionMs: Value(positionMs),
        playbackPositionSeconds: Value(posSeconds),
        isFinished: Value(finished),
        lastPlayed: Value(DateTime.now()),
        // Keep durationSeconds in sync with actual audio — RSS values are often
        // rounded or wrong, causing the progress bar to exceed 100%.
        durationSeconds: durationMs > 0 ? Value(durationMs ~/ 1000) : const Value.absent(),
        // Clear the WiFi queue mark once the episode is finished
        markedForDownload: finished ? const Value(false) : const Value.absent(),
      ),
    );
  }

  /// Explicitly mark episode as finished (e.g. after natural completion).
  /// Also clears any pending WiFi download queue — no point downloading
  /// something the user has already listened to.
  Future<void> markFinished(String id) =>
      (update(episodes)..where((e) => e.id.equals(id))).write(
        EpisodesCompanion(
          isFinished: const Value(true),
          lastPlayed: Value(DateTime.now()),
          markedForDownload: const Value(false),
        ),
      );

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

  /// Episodes whose download was interrupted (taskId set, not yet downloaded).
  /// Clears the stale taskId, re-queues them for WiFi download, and returns
  /// the stale task IDs so the caller can cancel them in flutter_downloader.
  Future<List<String>> resetIncompleteDownloads() async {
    final stale = await (select(episodes)
          ..where((e) =>
              e.downloadTaskId.isNotNull() & e.isDownloaded.equals(false)))
        .get();
    if (stale.isEmpty) return [];
    await (update(episodes)
          ..where((e) =>
              e.downloadTaskId.isNotNull() & e.isDownloaded.equals(false)))
        .write(const EpisodesCompanion(
          downloadTaskId: Value(null),
          markedForDownload: Value(true),
        ));
    return stale.map((e) => e.downloadTaskId).whereType<String>().toList();
  }

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

  /// Episodes that are downloaded OR queued for WiFi download.
  /// Used when the user taps "Show marked for download" in the downloaded filter.
  Stream<List<Episode>> watchDownloadedOrMarkedEpisodes() {
    return (select(episodes)
          ..where((e) =>
              (e.isDownloaded.equals(true) | e.markedForDownload.equals(true)) &
              (e.isSubscribed.equals(true) |
               e.isDownloaded.equals(true) |
               e.lastPositionMs.isBiggerThanValue(0)))
          ..orderBy([(e) => OrderingTerm.desc(e.publishDate)]))
        .watch()
        .distinct(_episodeListEqual);
  }

  Future<void> deleteLocalFile(String id) async {
    final ep = await (select(episodes)..where((e) => e.id.equals(id)))
        .getSingleOrNull();
    if (ep?.localPath != null) {
      final f = File(ep!.localPath!);
      if (f.existsSync()) f.deleteSync();
    }
    await (update(episodes)..where((e) => e.id.equals(id))).write(
      const EpisodesCompanion(
        isDownloaded: Value(false),
        localPath: Value(null),
        downloadTaskId: Value(null),
      ),
    );
  }

  /// Delete local files for finished subscribed episodes downloaded more than
  /// 2 days ago. Temp episodes are always deleted immediately via
  /// cleanupTempEpisode() and never reach this routine.
  Future<void> deleteFinishedDownloads() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 2));
    final finished = await (select(episodes)
          ..where((e) =>
              e.isSubscribed.equals(true) &
              e.isFinished.equals(true) &
              e.isDownloaded.equals(true) &
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
  /// Played episodes: removed 7 days after last playback.
  /// Never-started episodes: removed if publish date is >7 days old.
  /// In-progress episodes (started but not finished) are always kept.
  Future<void> cleanupStaleTempEpisodes() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));

    final stale = await (select(episodes)
          ..where((e) =>
              e.isSubscribed.equals(false) &
              (
                // Played: wait 7 days from last playback before removing
                (e.isFinished.equals(true) &
                    e.lastPlayed.isSmallerThanValue(cutoff)) |
                // Never started: no play mark and old content
                (e.lastPositionMs.equals(0) &
                    e.isFinished.equals(false) &
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

    // Feed-level cleanup: for each temp podcast, delete the whole feed if
    // all episodes are finished and the most recent play was > 7 days ago.
    final tempPods = await (select(podcasts)
          ..where((p) => p.isSubscribed.equals(false)))
        .get();
    for (final pod in tempPods) {
      final eps = await (select(episodes)
            ..where((e) => e.podcastId.equals(pod.id)))
          .get();
      if (eps.isEmpty) {
        await (delete(podcasts)..where((p) => p.id.equals(pod.id))).go();
        continue;
      }
      // Keep feed if any episode is unfinished (in-progress or never started)
      if (eps.any((e) => !e.isFinished)) continue;
      // Keep feed if the most recently played episode is still recent
      final lastPlay = eps
          .where((e) => e.lastPlayed != null)
          .map((e) => e.lastPlayed!)
          .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
      if (lastPlay == null || lastPlay.isAfter(cutoff)) continue;
      // All finished and idle for 7+ days — remove the feed
      for (final ep in eps) {
        if (ep.localPath != null) {
          final f = File(ep.localPath!);
          if (f.existsSync()) f.deleteSync();
        }
      }
      final ids = eps.map((e) => e.id).toList();
      await (delete(episodes)..where((e) => e.id.isIn(ids))).go();
      await (delete(podcasts)..where((p) => p.id.equals(pod.id))).go();
    }
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

  /// Delete a temp podcast and all its episodes if no episode is still active
  /// (in-progress or downloaded). Called after a temp episode's download is
  /// deleted or the episode is manually removed.
  Future<void> cleanupTempFeedIfDone(String podcastId) async {
    final pod = await (select(podcasts)
          ..where((p) => p.id.equals(podcastId)))
        .getSingleOrNull();
    if (pod == null || pod.isSubscribed) return;

    final eps = await (select(episodes)
          ..where((e) => e.podcastId.equals(podcastId)))
        .get();

    // Keep feed if any episode is in-progress or still has a local file
    final hasActive = eps.any((e) =>
        e.isDownloaded || (!e.isFinished && e.lastPositionMs > 0));
    if (hasActive) return;

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

  /// Update the podcast cover URL. Called during refresh when RSS provides a
  /// non-empty image so the grid/header stays in sync with the feed.
  Future<void> updatePodcastImageUrl(String podcastId, String newUrl) =>
      (update(podcasts)..where((p) => p.id.equals(podcastId)))
          .write(PodcastsCompanion(imageUrl: Value(newUrl)));

  Future<Episode?> getEpisode(String id) =>
      (select(episodes)..where((e) => e.id.equals(id))).getSingleOrNull();

  Stream<Episode?> watchEpisode(String id) =>
      (select(episodes)..where((e) => e.id.equals(id))).watchSingleOrNull();
}
