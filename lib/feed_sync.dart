// lib/feed_sync.dart
//
// Loading feeds into the database: refresh, subscribe and preview. Data work
// only — the home screen calls these and does the navigation around them.

import 'dart:async';
import 'dart:math' show min;

import 'package:drift/drift.dart' show Value;

import 'app_database.dart';
import 'podcast_service.dart';

extension FeedDataX on FeedData {
  /// The feed's cover, or '' when it has none.
  String get image => podcast.image?.isNotEmpty == true ? podcast.image! : '';

  String titleOr(String fallback) =>
      podcast.title?.isNotEmpty == true ? podcast.title! : fallback;
}

class FeedSync {
  FeedSync._();

  /// Feeds loading at once: enough to hide slow servers, few enough not to
  /// flood the connection (and memory) with a hundred subscriptions.
  static const _parallel = 6;

  /// How long finished feeds wait to be written together: the lists update
  /// as the refresh goes, but not once per feed.
  static const _writeEvery = Duration(seconds: 2);

  /// Refreshes every subscribed podcast except paused ones (their page's
  /// pull-to-refresh still works), [_parallel] at a time. A feed that failed
  /// while others loaded counts towards its "feed not loading" note; when
  /// none loaded the device is likely offline, which isn't the feed's fault.
  static Future<void> refreshAll(AppDatabase db) async {
    final pods = (await db.getAllPodcasts()).where((p) => !p.syncPaused).toList();
    final writer = _RefreshWriter(db);
    final failed = <String>[];
    var anyLoaded = false;
    final queue = pods.iterator;
    Future<void> worker() async {
      while (queue.moveNext()) {
        final pod = queue.current;
        final update = await _fetch(pod);
        if (update == null) {
          failed.add(pod.id);
        } else {
          anyLoaded = true;
          writer.add(pod.id, update);
        }
      }
    }

    await Future.wait([for (var i = 0; i < min(_parallel, pods.length); i++) worker()]);
    await writer.close();
    if (anyLoaded && failed.isNotEmpty) await db.countFeedFailures(failed);
    await db.foldOffFeedTwins();
  }

  /// Refreshes one subscribed podcast (by id). A failure here isn't counted:
  /// with nothing else loading there's no telling the device is online.
  static Future<void> refreshPodcast(AppDatabase db, String podcastId) async {
    final pod = await db.getPodcast(podcastId);
    if (pod == null) return;
    final update = await _fetch(pod);
    if (update == null) return;
    await db.saveFeedRefresh(update.episodes, {pod.id: update.podcast});
    await db.foldOffFeedTwins(pod.id);
  }

  /// Subscribes to [result]. Fetches first, then writes everything in one
  /// transaction: a preview list stays put while the network is busy and then
  /// updates in place (same episodes, now subscribed). Returns the Apple stubs
  /// resolved on the way, {appleId → rssGuid}.
  static Future<Map<String, String>> subscribe(
      AppDatabase db, PodcastResult result) async {
    final data = await PodcastService.loadFeed(result.feedUrl);
    final image = data != null && data.image.isNotEmpty ? data.image : result.imageUrl;
    return db.subscribePodcast(
      result.toCompanion().copyWith(imageUrl: Value(image)),
      data == null ? const [] : _asSubscribed(data.episodes, result.feedUrl, image),
    );
  }

  /// Subscribes to [fallback]'s feed by its URL alone (an OPML file, a
  /// backup): title, cover and description come from the feed, else from
  /// [fallback]. A feed that doesn't load is subscribed all the same with
  /// what [fallback] knows; its next refresh fills it in. Returns whether it
  /// loaded.
  static Future<bool> subscribeUrl(AppDatabase db, PodcastResult fallback) async {
    final (feedUrl, data) = await loadFeedWithWww(fallback.feedUrl);
    if (data == null) {
      await db.subscribePodcast(fallback.toCompanion(), const []);
      return false;
    }
    final result = fallback.copyWith(
      id: feedUrl,
      feedUrl: feedUrl,
      title: data.titleOr(fallback.title),
      description: data.podcast.description ?? fallback.description,
      imageUrl: data.image.isNotEmpty ? data.image : fallback.imageUrl,
    );
    await db.subscribePodcast(result.toCompanion(),
        _asSubscribed(data.episodes, feedUrl, result.imageUrl));
    return true;
  }

  /// Subscribes to every one of [feeds], [_parallel] at a time, with
  /// [subscribeUrl] (or [subscribe], in tests). Returns how many didn't load.
  static Future<int> subscribeAll(
    AppDatabase db,
    List<PodcastResult> feeds, {
    Future<bool> Function(PodcastResult feed)? subscribe,
    void Function(int done, int total)? onProgress,
  }) async {
    final queue = feeds.iterator;
    var done = 0, failed = 0;
    Future<void> worker() async {
      while (queue.moveNext()) {
        final feed = queue.current;
        try {
          final loaded = await (subscribe ?? (f) => subscribeUrl(db, f))(feed);
          if (!loaded) failed++;
        } catch (e) {
          failed++;
        }
        onProgress?.call(++done, feeds.length);
      }
    }

    await Future.wait([for (var i = 0; i < min(_parallel, feeds.length); i++) worker()]);
    return failed;
  }

