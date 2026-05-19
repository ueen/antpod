// lib/app_database.dart
//
// Schema version: 6
//   v1 → v2: Episodes.isSubscribed added
//   v2 → v3: Episodes.isFinished added (true = fully listened)
//            Episodes.lastPositionMs added (millisecond precision resume point)
//   v3 → v4: Episodes.chaptersUrl added
//   v4 → v5: Episodes.lastPlayed added (timestamp of most recent playback)
//   v5 → v6: Episodes.markedForDownload added (queued for WiFi download)
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

// ─── Database ─────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [Podcasts, Episodes])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'antpod'));

  @override
  int get schemaVersion => 6;

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
    },
  );

  // ── Podcasts ──────────────────────────────────────────────────────────────

  Stream<List<Podcast>> watchAllPodcasts() =>
      (select(podcasts)..orderBy([(p) => OrderingTerm.asc(p.title)])).watch();

  Future<List<Podcast>> getAllPodcasts() => select(podcasts).get();

  Future<void> insertPodcast(PodcastsCompanion pod) =>
      into(podcasts).insertOnConflictUpdate(pod);

  Future<void> deletePodcast(String id) async {
    final eps = await (select(episodes)
          ..where((e) => e.podcastId.equals(id))
          ..where((e) => e.isDownloaded.equals(true)))
        .get();
    for (final ep in eps) {
      if (ep.localPath != null) {
        final f = File(ep.localPath!);
        if (f.existsSync()) f.deleteSync();
      }
    }
    await (delete(episodes)..where((e) => e.podcastId.equals(id))).go();
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
        .watch();
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
          .watch();

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

  Future<void> markEpisodesSubscribed(String podcastId) =>
      (update(episodes)..where((e) => e.podcastId.equals(podcastId))).write(
        const EpisodesCompanion(isSubscribed: Value(true)),
      );

  /// Save resume position (ms + seconds) and optionally mark finished.
  Future<void> updatePlaybackPosition(
    String id, {
    required int positionMs,
    required int durationMs,
  }) async {
    final posSeconds = positionMs ~/ 1000;
    // Consider finished if within last 5 % of total duration
    final finished = durationMs > 0 && positionMs >= durationMs * 0.95;

    await (update(episodes)..where((e) => e.id.equals(id))).write(
      EpisodesCompanion(
        lastPositionMs: Value(positionMs),
        playbackPositionSeconds: Value(posSeconds),
        isFinished: Value(finished),
        lastPlayed: Value(DateTime.now()),
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
            ..where((e) => e.markedForDownload.equals(true)))
          .get();

  Stream<List<Episode>> watchMarkedForDownloadEpisodes() =>
      (select(episodes)
            ..where((e) => e.markedForDownload.equals(true)))
          .watch();

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
        .watch();
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

    if (stale.isEmpty) return;

    for (final ep in stale) {
      if (ep.localPath != null) {
        final f = File(ep.localPath!);
        if (f.existsSync()) f.deleteSync();
      }
    }

    final ids = stale.map((e) => e.id).toList();
    await (delete(episodes)..where((e) => e.id.isIn(ids))).go();

    final affectedPodcastIds = stale.map((e) => e.podcastId).toSet();
    for (final podId in affectedPodcastIds) {
      final remaining =
          await (select(episodes)..where((e) => e.podcastId.equals(podId)))
              .get();
      if (remaining.isEmpty) {
        await (delete(podcasts)..where((p) => p.id.equals(podId))).go();
      }
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
    }
  }

  Future<Episode?> getEpisode(String id) =>
      (select(episodes)..where((e) => e.id.equals(id))).getSingleOrNull();

  Stream<Episode?> watchEpisode(String id) =>
      (select(episodes)..where((e) => e.id.equals(id))).watchSingleOrNull();
}
