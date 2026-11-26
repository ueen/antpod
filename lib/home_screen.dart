// lib/home_screen.dart
import 'dart:async';
import 'dart:convert';

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

import 'about.dart';
import 'app_database.dart';
import 'download_provider.dart';
import 'discover_list.dart';
import 'download_service.dart';
import 'episode_feed.dart';
import 'feed_state.dart';
import 'feed_sync.dart';
import 'filter_chips.dart';
import 'l10n/app_localizations.dart';
import 'mini_player.dart';
import 'player_provider.dart';
import 'podcast_header.dart';
import 'podcast_service.dart';
import 'share_utils.dart';
import 'network.dart';

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

  final _antWalkerKey = GlobalKey<AntWalkerState>();

  String? _filterPodcastId;
  Podcast? _filterPodcast;

  // Set when search is opened from a podcast feed; null when opened from home.
  String? _searchPodcastId;

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _piSearchTimer;

  List<PodcastResult> _trending = [];
  DateTime? _trendingFetchedAt;
  List<UnifiedResult> _unifiedSearchResults = [];
  int _searchOffset = 0;
  bool _searchHasMore = true;
  bool _loadingMoreSearch = false;
  bool _loadingTrending = false;
  bool _searchingPI = false;
  bool _trendingFailed = false;

  // Preview (unsubscribed podcast header + episodes)
  PodcastResult? _previewResult;
  _FeedMode _previewFrom = _FeedMode.discover;
  bool _previewLoading = false;

  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<Object>? _playerErrorSub;
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
      if (results.isOffline != _isOffline) setState(() => _isOffline = results.isOffline);
      if (results.isUnmetered) _downloadMarkedEpisodes();
    });

    // Playback that failed: say so, instead of a player that just stops.
    _playerErrorSub = context.read<PlayerProvider>().errors.listen((_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      final player = context.read<PlayerProvider>();
      final offline =
          player.isOffline && player.currentEpisode?.localPath == null;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(offline ? l10n.offlineSub : l10n.playbackError)));
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
      // No subscriptions: Discover is home (back from a linked preview
      // lands there too, see _exitPreview).
      if (pods.isEmpty && _mode == _FeedMode.feed) _enterDiscover();
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
    final feed = ShareUtils.restoreProto(rawFeed);
    final guidHash = q['e'] ?? q['h'];
    final db = context.read<AppDatabase>();

    // Close any open player sheet / dialog / pushed page so the target is visible.
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (_mode != _FeedMode.feed || _searchQuery.isNotEmpty) _exitToFeed();

    final subscribed = await db.findSubscribed(feed);
    if (!mounted) return;

    final hasEpisode = guidHash != null && guidHash.isNotEmpty;

    // Routing below leaves the home feed, so it no longer needs blanking.
    _linkOpening = false;

    // ── Subscribed podcast ────────────────────────────────────────────────
    if (subscribed != null) {
      await _openSubscribed(subscribed);
      if (!hasEpisode || !mounted) return;
      var episode = await _findByHash(db, subscribed.id, guidHash);
      if (episode == null) {
        // Not in the DB yet (feed not refreshed since it was published).
        await FeedSync.refreshPodcast(db, subscribed.id);
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
    final loading =
        _openPreview(PodcastResult.feed(feed, title: existing?.podcastTitle ?? ''));
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
    final ep = context.read<PlayerProvider>().currentEpisode;
    if (ep != null) _openPodcast(PodcastResult.fromEpisode(ep));
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
    _playerErrorSub?.cancel();
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
      if (!(await Connectivity().checkConnectivity()).isUnmetered) return;
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
        } catch (e) {
          debugPrint('[home] queued download error: $e');
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

  /// Opens a podcast from anywhere (search, trending, a cover, the player):
  /// its page when subscribed, otherwise a preview.
  Future<void> _openPodcast(PodcastResult result) async {
    final subscribed = await context.read<AppDatabase>().findSubscribed(result.feedUrl);
    if (!mounted) return;
    if (subscribed != null) {
      await _openSubscribed(subscribed);
    } else {
      _openPreview(result);
    }
  }

  Future<void> _openSubscribed(Podcast podcast) async {
    _enterPodcastFilter(podcast);
    // Resolve apple-* stubs played from search results for this podcast
    // (no-op when there are none).
    final migrated =
        await context.read<AppDatabase>().migrateAppleEpisodeStubs(podcast.id);
    if (mounted) await _reloadMigratedCurrent(migrated);
  }

  /// Shows the preview for [result] at once and loads its feed into the DB as
  /// temp rows. Returns the loaded feed (null on failure) so a deep link can
  /// pick its episode out of the same load.
  Future<FeedData?> _openPreview(PodcastResult result) {
    setState(() {
      _previewResult = result.copyWith(imageUrl: ''); // placeholder until the RSS cover
      _previewLoading = true;
      _previewFrom = _mode;
      _mode = _FeedMode.previewPodcast;
      _filter = _filter.copyWith(podcasts: true);
    });
    return _loadPreview(result);
  }

  /// Loads the preview's feed and fills in its header; also the preview's
  /// pull-to-refresh.
  Future<FeedData?> _loadPreview(PodcastResult result) async {
    final loaded = await FeedSync.loadPreview(context.read<AppDatabase>(), result);
    if (!mounted) return loaded?.data;
    if (loaded != null) await _reloadMigratedCurrent(loaded.migrated);
    // Still showing this preview? The user may have left or opened another.
    if (mounted &&
        _mode == _FeedMode.previewPodcast &&
        _previewResult?.feedUrl == result.feedUrl) {
      setState(() {
        if (loaded != null) _previewResult = loaded.result;
        _previewLoading = false;
      });
    }
    return loaded?.data;
  }

  Future<void> _exitPreview() async {
    var target = _previewFrom;
    // Without subscriptions home is empty, so Discover stands in for it
    // (a linked preview on a fresh install, or the last podcast unsubscribed).
    if (target == _FeedMode.feed) {
      final pods = await context.read<AppDatabase>().getAllPodcasts();
      if (!mounted || _mode != _FeedMode.previewPodcast) return;
      if (pods.isEmpty) target = _FeedMode.discover;
    }
    setState(() {
      _mode = target;
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
  // the user decides. Then a bottom sheet: unsubscribe & delete (destructive);
  // finish episodes (temp feed that goes once played out; only when something
  // is downloaded or started); don't load new episodes (stays subscribed and
  // as is, just no refresh). The last two only flip flags: nothing is deleted.
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
                if (canKeep) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error,
                      side: BorderSide(color: cs.error.withValues(alpha: 0.6)),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(PodcastHeader.finishEpisodesIcon),
                    label: Text(l10n.unsubscribeFinishEpisodes),
                    onPressed: () => Navigator.pop(ctx, 'finish'),
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(PodcastHeader.stopNewEpisodesIcon),
                  label: Text(l10n.stopNewEpisodes),
                  onPressed: () => Navigator.pop(ctx, 'stop'),
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
    } else if (action == 'finish') {
      await _unsubscribeFinishEpisodes(podcast);
    } else if (action == 'stop') {
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
    if (!paused) FeedSync.refreshPodcast(db, podcast.id);
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

  /// Unsubscribe, finish episodes: the podcast turns temp with every episode
  /// and its play state intact (cleaned up once played out) and stays open, now
  /// with a subscribe button to come back.
  Future<void> _unsubscribeFinishEpisodes(Podcast podcast) async {
    final db = context.read<AppDatabase>();

    // As in _unsubscribe: the player must not hold an episode whose podcastId
    // is about to change underneath it.
    await _closePlayerFor(podcast);

    try {
      await db.demoteToTempFeed(podcast);
    } catch (e, st) {
      debugPrint('[unsub-finish] ERROR: $e\n$st');
    }
    if (!mounted) return;
    setState(() {
      _previewResult = PodcastResult.fromPodcast(podcast);
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
    _antWalkerKey.currentState?.startWalk();
    showAboutBubble(context);
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
  List<UnifiedResult> _buildUnified(
      List<PodcastResult> podcasts, List<Episode> episodes) {
    final result = <UnifiedResult>[];
    final pi = podcasts.iterator;
    final ei = episodes.iterator;
    bool hasP = pi.moveNext();
    bool hasE = ei.moveNext();
    while (hasP || hasE) {
      if (hasP) { result.add(UnifiedResult(podcast: pi.current)); hasP = pi.moveNext(); }
      if (hasE) { result.add(UnifiedResult(episode: ei.current)); hasE = ei.moveNext(); }
    }
    return result;
  }

  /// Country for Apple's charts and episode search, from the app locale.
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
      publishDate: Value(e.publishDate), chaptersUrl: Value(e.chaptersUrl),
      isSubscribed: const Value(false),
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
        .map((p) => UnifiedResult(podcast: p))
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
    final country = _searchCountry;
    final language = Localizations.localeOf(context).languageCode;
    final lang = language == 'en' ? 'en' : '$language,en';
    setState(() { _loadingTrending = true; _trendingFailed = false; });

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
      } catch (_) {
        if (mounted) setState(() { _trendingFailed = true; _loadingTrending = false; });
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

  Future<void> _onCoverTap(Episode episode, AppDatabase _) =>
      _openPodcast(PodcastResult.fromEpisode(episode));

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
      await FeedSync.refreshAll(db);
    } finally {
      // Never leave the refresh header stuck, even if a step above throws.
      if (startup && mounted) setState(() => _startupRefreshing = false);
    }
    _downloadMarkedEpisodes();
  }

  // ─── Filter chip handler ──────────────────────────────────────────────────

  void _onFilterToggle(String key) {
    // Search mode: update ephemeral search filter only, never persist.
    if (_isSearchMode) {
      setState(() {
        if (key == 'podcasts') {
          // Dropping the podcast scope turns this into the search from home.
          _searchPodcastId = null;
          _searchFilter = _searchFilter.copyWith(podcasts: false);
        } else {
          _searchFilter = _searchFilter.toggle(key);
        }
      });
      return;
    }

    final inPodcastView =
        _mode == _FeedMode.podcastFilter || _mode == _FeedMode.previewPodcast;
    setState(() {
      if (key == 'podcasts' && inPodcastView) {
        // From a podcast view, the Podcasts chip goes back to the episode list.
        _mode = _FeedMode.feed;
        _filterPodcastId = null;
        _filterPodcast = null;
        _filter = _filter.copyWith(podcasts: false);
      } else if (key == 'podcasts') {
        _filter = _filter.togglePodcasts();
      } else {
        // In a podcast view the podcasts flag stays on; on the home feed it's off.
        _filter = _filter.toggle(key).copyWith(podcasts: inPodcastView);
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
                    // One search everywhere. From a podcast page it starts
                    // scoped to that podcast (Podcasts chip on); deselecting
                    // the chip leaves exactly the search from home.
                    onSearchOpen: () => setState(() {
                      final scope =
                          _mode == _FeedMode.podcastFilter ? _filterPodcastId : null;
                      _mode = _FeedMode.searchEpisodes;
                      _searchQuery = ''; _searchCtrl.clear();
                      _searchPodcastId = scope;
                      _searchFilter = FilterState(newOnly: false, podcasts: scope != null);
                      _searchFilterChipsVisible = scope != null;
                    }),
                    onPlusPressed: _enterDiscover,
                    onFilterToggle: _toggleFilterChips,
                    onLogoTap: () => _showAbout(context),
                    onInfoPressed: () => launchUrl(
                      Uri.parse('https://antpod.eu/guide'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(child: AntWalker(key: _antWalkerKey)),
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
          isSubscribed: false,
          isLoading: _previewLoading,
          filter: _filter,
          filterChipsVisible: _filterChipsVisible,
          onFilterToggle: _onFilterToggle,
          onRefresh: () => _loadPreview(_previewResult!),
          onSubscribe: () async {
            final db = context.read<AppDatabase>();
            final result = _previewResult!;
            await _reloadMigratedCurrent(await FeedSync.subscribe(db, result));
            if (!mounted) return;
            // Land on the new podcast's page; back from there returns home.
            final pod = await db.getPodcast(result.feedUrl);
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
          isSubscribed: true,
          filter: _filter,
          filterChipsVisible: _filterChipsVisible,
          onFilterToggle: _onFilterToggle,
          onRefresh: () => FeedSync.refreshPodcast(db, _filterPodcastId!),
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
        return DiscoverList(
          searchQuery: _searchQuery,
          trending: _trending,
          unifiedSearchResults: _unifiedSearchResults,
          loadingTrending: _loadingTrending,
          searchingPI: _searchingPI,
          searchHasMore: _searchHasMore,
          loadingMoreSearch: _loadingMoreSearch,
          isOffline: _isOffline,
          trendingFailed: _trendingFailed,
          cs: cs, l10n: l10n,
          onOpen: _openPodcast,
          onRefresh: () => _loadDiscover(forceRefresh: true),
          onLoadMore: _loadMorePISearch,
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
        if (mode == _FeedMode.searchEpisodes) _filterButton(),
      ],
    );
  }

  /// Toggles the filter chips; a dot shows while any filter is on.
  Widget _filterButton() => Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            icon: Icon(Icons.tune_rounded,
                color: filterChipsVisible ? cs.primary : cs.onSurface),
            onPressed: onFilterToggle,
            tooltip: l10n.tooltipFilter,
          ),
          if (filter.hasAny)
            Positioned(right: 8, top: 8, child: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
            )),
        ],
      );

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
                      message: l10n.tooltipGuide,
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
        _filterButton(),
        IconButton(
          icon: Icon(Icons.search_rounded, color: cs.onSurface),
          onPressed: onSearchOpen,
          tooltip: l10n.tooltipSearch),
        IconButton(
          icon: Icon(Icons.add_rounded, color: cs.onSurface),
          onPressed: onPlusPressed,
          tooltip: l10n.tooltipDiscover),
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => ShareUtils.sharePodcast(podcast.title, podcast.feedUrl),
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
  /// Podcast id, which is its feed URL.
  final String feedId;
  final String imageUrl;
  final String title;
  final String author;
  final String description;
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
    required this.author, required this.description,
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
        _FinishingWatcher(
          db: db,
          podcastId: feedId,
          enabled: !isSubscribed,
          builder: (finishing) => PodcastHeader(
            imageUrl: imageUrl,
            title: title,
            author: author,
            description: description,
            feedUrl: feedId,
            onSubscribe: onSubscribe,
            onUnsubscribe: onUnsubscribe,
            syncPaused: syncPaused,
            finishing: finishing,
          ),
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

/// Rebuilds [builder] with whether an unsubscribed feed still has episodes
/// left to finish (started or downloaded). Keeps one stream per podcast.
class _FinishingWatcher extends StatefulWidget {
  final AppDatabase db;
  final String podcastId;
  final bool enabled;
  final Widget Function(bool finishing) builder;

  const _FinishingWatcher({
    required this.db, required this.podcastId,
    required this.enabled, required this.builder,
  });

  @override
  State<_FinishingWatcher> createState() => _FinishingWatcherState();
}

class _FinishingWatcherState extends State<_FinishingWatcher> {
  Stream<bool>? _stream;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(_FinishingWatcher old) {
    super.didUpdateWidget(old);
    if (old.podcastId != widget.podcastId || old.enabled != widget.enabled ||
        old.db != widget.db) {
      _subscribe();
    }
  }

  void _subscribe() => _stream = widget.enabled
      ? widget.db.watchHasEpisodesToFinish(widget.podcastId)
      : null;

  // Always a StreamBuilder (null stream when disabled): switching widget type
  // here would rebuild the header from scratch on (re)subscribe and cut its
  // animations short. A dropped stream keeps its last value, hence the check.
  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
        stream: _stream,
        builder: (_, snap) =>
            widget.builder(_stream != null && (snap.data ?? false)),
      );
}
