// lib/home_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_links/app_links.dart';

import 'app_database.dart';
import 'download_provider.dart';
import 'download_service.dart';
import 'episode_tile.dart';
import 'l10n/app_localizations.dart';
import 'mini_player.dart';
import 'player_provider.dart';
import 'podcast_header.dart';
import 'package:share_plus/share_plus.dart';
import 'podcast_service.dart';
import 'share_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Filter state
// ─────────────────────────────────────────────────────────────────────────────

// Scrolls ~40 % further than Android default (friction 0.015 → 0.009) while
// keeping a clean exponential decay — no spring tail.
class _SmoothScrollPhysics extends ClampingScrollPhysics {
  const _SmoothScrollPhysics()
      : super(parent: const AlwaysScrollableScrollPhysics());

  @override
  _SmoothScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      const _SmoothScrollPhysics();

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    final tolerance = toleranceFor(position);
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    if (velocity.abs() < tolerance.velocity) return null;
    if (velocity > 0 && position.pixels >= position.maxScrollExtent) return null;
    if (velocity < 0 && position.pixels <= position.minScrollExtent) return null;
    return ClampingScrollSimulation(
      position: position.pixels,
      velocity: velocity,
      friction: 0.007,
      tolerance: tolerance,
    );
  }
}

enum _SortMode { none, alphabetical, oldest, random }


List<Episode> _sortEpisodes(List<Episode> eps, _SortMode sort, {bool inProgress = false}) {
  List<Episode> result;
  switch (sort) {
    case _SortMode.alphabetical:
      result = List.of(eps)..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    case _SortMode.oldest:
      result = List.of(eps)..sort((a, b) => a.publishDate.compareTo(b.publishDate));
    case _SortMode.random:
      result = List.of(eps)..shuffle(math.Random());
    case _SortMode.none:
      result = List.of(eps);
  }
  if (!inProgress) return result;
  // Float started episodes to top while preserving base sort within each group
  return [
    ...result.where((e) => e.lastPositionMs > 0),
    ...result.where((e) => e.lastPositionMs <= 0),
  ];
}

class _FilterState {
  final bool newOnly;    // true = show only unplayed (DEFAULT)
  final bool history;   // true = show only finished episodes
  final bool downloaded;
  final _SortMode sort;
  final bool inProgress; // float started episodes to top, combinable with sort
  final bool podcasts;

  const _FilterState({
    this.newOnly = true,
    this.history = false,
    this.downloaded = false,
    this.sort = _SortMode.none,
    this.inProgress = false,
    this.podcasts = false,
  });

  // Dot appears whenever any chip is visually active
  bool get hasAny =>
      newOnly || history || downloaded || sort != _SortMode.none || inProgress || podcasts;

  bool get isOldestFirst => sort == _SortMode.oldest;

  _FilterState copyWith({
    bool? newOnly, bool? history, bool? downloaded,
    _SortMode? sort, bool? inProgress, bool? podcasts,
  }) =>
      _FilterState(
        newOnly: newOnly ?? this.newOnly,
        history: history ?? this.history,
        downloaded: downloaded ?? this.downloaded,
        sort: sort ?? this.sort,
        inProgress: inProgress ?? this.inProgress,
        podcasts: podcasts ?? this.podcasts,
      );

  _FilterState togglePodcasts() => podcasts
      ? const _FilterState()
      : const _FilterState(podcasts: true, newOnly: false);
}

// ─────────────────────────────────────────────────────────────────────────────
// Feed mode
// ─────────────────────────────────────────────────────────────────────────────

