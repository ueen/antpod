// lib/home_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_links/app_links.dart';

import 'app_database.dart';
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

enum _SortMode { none, alphabetical, oldest }

class _FilterState {
  final bool newOnly;    // true = show only unplayed (DEFAULT)
  final bool history;   // true = show only finished episodes
  final bool downloaded;
  final _SortMode sort;
  final bool podcasts;

  const _FilterState({
    this.newOnly = true,
    this.history = false,
    this.downloaded = false,
    this.sort = _SortMode.none,
    this.podcasts = false,
  });

  // Dot appears whenever any chip is visually active
  bool get hasAny =>
      newOnly || history || downloaded || sort != _SortMode.none || podcasts;

  bool get isOldestFirst => sort == _SortMode.oldest;

  _FilterState copyWith({
    bool? newOnly, bool? history, bool? downloaded,
    _SortMode? sort, bool? podcasts,
  }) =>
      _FilterState(
        newOnly: newOnly ?? this.newOnly,
        history: history ?? this.history,
        downloaded: downloaded ?? this.downloaded,
        sort: sort ?? this.sort,
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
  final _antWalkerKey = GlobalKey<_AntWalkerState>();

  String? _filterPodcastId;
  Podcast? _filterPodcast;

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  List<PodcastResult> _trending = [];
  List<PodcastResult> _recommended = [];
  List<PodcastResult> _piSearchResults = [];
  bool _loadingTrending = false;
  bool _loadingRec = false;
  bool _searchingPI = false;
  String? _trendingError;

  // Preview (unsubscribed podcast header + episodes)
  PodcastResult? _previewResult;
  bool _loadingPreview = false;
  _FeedMode _previewFrom = _FeedMode.discover;

  StreamSubscription<Uri>? _linkSub;
  Uri? _pendingDeepLink;

  @override
  void initState() {
    super.initState();

    final links = AppLinks();
    // Store initial link; process it only after the widget is fully initialized
    links.getInitialLink().then((uri) { if (uri != null) _pendingDeepLink = uri; });
    _linkSub = links.uriLinkStream.listen((uri) => _handleDeepLink(uri));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadFilterPrefs();
      if (!mounted) return;
      final db = context.read<AppDatabase>();
      final pods = await db.getAllPodcasts();
      if (!mounted) return;
      if (pods.isEmpty) {
        _enterDiscover();
      } else {
        _refresh(db); // async background sync on startup
      }
      // Process initial deep link after the app has finished initializing
      final pending = _pendingDeepLink;
      _pendingDeepLink = null;
      if (pending != null) _handleDeepLink(pending);
    });
  }

  Future<void> _handleDeepLink(Uri uri) async {
    final feed = uri.queryParameters['feed'];
    if (feed == null || feed.isEmpty || !mounted) return;
    // Capture context-dependent objects before any await gaps
    final db = context.read<AppDatabase>();
    final player = context.read<PlayerProvider>();
    final guid = uri.queryParameters['guid'];

    // Episode deep link — open podcast first, load into player, then show sheet
    if (guid != null && guid.isNotEmpty) {
      final audio = uri.queryParameters['audio'] ?? '';
      if (audio.isEmpty) return;
      var episode = await db.getEpisode(guid);
      if (episode == null) {
        await db.insertTempEpisode(EpisodesCompanion(
          id: Value(guid),
          podcastId: Value(feed),
          podcastTitle: Value(uri.queryParameters['podcast'] ?? ''),
          podcastImageUrl: Value(uri.queryParameters['cover'] ?? ''),
          title: Value(uri.queryParameters['title'] ?? ''),
          description: const Value(''),
          audioUrl: Value(audio),
          durationSeconds: Value(int.tryParse(uri.queryParameters['duration'] ?? '') ?? 0),
          publishDate: Value(DateTime.now()),
          isSubscribed: const Value(false),
        ));
        episode = await db.getEpisode(guid);
      }
      if (episode == null || !mounted) return;

      // Navigate to podcast context so it's visible behind the player sheet
      final all = await db.getAllPodcasts();
      if (!mounted) return;
      final subscribed = all.where((p) => p.feedUrl == feed || p.id == feed).firstOrNull;
      if (subscribed != null) {
        setState(() {
          _mode = _FeedMode.podcastFilter;
          _filterPodcastId = subscribed.id;
          _filterPodcast = subscribed;
        });
      } else {
        // Run in background — loads full feed (including show notes) and updates db
        _openPreview(PodcastResult(
          id: uri.queryParameters['id'] ?? feed,
          title: uri.queryParameters['title'] ?? '',
          author: '',
          description: '',
          imageUrl: uri.queryParameters['cover'] ?? '',
          feedUrl: feed,
        ));
      }

      await player.load(episode);
      if (!mounted) return;
      await showPlayerSheet(context, onPodcastTap: _openPodcastFromPlayer);
      return;
    }

    // Podcast deep link — navigate to subscribed feed or open preview
    final all = await db.getAllPodcasts();
    if (!mounted) return;
    final subscribed = all.where((p) => p.feedUrl == feed || p.id == feed).firstOrNull;
    if (subscribed != null) {
      setState(() {
        _mode = _FeedMode.podcastFilter;
        _filterPodcastId = subscribed.id;
        _filterPodcast = subscribed;
      });
    } else {
      _openPreview(PodcastResult(
        id: uri.queryParameters['id'] ?? feed,
        title: uri.queryParameters['title'] ?? '',
        author: '',
        description: '',
        imageUrl: uri.queryParameters['cover'] ?? '',
        feedUrl: feed,
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
        setState(() {
          _mode = _FeedMode.podcastFilter;
          _filterPodcastId = subscribed.id;
          _filterPodcast = subscribed;
        });
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
    await prefs.setBool('filter_podcasts', _filter.podcasts);
    await prefs.setBool('filter_chipsVisible', _filterChipsVisible);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _enterDiscover() {
    setState(() {
      _mode = _FeedMode.discover;
      _searchQuery = '';
      _searchCtrl.clear();
      _piSearchResults = [];
    });
    // Only reload if we have no data yet
    if (_trending.isEmpty && _recommended.isEmpty) _loadDiscover();
  }

  void _exitToFeed() {
    setState(() {
      _mode = _FeedMode.feed;
      _filterPodcastId = null;
      _filterPodcast = null;
      _searchQuery = '';
      _searchCtrl.clear();
      _piSearchResults = [];
    });
  }

  // ── Preview unsubscribed podcast ──────────────────────────────────────────

  Future<void> _openPreview(PodcastResult result) async {
    setState(() {
      _previewResult = result;
      _loadingPreview = true;
      _previewFrom = _mode;
      _mode = _FeedMode.previewPodcast;
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
    final db = context.read<AppDatabase>();
    await db.deletePodcast(podcast.id);
    if (mounted) _exitToFeed();
  }

  void _toggleFilterChips() {
    setState(() => _filterChipsVisible = !_filterChipsVisible);
    _saveFilterPrefs();
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
    setState(() => _searchQuery = v);
    if (_mode == _FeedMode.discover) _debouncedPISearch(v);
  }

  // ── PodcastIndex search ───────────────────────────────────────────────────

  Future<void> _debouncedPISearch(String q) async {
    if (q.trim().length < 2) { setState(() => _piSearchResults = []); return; }
    setState(() => _searchingPI = true);
    final results = await PodcastService.search(q.trim());
    if (mounted && _searchQuery == q) {
      setState(() { _piSearchResults = results; _searchingPI = false; });
    }
  }

  // ── Discover data ─────────────────────────────────────────────────────────

  Future<void> _loadDiscover() async {
    final db = context.read<AppDatabase>();
    final langCode = Localizations.localeOf(context).languageCode;
    final lang = langCode == 'en' ? 'en' : '$langCode,en';
    setState(() { _loadingTrending = true; _loadingRec = true; _trendingError = null; });
    try {
      final t = await PodcastService.trending(max: 10, lang: lang);
      if (mounted) setState(() { _trending = t; _loadingTrending = false; });
    } catch (e) {
      if (mounted) setState(() { _trendingError = e.toString(); _loadingTrending = false; });
    }
    try {
      final subs = await db.getAllPodcasts();
      final r = await PodcastService.recommendations(subscribed: subs, max: 10, lang: lang);
      if (mounted) setState(() { _recommended = r; _loadingRec = false; });
    } catch (_) {
      if (mounted) setState(() { _loadingRec = false; });
    }
  }

  // ── Subscribe ─────────────────────────────────────────────────────────────

  Future<void> _subscribe(PodcastResult result) async {
    final db = context.read<AppDatabase>();
    // Insert podcast metadata and mark any temp episodes as subscribed (fast)
    await db.insertPodcast(result.toCompanion());
    await db.markEpisodesSubscribed(result.feedUrl);
    // Fetch latest feed to get any new episodes
    final data = await PodcastService.loadFeed(result.feedUrl);
    if (data != null) await db.insertEpisodes(data.episodes);
  }

  // ── Cover tap → podcast filter (or preview for temp episodes) ───────────

  Future<void> _onCoverTap(Episode episode, AppDatabase db) async {
    if (_filterPodcastId == episode.podcastId) {
      setState(() {
        _mode = _FeedMode.feed; _filterPodcastId = null; _filterPodcast = null;
      });
      return;
    }
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
    setState(() {
      _mode = _FeedMode.podcastFilter;
      _filterPodcastId = episode.podcastId;
      _filterPodcast = pod;
    });
  }

  void _onPodcastTileSelect(Podcast pod) {
    setState(() {
      _mode = _FeedMode.podcastFilter;
      _filterPodcastId = pod.id;
      _filterPodcast = pod;
      _filter = const _FilterState();
    });
  }

  // ── Refresh ───────────────────────────────────────────────────────────────

  Future<void> _refresh(AppDatabase db) async {
    final pods = await db.getAllPodcasts();
    for (final pod in pods) {
      final data = await PodcastService.loadFeed(pod.feedUrl);
      if (data != null) {
        final eps = data.episodes.map((e) => EpisodesCompanion(
          id: e.id, podcastId: Value(pod.id),
          podcastTitle: e.podcastTitle, podcastImageUrl: e.podcastImageUrl,
          title: e.title, description: e.description, audioUrl: e.audioUrl,
          durationSeconds: e.durationSeconds, publishDate: e.publishDate,
        )).toList();
        await db.insertEpisodes(eps);
      }
    }
  }

  // ─── Filter chip handler ──────────────────────────────────────────────────

  void _onFilterToggle(String key) {
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
                    searchCtrl: _searchCtrl, filter: _filter,
                    filterChipsVisible: _filterChipsVisible,
                    l10n: l10n, cs: cs,
                    onBack: _mode == _FeedMode.previewPodcast ? _exitPreview : _exitToFeed,
                    onSearchChanged: _onSearchChanged,
                    onClearSearch: () => setState(() {
                      _searchQuery = ''; _searchCtrl.clear(); _piSearchResults = [];
                    }),
                    onSearchOpen: () => setState(() {
                      _mode = _FeedMode.searchEpisodes;
                      _searchQuery = ''; _searchCtrl.clear();
                    }),
                    onPlusPressed: _enterDiscover,
                    onFilterToggle: _toggleFilterChips,
                    onLogoTap: () => _showAbout(context),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(child: _AntWalker(key: _antWalkerKey)),
                  ),
                ],
              ),

              // Filter chips — toggle via tune icon, only in feed/search modes
              ClipRect(
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  heightFactor: (_filterChipsVisible &&
                          (_mode == _FeedMode.feed ||
                              _mode == _FeedMode.searchEpisodes))
                      ? 1.0
                      : 0.0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: (_filterChipsVisible &&
                            (_mode == _FeedMode.feed ||
                                _mode == _FeedMode.searchEpisodes))
                        ? 1.0
                        : 0.0,
                    child: _FilterChipsRow(
                      filter: _filter, l10n: l10n, cs: cs,
                      onToggle: _onFilterToggle,
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
        return _PreviewFeed(
          result: _previewResult!,
          loading: _loadingPreview,
          cs: cs, l10n: l10n,
          onSubscribe: () {
            final result = _previewResult!;
            _exitToFeed();
            _subscribe(result).then((_) {
              if (mounted) _refresh(context.read<AppDatabase>());
            });
          },
        );

      case _FeedMode.podcastFilter:
        return _PodcastFilteredFeed(
          db: db, cs: cs,
          podcastId: _filterPodcastId!, podcast: _filterPodcast,
          onCoverTap: _onCoverTap,
          onUnsubscribe: _filterPodcast != null ? () => _unsubscribe(_filterPodcast!) : null,
        );

      case _FeedMode.discover:
        return _DiscoverList(
          searchQuery: _searchQuery,
          trending: _trending, recommended: _recommended,
          piSearchResults: _piSearchResults,
          loadingTrending: _loadingTrending, loadingRec: _loadingRec,
          searchingPI: _searchingPI,
          trendingError: _trendingError,
          cs: cs, l10n: l10n,
          onPreview: _openPreview,
          onRefresh: _loadDiscover,
        );

      case _FeedMode.feed:
      case _FeedMode.searchEpisodes:
        if (_filter.podcasts) {
          return _PodcastGrid(
            db: db, cs: cs, l10n: l10n,
            onSelect: _onPodcastTileSelect,
          );
        }
        return _EpisodeFeed(
          db: db, cs: cs, l10n: l10n, filter: _filter,
          searchQuery: _mode == _FeedMode.searchEpisodes ? _searchQuery : '',
          onCoverTap: _onCoverTap, onRefresh: () => _refresh(db),
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

  const _Toolbar({
    required this.mode, required this.searchOpen, required this.searchCtrl,
    required this.filter, required this.filterChipsVisible,
    required this.l10n, required this.cs,
    required this.onBack, required this.onSearchChanged, required this.onClearSearch,
    required this.onSearchOpen, required this.onPlusPressed,
    required this.onFilterToggle, required this.onLogoTap,
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
        IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
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
          IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: onClearSearch),
      ],
    );
  }

  Widget _defaultRow() {
    return Row(
      children: [
        const SizedBox(width: 8),
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
        const Spacer(),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(Icons.tune_rounded,
                  color: filterChipsVisible ? cs.primary : cs.onSurface),
              onPressed: onFilterToggle,
            ),
            if (filter.hasAny)
              Positioned(right: 8, top: 8, child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
              )),
          ],
        ),
        IconButton(
          icon: Icon(Icons.search, color: cs.onSurface),
          onPressed: onSearchOpen),
        IconButton(
          icon: Icon(Icons.add, color: cs.onSurface),
          onPressed: onPlusPressed,
          tooltip: l10n.subscribeDialogTitle),
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
  final bool showNewChip;
  final bool showDownloadedChip;

  const _FilterChipsRow({
    required this.filter, required this.l10n,
    required this.cs, required this.onToggle,
    this.showPodcastsChip = true,
    this.showNewChip = true,
    this.showDownloadedChip = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          if (showNewChip) ...[
            _Chip(label: l10n.filterNew,
                active: filter.newOnly && !filter.podcasts,
                cs: cs, icon: Icons.headphones,
                onTap: () => onToggle('new')),
            const SizedBox(width: 8),
          ],
          if (showDownloadedChip) ...[
            _Chip(label: l10n.filterDownloaded,
                active: filter.downloaded && !filter.podcasts,
                cs: cs, icon: Icons.download_done,
                onTap: () => onToggle('dl')),
            const SizedBox(width: 8),
          ],
          _Chip(label: l10n.filterListened,
              active: filter.history && !filter.podcasts,
              cs: cs, icon: Icons.check_circle_outline,
              onTap: () => onToggle('history')),
          if (showPodcastsChip) ...[
            const SizedBox(width: 8),
            _Chip(label: l10n.filterPodcasts,
                active: filter.podcasts, cs: cs,
                icon: Icons.library_music_outlined,
                onTap: () => onToggle('podcasts')),
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
    return AnimatedContainer(
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
                Icon(Icons.close, size: 14, color: cs.onPrimary),
              ],
            ],
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
                Icon(Icons.podcasts_outlined, size: 52, color: cs.onSurfaceVariant),
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
                    child: const Icon(Icons.podcasts, size: 36)),
                errorWidget: (_, __, ___) => Container(
                    color: cs.surfaceContainerHighest,
                    child: const Icon(Icons.podcasts, size: 36)),
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

  const _EpisodeFeed({
    required this.db, required this.cs,
    required this.l10n, required this.filter,
    required this.onCoverTap, required this.onRefresh,
    this.searchQuery = '',
  });

  @override
  State<_EpisodeFeed> createState() => _EpisodeFeedState();
}

class _EpisodeFeedState extends State<_EpisodeFeed> {
  GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  List<Episode> _displayed = [];
  List<Episode> _raw = [];
  StreamSubscription<List<Episode>>? _sub;
  bool _initialLoad = true;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(_EpisodeFeed old) {
    super.didUpdateWidget(old);
    final streamChanged = old.filter.history != widget.filter.history ||
        old.filter.newOnly != widget.filter.newOnly;
    if (streamChanged) {
      _sub?.cancel();
      _subscribe();
    } else if (old.filter != widget.filter || old.searchQuery != widget.searchQuery) {
      // Sort/filter changed — reset the list entirely so reordering is applied.
      // diffUpdate only handles insertions/removals, not positional changes.
      final filtered = _applyFilters(_raw);
      setState(() {
        _listKey = GlobalKey<AnimatedListState>();
        _displayed = List.of(filtered);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Stream<List<Episode>> get _stream {
    if (widget.filter.history) return widget.db.watchFinishedEpisodes();
    if (widget.filter.newOnly) return widget.db.watchUnfinishedEpisodes();
    return widget.db.watchAllFeedEpisodes();
  }

  void _subscribe() {
    _sub = _stream.listen(_onData);
  }

  List<Episode> _applyFilters(List<Episode> raw) {
    var eps = raw;
    if (widget.searchQuery.isNotEmpty) {
      final q = widget.searchQuery.toLowerCase();
      eps = eps.where((e) =>
          e.title.toLowerCase().contains(q) ||
          e.podcastTitle.toLowerCase().contains(q)).toList();
    }
    if (widget.filter.downloaded) eps = eps.where((e) => e.isDownloaded).toList();
    if (widget.filter.sort == _SortMode.alphabetical) {
      eps = List.of(eps)
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } else if (widget.filter.sort == _SortMode.oldest) {
      eps = List.of(eps)..sort((a, b) => a.publishDate.compareTo(b.publishDate));
    }
    return eps;
  }

  void _onData(List<Episode> raw) {
    _raw = raw;
    final filtered = _applyFilters(raw);
    if (_initialLoad) {
      _initialLoad = false;
      setState(() => _displayed = List.of(filtered));
      return;
    }
    _diffUpdate(filtered);
  }

  void _diffUpdate(List<Episode> newList) {
    final state = _listKey.currentState;
    if (state == null) {
      setState(() => _displayed = List.of(newList));
      return;
    }

    // Remove items no longer in newList (backwards to keep indices stable)
    for (int i = _displayed.length - 1; i >= 0; i--) {
      final ep = _displayed[i];
      if (!newList.any((e) => e.id == ep.id)) {
        _displayed.removeAt(i);
        state.removeItem(
          i,
          (ctx, anim) => _animatedTile(ep, anim),
          duration: const Duration(milliseconds: 280),
        );
      }
    }

    // Insert items now in newList that weren't before
    for (int i = 0; i < newList.length; i++) {
      final ep = newList[i];
      if (!_displayed.any((e) => e.id == ep.id)) {
        _displayed.insert(i, ep);
        state.insertItem(i, duration: const Duration(milliseconds: 280));
      }
    }

    // Update data for existing items in-place; do NOT replace the whole list,
    // which would conflict with in-flight AnimatedList remove animations.
    setState(() {
      for (int i = 0; i < _displayed.length; i++) {
        final updated = newList.firstWhere(
          (e) => e.id == _displayed[i].id,
          orElse: () => _displayed[i],
        );
        _displayed[i] = updated;
      }
    });
  }

  Widget _animatedTile(Episode ep, Animation<double> anim) {
    final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
    return SizeTransition(
      sizeFactor: curved,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
        child: Column(
          children: [
            EpisodeTile(
              episode: ep,
              onCoverTap: () => widget.onCoverTap(ep, widget.db),
            ),
            Divider(
              height: 1,
              color: widget.cs.outlineVariant.withValues(alpha: 0.5),
              indent: 88,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoad) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_displayed.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.podcasts_outlined, size: 52, color: widget.cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              widget.searchQuery.isNotEmpty || widget.filter.hasAny
                  ? widget.l10n.emptySearchTitle
                  : widget.l10n.emptyFeedTitle,
              style: TextStyle(fontSize: 16, color: widget.cs.onSurfaceVariant),
            ),
            if (widget.searchQuery.isEmpty && !widget.filter.hasAny) ...[
              const SizedBox(height: 6),
              Text(widget.l10n.emptyFeedSub,
                  style: TextStyle(fontSize: 13, color: widget.cs.onSurfaceVariant)),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: AnimatedList(
        key: _listKey,
        padding: const EdgeInsets.only(bottom: 88),
        initialItemCount: _displayed.length,
        itemBuilder: (ctx, i, anim) => _animatedTile(_displayed[i], anim),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Podcast-filtered feed (with filter chips)
// ─────────────────────────────────────────────────────────────────────────────

class _PodcastFilteredFeed extends StatefulWidget {
  final AppDatabase db;
  final ColorScheme cs;
  final String podcastId;
  final Podcast? podcast;
  final Future<void> Function(Episode, AppDatabase) onCoverTap;
  final VoidCallback? onUnsubscribe;

  const _PodcastFilteredFeed({
    required this.db, required this.cs,
    required this.podcastId, required this.podcast,
    required this.onCoverTap,
    this.onUnsubscribe,
  });

  @override
  State<_PodcastFilteredFeed> createState() => _PodcastFilteredFeedState();
}

class _PodcastFilteredFeedState extends State<_PodcastFilteredFeed> {
  _FilterState _filter = const _FilterState();

  void _onToggle(String key) => setState(() {
    switch (key) {
      case 'new':
        _filter = _filter.copyWith(newOnly: !_filter.newOnly, history: false);
      case 'history':
        _filter = _filter.copyWith(history: !_filter.history, newOnly: false);
      case 'dl':
        _filter = _filter.copyWith(downloaded: !_filter.downloaded);
      case 'az':
        _filter = _filter.copyWith(
          sort: _filter.sort == _SortMode.alphabetical
              ? _SortMode.none : _SortMode.alphabetical);
      case 'oldest':
        _filter = _filter.copyWith(
          sort: _filter.sort == _SortMode.oldest
              ? _SortMode.none : _SortMode.oldest);
    }
  });

  List<Episode> _applyFilters(List<Episode> raw) {
    var eps = raw;
    if (_filter.history) {
      eps = eps.where((e) => e.isFinished).toList();
    } else if (_filter.newOnly) {
      eps = eps.where((e) => !e.isFinished).toList();
    }
    if (_filter.downloaded) eps = eps.where((e) => e.isDownloaded).toList();
    if (_filter.sort == _SortMode.alphabetical) {
      eps = List.of(eps)
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } else if (_filter.sort == _SortMode.oldest) {
      eps = List.of(eps)..sort((a, b) => a.publishDate.compareTo(b.publishDate));
    }
    return eps;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = widget.cs;

    return StreamBuilder<List<Episode>>(
      stream: widget.db.watchEpisodesForPodcast(widget.podcastId),
      builder: (context, snap) {
        final eps = _applyFilters(snap.data ?? []);
        return Column(
          children: [
            if (widget.podcast != null)
              PodcastHeader(
                imageUrl: widget.podcast!.imageUrl,
                title: widget.podcast!.title,
                author: widget.podcast!.author,
                description: widget.podcast!.description,
                shareUrl: ShareUtils.podcastUrl(widget.podcast!),
                onUnsubscribe: widget.onUnsubscribe,
              ),
            // Filter chips (no Podcasts chip here)
            _FilterChipsRow(
              filter: _filter, l10n: l10n, cs: cs,
              onToggle: _onToggle, showPodcastsChip: false,
            ),
            Expanded(
              child: eps.isEmpty
                  ? Center(
                      child: Text(l10n.emptySearchTitle,
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
                        onCoverTap: () => widget.onCoverTap(eps[i], widget.db),
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

class _DiscoverList extends StatefulWidget {
  final String searchQuery;
  final List<PodcastResult> trending;
  final List<PodcastResult> recommended;
  final List<PodcastResult> piSearchResults;
  final bool loadingTrending, loadingRec, searchingPI;
  final String? trendingError;
  final ColorScheme cs;
  final AppLocalizations l10n;
  final void Function(PodcastResult) onPreview;
  final Future<void> Function() onRefresh;

  const _DiscoverList({
    required this.searchQuery, required this.trending, required this.recommended,
    required this.piSearchResults, required this.loadingTrending,
    required this.loadingRec, required this.searchingPI,
    this.trendingError,
    required this.cs, required this.l10n,
    required this.onPreview, required this.onRefresh,
  });

  @override
  State<_DiscoverList> createState() => _DiscoverListState();
}

class _DiscoverListState extends State<_DiscoverList>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Widget _podcastList(List<PodcastResult> results) => ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: results.length,
        itemBuilder: (_, i) => _DiscoverPodcastTile(
          result: results[i], rank: i + 1,
          cs: widget.cs, l10n: widget.l10n,
          onPreview: widget.onPreview,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final l10n = widget.l10n;

    // ── Search results overlay ──────────────────────────────────────────────
    if (widget.searchQuery.trim().length >= 2) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: widget.searchingPI
            ? const Center(child: CircularProgressIndicator())
            : widget.piSearchResults.isEmpty
                ? Center(child: Text(l10n.searchNoResults,
                      style: TextStyle(color: cs.onSurfaceVariant)))
                : _podcastList(widget.piSearchResults),
      );
    }

    // ── Two-tab view ────────────────────────────────────────────────────────
    return Column(
      children: [
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
                                Icon(Icons.wifi_off_outlined,
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

class _DiscoverPodcastTile extends StatefulWidget {
  final PodcastResult result;
  final int rank;
  final ColorScheme cs;
  final AppLocalizations l10n;
  final void Function(PodcastResult) onPreview;

  const _DiscoverPodcastTile({
    required this.result, required this.rank, required this.cs,
    required this.l10n, required this.onPreview,
  });

  @override
  State<_DiscoverPodcastTile> createState() => _DiscoverPodcastTileState();
}

class _DiscoverPodcastTileState extends State<_DiscoverPodcastTile> {
  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final cs = widget.cs;

    return InkWell(
      onTap: () => widget.onPreview(r),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text('${widget.rank}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary)),
            ),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: r.imageUrl, width: 56, height: 56, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 56, height: 56, color: cs.surfaceContainerHighest,
                  child: const Icon(Icons.podcasts, size: 28)),
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
// Preview feed (unsubscribed podcast) — DB-backed, uses EpisodeTile
// ─────────────────────────────────────────────────────────────────────────────

class _PreviewFeed extends StatefulWidget {
  final PodcastResult result;
  final bool loading;
  final ColorScheme cs;
  final AppLocalizations l10n;
  final VoidCallback onSubscribe;

  const _PreviewFeed({
    required this.result, required this.loading,
    required this.cs, required this.l10n,
    required this.onSubscribe,
  });

  @override
  State<_PreviewFeed> createState() => _PreviewFeedState();
}

class _PreviewFeedState extends State<_PreviewFeed> {
  _FilterState _filter = const _FilterState(newOnly: false);

  void _onToggle(String key) => setState(() {
    switch (key) {
      case 'history':
        _filter = _filter.copyWith(history: !_filter.history, newOnly: false);
      case 'dl':
        _filter = _filter.copyWith(downloaded: !_filter.downloaded);
      case 'az':
        _filter = _filter.copyWith(
          sort: _filter.sort == _SortMode.alphabetical
              ? _SortMode.none : _SortMode.alphabetical);
      case 'oldest':
        _filter = _filter.copyWith(
          sort: _filter.sort == _SortMode.oldest
              ? _SortMode.none : _SortMode.oldest);
    }
  });

  List<Episode> _applyFilters(List<Episode> raw) {
    var eps = raw;
    if (_filter.history) eps = eps.where((e) => e.isFinished).toList();
    if (_filter.downloaded) eps = eps.where((e) => e.isDownloaded).toList();
    if (_filter.sort == _SortMode.alphabetical) {
      eps = List.of(eps)
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } else if (_filter.sort == _SortMode.oldest) {
      eps = List.of(eps)..sort((a, b) => a.publishDate.compareTo(b.publishDate));
    }
    return eps;
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final cs = widget.cs;
    final l10n = widget.l10n;

    return Column(
      children: [
        PodcastHeader(
          imageUrl: widget.result.imageUrl,
          title: widget.result.title,
          author: widget.result.author,
          description: widget.result.description,
          shareUrl: ShareUtils.podcastResultUrl(widget.result),
          onSubscribe: widget.onSubscribe,
        ),
        _FilterChipsRow(
          filter: _filter, l10n: l10n, cs: cs,
          onToggle: _onToggle,
          showPodcastsChip: false,
          showNewChip: false,
          showDownloadedChip: false,
        ),
        Expanded(
          child: widget.loading
              ? const Center(child: CircularProgressIndicator())
              : StreamBuilder<List<Episode>>(
                  stream: db.watchEpisodesForPodcast(widget.result.feedUrl),
                  builder: (ctx, snap) {
                    final eps = _applyFilters(snap.data ?? []);
                    if (eps.isEmpty) {
                      return Center(child: Text(l10n.emptyFeedTitle,
                          style: TextStyle(color: cs.onSurfaceVariant)));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: eps.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                          indent: 88),
                      itemBuilder: (_, i) => EpisodeTile(
                        episode: eps[i],
                        onCoverTap: () {},
                        isSubscribedContext: false,
                      ),
                    );
                  },
                ),
        ),
      ],
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
    // Random gap between 5 and 10 minutes
    final ms = 300000 + _rng.nextInt(300001);
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