  /// Loads [result]'s feed as a temp podcast for its preview, and resolves
  /// Apple stubs against it (their progress moves to the RSS episode). Returns
  /// [result] filled in from the feed, the feed itself and the resolved stubs,
  /// or null when the feed doesn't load.
  static Future<({PodcastResult result, FeedData data, Map<String, String> migrated})?>
      loadPreview(AppDatabase db, PodcastResult result) async {
    // The URL that actually loaded (share links drop "www.") is the one the
    // episodes reference, so the podcast row and the preview use it too.
    final (feedUrl, data) = await loadFeedWithWww(result.feedUrl);
    if (data == null) return null;
    final loaded = result.copyWith(
      id: result.id == result.feedUrl ? feedUrl : result.id,
      feedUrl: feedUrl,
      title: data.titleOr(result.title),
      description: data.podcast.description ?? result.description,
      imageUrl: data.image.isNotEmpty ? data.image : result.imageUrl,
    );
    await db.insertTempPodcast(loaded.toCompanion());
    await db.insertTempEpisodes(data.episodes);
    final migrated = await db.migrateAppleEpisodeStubs(feedUrl);
    return (result: loaded, data: data, migrated: migrated);
  }

  /// Loads a feed, returning the URL that actually worked. Share links drop
  /// "www.", which some hosts don't redirect, so retry with it before giving up.
  static Future<(String, FeedData?)> loadFeedWithWww(String feed) async {
    final data = await PodcastService.loadFeed(feed);
    if (data != null) return (feed, data);
    final withWww = feed.replaceFirstMapped(
        RegExp(r'^(https?://)(?!www\.)'), (m) => '${m[1]}www.');
    if (withWww == feed) return (feed, null);
    final retry = await PodcastService.loadFeed(withWww);
    return retry != null ? (withWww, retry) : (feed, null);
  }

  /// Loads [pod]'s feed if it changed since its last refresh. Returns its
  /// episodes tagged as subscribed (none when unchanged) and the podcast's
  /// columns to write: the cover kept in sync, the new validators and a
  /// cleared failure count. Null when the feed doesn't load.
  static Future<_FeedUpdate?> _fetch(Podcast pod) async {
    final fetch = await PodcastService.fetchFeed(pod.feedUrl, known: (
      etag: pod.feedEtag,
      lastModified: pod.feedLastModified,
      hash: pod.feedHash,
    ));
    if (fetch == null) return null;
    final (:data, validators: v, :url) = fetch;
    final image = data?.image ?? '';
    // Only what changed, so an unchanged feed usually writes nothing.
    Value<T> changed<T>(T now, T before) =>
        now != before ? Value(now) : const Value.absent();
    final podcast = PodcastsCompanion(
      // Moved for good: asked for at its new home from now on.
      feedUrl: changed(url, pod.feedUrl),
      imageUrl: image.isNotEmpty ? changed(image, pod.imageUrl) : const Value.absent(),
      feedEtag: changed(v.etag, pod.feedEtag),
      feedLastModified: changed(v.lastModified, pod.feedLastModified),
      feedHash: changed(v.hash, pod.feedHash),
      feedFailures: changed(0, pod.feedFailures),
    );
    return (
      // Fall back to the stored cover so a working URL never turns into ''.
      episodes: data == null
          ? const <EpisodesCompanion>[]
          : _asSubscribed(data.episodes, pod.id, image.isNotEmpty ? image : pod.imageUrl),
      podcast: podcast,
    );
  }

  /// Parsed feed episodes, re-tagged as belonging to subscribed [podcastId].
  static List<EpisodesCompanion> _asSubscribed(
          List<EpisodesCompanion> episodes, String podcastId, String image) =>
      [
        for (final e in episodes)
          e.copyWith(
            podcastId: Value(podcastId),
            podcastImageUrl: Value(image),
            isSubscribed: const Value(true),
          ),
      ];
}

/// What refreshing one podcast found: see [FeedSync._fetch].
typedef _FeedUpdate = ({List<EpisodesCompanion> episodes, PodcastsCompanion podcast});

/// Collects finished feeds during [FeedSync.refreshAll] and writes them in
/// one transaction every [FeedSync._writeEvery], one write after another.
class _RefreshWriter {
  final AppDatabase db;
  _RefreshWriter(this.db);

  final _episodes = <EpisodesCompanion>[];
  final _podcasts = <String, PodcastsCompanion>{};
  Timer? _timer;
  Future<void> _writes = Future.value();
  (Object, StackTrace)? _error;

  void add(String podcastId, _FeedUpdate update) {
    _episodes.addAll(update.episodes);
    // An all-absent companion is nothing to write.
    if (update.podcast.toColumns(false).isNotEmpty) {
      _podcasts[podcastId] = update.podcast;
    }
    // Only a change starts the timer: an unchanged feed writes nothing.
    if (_episodes.isNotEmpty || _podcasts.isNotEmpty) {
      _timer ??= Timer(FeedSync._writeEvery, _write);
    }
  }

  void _write() {
    _timer = null;
    if (_episodes.isEmpty && _podcasts.isEmpty) return;
    final episodes = List.of(_episodes);
    final podcasts = Map.of(_podcasts);
    _episodes.clear();
    _podcasts.clear();
    // A failed write doesn't stop the next one; close() reports the first.
    _writes = _writes
        .then((_) => db.saveFeedRefresh(episodes, podcasts))
        .catchError((Object e, StackTrace s) { _error ??= (e, s); });
  }

  /// Writes what's left and waits for all writes; rethrows the first error.
  Future<void> close() async {
    _timer?.cancel();
    _write();
    await _writes;
    if (_error case (final e, final s)) Error.throwWithStackTrace(e, s);
  }
}
