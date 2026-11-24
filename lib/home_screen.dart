// lib/home_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_links/app_links.dart';

import 'app_database.dart';
import 'download_provider.dart';
import 'download_service.dart';
import 'episode_feed.dart';
import 'episode_tile.dart';
import 'feed_state.dart';
import 'filter_chips.dart';
import 'l10n/app_localizations.dart';
import 'mini_player.dart';
import 'player_provider.dart';
import 'podcast_header.dart';
import 'package:share_plus/share_plus.dart';
import 'podcast_service.dart';
import 'share_utils.dart';


// ─────────────────────────────────────────────────────────────────────────────
// Feed mode
// ─────────────────────────────────────────────────────────────────────────────

enum _FeedMode { feed, podcastFilter, searchEpisodes, discover, previewPodcast }

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  /// The link that launched the app (fetched in main), so a cold start opens
  /// straight into the linked podcast instead of showing home first.
  final Uri? initialLink;
  const HomeScreen({super.key, this.initialLink});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _FeedMode _mode = _FeedMode.feed;
  FilterState _filter = const FilterState();
  bool _filterChipsVisible = true;
  bool _startupRefreshing = false;

  // Search mode has its own ephemeral filter state — never persisted.
  FilterState _searchFilter = const FilterState(newOnly: false);
  bool _searchFilterChipsVisible = false;

  bool get _isSearchMode => _mode == _FeedMode.searchEpisodes;
  FilterState get _effectiveFilter => _isSearchMode ? _searchFilter : _filter;
  bool get _effectiveChipsVisible =>
      _isSearchMode ? _searchFilterChipsVisible : _filterChipsVisible;

  final _antWalkerKey = GlobalKey<_AntWalkerState>();

  String? _filterPodcastId;
  Podcast? _filterPodcast;

  // Set when search is opened from a podcast feed; null when opened from home.
  String? _searchPodcastId;

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _piSearchTimer;

  List<PodcastResult> _trending = [];
  DateTime? _trendingFetchedAt;
  List<_UnifiedResult> _unifiedSearchResults = [];
  int _searchOffset = 0;
  bool _searchHasMore = true;
  bool _loadingMoreSearch = false;
  bool _loadingTrending = false;
  bool _searchingPI = false;
  String? _trendingError;

  // Preview (unsubscribed podcast header + episodes)
  PodcastResult? _previewResult;
  _FeedMode _previewFrom = _FeedMode.discover;
  bool _previewLoading = false;

  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Uri? _pendingDeepLink;
  bool _appReady = false;
  // While a launch link is being routed the home feed stays blank, so the
  // app opens on the linked podcast rather than flashing home first.
  late bool _linkOpening = widget.initialLink != null;
  String? _lastDeepLink;
  DateTime _lastDeepLinkAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _downloadingMarked = false;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();

    // app_links ≥6 emits the initial link on uriLinkStream too, so this single
    // listener covers cold start and warm links. Links that arrive before the
    // app has finished initializing are parked and handled at the end of init.
    _linkSub = AppLinks().uriLinkStream.listen((uri) {
      if (_appReady) {
        _handleDeepLink(uri);
      } else {
        _pendingDeepLink = uri;
      }
    });

    // Auto-download queued episodes when WiFi becomes available; track offline state.
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) =>
          r == ConnectivityResult.none || r == ConnectivityResult.bluetooth);
      if (offline != _isOffline) setState(() => _isOffline = offline);
      if (results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        _downloadMarkedEpisodes();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // SharedPreferences is pre-warmed in main(), so this returns instantly.
      await _loadFilterPrefs();
      if (!mounted) return;
      final db = context.read<AppDatabase>();
      final player = context.read<PlayerProvider>();
      final pods = await db.getAllPodcasts();
      if (!mounted) return;
      // Restore the last episode before any link is handled, so a linked
      // episode that starts playing can't be overwritten by the restore.
      if (pods.isNotEmpty) await player.restoreLastEpisode();
      if (!mounted) return;
      _appReady = true;
      final link = _pendingDeepLink ?? widget.initialLink;
      _pendingDeepLink = null;
      if (link != null) {
        // Route first: the linked feed loads without the startup refresh's
        // feed isolates competing with it.
        try {
          await _handleDeepLink(link);
        } finally {
          // A link that didn't route (bad params) falls back to home.
          if (mounted && _linkOpening) setState(() => _linkOpening = false);
        }
        if (!mounted) return;
      }
      if (pods.isEmpty) {
        // No subscriptions: Discover is home, also behind a linked preview.
        if (_mode == _FeedMode.feed) {
          _enterDiscover();
        } else if (_mode == _FeedMode.previewPodcast) {
          _previewFrom = _FeedMode.discover;
        }
      }
      if (pods.isNotEmpty) {
        // Schedule the RSS refresh at idle priority so it only starts after
        // the first frame is fully painted and the scheduler has no pending work.
        SchedulerBinding.instance.scheduleTask(
          () { if (mounted) _refresh(db, startup: true); },
          Priority.idle,
        );
      }
    });
  }

  static String _restoreProto(String s) {
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('h0:')) return 'http://${s.substring(3)}';
    return 'https://$s';
  }

  // Hash-match all episodes for a podcast against a 11-char base64url MD5 hash.
  Future<Episode?> _findByHash(AppDatabase db, String podcastId, String hash) async {
    final eps = await (db.select(db.episodes)
          ..where((e) => e.podcastId.equals(podcastId)))
        .get();
    for (final ep in eps) {
      if (ShareUtils.guidHash(ep.id) == hash) return ep;
    }
    return null;
  }

  // Share links strip the protocol and a leading "www." from the feed URL, so
  // compare feeds in that same reduced form.
  static String _normFeed(String url) => url
      .replaceFirst(RegExp(r'^https?://'), '')
      .replaceFirst(RegExp(r'^www\.'), '')
      .replaceFirst(RegExp(r'/+$'), '');

  // Load a feed, returning the URL that actually worked. Share links drop
  // "www.", which some hosts don't redirect, so retry with it before giving up.
  Future<(String, FeedData?)> _loadFeedWithWww(String feed) async {
    final data = await PodcastService.loadFeed(feed);
    if (data != null) return (feed, data);
    final withWww = feed.replaceFirstMapped(
        RegExp(r'^(https?://)(?!www\.)'), (m) => '${m[1]}www.');
    if (withWww == feed) return (feed, null);
    final retry = await PodcastService.loadFeed(withWww);
    return retry != null ? (withWww, retry) : (feed, null);
  }

  Future<void> _handleDeepLink(Uri uri) async {
    // Android can deliver the same intent twice (cold start + onNewIntent).
    final key = uri.toString();
    final now = DateTime.now();
    if (key == _lastDeepLink && now.difference(_lastDeepLinkAt).inSeconds < 3) return;
    _lastDeepLink = key;
    _lastDeepLinkAt = now;

    // p = podcast feed (proto stripped), e = episode guid hash.
    // f / h are the legacy names from earlier builds.
    final q = uri.queryParameters;
    final rawFeed = q['p'] ?? q['f'];
    if (rawFeed == null || rawFeed.isEmpty || !mounted) return;
    final feed = _restoreProto(rawFeed);
    final guidHash = q['e'] ?? q['h'];
    final db = context.read<AppDatabase>();

    // Close any open player sheet / dialog / pushed page so the target is visible.
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (_mode != _FeedMode.feed || _searchQuery.isNotEmpty) _exitToFeed();

    final all = await db.getAllPodcasts();
    if (!mounted) return;
    final norm = _normFeed(feed);
    final subscribed = all
        .where((p) => p.id == feed || _normFeed(p.feedUrl) == norm)
        .firstOrNull;

    final hasEpisode = guidHash != null && guidHash.isNotEmpty;

    // Routing below leaves the home feed, so it no longer needs blanking.
    _linkOpening = false;

    // ── Subscribed podcast ────────────────────────────────────────────────
    if (subscribed != null) {
      _enterPodcastFilter(subscribed);
      if (!hasEpisode) return;
      var episode = await _findByHash(db, subscribed.id, guidHash);
      if (episode == null) {
        // Not in the DB yet (feed not refreshed since it was published).
        await _refreshSinglePodcast(subscribed.id);
        episode = await _findByHash(db, subscribed.id, guidHash);
      }
      if (episode != null && mounted) unawaited(_playFromLink(episode));
      return;
    }

    // ── Not subscribed: preview ───────────────────────────────────────────
    // The preview opens right away and loads the feed itself (once); an
    // episode link then plays the shared episode out of that load. A temp
    // episode left from an earlier preview can start without waiting.
    final existing = hasEpisode ? await _findByHash(db, feed, guidHash) : null;
    if (!mounted) return;
    final loading = _openPreview(PodcastResult(
      id: feed,
      title: existing?.podcastTitle ?? '',
      author: '',
      description: '',
      imageUrl: '',
      feedUrl: feed,
    ));
    if (!hasEpisode) return;
    var episode = existing;
    if (episode == null) {
      final data = await loading;
      final match = data?.episodes
          .where((e) => ShareUtils.guidHash(e.id.value) == guidHash)
          .firstOrNull;
      // Episode no longer in the feed: the preview still shows the podcast.
      if (match == null || !mounted) return;
      // Inserted by the preview (insert-or-ignore, so an existing row wins).
      episode = await db.getEpisode(match.id.value);
    }
    // Not awaited: the sheet stays open until dismissed, and startup work
    // waiting on this handler shouldn't wait on that.
    if (episode != null && mounted) unawaited(_playFromLink(episode));
  }

  // Start the shared episode and show the player. play() sets the current
  // episode synchronously, so the sheet opens on it while it still buffers.
  Future<void> _playFromLink(Episode episode) async {
    context.read<PlayerProvider>().play(episode);
    await showPlayerSheet(context, onPodcastTap: _openPodcastFromPlayer);
  }

  void _openPodcastFromPlayer() {
    final player = context.read<PlayerProvider>();
    final ep = player.currentEpisode;
    if (ep == null || !mounted) return;
    final db = context.read<AppDatabase>();
    db.getAllPodcasts().then((all) {
      if (!mounted) return;
      final subscribed =
          all.where((p) => p.feedUrl == ep.podcastId || p.id == ep.podcastId).firstOrNull;
      if (subscribed != null) {
        _enterPodcastFilter(subscribed);
      } else {
        _openPreview(PodcastResult(
          id: ep.podcastId,
          title: ep.podcastTitle,
          author: '',
          description: '',
          imageUrl: ep.podcastImageUrl,
          feedUrl: ep.podcastId,
        ));
      }
    });
  }

  Future<void> _loadFilterPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final sortIndex = prefs.getInt('filter_sort') ?? 0;
    if (!mounted) return;
    setState(() {
      _filter = FilterState(
        newOnly: prefs.getBool('filter_newOnly') ?? true,
        history: prefs.getBool('filter_history') ?? false,
        downloaded: prefs.getBool('filter_downloaded') ?? false,
        sort: SortMode.values[sortIndex.clamp(0, SortMode.values.length - 1)],
        inProgress: prefs.getBool('filter_inProgress') ?? false,
        podcasts: prefs.getBool('filter_podcasts') ?? false,
      );
      _filterChipsVisible = prefs.getBool('filter_chipsVisible') ?? true;
    });
  }

  Future<void> _saveFilterPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('filter_newOnly', _filter.newOnly);
    await prefs.setBool('filter_history', _filter.history);
    await prefs.setBool('filter_downloaded', _filter.downloaded);
    await prefs.setInt('filter_sort', _filter.sort.index);
    await prefs.setBool('filter_inProgress', _filter.inProgress);
    await prefs.setBool('filter_podcasts', _filter.podcasts);
    await prefs.setBool('filter_chipsVisible', _filterChipsVisible);
  }

  @override
  void dispose() {
    _piSearchTimer?.cancel();
    _linkSub?.cancel();
    _connectivitySub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── WiFi queue auto-download ──────────────────────────────────────────────

  // Trigger WiFi downloads — called on startup and on WiFi reconnect. Waits
  // for DownloadProvider.restore() so downloads that finished or kept running
  // while the app was closed are settled before anything is re-enqueued.
  Future<void> _downloadMarkedEpisodes() async {
    if (_downloadingMarked || !mounted) return;
    _downloadingMarked = true;
    try {
      final db = context.read<AppDatabase>();
      final downloads = context.read<DownloadProvider>();
      await downloads.restore();
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.wifi) &&
          !connectivity.contains(ConnectivityResult.ethernet)) { return; }
      if (!mounted) return;
      await DownloadService.requestNotificationPermission();
      if (!mounted) return;
      final marked = await db.getMarkedForDownloadEpisodes();
      for (final ep in marked) {
        if (downloads.isDownloading(ep.id)) continue;
        try {
          final taskId = await DownloadService.downloadEpisode(
            episodeId: ep.id, audioUrl: ep.audioUrl,
            episodeTitle: ep.title, db: db,
          );
          if (taskId != null) downloads.trackDownload(taskId, episodeId: ep.id, title: ep.title);
          // If taskId is null, mark is preserved for retry on next WiFi connect.
        } catch (_) {
          // Keep mark set so the episode retries on next WiFi connect.
        }
      }
    } finally {
      _downloadingMarked = false;
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _enterDiscover() {
    setState(() {
      _mode = _FeedMode.discover;
      _searchQuery = '';
      _searchCtrl.clear();
      
      _unifiedSearchResults = [];
    });
    // Only reload if we have no data yet
    if (_trending.isEmpty) _loadDiscover();
  }

  void _searchOnline() {
    final q = _searchQuery;
    setState(() {
      _mode = _FeedMode.discover;
      
      _unifiedSearchResults = [];
    });
    if (q.isNotEmpty) {
      _debouncedPISearch(q);
    } else if (_trending.isEmpty) {
      _loadDiscover();
    }
  }

  void _exitToFeed() {
    setState(() {
      _mode = _FeedMode.feed;
      _filterPodcastId = null;
      _filterPodcast = null;
      _searchPodcastId = null;
      _searchQuery = '';
      _searchCtrl.clear();
      _unifiedSearchResults = [];
      _filter = _filter.copyWith(podcasts: false);
    });
  }

  // ── Preview unsubscribed podcast ──────────────────────────────────────────

  Future<void> _openPodcastResult(PodcastResult result) async {
    final db = context.read<AppDatabase>();
    final all = await db.getAllPodcasts();
    if (!mounted) return;
    final subscribed = all
        .where((p) => p.feedUrl == result.feedUrl || p.id == result.feedUrl)
        .firstOrNull;
    if (subscribed != null) {
      // Migrate any apple-* stubs the user may have played from search results
      // for this already-subscribed podcast. No-op if no stubs exist.
      final migrated = await db.migrateAppleEpisodeStubs(subscribed.id);
      if (!mounted) return;
      await _reloadMigratedCurrent(migrated);
      if (!mounted) return;
      _enterPodcastFilter(subscribed);
    } else {
      _openPreview(result);
    }
  }

  /// Shows the preview for [result] at once and loads its feed into the DB as
  /// temp rows. Returns the loaded feed (null on failure) so a deep link can
  /// pick its episode out of the same load.
  Future<FeedData?> _openPreview(PodcastResult result) async {
    setState(() {
      _previewResult = PodcastResult(
        id: result.id,
        title: result.title,
        author: result.author,
        description: result.description,
        imageUrl: '',  // show placeholder until RSS cover loads
        feedUrl: result.feedUrl,
      );
      _previewLoading = true;
      _previewFrom = _mode;
      _mode = _FeedMode.previewPodcast;
      _filter = _filter.copyWith(podcasts: true);
    });
    final db = context.read<AppDatabase>();
    // The URL that actually loaded (share links drop "www.") is the one the
    // episodes reference, so the podcast row and the preview use it too.
    final (feedUrl, data) = await _loadFeedWithWww(result.feedUrl);
    // Still showing this preview? The user may have left or opened another.
    bool current() =>
        mounted &&
        _mode == _FeedMode.previewPodcast &&
        _previewResult?.feedUrl == result.feedUrl;
    if (!mounted) return data;
    if (data == null) {
      if (current()) setState(() => _previewLoading = false);
      return null;
    }
    final title = data.podcast.title?.isNotEmpty == true ? data.podcast.title! : result.title;
    final image = data.podcast.image?.isNotEmpty == true ? data.podcast.image! : '';
    await db.insertTempPodcast(PodcastsCompanion(
      id: Value(feedUrl),
      title: Value(title),
      description: Value(data.podcast.description ?? result.description),
      imageUrl: Value(image.isNotEmpty ? image : result.imageUrl),
      feedUrl: Value(feedUrl),
      author: Value(result.author),
    ));
    await db.insertTempEpisodes(data.episodes);
    // Resolve Apple stubs (id: 'apple-*') to real RSS episodes by title-match.
    // Migrates any saved playback progress to the RSS episode, then removes the stub.
    final migrated = await db.migrateAppleEpisodeStubs(feedUrl);
    if (!mounted) return data;
    await _reloadMigratedCurrent(migrated);
    if (!current()) return data;
    setState(() {
      _previewResult = PodcastResult(
        id: result.id == result.feedUrl ? feedUrl : result.id,
        title: title,
        author: result.author,
        description: data.podcast.description ?? result.description,
        imageUrl: image,
        feedUrl: feedUrl,
      );
      _previewLoading = false;
    });
    return data;
  }

  void _exitPreview() {
    setState(() {
      _mode = _previewFrom;
      _previewResult = null;
      _filter = _filter.copyWith(podcasts: false);
    });
    // Discover may never have loaded (app opened straight into a preview).
    if (_mode == _FeedMode.discover && _trending.isEmpty) _loadDiscover();
  }

  // ── Unsubscribe ───────────────────────────────────────────────────────────

  /// Closes the player if it holds an episode of [podcast]; no-op otherwise.
  Future<void> _closePlayerFor(Podcast podcast) async {
    final player = context.read<PlayerProvider>();
    final epPodId = player.currentEpisode?.podcastId;
    if (epPodId != null && (epPodId == podcast.id || epPodId == podcast.feedUrl)) {
      await player.stopAndClear();
    }
  }

  // Pressing unsubscribe first stops playback of this podcast and closes the
  // player (even if the sheet is then cancelled), so no episode is "live" while
  // the user decides. Then a bottom sheet: unsubscribe & delete (destructive),
  // then either keep episodes (temp feed; when something is downloaded or
  // started) or, when there's nothing to keep, pause new episodes. Both leave
  // the podcast's current episodes in place, so only one is ever offered.
  Future<void> _confirmUnsubscribe(Podcast podcast) async {
    final db = context.read<AppDatabase>();
    // Awaited: the player saves its position first, so the episode that was
    // just playing is counted as started below.
    await _closePlayerFor(podcast);
    final eps = await (db.select(db.episodes)
          ..where((e) =>
              e.podcastId.equals(podcast.id) | e.podcastId.equals(podcast.feedUrl)))
        .get();
    // Same test the keep action applies, so the option never keeps nothing.
    final canKeep = eps.any(AppDatabase.isKeepWorthy);
    final downloaded = eps.where((e) => e.isDownloaded).length;
    final started = eps
        .where((e) => !e.isDownloaded && AppDatabase.isKeepWorthy(e))
        .length;
    if (!mounted) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final l10n = AppLocalizations.of(ctx)!;
        // What "keep episodes" would keep; neutral, since nothing is lost
        // unless delete is chosen.
        final found = downloaded > 0 && started > 0
            ? l10n.foundStartedAndDownloaded
            : downloaded > 0
                ? l10n.foundDownloaded(downloaded)
                : started > 0
                    ? l10n.foundStarted(started)
                    : null;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.unsubscribeConfirm,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                if (found != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(found,
                            style: TextStyle(
                                fontSize: 13, color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                    minimumSize: const Size.fromHeight(52),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(l10n.unsubscribeDeleteAll),
                  onPressed: () => Navigator.pop(ctx, 'delete'),
                ),
                const SizedBox(height: 10),
                if (canKeep)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error,
                      side: BorderSide(color: cs.error.withValues(alpha: 0.6)),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: Text(l10n.unsubscribeKeepEpisodes),
                    onPressed: () => Navigator.pop(ctx, 'keep'),
                  )
                else
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(Icons.pause_circle_outline_rounded),
                    label: Text(l10n.pauseNewEpisodes),
                    onPressed: () => Navigator.pop(ctx, 'pause'),
                  ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.cancel),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    if (action == 'delete') {
      await _unsubscribe(podcast);
    } else if (action == 'keep') {
      await _unsubscribeKeepEpisodes(podcast);
    } else if (action == 'pause') {
      await _setSyncPaused(podcast, true);
    }
  }

  Future<void> _setSyncPaused(Podcast podcast, bool paused) async {
    final db = context.read<AppDatabase>();
    await db.setPodcastSyncPaused(podcast.id, paused);
    if (!mounted) return;
    if (_filterPodcastId == podcast.id) {
      setState(() => _filterPodcast = podcast.copyWith(syncPaused: paused));
    }
    // Resuming: catch up on what was missed while paused.
    if (!paused) _refreshSinglePodcast(podcast.id);
  }

  Future<void> _unsubscribe(Podcast podcast) async {
    final db        = context.read<AppDatabase>();
    final downloads = context.read<DownloadProvider>();

    // Already closed when the sheet opened; again in case playback was
    // resumed meanwhile (e.g. headset button).
    await _closePlayerFor(podcast);

    try {
      // Cancel any in-progress downloads for this podcast's episodes.
      final eps = await (db.select(db.episodes)
            ..where((e) =>
                e.podcastId.equals(podcast.id) | e.podcastId.equals(podcast.feedUrl))
            ..where((e) => e.downloadTaskId.isNotNull())
            ..where((e) => e.isDownloaded.equals(false)))
          .get();
      for (final ep in eps) {
        if (ep.downloadTaskId != null) {
          await downloads.cancelDownload(ep.id, ep.downloadTaskId);
        }
      }
      await db.deletePodcast(podcast.id);
    } catch (e, st) {
      debugPrint('[unsub] ERROR: $e\n$st');
    } finally {
      if (mounted) _exitToFeed();
    }
  }

  /// Unsubscribe but keep downloaded/started episodes. The podcast becomes a
  /// temp feed — cleaned up once those are played — and stays open, now with
  /// a subscribe button to come back.
  Future<void> _unsubscribeKeepEpisodes(Podcast podcast) async {
    final db        = context.read<AppDatabase>();
    final downloads = context.read<DownloadProvider>();

    // As in _unsubscribe: the player must not hold an episode whose podcastId
    // is about to change underneath it.
    await _closePlayerFor(podcast);

    try {
      final dropped = await db.demoteToTempFeed(podcast);
      for (final ep in dropped) {
        if (ep.downloadTaskId != null && !ep.isDownloaded) {
          await downloads.cancelDownload(ep.id, ep.downloadTaskId);
        }
      }
    } catch (e, st) {
      debugPrint('[unsub-keep] ERROR: $e\n$st');
    }
    if (!mounted) return;
    setState(() {
      _previewResult = PodcastResult(
        id: podcast.feedUrl,
        title: podcast.title,
        author: podcast.author,
        description: podcast.description,
        imageUrl: podcast.imageUrl,
        feedUrl: podcast.feedUrl,
      );
      _previewLoading = false;
      _previewFrom = _FeedMode.feed;   // back → home
      _mode = _FeedMode.previewPodcast;
      _filterPodcastId = null;
      _filterPodcast = null;
      _filter = _filter.copyWith(podcasts: true);
    });
  }

  void _toggleFilterChips() {
    if (_isSearchMode) {
      setState(() => _searchFilterChipsVisible = !_searchFilterChipsVisible);
    } else {
      setState(() => _filterChipsVisible = !_filterChipsVisible);
      _saveFilterPrefs();
    }
  }

  void _showAbout(BuildContext context) {
    _antWalkerKey.currentState?._startWalk();
    final topPad = MediaQuery.of(context).padding.top;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'About AntPod',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        // cs comes from the dialog's own context so it respects the live theme
        final cs = Theme.of(ctx).colorScheme;
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.pop(ctx),
          child: FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
              alignment: Alignment.topLeft,
              child: Padding(
                padding: EdgeInsets.only(
                  top: topPad + 46,
                  left: 12,
                  right: 12,
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      width: 300,
                      child: CustomPaint(
                        painter: _BubblePainter(cs: cs),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Title row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ClipOval(child: SvgPicture.asset(
                                      'antpodlogo.svg', width: 24, height: 24)),
                                  const SizedBox(width: 8),
                                  Text('AntPod',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: cs.onPrimaryContainer,
                                      letterSpacing: -0.4,
                                    )),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Body text
                              Text(
                                'The anthill for your podcasts — '
                                'every episode carried home to the hill tirelessly. '
                                'A nimble scout hatched from the spirit of the grand old AntennaPod.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: cs.onPrimaryContainer,
                                  fontSize: 12.5,
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: 14),
                              // GitHub button
                              GestureDetector(
                                onTap: () => launchUrl(
                                  Uri.parse('https://github.com/ueen/antpod'),
                                  mode: LaunchMode.externalApplication,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: cs.onPrimaryContainer.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: cs.onPrimaryContainer.withValues(alpha: 0.25),
                                        width: 1),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SvgPicture.string(
                                        _kGithubSvg,
                                        width: 15, height: 15,
                                        colorFilter: ColorFilter.mode(
                                            cs.onPrimaryContainer, BlendMode.srcIn),
                                      ),
                                      const SizedBox(width: 7),
                                      Text(
                                        'github.com/ueen/antpod',
                                        style: TextStyle(
                                          color: cs.onPrimaryContainer,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _onSearchChanged(String v) {
    setState(() {
      _searchQuery = v;
      // Typing deselects the Podcasts grid — search works on episodes only
      if (v.isNotEmpty && _filter.podcasts) {
        _filter = _filter.copyWith(podcasts: false);
      }
    });
    if (_mode == _FeedMode.discover) {
      // Debounce API calls — fire only after 400 ms of silence
      _piSearchTimer?.cancel();
      _piSearchTimer = Timer(const Duration(milliseconds: 400), () => _debouncedPISearch(v));
    }
  }

  // ── PodcastIndex search ───────────────────────────────────────────────────

  // Merge PodcastIndex + Apple results; PodcastIndex wins on duplicate feed URLs.
  // Interleave API-ordered podcasts and episodes 1-for-1.
  // Both sources are already ranked by relevance by their respective APIs.
  List<_UnifiedResult> _buildUnified(
      List<PodcastResult> podcasts, List<Episode> episodes) {
    final result = <_UnifiedResult>[];
    final pi = podcasts.iterator;
    final ei = episodes.iterator;
    bool hasP = pi.moveNext();
    bool hasE = ei.moveNext();
    while (hasP || hasE) {
      if (hasP) { result.add(_UnifiedResult(podcast: pi.current)); hasP = pi.moveNext(); }
      if (hasE) { result.add(_UnifiedResult(episode: ei.current)); hasE = ei.moveNext(); }
    }
    return result;
  }

  String get _searchCountry {
    final locale = Localizations.localeOf(context);
    return (locale.countryCode ?? locale.languageCode).toLowerCase();
  }

  Future<void> _debouncedPISearch(String q) async {
    final trimmed = q.trim();
    if (trimmed.length < 2) {
      setState(() {  _unifiedSearchResults = []; });
      return;
    }
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      setState(() {  _unifiedSearchResults = []; _searchingPI = false; });
      return;
    }
    setState(() { _searchingPI = true; _searchOffset = 0; _searchHasMore = true; });
    final country = _searchCountry;
    final db = context.read<AppDatabase>();
    final fetched = await Future.wait([
      PodcastService.search(trimmed),
      PodcastService.searchEpisodes(trimmed, country: country),
    ]);
    if (!mounted || _searchQuery != q) return;
    final podcasts = fetched[0] as List<PodcastResult>;
    final apiEpisodes = fetched[1] as List<Episode>;
    final companions = apiEpisodes.map((e) => EpisodesCompanion(
      id: Value(e.id), podcastId: Value(e.podcastId),
      podcastTitle: Value(e.podcastTitle), podcastImageUrl: Value(e.podcastImageUrl),
      title: Value(e.title), description: Value(e.description),
      audioUrl: Value(e.audioUrl), durationSeconds: Value(e.durationSeconds),
      publishDate: Value(e.publishDate), isSubscribed: const Value(false),
    )).toList();
    await db.insertTempEpisodes(companions);
    if (!mounted || _searchQuery != q) return;
    setState(() {
      _unifiedSearchResults = _buildUnified(podcasts, apiEpisodes);
      _searchHasMore = (fetched[0] as List).length == 20;
      _searchingPI = false;
    });
  }

  Future<void> _loadMorePISearch() async {
    if (_loadingMoreSearch || !_searchHasMore) return;
    final q = _searchQuery;
    if (q.trim().length < 2) return;
    setState(() { _loadingMoreSearch = true; _searchOffset += 20; });
    final more = await PodcastService.search(q.trim(), offset: _searchOffset);
    if (!mounted || _searchQuery != q) return;
    if (more.isEmpty) {
      setState(() { _searchHasMore = false; _loadingMoreSearch = false; });
      return;
    }
    final existing = {for (final r in _unifiedSearchResults) if (r.podcast != null) r.podcast!.feedUrl};
    final newPods = more
        .where((p) => p.feedUrl.isNotEmpty && !existing.contains(p.feedUrl))
        .map((p) => _UnifiedResult(podcast: p))
        .toList();
    setState(() {
      _unifiedSearchResults = [..._unifiedSearchResults, ...newPods];
      _searchHasMore = more.length == 20;
      _loadingMoreSearch = false;
    });
  }

  // ── Discover data ─────────────────────────────────────────────────────────

  static const _kTrendingCacheKey = 'trending_cache_v1';
  static const _kTrendingCacheTsKey = 'trending_cache_ts_v1';

  Future<void> _loadDiscover({bool forceRefresh = false}) async {
    // Return cached data if it's less than 1 day old and we have results.
    if (!forceRefresh && _trending.isNotEmpty && _trendingFetchedAt != null &&
        DateTime.now().difference(_trendingFetchedAt!).inHours < 24) {
      return;
    }

    // Try loading from SharedPreferences cache first (survives app restarts).
    if (!forceRefresh) {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt(_kTrendingCacheTsKey);
      final raw = prefs.getString(_kTrendingCacheKey);
      if (ts != null && raw != null) {
        final age = DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(ts));
        if (age.inHours < 24) {
          try {
            final list = (jsonDecode(raw) as List)
                .cast<Map<String, dynamic>>()
                .map(PodcastResult.fromJson)
                .toList();
            if (list.isNotEmpty && mounted) {
              setState(() {
                _trending = list;
                _trendingFetchedAt = DateTime.fromMillisecondsSinceEpoch(ts);
              });
              return;
            }
          } catch (_) {}
        }
      }
    }

    if (!mounted) return;
    final locale = Localizations.localeOf(context);
    final country = (locale.countryCode ?? locale.languageCode).toLowerCase();
    final lang = locale.languageCode == 'en' ? 'en' : '${locale.languageCode},en';
    setState(() { _loadingTrending = true; _trendingError = null; });

    List<PodcastResult> charts;
    try {
      charts = await PodcastService.appleCharts(country, limit: 10);
    } catch (_) {
      charts = [];
    }
    if (!mounted) return;

    if (charts.isEmpty) {
      try {
        charts = await PodcastService.trending(max: 10, lang: lang);
      } catch (e) {
        if (mounted) setState(() { _trendingError = e.toString(); _loadingTrending = false; });
        return;
      }
    }
    if (!mounted) return;

    // Persist to cache.
    final now = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kTrendingCacheTsKey, now.millisecondsSinceEpoch);
      await prefs.setString(_kTrendingCacheKey,
          jsonEncode(charts.map((c) => c.toJson()).toList()));
    } catch (_) {}

    if (mounted) {
      setState(() {
        _trending = charts;
        _trendingFetchedAt = now;
        _loadingTrending = false;
      });
    }
  }

  // ── Subscribe ─────────────────────────────────────────────────────────────

  // Fetch first, then write everything in one transaction: the preview list
  // stays put while the network is busy, and the episode stream emits once,
  // so the list diffs in place (same episodes, now subscribed) instead of
  // emptying and refilling.
  Future<void> _subscribe(PodcastResult result) async {
    final db = context.read<AppDatabase>();
    final data = await PodcastService.loadFeed(result.feedUrl);
    final rssImage = data?.podcast.image?.isNotEmpty == true ? data!.podcast.image! : '';
    final image = rssImage.isNotEmpty ? rssImage : result.imageUrl;
    final migrated = await db.subscribePodcast(
      result.toCompanion().copyWith(imageUrl: Value(image)),
      data == null ? const [] : _asSubscribed(data.episodes, result.feedUrl, image),
    );
    await _reloadMigratedCurrent(migrated);
  }

  /// After Apple stubs were resolved: if the player holds one of them, swap
  /// in its RSS episode.
  Future<void> _reloadMigratedCurrent(Map<String, String> migrated) async {
    final db = context.read<AppDatabase>();
    final player = context.read<PlayerProvider>();
    final rssId = migrated[player.currentEpisode?.id];
    if (rssId == null) return;
    final rssEp = await db.getEpisode(rssId);
    if (rssEp != null && mounted) await player.load(rssEp);
  }

  // ── Cover tap → podcast filter (or preview for temp episodes) ───────────

  Future<void> _onCoverTap(Episode episode, AppDatabase db) async {
    final all = await db.getAllPodcasts();
    final pod = all.where((p) => p.id == episode.podcastId).firstOrNull;
    if (pod == null) {
      // Temp episode — open preview so user can subscribe
      if (!mounted) return;
      _openPreview(PodcastResult(
        id: episode.podcastId,
        title: episode.podcastTitle,
        author: '',
        description: '',
        imageUrl: episode.podcastImageUrl,
        feedUrl: episode.podcastId,
      ));
      return;
    }
    final migrated = await db.migrateAppleEpisodeStubs(pod.id);
    if (!mounted) return;
    await _reloadMigratedCurrent(migrated);
    if (!mounted) return;
    _enterPodcastFilter(pod);
  }

  void _enterPodcastFilter(Podcast podcast) {
    setState(() {
      _mode = _FeedMode.podcastFilter;
      _filterPodcastId = podcast.id;
      _filterPodcast = podcast;
      _filter = _filter.copyWith(podcasts: true);
    });
  }

  void _onPodcastTileSelect(Podcast pod) => _enterPodcastFilter(pod);

  // ── Refresh ───────────────────────────────────────────────────────────────

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

  Future<void> _refresh(AppDatabase db, {bool startup = false}) async {
    // Read before any await: the cleanup must not delete what's playing.
    final playingId = mounted
        ? context.read<PlayerProvider>().currentEpisode?.id
        : null;
    if (startup && mounted) {
      setState(() => _startupRefreshing = true);
      // Settle downloads from the last run early so progress shows right away.
      context.read<DownloadProvider>().restore();
    }
    try {
      await db.cleanupStaleTempEpisodes(keepId: playingId);
      await db.deleteFinishedDownloads();
      // Paused podcasts keep their episodes but are skipped by the auto-refresh
      // (manual pull-to-refresh on the podcast page still works).
      final pods = (await db.getAllPodcasts()).where((p) => !p.syncPaused).toList();
      // Fetch all feeds in parallel, then write once — one DB write = one stream event.
      final results = await Future.wait(pods.map((pod) async {
        final data = await PodcastService.loadFeed(pod.feedUrl);
        if (data == null) return <EpisodesCompanion>[];
        final rssImage = data.podcast.image?.isNotEmpty == true ? data.podcast.image! : '';
        // Keep Podcasts.imageUrl in sync when RSS provides a cover.
        if (rssImage.isNotEmpty && rssImage != pod.imageUrl) {
          await db.updatePodcastImageUrl(pod.id, rssImage);
        }
        // Fall back to the stored podcast cover when RSS omits the image so we
        // never overwrite a working URL with an empty string.
        final episodeImage = rssImage.isNotEmpty ? rssImage : pod.imageUrl;
        return _asSubscribed(data.episodes, pod.id, episodeImage);
      }));
      final all = results.expand((e) => e).toList();
      if (all.isNotEmpty) await db.insertEpisodes(all);
    } finally {
      // Never leave the refresh header stuck, even if a step above throws.
      if (startup && mounted) setState(() => _startupRefreshing = false);
    }
    _downloadMarkedEpisodes();
  }

  // Re-fetch a single feed's RSS and update episodes/metadata.
  // Used as the pull-to-refresh action in podcast view and preview view.
  Future<void> _refreshSinglePodcast(String feedId, {bool isSubscribed = true}) async {
    if (!mounted) return;
    final db = context.read<AppDatabase>();
    final data = await PodcastService.loadFeed(feedId);
    if (data == null || !mounted) return;

    final rssImage = data.podcast.image?.isNotEmpty == true ? data.podcast.image! : '';

    if (isSubscribed) {
      final pod = await (db.select(db.podcasts)
            ..where((p) => p.id.equals(feedId)))
          .getSingleOrNull();
      if (!mounted) return;
      final storedImage = pod?.imageUrl ?? '';
      if (rssImage.isNotEmpty && rssImage != storedImage) {
        await db.updatePodcastImageUrl(feedId, rssImage);
      }
      final episodeImage = rssImage.isNotEmpty ? rssImage : storedImage;
      final episodes = _asSubscribed(data.episodes, feedId, episodeImage);
      if (episodes.isNotEmpty) await db.insertEpisodes(episodes);
    } else {
      // Preview: refresh temp episodes and update in-memory metadata.
      final podcastImage = rssImage.isNotEmpty ? rssImage : (_previewResult?.imageUrl ?? '');
      await db.insertTempPodcast(PodcastsCompanion(
        id: Value(feedId),
        title: Value(data.podcast.title?.isNotEmpty == true
            ? data.podcast.title!
            : (_previewResult?.title ?? '')),
        description: Value(data.podcast.description ?? (_previewResult?.description ?? '')),
        imageUrl: Value(podcastImage),
        feedUrl: Value(feedId),
        author: Value(_previewResult?.author ?? ''),
      ));
      await db.insertTempEpisodes(data.episodes);
      if (mounted && _previewResult != null) {
        setState(() {
          _previewResult = PodcastResult(
            id: _previewResult!.id,
            title: data.podcast.title?.isNotEmpty == true
                ? data.podcast.title!
                : _previewResult!.title,
            author: _previewResult!.author,
            description: data.podcast.description ?? _previewResult!.description,
            imageUrl: podcastImage,
            feedUrl: feedId,
          );
        });
      }
    }
  }

  // ─── Filter chip handler ──────────────────────────────────────────────────

  void _onFilterToggle(String key) {
    // Search mode: update ephemeral search filter only, never persist.
    if (_isSearchMode) {
      setState(() {
        switch (key) {
          case 'new':
            _searchFilter = _searchFilter.copyWith(
                newOnly: !_searchFilter.newOnly, history: false);
          case 'history':
            _searchFilter = _searchFilter.copyWith(
                history: !_searchFilter.history, newOnly: false,
                downloaded: false, inProgress: false);
          case 'dl':
            _searchFilter = _searchFilter.copyWith(
                downloaded: !_searchFilter.downloaded);
          case 'az':
            _searchFilter = _searchFilter.copyWith(
                sort: _searchFilter.sort == SortMode.alphabetical
                    ? SortMode.none : SortMode.alphabetical);
          case 'oldest':
            _searchFilter = _searchFilter.copyWith(
                sort: _searchFilter.sort == SortMode.oldest
                    ? SortMode.none : SortMode.oldest);
          case 'random':
            _searchFilter = _searchFilter.copyWith(
                sort: _searchFilter.sort == SortMode.random
                    ? SortMode.none : SortMode.random);
          case 'inprogress':
            _searchFilter = _searchFilter.copyWith(
                inProgress: !_searchFilter.inProgress);
          case 'podcasts':
            _searchFilter = _searchFilter.copyWith(
                podcasts: !_searchFilter.podcasts);
        }
      });
      return;
    }

    // From podcast view, tapping Podcasts chip exits back to the episode list
    if (key == 'podcasts' &&
        (_mode == _FeedMode.podcastFilter || _mode == _FeedMode.previewPodcast)) {
      setState(() {
        _mode = _FeedMode.feed;
        _filterPodcastId = null;
        _filterPodcast = null;
        _filter = _filter.copyWith(podcasts: false);
      });
      _saveFilterPrefs();
      return;
    }
    setState(() {
      // In podcast view the podcasts flag must stay true; only clear it on the home feed.
      final inPodcastView = _mode == _FeedMode.podcastFilter || _mode == _FeedMode.previewPodcast;
      switch (key) {
        case 'new':
          _filter = _filter.copyWith(
              newOnly: !_filter.newOnly,
              history: false,
              podcasts: inPodcastView ? null : false);
        case 'history':
          _filter = _filter.copyWith(
              history: !_filter.history,
              newOnly: false,
              downloaded: false,
              inProgress: false,
              podcasts: inPodcastView ? null : false);
        case 'dl':
          _filter = _filter.copyWith(
              downloaded: !_filter.downloaded,
              podcasts: inPodcastView ? null : false);
        case 'az':
          _filter = _filter.copyWith(
            sort: _filter.sort == SortMode.alphabetical
                ? SortMode.none : SortMode.alphabetical,
            podcasts: inPodcastView ? null : false,
          );
        case 'oldest':
          _filter = _filter.copyWith(
            sort: _filter.sort == SortMode.oldest
                ? SortMode.none : SortMode.oldest,
            podcasts: inPodcastView ? null : false,
          );
        case 'random':
          _filter = _filter.copyWith(
            sort: _filter.sort == SortMode.random
                ? SortMode.none : SortMode.random,
            podcasts: inPodcastView ? null : false,
          );
        case 'inprogress':
          _filter = _filter.copyWith(
            inProgress: !_filter.inProgress,
            podcasts: inPodcastView ? null : false,
          );
        case 'podcasts':
          _filter = _filter.togglePodcasts();
      }
    });
    _saveFilterPrefs();
  }

  // feed and searchEpisodes share a key so EpisodeFeed is reused (no flash).
  // Preview and podcast page of the same feed share one too, so subscribing
  // or unsubscribing (keep episodes) updates the list in place.
  Key get _bodyKey {
    switch (_mode) {
      case _FeedMode.feed:
      case _FeedMode.searchEpisodes:
        return const ValueKey('episode_feed');
      case _FeedMode.podcastFilter:
        return ValueKey('podcast_${_filterPodcast?.feedUrl ?? _filterPodcastId ?? ""}');
      case _FeedMode.discover:
        return const ValueKey('discover');
      case _FeedMode.previewPodcast:
        return ValueKey('podcast_${_previewResult?.feedUrl ?? ""}');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final searchOpen =
        _mode == _FeedMode.discover || _mode == _FeedMode.searchEpisodes;

    return PopScope(
      canPop: _mode == _FeedMode.feed,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_mode == _FeedMode.previewPodcast) {
          _exitPreview();
        } else {
          _exitToFeed();
        }
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _Toolbar(
                    mode: _mode, searchOpen: searchOpen,
                    searchCtrl: _searchCtrl, filter: _effectiveFilter,
                    filterChipsVisible: _effectiveChipsVisible,
                    l10n: l10n, cs: cs,
                    onBack: _mode == _FeedMode.previewPodcast ? _exitPreview : _exitToFeed,
                    onSearchChanged: _onSearchChanged,
                    onClearSearch: () => setState(() {
                      _searchQuery = ''; _searchCtrl.clear(); 
                    }),
                    onSearchOpen: () {
                      final fromPodcast = _mode == _FeedMode.podcastFilter;
                      setState(() {
                        _mode = _FeedMode.searchEpisodes;
                        _searchQuery = ''; _searchCtrl.clear();
                        if (fromPodcast) {
                          _searchPodcastId = _filterPodcastId;
                          _searchFilter = const FilterState(newOnly: false, podcasts: true);
                          _searchFilterChipsVisible = true;
                        } else {
                          _searchPodcastId = null;
                          _searchFilter = const FilterState(newOnly: false);
                          _searchFilterChipsVisible = false;
                        }
                      });
                    },
                    onPlusPressed: _enterDiscover,
                    onFilterToggle: _toggleFilterChips,
                    onLogoTap: () => _showAbout(context),
                    onInfoPressed: () => launchUrl(
                      Uri.parse('https://antpod.eu/guide'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(child: _AntWalker(key: _antWalkerKey)),
                  ),
                ],
              ),

              // Filter chips — visible in feed and episode-search modes.
              // The 10px top spacer is inside the collapse so it folds away too.
              ClipRect(
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  heightFactor: (_effectiveChipsVisible && !_linkOpening &&
                          (_mode == _FeedMode.feed ||
                           _mode == _FeedMode.searchEpisodes))
                      ? 1.0
                      : 0.0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: (_effectiveChipsVisible && !_linkOpening &&
                            (_mode == _FeedMode.feed ||
                             _mode == _FeedMode.searchEpisodes))
                        ? 1.0
                        : 0.0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 10),
                        FilterChipsRow(
                          filter: _effectiveFilter, l10n: l10n, cs: cs,
                          onToggle: _onFilterToggle,
                          showPodcastsChip: !_isSearchMode || _searchPodcastId != null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Expanded(
                child: Stack(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: KeyedSubtree(
                        key: _bodyKey,
                        child: _buildBody(db, cs, l10n),
                      ),
                    ),
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: MiniPlayer(onPodcastTap: _openPodcastFromPlayer),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppDatabase db, ColorScheme cs, AppLocalizations l10n) {
    switch (_mode) {
      case _FeedMode.previewPodcast:
        return _PodcastFeed(
          db: db, cs: cs, l10n: l10n,
          feedId: _previewResult!.feedUrl,
          imageUrl: _previewResult!.imageUrl,
          title: _previewResult!.title,
          author: _previewResult!.author,
          description: _previewResult!.description,
          shareUrl: ShareUtils.podcastResultUrl(_previewResult!),
          isSubscribed: false,
          isLoading: _previewLoading,
          filter: _filter,
          filterChipsVisible: _filterChipsVisible,
          onFilterToggle: _onFilterToggle,
          onRefresh: () => _refreshSinglePodcast(_previewResult!.feedUrl, isSubscribed: false),
          onSubscribe: () async {
            final result = _previewResult!;
            final db = context.read<AppDatabase>();
            await _subscribe(result);
            if (!mounted) return;
            // Land on the new podcast's page; back from there returns home.
            final pod = await (db.select(db.podcasts)
                  ..where((p) => p.id.equals(result.feedUrl)))
                .getSingleOrNull();
            if (!mounted) return;
            _previewResult = null;
            if (pod != null) {
              _enterPodcastFilter(pod);
            } else {
              _exitToFeed();
            }
          },
        );

      case _FeedMode.podcastFilter:
        return _PodcastFeed(
          db: db, cs: cs, l10n: l10n,
          feedId: _filterPodcastId!,
          imageUrl: _filterPodcast?.imageUrl ?? '',
          title: _filterPodcast?.title ?? '',
          author: _filterPodcast?.author ?? '',
          description: _filterPodcast?.description ?? '',
          shareUrl: _filterPodcast != null ? ShareUtils.podcastUrl(_filterPodcast!) : '',
          isSubscribed: true,
          filter: _filter,
          filterChipsVisible: _filterChipsVisible,
          onFilterToggle: _onFilterToggle,
          onRefresh: () => _refreshSinglePodcast(_filterPodcastId!),
          onCoverTap: _onCoverTap,
          // Paused counts as not subscribed: + resumes new episodes.
          onSubscribe: _filterPodcast?.syncPaused == true
              ? () => _setSyncPaused(_filterPodcast!, false)
              : null,
          onUnsubscribe: _filterPodcast != null && !_filterPodcast!.syncPaused
              ? () => _confirmUnsubscribe(_filterPodcast!)
              : null,
          syncPaused: _filterPodcast?.syncPaused ?? false,
        );

      case _FeedMode.discover:
        return _DiscoverList(
          searchQuery: _searchQuery,
          trending: _trending,
          unifiedSearchResults: _unifiedSearchResults,
          loadingTrending: _loadingTrending,
          searchingPI: _searchingPI,
          searchHasMore: _searchHasMore,
          loadingMoreSearch: _loadingMoreSearch,
          isOffline: _isOffline,
          trendingError: _trendingError,
          cs: cs, l10n: l10n,
          onPreview: _openPodcastResult,
          onRefresh: () => _loadDiscover(forceRefresh: true),
          onLoadMore: _loadMorePISearch,
          onCoverTap: _openPodcastResult,
        );

      case _FeedMode.feed:
      case _FeedMode.searchEpisodes:
        if (_linkOpening && _mode == _FeedMode.feed) {
          return const SizedBox.expand();
        }
        if (_filter.podcasts && !_isSearchMode) {
          return _PodcastGrid(
            db: db, cs: cs, l10n: l10n,
            onSelect: _onPodcastTileSelect,
          );
        }
        return EpisodeFeed(
          db: db, cs: cs, l10n: l10n, filter: _effectiveFilter,
          searchQuery: _mode == _FeedMode.searchEpisodes ? _searchQuery : '',
          podcastIdFilter: _isSearchMode ? _searchPodcastId : null,
          onCoverTap: _onCoverTap, onRefresh: () => _refresh(db),
          onSearchOnline: _mode == _FeedMode.searchEpisodes ? _searchOnline : null,
          refreshing: _startupRefreshing,
          onShowAllDownloads: _effectiveFilter.downloaded && !_isSearchMode
              ? () => setState(() {
                    _filter = const FilterState(downloaded: true, newOnly: false);
                    _saveFilterPrefs();
                  })
              : null,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toolbar
// ─────────────────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final _FeedMode mode;
  final bool searchOpen;
  final TextEditingController searchCtrl;
  final FilterState filter;
  final bool filterChipsVisible;
  final AppLocalizations l10n;
  final ColorScheme cs;
  final VoidCallback onBack;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onSearchOpen;
  final VoidCallback onPlusPressed;
  final VoidCallback onFilterToggle;
  final VoidCallback onLogoTap;
  final VoidCallback onInfoPressed;

  const _Toolbar({
    required this.mode, required this.searchOpen, required this.searchCtrl,
    required this.filter, required this.filterChipsVisible,
    required this.l10n, required this.cs,
    required this.onBack, required this.onSearchChanged, required this.onClearSearch,
    required this.onSearchOpen, required this.onPlusPressed,
    required this.onFilterToggle, required this.onLogoTap,
    required this.onInfoPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.5))),
      child: searchOpen ? _searchRow() : _defaultRow(),
    );
  }

  Widget _searchRow() {
    return Row(
      children: [
        IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
        Expanded(
          child: TextField(
            controller: searchCtrl, autofocus: true,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: mode == _FeedMode.discover
                  ? l10n.searchHint : l10n.toolbarSearchHint,
              border: InputBorder.none,
              hintStyle: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ),
        if (searchCtrl.text.isNotEmpty)
          IconButton(icon: const Icon(Icons.clear_rounded, size: 20), onPressed: onClearSearch),
        if (mode == _FeedMode.searchEpisodes)
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: Icon(Icons.tune_rounded,
                    color: filterChipsVisible ? cs.primary : cs.onSurface),
                onPressed: onFilterToggle,
                tooltip: 'Filter',
              ),
              if (filter.hasAny)
                Positioned(right: 8, top: 8, child: Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                )),
            ],
          ),
      ],
    );
  }

  Widget _defaultRow() {
    final inPodcast = mode == _FeedMode.podcastFilter || mode == _FeedMode.previewPodcast;
    return Row(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: inPodcast
              ? IconButton(
                  key: const ValueKey('back'),
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: onBack)
              : Row(
                  key: const ValueKey('brand'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: onLogoTap,
                      child: ClipOval(child: SvgPicture.asset('antpodlogo.svg', width: 28, height: 28)),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onLogoTap,
                      child: Text('AntPod', style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 20,
                        color: cs.onSurface, letterSpacing: -0.5)),
                    ),
                    Tooltip(
                      message: 'Guide',
                      child: GestureDetector(
                        onTap: onInfoPressed,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 16, 28, 16),
                          child: Icon(Icons.info_rounded, size: 18, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        const Spacer(),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(Icons.tune_rounded,
                  color: filterChipsVisible ? cs.primary : cs.onSurface),
              onPressed: onFilterToggle,
              tooltip: 'Filter',
            ),
            if (filter.hasAny)
              Positioned(right: 8, top: 8, child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
              )),
          ],
        ),
        IconButton(
          icon: Icon(Icons.search_rounded, color: cs.onSurface),
          onPressed: onSearchOpen,
          tooltip: 'Search'),
        IconButton(
          icon: Icon(Icons.add_rounded, color: cs.onSurface),
          onPressed: onPlusPressed,
          tooltip: 'Discover'),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Podcast grid
// ─────────────────────────────────────────────────────────────────────────────


class _PodcastGrid extends StatelessWidget {
  final AppDatabase db;
  final ColorScheme cs;
  final AppLocalizations l10n;
  final ValueChanged<Podcast> onSelect;

  const _PodcastGrid({
    required this.db, required this.cs,
    required this.l10n, required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Podcast>>(
      stream: db.watchAllPodcasts(),
      builder: (context, snap) {
        final pods = snap.data ?? [];
        if (pods.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.podcasts_rounded, size: 52, color: cs.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(l10n.emptyPodcastsTitle,
                    style: TextStyle(
                        fontSize: 16, color: cs.onSurfaceVariant)),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.68,
          ),
          itemCount: pods.length,
          itemBuilder: (_, i) => _PodcastGridTile(
            podcast: pods[i], cs: cs, onTap: () => onSelect(pods[i]),
          ),
        );
      },
    );
  }
}

class _PodcastGridTile extends StatelessWidget {
  final Podcast podcast;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _PodcastGridTile({
    required this.podcast, required this.cs, required this.onTap,
  });

  void _share() {
    final url = ShareUtils.podcastUrl(podcast);
    SharePlus.instance.share(ShareParams(text: '${podcast.title}\n$url', subject: podcast.title));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: _share,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: podcast.imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                    color: cs.surfaceContainerHighest,
                    child: const Icon(Icons.podcasts_rounded, size: 36)),
                errorWidget: (_, __, ___) => Container(
                    color: cs.surfaceContainerHighest,
                    child: const Icon(Icons.podcasts_rounded, size: 36)),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            podcast.title,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: cs.onSurface),
          ),
          if (podcast.author.isNotEmpty)
            Text(
              podcast.author,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}


class _PodcastFeed extends StatelessWidget {
  final AppDatabase db;
  final ColorScheme cs;
  final AppLocalizations l10n;
  final String feedId;
  final String imageUrl;
  final String title;
  final String author;
  final String description;
  final String shareUrl;
  final bool isSubscribed;
  final FilterState filter;
  final bool filterChipsVisible;
  final ValueChanged<String> onFilterToggle;
  final Future<void> Function(Episode, AppDatabase)? onCoverTap;
  final VoidCallback? onSubscribe;
  final VoidCallback? onUnsubscribe;
  final Future<void> Function()? onRefresh;
  final bool isLoading;
  final bool syncPaused;

  const _PodcastFeed({
    required this.db, required this.cs, required this.l10n,
    required this.feedId, required this.imageUrl, required this.title,
    required this.author, required this.description, required this.shareUrl,
    required this.isSubscribed,
    required this.filter, required this.filterChipsVisible,
    required this.onFilterToggle,
    this.onCoverTap, this.onSubscribe, this.onUnsubscribe,
    this.onRefresh, this.isLoading = false, this.syncPaused = false,
  });

  @override
  Widget build(BuildContext context) {
    return EpisodeFeed(
      db: db, cs: cs, l10n: l10n,
      filter: filter,
      podcastIdFilter: feedId,
      onCoverTap: onCoverTap ?? (_, __) async {},
      onRefresh: onRefresh ?? () async {},
      isLoading: isLoading,
      headerSlivers: [
        PodcastHeader(
          imageUrl: imageUrl,
          title: title,
          author: author,
          description: description,
          shareUrl: shareUrl,
          onSubscribe: onSubscribe,
          onUnsubscribe: onUnsubscribe,
          syncPaused: syncPaused,
        ),
        ClipRect(
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            heightFactor: filterChipsVisible ? 1.0 : 0.0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: filterChipsVisible ? 1.0 : 0.0,
              child: FilterChipsRow(
                filter: filter, l10n: l10n, cs: cs,
                onToggle: onFilterToggle,
                showPodcastsChip: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Discover list
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Unified search result (podcast or episode, pre-scored for interleaving)
// ─────────────────────────────────────────────────────────────────────────────

class _UnifiedResult {
  final PodcastResult? podcast;
  final Episode? episode;
  const _UnifiedResult({this.podcast, this.episode});
}

class _DiscoverList extends StatefulWidget {
  final String searchQuery;
  final List<PodcastResult> trending;
  final List<_UnifiedResult> unifiedSearchResults;
  final bool loadingTrending, searchingPI;
  final bool searchHasMore, loadingMoreSearch;
  final bool isOffline;
  final String? trendingError;
  final ColorScheme cs;
  final AppLocalizations l10n;
  final void Function(PodcastResult) onPreview;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final void Function(PodcastResult) onCoverTap;

  const _DiscoverList({
    required this.searchQuery, required this.trending,
    required this.unifiedSearchResults,
    required this.loadingTrending, required this.searchingPI,
    required this.searchHasMore, required this.loadingMoreSearch,
    this.isOffline = false,
    this.trendingError,
    required this.cs, required this.l10n,
    required this.onPreview, required this.onRefresh,
    required this.onLoadMore, required this.onCoverTap,
  });

  @override
  State<_DiscoverList> createState() => _DiscoverListState();
}

class _DiscoverListState extends State<_DiscoverList> {
  final _searchScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchScrollCtrl.addListener(_onSearchScroll);
  }

  void _onSearchScroll() {
    if (_searchScrollCtrl.position.pixels >=
        _searchScrollCtrl.position.maxScrollExtent - 300) {
      widget.onLoadMore();
    }
  }

  @override
  void dispose() {
    _searchScrollCtrl.dispose();
    super.dispose();
  }

  bool _isUrl(String q) {
    final lower = q.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  void _showRssDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.l10n.addRssFeed),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://...',
            prefixIcon: Icon(Icons.rss_feed_rounded),
          ),
          keyboardType: TextInputType.url,
          onSubmitted: (url) {
            url = url.trim();
            if (url.isEmpty) return;
            Navigator.pop(ctx);
            widget.onPreview(PodcastResult(
              id: url, title: '', author: '', description: '',
              imageUrl: '', feedUrl: url,
            ));
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(widget.l10n.cancel)),
          FilledButton(
            onPressed: () {
              final url = ctrl.text.trim();
              if (url.isEmpty) return;
              Navigator.pop(ctx);
              widget.onPreview(PodcastResult(
                id: url, title: '', author: '', description: '',
                imageUrl: '', feedUrl: url,
              ));
            },
            child: Text(widget.l10n.openFeed),
          ),
        ],
      ),
    );
  }

  Widget _unifiedList(List<_UnifiedResult> results) {
    final itemCount = results.length + (widget.loadingMoreSearch ? 1 : 0);
    return ListView.builder(
      controller: _searchScrollCtrl,
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: itemCount,
      itemBuilder: (_, i) {
        if (i >= results.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final r = results[i];
        if (r.podcast != null) {
          return _DiscoverPodcastTile(
            result: r.podcast!, rank: i + 1, showRank: false,
            cs: widget.cs, l10n: widget.l10n,
            onPreview: widget.onPreview,
          );
        }
        final ep = r.episode!;
        return Column(children: [
          EpisodeTile(
            episode: ep,
            isSubscribedContext: false,
            onCoverTap: () => widget.onCoverTap(PodcastResult(
              id: ep.podcastId, title: ep.podcastTitle, author: '',
              description: '', imageUrl: ep.podcastImageUrl, feedUrl: ep.podcastId,
            )),
          ),
          Divider(height: 1,
              color: widget.cs.outlineVariant.withValues(alpha: 0.5), indent: 88),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final l10n = widget.l10n;

    // ── Search results overlay ──────────────────────────────────────────────
    if (widget.searchQuery.trim().length >= 2) {
      if (_isUrl(widget.searchQuery)) {
        final url = widget.searchQuery.trim();
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.rss_feed_rounded, size: 44, color: cs.primary),
                const SizedBox(height: 14),
                Text(l10n.subscribeToRss,
                    style: TextStyle(fontWeight: FontWeight.w600,
                        fontSize: 16, color: cs.onSurface)),
                const SizedBox(height: 6),
                Text(url,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    maxLines: 3, overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () => widget.onPreview(PodcastResult(
                    id: url, title: '', author: '', description: '',
                    imageUrl: '', feedUrl: url,
                  )),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(l10n.openFeed),
                ),
              ],
            ),
          ),
        );
      }

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: widget.searchingPI
            ? const Center(child: CircularProgressIndicator())
            : widget.unifiedSearchResults.isEmpty
                ? Center(
                    child: widget.isOffline
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.wifi_off_rounded, size: 36,
                                  color: cs.onSurfaceVariant),
                              const SizedBox(height: 8),
                              Text(l10n.offlineSub,
                                  style: TextStyle(color: cs.onSurfaceVariant)),
                            ],
                          )
                        : Text(l10n.searchNoResults,
                            style: TextStyle(color: cs.onSurfaceVariant)),
                  )
                : _unifiedList(widget.unifiedSearchResults),
      );
    }

    // ── Trending list ────────────────────────────────────────────────────────
    return Column(
      children: [
        InkWell(
          onTap: () => _showRssDialog(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.rss_feed_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 12),
                Text(l10n.addByRssUrl,
                    style: TextStyle(fontWeight: FontWeight.w600,
                        fontSize: 14, color: cs.onSurface)),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant, size: 20),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            // One scroll view in every state: the title scrolls away with the
            // list, and pull-to-refresh also works while loading/empty/error.
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _trendsTitle(cs)),
                if (widget.loadingTrending)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (widget.trendingError != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        Icon(Icons.wifi_off_rounded,
                            size: 40, color: cs.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text('Could not load trending podcasts',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text(widget.trendingError!,
                            style: TextStyle(fontSize: 12,
                                color: cs.onSurfaceVariant),
                            textAlign: TextAlign.center),
                      ]),
                    ),
                  )
                else if (widget.trending.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('No trending podcasts available.',
                        style: TextStyle(color: cs.onSurfaceVariant))),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 88),
                    sliver: SliverList.builder(
                      itemCount: widget.trending.length,
                      itemBuilder: (_, i) => _DiscoverPodcastTile(
                        result: widget.trending[i], rank: i + 1,
                        cs: widget.cs, l10n: widget.l10n,
                        onPreview: widget.onPreview,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Tab-like pill so the section title reads as a label, not body text.
  Widget _trendsTitle(ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              // The active filter chip's color: as the border, and as a
              // light tint behind the (orange) title.
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.primary, width: 1.5),
            ),
            child: const Text('Apple Trends',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                    color: Color(0xFFFF9A30))),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Discover podcast tile