enum _FeedMode { feed, podcastFilter, searchEpisodes, discover, previewPodcast }

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _FeedMode _mode = _FeedMode.feed;
  _FilterState _filter = const _FilterState();
  bool _filterChipsVisible = true;

  // Search mode has its own ephemeral filter state — never persisted.
  _FilterState _searchFilter = const _FilterState(newOnly: false);
  bool _searchFilterChipsVisible = false;

  bool get _isSearchMode => _mode == _FeedMode.searchEpisodes;
  _FilterState get _effectiveFilter => _isSearchMode ? _searchFilter : _filter;
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
  List<PodcastResult> _recommended = [];
  List<_UnifiedResult> _unifiedSearchResults = [];
  int _searchOffset = 0;
  bool _searchHasMore = true;
  bool _loadingMoreSearch = false;
  bool _loadingTrending = false;
  bool _loadingRec = false;
  bool _searchingPI = false;
  String? _trendingError;

  // Preview (unsubscribed podcast header + episodes)
  PodcastResult? _previewResult;
  bool _loadingPreview = false;
  _FeedMode _previewFrom = _FeedMode.discover;

  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Uri? _pendingDeepLink;

  @override
  void initState() {
    super.initState();

    final links = AppLinks();
    // Store initial link; process it only after the widget is fully initialized
    links.getInitialLink().then((uri) { if (uri != null) _pendingDeepLink = uri; });
    _linkSub = links.uriLinkStream.listen((uri) => _handleDeepLink(uri));

    // Auto-download queued episodes when WiFi becomes available
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        _downloadMarkedEpisodes();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadFilterPrefs();
      if (!mounted) return;
      final db = context.read<AppDatabase>();
      final player = context.read<PlayerProvider>();
      final pods = await db.getAllPodcasts();
      if (!mounted) return;
      if (pods.isEmpty) {
        _enterDiscover();
      } else {
        _refresh(db); // async background sync on startup
        player.restoreLastEpisode();
      }
      // Process initial deep link after the app has finished initializing
      final pending = _pendingDeepLink;
      _pendingDeepLink = null;
      if (pending != null) _handleDeepLink(pending);
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

  Future<void> _handleDeepLink(Uri uri) async {
    final rawFeed = uri.queryParameters['f'];
    final feed = rawFeed != null && rawFeed.isNotEmpty ? _restoreProto(rawFeed) : null;
    if (feed == null || !mounted) return;
    final db = context.read<AppDatabase>();
    final player = context.read<PlayerProvider>();
    final guidHash = uri.queryParameters['h'];

    final all = await db.getAllPodcasts();
    if (!mounted) return;
    final subscribed = all.where((p) => p.feedUrl == feed || p.id == feed).firstOrNull;

    if (guidHash != null && guidHash.isNotEmpty) {
      // Episode link — find by hash in DB, or fetch feed and hash-match.
      var episode = await _findByHash(db, feed, guidHash);

      if (episode == null && subscribed == null) {
        final data = await PodcastService.loadFeed(feed);
        if (!mounted) return;
        final companion = data?.episodes
            .where((e) => ShareUtils.guidHash(e.id.value) == guidHash)
            .firstOrNull;
        if (companion != null) {
          await db.insertTempEpisode(companion);
          episode = await db.getEpisode(companion.id.value);
        }
      }

      if (subscribed != null) {
        _enterPodcastFilter(subscribed);
        if (episode != null && mounted) {
          await player.load(episode);
          if (!mounted) return;
          await showPlayerSheet(context, onPodcastTap: _openPodcastFromPlayer);
        }
        return;
      }

      if (episode == null || !mounted) return;
      _openPreview(PodcastResult(
        id: feed, title: episode.podcastTitle, author: '',
        description: '', imageUrl: episode.podcastImageUrl, feedUrl: feed,
      ));
      await player.load(episode);
      if (!mounted) return;
      await showPlayerSheet(context, onPodcastTap: _openPodcastFromPlayer);
      return;
    }

    // Podcast-only link.
    if (subscribed != null) {
      _enterPodcastFilter(subscribed);
    } else {
      _openPreview(PodcastResult(
        id: feed, title: '', author: '', description: '', imageUrl: '', feedUrl: feed,
      ));
    }
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
      _filter = _FilterState(
        newOnly: prefs.getBool('filter_newOnly') ?? true,
        history: prefs.getBool('filter_history') ?? false,
        downloaded: prefs.getBool('filter_downloaded') ?? false,
        sort: _SortMode.values[sortIndex.clamp(0, _SortMode.values.length - 1)],
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

  // Run once at startup: cancel stale flutter_downloader tasks (started in a
  // previous session but never completed), delete partial files, and re-queue
  // as markedForDownload so the dotted-bar state is shown correctly.
  Future<void> _cleanupInterruptedDownloads() async {
    if (!mounted) return;
    final db = context.read<AppDatabase>();
    final staleTaskIds = await db.resetIncompleteDownloads();
    for (final taskId in staleTaskIds) {
      await DownloadService.cancelAndCleanup(taskId);
    }
  }

  // Trigger WiFi downloads — called on startup (after cleanup) and on WiFi
  // reconnect. Does NOT touch in-progress downloads from the current session.
  Future<void> _downloadMarkedEpisodes() async {
    if (!mounted) return;
    final connectivity = await Connectivity().checkConnectivity();
    if (!connectivity.contains(ConnectivityResult.wifi) &&
        !connectivity.contains(ConnectivityResult.ethernet)) { return; }
    if (!mounted) return;
    final db = context.read<AppDatabase>();
    final downloads = context.read<DownloadProvider>();
    final marked = await db.getMarkedForDownloadEpisodes();
    if (marked.isEmpty) return;
    for (final ep in marked) {
      await db.clearMarkedForDownload(ep.id);
      final taskId = await DownloadService.downloadEpisode(
        episodeId: ep.id, audioUrl: ep.audioUrl,
        episodeTitle: ep.title, db: db,
      );
      if (taskId != null) downloads.trackDownload(taskId);
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
    if (_trending.isEmpty && _recommended.isEmpty) _loadDiscover();
  }

  void _searchOnline() {
    final q = _searchQuery;
    setState(() {
      _mode = _FeedMode.discover;
      
      _unifiedSearchResults = [];
    });
    if (q.isNotEmpty) {
      _debouncedPISearch(q);
    } else if (_trending.isEmpty && _recommended.isEmpty) {
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
      _filter = _filter.copyWith(newOnly: true, history: false, podcasts: false);
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
      _enterPodcastFilter(subscribed);
    } else {
      _openPreview(result);
    }
  }

  Future<void> _openPreview(PodcastResult result) async {
    setState(() {
      _previewResult = result;
      _loadingPreview = true;
      _previewFrom = _mode;
      _mode = _FeedMode.previewPodcast;
      _filter = _filter.copyWith(newOnly: false, podcasts: false);
    });
    final db = context.read<AppDatabase>();
    final data = await PodcastService.loadFeed(result.feedUrl);
    if (!mounted) return;
    if (data != null) {
      await db.insertTempEpisodes(data.episodes);
      // Backfill any metadata that was missing when opening from a temp episode cover tap
      setState(() {
        _previewResult = PodcastResult(
          id: result.id,
          title: data.podcast.title?.isNotEmpty == true ? data.podcast.title! : result.title,
          author: result.author,
          description: data.podcast.description ?? result.description,
          imageUrl: data.podcast.image?.isNotEmpty == true ? data.podcast.image! : result.imageUrl,
          feedUrl: result.feedUrl,
        );
      });
    }
    if (mounted) setState(() => _loadingPreview = false);
  }

  void _exitPreview() {
    setState(() {
      _mode = _previewFrom;
      _previewResult = null;
    });
  }

  // ── Unsubscribe ───────────────────────────────────────────────────────────

  Future<void> _unsubscribe(Podcast podcast) async {
    final db       = context.read<AppDatabase>();
    final player   = context.read<PlayerProvider>();
    final downloads = context.read<DownloadProvider>();

    // Stop player if it's playing an episode from this podcast.
    if (player.currentEpisode?.podcastId == podcast.id) {
      await player.stopAndClear();
    }

    // Cancel any in-progress downloads for this podcast's episodes.
    final eps = await (db.select(db.episodes)
          ..where((e) => e.podcastId.equals(podcast.id))
          ..where((e) => e.downloadTaskId.isNotNull()))
        .get();
    for (final ep in eps) {
      if (ep.downloadTaskId != null) {
        await downloads.cancelDownload(ep.downloadTaskId!, ep.id);
      }
    }

    await db.deletePodcast(podcast.id);
    if (mounted) _exitToFeed();
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
        _filter = _filter.copyWith(podcasts: false, newOnly: false);
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
  List<PodcastResult> _mergeSearchResults(
      List<PodcastResult> pi, List<PodcastResult> apple) {
    final merged = <String, PodcastResult>{};
    for (final p in pi) {
      if (p.feedUrl.isNotEmpty) merged[p.feedUrl] = p;
    }
    for (final p in apple) {
      if (p.feedUrl.isNotEmpty) merged.putIfAbsent(p.feedUrl, () => p);
    }
    return merged.values.toList();
  }

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
      PodcastService.appleSearch(trimmed, country: country),
      PodcastService.appleEpisodeSearch(trimmed, country: country),
    ]);
    if (!mounted || _searchQuery != q) return;
    final podcasts = _mergeSearchResults(
        fetched[0] as List<PodcastResult>, fetched[1] as List<PodcastResult>);
    final apiEpisodes = fetched[2] as List<Episode>;
    // Persist API episodes so player/download infra can access them
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
      _searchHasMore = fetched[0].length == 20;
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

  Future<void> _loadDiscover() async {
    final db = context.read<AppDatabase>();
    final locale = Localizations.localeOf(context);
    final country = (locale.countryCode ?? locale.languageCode).toLowerCase();
    final lang = locale.languageCode == 'en' ? 'en' : '${locale.languageCode},en';
    setState(() { _loadingTrending = true; _loadingRec = true; _trendingError = null; });

    // Fetch charts + subscriptions in parallel, reuse chart result for both tabs.
    final parallel = await Future.wait([
      PodcastService.appleCharts(country, limit: 20),
      db.getAllPodcasts(),
    ]);
    if (!mounted) return;
    var charts = parallel[0] as List<PodcastResult>;
    final subs = parallel[1] as List<Podcast>;

    if (charts.isEmpty) {
      // Apple Charts unavailable — fall back to PI trending.
      try {
        charts = await PodcastService.trending(max: 20, lang: lang);
      } catch (e) {
        if (mounted) setState(() { _trendingError = e.toString(); _loadingTrending = false; _loadingRec = false; });
        return;
      }
    }
    if (!mounted) return;

    final subscribedUrls = subs.map((p) => p.feedUrl).toSet();
    // Suggestions = same chart, subscribed podcasts filtered out.
    final suggestions = charts
        .where((p) => !subscribedUrls.contains(p.feedUrl))
        .take(15)
        .toList();

    setState(() {
      _trending = charts;
      _recommended = suggestions;
      _loadingTrending = false;
      _loadingRec = false;
    });
  }

  // ── Subscribe ─────────────────────────────────────────────────────────────

  Future<void> _subscribe(PodcastResult result) async {
    final db = context.read<AppDatabase>();
    await db.insertPodcast(result.toCompanion());
    // Remove Apple search stubs and unplayed preview episodes for this feed.
    await db.deleteUnplayedTempEpisodes(result.feedUrl);
    // Promote played/finished temp episodes (e.g. from deep link) to subscribed.
    await db.markEpisodesSubscribed(result.feedUrl);
    final data = await PodcastService.loadFeed(result.feedUrl);
    if (data != null) {
      await db.insertEpisodes(
        data.episodes
            .map((e) => e.copyWith(
                  podcastId: Value(result.feedUrl),
                  isSubscribed: const Value(true),
                ))
            .toList(),
      );
    }
  }

  // ── Cover tap → podcast filter (or preview for temp episodes) ───────────

  Future<void> _onCoverTap(Episode episode, AppDatabase db) async {
    final all = await db.getAllPodcasts();
    final pod = all.where((p) => p.id == episode.podcastId).firstOrNull;
    if (pod == null) {
      // Temp episode — open preview so user can subscribe
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
    _enterPodcastFilter(pod);
  }

  void _enterPodcastFilter(Podcast podcast) {
    setState(() {
      _mode = _FeedMode.podcastFilter;
      _filterPodcastId = podcast.id;
      _filterPodcast = podcast;
      _filter = _filter.copyWith(newOnly: false, podcasts: false);
    });
  }

  void _onPodcastTileSelect(Podcast pod) => _enterPodcastFilter(pod);

  // ── Refresh ───────────────────────────────────────────────────────────────

  Future<void> _refresh(AppDatabase db) async {
    await db.cleanupStaleTempEpisodes();
    final pods = await db.getAllPodcasts();
    // Fetch all feeds in parallel, then write once — one DB write = one stream event.
    final results = await Future.wait(pods.map((pod) async {
      final data = await PodcastService.loadFeed(pod.feedUrl);
      if (data == null) return <EpisodesCompanion>[];
      return data.episodes.map((e) => EpisodesCompanion(
        id: e.id, podcastId: Value(pod.id),
        podcastTitle: e.podcastTitle, podcastImageUrl: e.podcastImageUrl,
        title: e.title, description: e.description, audioUrl: e.audioUrl,
        durationSeconds: e.durationSeconds, publishDate: e.publishDate,
        chaptersUrl: e.chaptersUrl,
        isSubscribed: const Value(true),
      )).toList();
    }));
    final all = results.expand((e) => e).toList();
    if (all.isNotEmpty) await db.insertEpisodes(all);
    await _cleanupInterruptedDownloads();
    _downloadMarkedEpisodes();
  }

  // ─── Filter chip handler ──────────────────────────────────────────────────

  void _onFilterToggle(String key) {
    // Search mode: update ephemeral search filter only, never persist.
    if (_isSearchMode) {
      setState(() {
        switch (key) {
          case 'new':
            _searchFilter = _searchFilter.copyWith(
                newOnly: !_searchFilter.newOnly, history: false, podcasts: false);
          case 'history':
            _searchFilter = _searchFilter.copyWith(
                history: !_searchFilter.history, newOnly: false,
                downloaded: false, inProgress: false, podcasts: false);
          case 'dl':
            _searchFilter = _searchFilter.copyWith(
                downloaded: !_searchFilter.downloaded, podcasts: false);
          case 'az':
            _searchFilter = _searchFilter.copyWith(
                sort: _searchFilter.sort == _SortMode.alphabetical
                    ? _SortMode.none : _SortMode.alphabetical, podcasts: false);
          case 'oldest':
            _searchFilter = _searchFilter.copyWith(
                sort: _searchFilter.sort == _SortMode.oldest
                    ? _SortMode.none : _SortMode.oldest, podcasts: false);
          case 'random':
            _searchFilter = _searchFilter.copyWith(
                sort: _searchFilter.sort == _SortMode.random
                    ? _SortMode.none : _SortMode.random, podcasts: false);
          case 'inprogress':
            _searchFilter = _searchFilter.copyWith(
                inProgress: !_searchFilter.inProgress, podcasts: false);
          case 'podcasts':
            _searchFilter = _searchFilter.copyWith(
                podcasts: !_searchFilter.podcasts);
        }
      });
      return;
    }

    // From podcast view, tapping Podcasts chip exits to the grid
    if (key == 'podcasts' && _mode == _FeedMode.podcastFilter) {
      setState(() {
        _mode = _FeedMode.feed;
        _filterPodcastId = null;
        _filterPodcast = null;
        _filter = const _FilterState(podcasts: true, newOnly: false);
      });
      _saveFilterPrefs();
      return;
    }
    setState(() {
      switch (key) {
        case 'new':
          _filter = _filter.copyWith(
              newOnly: !_filter.newOnly,
              history: false,
              podcasts: false);
        case 'history':
          _filter = _filter.copyWith(
              history: !_filter.history,
              newOnly: false,
              downloaded: false,
              inProgress: false,
              podcasts: false);
        case 'dl':
          _filter = _filter.copyWith(
              downloaded: !_filter.downloaded,
              podcasts: false);
        case 'az':
          _filter = _filter.copyWith(
            sort: _filter.sort == _SortMode.alphabetical
                ? _SortMode.none : _SortMode.alphabetical,
            podcasts: false,
          );
        case 'oldest':
          _filter = _filter.copyWith(
            sort: _filter.sort == _SortMode.oldest
                ? _SortMode.none : _SortMode.oldest,
            podcasts: false,
          );
        case 'random':
          _filter = _filter.copyWith(
            sort: _filter.sort == _SortMode.random
                ? _SortMode.none : _SortMode.random,
            podcasts: false,
          );
        case 'inprogress':
          _filter = _filter.copyWith(
            inProgress: !_filter.inProgress,
            podcasts: false,
          );
        case 'podcasts':
          _filter = _filter.togglePodcasts();
      }
    });
    _saveFilterPrefs();
  }

  // feed and searchEpisodes share a key so _EpisodeFeed is reused (no flash)
  Key get _bodyKey {
    switch (_mode) {
      case _FeedMode.feed:
      case _FeedMode.searchEpisodes:
        return const ValueKey('episode_feed');
      case _FeedMode.podcastFilter:
        return ValueKey('podcast_${_filterPodcastId ?? ""}');
      case _FeedMode.discover:
        return const ValueKey('discover');
      case _FeedMode.previewPodcast:
        return const ValueKey('preview');
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
                          _searchFilter = const _FilterState(newOnly: false, podcasts: true);
                          _searchFilterChipsVisible = true;
                        } else {
                          _searchPodcastId = null;
                          _searchFilter = const _FilterState(newOnly: false);
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

              // Filter chips — visible in feed and episode-search modes
              ClipRect(
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  heightFactor: (_effectiveChipsVisible &&
                          (_mode == _FeedMode.feed ||
                           _mode == _FeedMode.searchEpisodes))
                      ? 1.0
                      : 0.0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: (_effectiveChipsVisible &&
                            (_mode == _FeedMode.feed ||
                             _mode == _FeedMode.searchEpisodes))
                        ? 1.0
                        : 0.0,
                    child: _FilterChipsRow(
                      filter: _effectiveFilter, l10n: l10n, cs: cs,
                      onToggle: _onFilterToggle,
                      showPodcastsChip: !_isSearchMode || _searchPodcastId != null,
                      podcastsFirst: _searchPodcastId != null,
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
          loading: _loadingPreview,
          isSubscribed: false,
          filter: _filter,
          filterChipsVisible: _filterChipsVisible,
          onFilterToggle: _onFilterToggle,
          onSubscribe: () {
            final result = _previewResult!;
            _exitToFeed();
            _subscribe(result).then((_) {
              if (mounted) _refresh(context.read<AppDatabase>());
            });
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
          loading: false,
          isSubscribed: true,
          filter: _filter,
          filterChipsVisible: _filterChipsVisible,
          onFilterToggle: _onFilterToggle,
          onCoverTap: _onCoverTap,
          onUnsubscribe: _filterPodcast != null ? () => _unsubscribe(_filterPodcast!) : null,
        );

      case _FeedMode.discover:
        return _DiscoverList(
          searchQuery: _searchQuery,
          trending: _trending, recommended: _recommended,
          unifiedSearchResults: _unifiedSearchResults,
          loadingTrending: _loadingTrending, loadingRec: _loadingRec,
          searchingPI: _searchingPI,
          searchHasMore: _searchHasMore,
          loadingMoreSearch: _loadingMoreSearch,
          trendingError: _trendingError,
          cs: cs, l10n: l10n,
          onPreview: _openPodcastResult,
          onRefresh: _loadDiscover,
          onLoadMore: _loadMorePISearch,
          onCoverTap: _openPodcastResult,
        );

      case _FeedMode.feed:
      case _FeedMode.searchEpisodes:
        if (_filter.podcasts && !_isSearchMode) {
          return _PodcastGrid(
            db: db, cs: cs, l10n: l10n,
            onSelect: _onPodcastTileSelect,
          );
        }
        return _EpisodeFeed(
          db: db, cs: cs, l10n: l10n, filter: _effectiveFilter,
          searchQuery: _mode == _FeedMode.searchEpisodes ? _searchQuery : '',
          podcastIdFilter: _isSearchMode ? _searchPodcastId : null,
          onCoverTap: _onCoverTap, onRefresh: () => _refresh(db),
          onSearchOnline: _mode == _FeedMode.searchEpisodes ? _searchOnline : null,
          onShowAllDownloads: _effectiveFilter.downloaded && !_isSearchMode
              ? () => setState(() {
                    _filter = const _FilterState(downloaded: true, newOnly: false);
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
  final _FilterState filter;
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
    return Row(
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
// Filter chips
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChipsRow extends StatelessWidget {
  final _FilterState filter;
  final AppLocalizations l10n;
  final ColorScheme cs;
  final ValueChanged<String> onToggle;
  final bool showPodcastsChip;
  final bool podcastsFirst;

  const _FilterChipsRow({
    required this.filter, required this.l10n,
    required this.cs, required this.onToggle,
    this.showPodcastsChip = true,
    this.podcastsFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final podcastsChip = _Chip(
      label: podcastsFirst ? l10n.filterPodcast : l10n.filterPodcasts,
      active: filter.podcasts, cs: cs,
      icon: Icons.library_music_rounded,
      onTap: () => onToggle('podcasts'),
    );
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          if (showPodcastsChip && podcastsFirst) ...[
            podcastsChip,
            const SizedBox(width: 8),
          ],
          _Chip(label: l10n.filterNew,
              active: filter.newOnly && !filter.podcasts,
              cs: cs, icon: Icons.headphones_rounded,
              onTap: () => onToggle('new')),
          const SizedBox(width: 8),
          _Chip(label: l10n.filterPlaying,
              active: filter.inProgress && !filter.podcasts,
              cs: cs, icon: Icons.play_circle_rounded,
              onTap: () => onToggle('inprogress')),
          const SizedBox(width: 8),
          _Chip(label: l10n.filterDownloaded,
              active: filter.downloaded && !filter.podcasts,
              cs: cs, icon: Icons.download_done_rounded,
              onTap: () => onToggle('dl')),
          const SizedBox(width: 8),
          _Chip(label: l10n.filterListened,
              active: filter.history && !filter.podcasts,
              cs: cs, icon: Icons.check_circle_outline,
              onTap: () => onToggle('history')),
          if (showPodcastsChip && !podcastsFirst) ...[
            const SizedBox(width: 8),
            podcastsChip,
          ],
          const SizedBox(width: 8),
          _Chip(label: l10n.filterAlphabetical,
              active: filter.sort == _SortMode.alphabetical && !filter.podcasts,
              cs: cs, icon: Icons.sort_by_alpha_rounded,
              onTap: () => onToggle('az')),
          const SizedBox(width: 8),
          _Chip(label: l10n.filterOldest,
              active: filter.sort == _SortMode.oldest && !filter.podcasts,
              cs: cs, icon: Icons.arrow_upward_rounded,
              onTap: () => onToggle('oldest')),
          const SizedBox(width: 8),
          _Chip(label: l10n.filterRandom,
              active: filter.sort == _SortMode.random && !filter.podcasts,
              cs: cs, icon: Icons.shuffle_rounded,
              onTap: () => onToggle('random')),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final ColorScheme cs;
  final IconData? icon;
  final VoidCallback onTap;

  const _Chip({
    required this.label, required this.active,
    required this.cs, required this.onTap, this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      clipBehavior: Clip.none,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: active ? cs.primary : cs.surfaceContainerHighest.withValues(alpha:0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? cs.primary : cs.outlineVariant, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14,
                    color: active ? cs.onPrimary : cs.onSurfaceVariant),
                const SizedBox(width: 5),
              ],
              Text(label, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: active ? cs.onPrimary : cs.onSurfaceVariant)),
              if (active) ...[
                const SizedBox(width: 6),
                Icon(Icons.close_rounded, size: 14, color: cs.onPrimary),
              ],
            ],
          ),
        ),
      ),
      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Episode feed — animated list with diff
// ─────────────────────────────────────────────────────────────────────────────

class _EpisodeFeed extends StatefulWidget {
  final AppDatabase db;
  final ColorScheme cs;
  final AppLocalizations l10n;
  final String searchQuery;
  final _FilterState filter;
  final Future<void> Function(Episode, AppDatabase) onCoverTap;
  final Future<void> Function() onRefresh;
  final VoidCallback? onSearchOnline;
  final VoidCallback? onShowAllDownloads;
  final String? podcastIdFilter;

  const _EpisodeFeed({
    required this.db, required this.cs,
    required this.l10n, required this.filter,
    required this.onCoverTap, required this.onRefresh,
    this.searchQuery = '',
    this.onSearchOnline,
    this.onShowAllDownloads,
    this.podcastIdFilter,
  });

  @override
  State<_EpisodeFeed> createState() => _EpisodeFeedState();
}

class _EpisodeFeedState extends State<_EpisodeFeed> {
  final GlobalKey<SliverAnimatedListState> _listKey = GlobalKey<SliverAnimatedListState>();
  List<Episode> _displayed = [];
  List<Episode> _raw = [];
  StreamSubscription<List<Episode>>? _sub;
  StreamSubscription<List<Episode>>? _markedSub;
  StreamSubscription<List<Episode>>? _downloadedCountSub;
  bool _initialLoad = true;
  bool _showMarked = false;
  int _markedCount = 0;
  int _totalDownloadedCount = 0;
  final _scrollCtrl = ScrollController();
  bool _showScrollTop = false;
  @override
  void initState() {
    super.initState();
    _subscribe();
    _markedSub = widget.db.watchMarkedForDownloadEpisodes().listen(
      (eps) => setState(() => _markedCount = eps.length),
    );
    _downloadedCountSub = widget.db.watchAllFeedEpisodes(downloadedOnly: true).listen(
      (eps) => setState(() => _totalDownloadedCount = eps.length),
    );
    _scrollCtrl.addListener(() {
      final show = _scrollCtrl.offset > 300;
      if (show != _showScrollTop) setState(() => _showScrollTop = show);
    });
  }

  @override
  void didUpdateWidget(_EpisodeFeed old) {
    super.didUpdateWidget(old);
    // Reset "show marked" when the downloaded filter is turned off
    if (!widget.filter.downloaded && _showMarked) {
      _showMarked = false;
    }
    // Stream source changes when search is toggled on/off, podcast filter changes,
    // or DB-level filters change
    final wasSearching = old.searchQuery.isNotEmpty;
    final isSearching = widget.searchQuery.isNotEmpty;
    final wasPodcastScoped = old.filter.podcasts && old.podcastIdFilter != null;
    final isPodcastScoped = widget.filter.podcasts && widget.podcastIdFilter != null;
    final streamChanged = wasSearching != isSearching ||
        wasPodcastScoped != isPodcastScoped ||
        (!isSearching && !isPodcastScoped && (
          old.filter.history != widget.filter.history ||
          old.filter.newOnly != widget.filter.newOnly ||
          old.filter.downloaded != widget.filter.downloaded
        ));
    if (streamChanged) {
      _sub?.cancel();
      _subscribe();
    } else if (old.filter != widget.filter || old.searchQuery != widget.searchQuery) {
      // Must go through _diffUpdate so SliverAnimatedList item count stays in sync
      _diffUpdate(_applyFilters(_raw));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _markedSub?.cancel();
    _downloadedCountSub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Stream<List<Episode>> get _stream {
    // Search mode or podcast-scoped search: fetch all, filter in-app
    final isPodcastScoped = widget.filter.podcasts && widget.podcastIdFilter != null;
    if (widget.searchQuery.isNotEmpty || isPodcastScoped) {
      return widget.db.watchAllFeedEpisodes(downloadedOnly: false);
    }
    // Show downloaded + marked episodes when user tapped "Show marked for download"
    if (_showMarked && widget.filter.downloaded) {
      return widget.db.watchDownloadedOrMarkedEpisodes();
    }
    final dl = widget.filter.downloaded;
    if (widget.filter.history) return widget.db.watchFinishedEpisodes(downloadedOnly: dl);
    if (widget.filter.newOnly) return widget.db.watchUnfinishedEpisodes(downloadedOnly: dl);
    return widget.db.watchAllFeedEpisodes(downloadedOnly: dl);
  }

  void _subscribe() {
    _sub = _stream.listen(_onData);
  }

  void _revealMarked() {
    setState(() => _showMarked = true);
    _sub?.cancel();
    _subscribe();
  }

  List<Episode> _applyFilters(List<Episode> raw) {
    var eps = raw;
    final isPodcastScoped = widget.filter.podcasts && widget.podcastIdFilter != null;
    if (widget.searchQuery.isNotEmpty || isPodcastScoped) {
      // Narrow to the specific podcast when opened from a podcast feed.
      if (isPodcastScoped) {
        eps = eps.where((e) => e.podcastId == widget.podcastIdFilter).toList();
      }
      // Narrow by text query.
      if (widget.searchQuery.isNotEmpty) {
        final q = widget.searchQuery.toLowerCase();
        eps = eps.where((e) =>
            e.title.toLowerCase().contains(q) ||
            e.podcastTitle.toLowerCase().contains(q)).toList();
      }
      // Apply chip filters.
      if (widget.filter.history) {
        eps = eps.where((e) => e.isFinished).toList();
      } else if (widget.filter.newOnly) {
        eps = eps.where((e) => !e.isFinished).toList();
      }
      if (widget.filter.downloaded) {
        eps = eps.where((e) => e.isDownloaded || e.markedForDownload).toList();
      }
      return _sortEpisodes(eps, widget.filter.sort,
          inProgress: widget.filter.inProgress);
    }
    // When showing downloaded + marked: downloaded group first, marked group second,
    // each group sorted by the active sort mode.
    if (_showMarked && widget.filter.downloaded) {
      final downloaded = _sortEpisodes(
        eps.where((e) => e.isDownloaded).toList(),
        widget.filter.sort, inProgress: widget.filter.inProgress,
      );
      final marked = _sortEpisodes(
        eps.where((e) => !e.isDownloaded && e.markedForDownload).toList(),
        widget.filter.sort, inProgress: widget.filter.inProgress,
      );
      return [...downloaded, ...marked];
    }
    return _sortEpisodes(eps, widget.filter.sort, inProgress: widget.filter.inProgress);
  }

  void _onData(List<Episode> raw) {
    _raw = raw;
    final filtered = _applyFilters(raw);
    if (_initialLoad) {
      setState(() {
        _displayed = List.of(filtered);
        _initialLoad = false;
      });
      return;
    }
    _diffUpdate(filtered);
  }

  void _diffUpdate(List<Episode> next) {
    final state = _listKey.currentState;
    if (state == null) {
      setState(() => _displayed = List.of(next));
      return;
    }

    final nextIds = {for (final e in next) e.id};
    final displayedIds = {for (final e in _displayed) e.id};

    int removedCount = 0;
    for (int i = _displayed.length - 1; i >= 0; i--) {
      if (!nextIds.contains(_displayed[i].id)) {
        final ep = _displayed.removeAt(i);
        state.removeItem(i, (ctx, anim) => _exitTile(ep, anim),
            duration: const Duration(milliseconds: 250));
        removedCount++;
      }
    }

    int addedCount = 0;
    for (int i = 0; i < next.length; i++) {
      if (!displayedIds.contains(next[i].id)) {
        _displayed.insert(i, next[i]);
        state.insertItem(i, duration: const Duration(milliseconds: 250));
        addedCount++;
      }
    }

    // Refresh data for items that stayed.
    final byId = {for (final e in next) e.id: e};
    for (int i = 0; i < _displayed.length; i++) {
      _displayed[i] = byId[_displayed[i].id] ?? _displayed[i];
    }

    if (removedCount + addedCount == 0) {
      // Pure filter/sort change — re-sort and rebuild. No animations were
      // triggered so there's no mid-flight reorder to worry about.
      final nextPos = {for (int i = 0; i < next.length; i++) next[i].id: i};
      _displayed.sort((a, b) => (nextPos[a.id] ?? 0).compareTo(nextPos[b.id] ?? 0));
      setState(() {});
    }
    // When items were added/removed the insert/remove loops already placed them
    // at the correct positions — no sort needed, SliverAnimatedList drives the rebuild.
  }

  Widget _tile(Episode ep) => RepaintBoundary(
        child: Column(
          children: [
            _LazyTile(episode: ep, onCoverTap: () => widget.onCoverTap(ep, widget.db)),
            Divider(height: 1, color: widget.cs.outlineVariant.withValues(alpha: 0.5), indent: 88),
          ],
        ),
      );

  Widget _animatedTile(Episode ep, Animation<double> anim) => SizeTransition(
        sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: _tile(ep),
        ),
      );

  Widget _exitTile(Episode ep, Animation<double> anim) => SizeTransition(
        sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: RepaintBoundary(
            child: Column(
              children: [
                EpisodeTile(episode: ep, onCoverTap: () => widget.onCoverTap(ep, widget.db)),
                Divider(height: 1, color: widget.cs.outlineVariant.withValues(alpha: 0.5), indent: 88),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_initialLoad) return const Center(child: CircularProgressIndicator());

    final isSearching = widget.searchQuery.isNotEmpty;
    final hasSearchFooter = isSearching && widget.onSearchOnline != null;
    // Show "show all downloads" footer when the downloaded filter is on but other
    // filters (new/history/in-progress) are hiding some downloaded episodes.
    // Only show "show all downloads" when other active filters are hiding some
    // downloaded episodes — i.e. the total downloaded count exceeds what's shown.
    final hasDownloadFooter = !isSearching &&
        widget.filter.downloaded &&
        widget.onShowAllDownloads != null &&
        (widget.filter.newOnly || widget.filter.history || widget.filter.inProgress) &&
        _totalDownloadedCount > _displayed.length;
    // Show "show marked for download" footer only when the download footer isn't
    // already showing — one footer at a time.
    final hasMarkedFooter = !isSearching &&
        !hasDownloadFooter &&
        widget.filter.downloaded &&
        !_showMarked &&
        _markedCount > 0;

    final isEmpty = _displayed.isEmpty;

    final child = isEmpty
        ? RefreshIndicator(
            key: const ValueKey('empty'),
            onRefresh: widget.onRefresh,
            child: CustomScrollView(
              physics: const _SmoothScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 320,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.podcasts_rounded, size: 52,
                              color: widget.cs.onSurfaceVariant),
                          const SizedBox(height: 16),
                          Text(
                            isSearching || widget.filter.hasAny
                                ? widget.l10n.emptySearchTitle
                                : widget.l10n.emptyFeedTitle,
                            style: TextStyle(
                                fontSize: 16, color: widget.cs.onSurfaceVariant),
                          ),
                          if (!isSearching && !widget.filter.hasAny) ...[
                            const SizedBox(height: 6),
                            Text(widget.l10n.emptyFeedSub,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: widget.cs.onSurfaceVariant)),
                          ],
                          if (hasSearchFooter) ...[
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: widget.onSearchOnline,
                              icon: const Icon(Icons.search_rounded, size: 18),
                              label: Text(widget.l10n.searchOnline),
                            ),
                          ],
                          if (hasDownloadFooter) ...[
                            const SizedBox(height: 20),
                            OutlinedButton.icon(
                              onPressed: widget.onShowAllDownloads,
                              icon: const Icon(Icons.download_done_rounded, size: 18),
                              label: Text(widget.l10n.showAllDownloads),
                            ),
                          ],
                          if (hasMarkedFooter) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _revealMarked,
                              icon: const Icon(Icons.download_rounded, size: 18),
                              label: Text(widget.l10n.showMarkedForDownload),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 88)),
              ],
            ),
          )
        : RefreshIndicator(
            key: const ValueKey('list'),
            onRefresh: widget.onRefresh,
            // Footers are separate slivers — never mixed into the animated list's
            // item count, so no RangeError when search/filter state changes.
            child: CustomScrollView(
              controller: _scrollCtrl,
              physics: const _SmoothScrollPhysics(),
              slivers: [
                SliverAnimatedList(
                  key: _listKey,
                  initialItemCount: _displayed.length,
                  itemBuilder: (ctx, i, anim) => _animatedTile(_displayed[i], anim),
                ),
                if (hasSearchFooter)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: OutlinedButton.icon(
                        onPressed: widget.onSearchOnline,
                        icon: const Icon(Icons.travel_explore, size: 18),
                        label: Text(widget.l10n.searchOnline),
                      ),
                    ),
                  ),
                if (hasDownloadFooter)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: OutlinedButton.icon(
                        onPressed: widget.onShowAllDownloads,
                        icon: const Icon(Icons.download_done_rounded, size: 18),
                        label: Text(widget.l10n.showAllDownloads),
                      ),
                    ),
                  ),
                if (hasMarkedFooter)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: OutlinedButton.icon(
                        onPressed: _revealMarked,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(widget.l10n.showMarkedForDownload),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 88)),
              ],
            ),
          );

    final cs = Theme.of(context).colorScheme;
    final hasMiniPlayer = context.select<PlayerProvider, bool>((p) => p.hasEpisode);
    final fabBottom = _showScrollTop ? (hasMiniPlayer ? 88.0 : 24.0) : -56.0;
    return Stack(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
          child: child,
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          right: 16,
          bottom: fabBottom,
          child: GestureDetector(
            onTap: () => _scrollCtrl.animateTo(
              0, duration: const Duration(milliseconds: 350), curve: Curves.easeOut),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: Icon(Icons.arrow_upward_rounded, color: cs.onPrimaryContainer, size: 22),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Podcast-filtered feed (with filter chips)
// ─────────────────────────────────────────────────────────────────────────────

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
  final bool loading;
  final bool isSubscribed;
  final _FilterState filter;
  final bool filterChipsVisible;
  final ValueChanged<String> onFilterToggle;
  final Future<void> Function(Episode, AppDatabase)? onCoverTap;
  final VoidCallback? onSubscribe;
  final VoidCallback? onUnsubscribe;

  const _PodcastFeed({
    required this.db, required this.cs, required this.l10n,
    required this.feedId, required this.imageUrl, required this.title,
    required this.author, required this.description, required this.shareUrl,
    required this.loading, required this.isSubscribed,
    required this.filter, required this.filterChipsVisible,
    required this.onFilterToggle,
    this.onCoverTap, this.onSubscribe, this.onUnsubscribe,
  });

  List<Episode> _applyFilters(List<Episode> raw) {
    var eps = raw;
    if (filter.history) {
      eps = eps.where((e) => e.isFinished).toList();
    } else if (filter.newOnly) {
      eps = eps.where((e) => !e.isFinished).toList();
    }
    if (filter.downloaded) eps = eps.where((e) => e.isDownloaded).toList();
    return _sortEpisodes(eps, filter.sort, inProgress: filter.inProgress);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Episode>>(
      stream: db.watchEpisodesForPodcast(feedId),
      builder: (context, snap) {
        final eps = _applyFilters(snap.data ?? []);
        return Column(
          children: [
            PodcastHeader(
              imageUrl: imageUrl,
              title: title,
              author: author,
              description: description,
              shareUrl: shareUrl,
              onSubscribe: onSubscribe,
              onUnsubscribe: onUnsubscribe,
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
                  child: _FilterChipsRow(
                    filter: filter, l10n: l10n, cs: cs,
                    onToggle: onFilterToggle,
                    showPodcastsChip: false,
                  ),
                ),
              ),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : eps.isEmpty
                      ? Center(child: Text(l10n.emptySearchTitle,
                            style: TextStyle(color: cs.onSurfaceVariant)))
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: eps.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: cs.outlineVariant.withValues(alpha: 0.5),
                              indent: 88),
                          itemBuilder: (_, i) => EpisodeTile(
                            episode: eps[i],
                            onCoverTap: onCoverTap != null
                                ? () => onCoverTap!(eps[i], db)
                                : () {},
                            isSubscribedContext: isSubscribed,
                          ),
                        ),
            ),
          ],
        );
      },
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
  final List<PodcastResult> recommended;
  final List<_UnifiedResult> unifiedSearchResults;
  final bool loadingTrending, loadingRec, searchingPI;
  final bool searchHasMore, loadingMoreSearch;
  final String? trendingError;
  final ColorScheme cs;
  final AppLocalizations l10n;
  final void Function(PodcastResult) onPreview;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final void Function(PodcastResult) onCoverTap;

  const _DiscoverList({
    required this.searchQuery, required this.trending, required this.recommended,
    required this.unifiedSearchResults,
    required this.loadingTrending, required this.loadingRec, required this.searchingPI,
    required this.searchHasMore, required this.loadingMoreSearch,
    this.trendingError,
    required this.cs, required this.l10n,
    required this.onPreview, required this.onRefresh,
    required this.onLoadMore, required this.onCoverTap,
  });

  @override
  State<_DiscoverList> createState() => _DiscoverListState();
}

class _DiscoverListState extends State<_DiscoverList>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _searchScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
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
    _tabCtrl.dispose();
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

  Widget _podcastList(List<PodcastResult> results, {bool showRank = true}) =>
      ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: results.length,
        itemBuilder: (_, i) => _DiscoverPodcastTile(
          result: results[i], rank: i + 1, showRank: showRank,
          cs: widget.cs, l10n: widget.l10n,
          onPreview: widget.onPreview,
        ),
      );

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
                ? Center(child: Text(l10n.searchNoResults,
                      style: TextStyle(color: cs.onSurfaceVariant)))
                : _unifiedList(widget.unifiedSearchResults),
      );
    }

    // ── Two-tab view ────────────────────────────────────────────────────────
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
        TabBar(
          controller: _tabCtrl,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          tabs: [
            Tab(text: l10n.discoverTabTrending),
            Tab(text: l10n.discoverTabSuggestions),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              // ── Trending ──────────────────────────────────────────────────
              RefreshIndicator(
                onRefresh: widget.onRefresh,
                child: widget.loadingTrending
                    ? const Center(child: CircularProgressIndicator())
                    : widget.trendingError != null
                        ? ListView(children: [
                            Padding(
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
                          ])
                        : widget.trending.isEmpty
                            ? Center(child: Text('No trending podcasts available.',
                                style: TextStyle(color: cs.onSurfaceVariant)))
                            : _podcastList(widget.trending),
              ),

              // ── Suggestions ───────────────────────────────────────────────
              RefreshIndicator(
                onRefresh: widget.onRefresh,
                child: widget.loadingRec
                    ? const Center(child: CircularProgressIndicator())
                    : widget.recommended.isEmpty
                        ? Center(child: Text(l10n.emptyFeedSub,
                            style: TextStyle(color: cs.onSurfaceVariant)))
                        : _podcastList(widget.recommended),
              ),
            ],
          ),
        ),
      ],
    );
  }
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

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shimmer = cs.onSurface.withValues(alpha: 0.08);
    return SizedBox(
      height: 72,
      child: Row(
        children: [
          const SizedBox(width: 16),
          Container(width: 56, height: 56, decoration: BoxDecoration(
            color: shimmer, borderRadius: BorderRadius.circular(6))),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 13, width: double.infinity, decoration: BoxDecoration(
                  color: shimmer, borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 6),
                Container(height: 11, width: 160, decoration: BoxDecoration(
                  color: shimmer, borderRadius: BorderRadius.circular(4))),
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

class _LazyTile extends StatefulWidget {
  final Episode episode;
  final VoidCallback onCoverTap;

  const _LazyTile({required this.episode, required this.onCoverTap});

  @override
  State<_LazyTile> createState() => _LazyTileState();
}

class _LazyTileState extends State<_LazyTile> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? EpisodeTile(episode: widget.episode, onCoverTap: widget.onCoverTap)
             : const _SkeletonTile();
}

