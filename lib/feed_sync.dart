// lib/feed_sync.dart
//
// Loading feeds into the database: refresh, subscribe and preview. Data work
// only — the home screen calls these and does the navigation around them.

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

  /// Refreshes every subscribed podcast except paused ones (their page's
  /// pull-to-refresh still works). Feeds load in parallel, then one write, so
  /// the episode stream emits once.
  static Future<void> refreshAll(AppDatabase db) async {
    final pods = (await db.getAllPodcasts()).where((p) => !p.syncPaused);
    final results = await Future.wait(pods.map((p) => _fetch(db, p)));
    final all = results.expand((e) => e).toList();
    if (all.isNotEmpty) await db.insertEpisodes(all);
  }

  /// Refreshes one subscribed podcast (by id).
  static Future<void> refreshPodcast(AppDatabase db, String podcastId) async {
    final pod = await db.getPodcast(podcastId);
    if (pod == null) return;
    final episodes = await _fetch(db, pod);
    if (episodes.isNotEmpty) await db.insertEpisodes(episodes);
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

  /// Loads [pod]'s feed, keeps its stored cover in sync and returns its
  /// episodes tagged as subscribed (none when the feed doesn't load).
  static Future<List<EpisodesCompanion>> _fetch(AppDatabase db, Podcast pod) async {
    final data = await PodcastService.loadFeed(pod.feedUrl);
    if (data == null) return const [];
    final image = data.image;
    if (image.isNotEmpty && image != pod.imageUrl) {
      await db.updatePodcastImageUrl(pod.id, image);
    }
    // Fall back to the stored cover so a working URL never turns into ''.
    return _asSubscribed(data.episodes, pod.id, image.isNotEmpty ? image : pod.imageUrl);
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