// ─────────────────────────────────────────────────────────────────────────────

class _DiscoverPodcastTile extends StatelessWidget {
  final PodcastResult result;
  final int rank;
  final bool showRank;
  final ColorScheme cs;
  final AppLocalizations l10n;
  final void Function(PodcastResult) onPreview;

  const _DiscoverPodcastTile({
    required this.result, required this.rank, required this.cs,
    required this.l10n, required this.onPreview, this.showRank = true,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
    final cs = this.cs;

    return InkWell(
      onTap: () => onPreview(r),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (showRank) ...[
              SizedBox(
                width: 28,
                child: Text('$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary)),
              ),
              const SizedBox(width: 8),
            ],
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: r.imageUrl, width: 56, height: 56, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 56, height: 56, color: cs.surfaceContainerHighest,
                  child: const Icon(Icons.podcasts_rounded, size: 28)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14,
                      color: cs.onSurface)),
                  if (r.author.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(r.author,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Speech-bubble painter for the About dialog
// ─────────────────────────────────────────────────────────────────────────────

const _kGithubSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
  <path fill="#000000" fill-rule="evenodd" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38
    0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01
    1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95
    0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0
    1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15
    0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38
    A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/>
</svg>
''';

class _BubblePainter extends CustomPainter {
  final ColorScheme cs;
  const _BubblePainter({required this.cs});

  @override
  void paint(Canvas canvas, Size size) {
    const r = 14.0;
    const triW = 18.0;
    const triH = 11.0;
    const triX = 36.0; // triangle tip x, aligned near top-left logo

    final path = Path()
      ..moveTo(r, triH)
      ..lineTo(triX - triW / 2, triH)
      ..lineTo(triX, 0)
      ..lineTo(triX + triW / 2, triH)
      ..lineTo(size.width - r, triH)
      ..arcToPoint(Offset(size.width, triH + r), radius: const Radius.circular(r))
      ..lineTo(size.width, size.height - r)
      ..arcToPoint(Offset(size.width - r, size.height), radius: const Radius.circular(r))
      ..lineTo(r, size.height)
      ..arcToPoint(Offset(0, size.height - r), radius: const Radius.circular(r))
      ..lineTo(0, triH + r)
      ..arcToPoint(Offset(r, triH), radius: const Radius.circular(r))
      ..close();

    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    final fill = Paint()
      ..shader = LinearGradient(
        colors: [cs.primaryContainer, cs.secondaryContainer, cs.tertiaryContainer],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds)
      ..style = PaintingStyle.fill;

    canvas.drawShadow(path, cs.primary.withValues(alpha: 0.3), 12, false);
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.cs != cs;
}

// ─────────────────────────────────────────────────────────────────────────────
// Ant walker — decorative ant that occasionally strolls across the toolbar
// ─────────────────────────────────────────────────────────────────────────────

class _AntWalker extends StatefulWidget {
  const _AntWalker({super.key});

  @override
  State<_AntWalker> createState() => _AntWalkerState();
}

class _AntWalkerState extends State<_AntWalker> with TickerProviderStateMixin {
  late final AnimationController _legCtrl;
  late final AnimationController _pathCtrl;
  Timer? _timer;
  _AntPath? _path;
  bool _walking = false;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _legCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    // _legCtrl only runs during a walk — stopped the rest of the time
    // so it doesn't hold a continuous animation frame callback.

    _pathCtrl = AnimationController(vsync: this);
    _pathCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        _legCtrl.stop();
        setState(() => _walking = false);
        _scheduleNext();
      }
    });

    _scheduleNext();
  }

  @override
  void dispose() {
    _legCtrl.dispose();
    _pathCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleNext() {
    // Random gap between 8 and 20 minutes
    final ms = 480000 + _rng.nextInt(720001);
    _timer = Timer(Duration(milliseconds: ms), () {
      if (mounted) _startWalk();
    });
  }

  void _startWalk() {
    _timer?.cancel();
    if (_walking) return;
    final w = MediaQuery.sizeOf(context).width;
    const toolbarH = 56.0;
    const margin = 10.0;

    final fromLeft = _rng.nextBool();
    final startX = fromLeft ? -20.0 : w + 20.0;
    final endX   = fromLeft ? w + 20.0 : -20.0;

    double randY() => margin + _rng.nextDouble() * (toolbarH - 2 * margin);

    // 2–4 interior waypoints for an organic, meandering path
    final numInterior = 2 + _rng.nextInt(3);
    final pts = <Offset>[Offset(startX, randY())];
    for (int i = 0; i < numInterior; i++) {
      final baseFrac = (i + 1) / (numInterior + 1);
      // Slight X jitter so progress isn't perfectly linear
      final xJitter = (endX - startX) * (_rng.nextDouble() - 0.5) * 0.16;
      final x = (startX + (endX - startX) * baseFrac + xJitter)
          .clamp(math.min(startX, endX), math.max(startX, endX)) as double;
      pts.add(Offset(x, randY()));
    }
    pts.add(Offset(endX, randY()));

    _path = _AntPath(pts);
    _pathCtrl.duration = Duration(milliseconds: 4000 + _rng.nextInt(3000));
    _pathCtrl.reset();
    _legCtrl.repeat();
    setState(() => _walking = true);
    _pathCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (!_walking || _path == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: Listenable.merge([_legCtrl, _pathCtrl]),
      builder: (_, __) {
        final pos   = _path!.evaluate(_pathCtrl.value);
        final angle = _path!.angle(_pathCtrl.value);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            const SizedBox.expand(), // gives the Stack its size from tight constraints
            Positioned(
              left: pos.dx - 14,
              top:  pos.dy - 14,
              width: 28, height: 28,
              child: Transform.rotate(
                angle: angle,
                child: CustomPaint(
                  painter: _AntPainter(
                    legPhase: _legCtrl.value,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFFD4956A)
                        : const Color(0xFF7B3F00),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// Multi-waypoint Catmull-Rom spline — smooth curves through arbitrary waypoints.
class _AntPath {
  final List<Offset> _pts;
  final List<double> _cumT; // cumulative t per segment (straight-line length proxy)

  _AntPath(List<Offset> pts)
      : _pts = pts,
        _cumT = _buildCumT(pts);

  static List<double> _buildCumT(List<Offset> pts) {
    double total = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      total += (pts[i + 1] - pts[i]).distance;
    }
    final result = [0.0];
    double acc = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      acc += (pts[i + 1] - pts[i]).distance;
      result.add(total > 0 ? acc / total : (i + 1) / (pts.length - 1).toDouble());
    }
    return result;
  }

  // Catmull-Rom bezier control points for segment i → i+1
  (Offset, Offset) _cp(int i) {
    final p0 = _pts[i];
    final p1 = _pts[i + 1];
    final prev = i > 0 ? _pts[i - 1] : p0 * 2 - p1;
    final next = i + 2 < _pts.length ? _pts[i + 2] : p1 * 2 - p0;
    return (p0 + (p1 - prev) * (1 / 6), p1 - (next - p0) * (1 / 6));
  }

  Offset evaluate(double t) {
    t = t.clamp(0.0, 1.0);
    for (int i = 0; i < _pts.length - 1; i++) {
      if (t <= _cumT[i + 1] || i == _pts.length - 2) {
        final span = _cumT[i + 1] - _cumT[i];
        final u = span > 1e-6 ? ((t - _cumT[i]) / span).clamp(0.0, 1.0) : 0.0;
        final (cp1, cp2) = _cp(i);
        final p0 = _pts[i]; final p1 = _pts[i + 1];
        final s = 1 - u;
        return p0 * (s*s*s) + cp1 * (3*s*s*u) + cp2 * (3*s*u*u) + p1 * (u*u*u);
      }
    }
    return _pts.last;
  }

  double angle(double t) {
    const dt = 0.002;
    final a = evaluate((t - dt).clamp(0.0, 1.0));
    final b = evaluate((t + dt).clamp(0.0, 1.0));
    final d = b - a;
    if (d.distanceSquared < 1e-10) return 0;
    return math.atan2(d.dy, d.dx) + math.pi / 2;
  }
}

// Ant drawn top-down, centered at (0,0) in local coords, facing -y
class _AntPainter extends CustomPainter {
  final double legPhase;
  final Color color;

  const _AntPainter({required this.legPhase, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);

    final fill = Paint()..color = color..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 0.85
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final t = legPhase * math.pi * 2;

    // Abdomen (largest, rear)
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 5.5), width: 5.5, height: 7),
      fill,
    );
    // Thorax (tiny waist in the middle)
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 3.2, height: 3.5),
      fill,
    );
    // Head (front)
    canvas.drawCircle(const Offset(0, -5.5), 2.8, fill);

    // Antennae — subtly wiggle
    canvas.drawLine(const Offset(0, -8.3),
        Offset(-3 + math.sin(t) * 0.25, -12.5), stroke);
    canvas.drawLine(const Offset(0, -8.3),
        Offset( 3 - math.sin(t) * 0.25, -12.5), stroke);

    // Six legs (3 pairs) with alternating-tripod gait
    for (var i = 0; i < 3; i++) {
      final yA = (i - 1) * 2.2; // –2.2, 0, +2.2 along the thorax

      // Right leg — tripod A swings on even indices
      final rP = (i.isEven) ? t : t + math.pi;
      final rSwing = math.sin(rP) * 2.2;
      canvas.drawLine(Offset(1.6, yA), Offset(7, yA + rSwing), stroke);

      // Left leg — opposite tripod
      final lP = (i.isOdd) ? t : t + math.pi;
      final lSwing = math.sin(lP) * 2.2;
      canvas.drawLine(Offset(-1.6, yA), Offset(-7, yA + lSwing), stroke);
    }
  }

  @override
  bool shouldRepaint(_AntPainter old) => old.legPhase != legPhase || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Lazy tile — skeleton on first frame, real EpisodeTile on second.
// Must NOT be given a ValueKey: without a key Flutter reconciles by position,
// so _ready stays true when items shift after insert/remove (no skeleton blip
// for existing items). Skeleton only shows for genuinely new inserts.
// ─────────────────────────────────────────────────────────────────────────────

