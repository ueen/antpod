// lib/home_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import 'app_database.dart';
import 'download_service.dart';
import 'episode_tile.dart';
import 'l10n/app_localizations.dart';
import 'mini_player.dart';
import 'player_provider.dart';
import 'podcast_header.dart';
import 'package:share_plus/share_plus.dart';
import 'podcast_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Filter state
// ─────────────────────────────────────────────────────────────────────────────

enum _SortMode { none, alphabetical }

class _FilterState {
  final bool downloaded;
  final bool played;
  final _SortMode sort;
  final bool podcasts;

  const _FilterState({
    this.downloaded = false,
    this.played = false,
    this.sort = _SortMode.none,
    this.podcasts = false,
  });

  bool get hasAny =>
      downloaded || played || sort != _SortMode.none || podcasts;

  _FilterState copyWith({
    bool? downloaded, bool? played, _SortMode? sort, bool? podcasts,
  }) =>
      _FilterState(
        downloaded: downloaded ?? this.downloaded,
        played: played ?? this.played,
        sort: sort ?? this.sort,
        podcasts: podcasts ?? this.podcasts,
      );

  _FilterState togglePodcasts() => podcasts
      ? const _FilterState()
      : const _FilterState(podcasts: true);
}

// ─────────────────────────────────────────────────────────────────────────────
// Feed mode
// ─────────────────────────────────────────────────────────────────────────────

enum _FeedMode { feed, podcastFilter, searchEpisodes, discover }

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final db = context.read<AppDatabase>();
      final pods = await db.getAllPodcasts();
      if (pods.isEmpty && mounted) _enterDiscover();
    });
  }

  @override
  void dispose() {
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
    _loadDiscover();
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
    setState(() { _loadingTrending = true; _loadingRec = true; });
    final t = await PodcastService.trending(max: 10);
    if (mounted) setState(() { _trending = t; _loadingTrending = false; });
    final subs = await db.getAllPodcasts();
    final r = await PodcastService.recommendations(subscribed: subs, max: 10);
    if (mounted) setState(() { _recommended = r; _loadingRec = false; });
  }

  // ── Subscribe ─────────────────────────────────────────────────────────────

  Future<void> _subscribe(PodcastResult result) async {
    final db = context.read<AppDatabase>();
    final l10n = AppLocalizations.of(context);
    await db.insertPodcast(result.toCompanion());
    final data = await PodcastService.loadFeed(result.feedUrl);
    if (data != null) await db.insertEpisodes(data.episodes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.subscribed(result.title))));
    }
  }

  // ── Play from Discover (temp episode) ────────────────────────────────────

  Future<void> _playTempEpisode(PodcastResult podcast, _DiscoverEpisode ep) async {
    final db = context.read<AppDatabase>();
    final player = context.read<PlayerProvider>();

    final companion = EpisodesCompanion(
      id: Value(ep.id),
      podcastId: Value(podcast.feedUrl),
      podcastTitle: Value(podcast.title),
      podcastImageUrl: Value(podcast.imageUrl),
      title: Value(ep.title),
      description: Value(ep.description),
      audioUrl: Value(ep.audioUrl),
      durationSeconds: Value(ep.durationSeconds),
      publishDate: Value(ep.publishDate),
      isSubscribed: const Value(false),
    );
    await db.insertTempEpisode(companion);
    final dbEp = await db.getEpisode(ep.id);
    if (dbEp != null && mounted) await player.play(dbEp);
  }

  // ── Download from Discover ────────────────────────────────────────────────

  Future<void> _downloadTempEpisode(
      PodcastResult podcast, _DiscoverEpisode ep) async {
    final db = context.read<AppDatabase>();
    final companion = EpisodesCompanion(
      id: Value(ep.id),
      podcastId: Value(podcast.feedUrl),
      podcastTitle: Value(podcast.title),
      podcastImageUrl: Value(podcast.imageUrl),
      title: Value(ep.title),
      description: Value(ep.description),
      audioUrl: Value(ep.audioUrl),
      durationSeconds: Value(ep.durationSeconds),
      publishDate: Value(ep.publishDate),
      isSubscribed: const Value(false),
    );
    await db.insertTempEpisode(companion);
    await DownloadService.downloadEpisode(
      episodeId: ep.id,
      audioUrl: ep.audioUrl,
      episodeTitle: ep.title,
      db: db,
    );
  }

  // ── Cover tap → podcast filter ────────────────────────────────────────────

  Future<void> _onCoverTap(Episode episode, AppDatabase db) async {
    if (_filterPodcastId == episode.podcastId) {
      setState(() {
        _mode = _FeedMode.feed; _filterPodcastId = null; _filterPodcast = null;
      });
      return;
    }
    final all = await db.getAllPodcasts();
    final pod = all.where((p) => p.id == episode.podcastId).firstOrNull;
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

  void _onFilterToggle(String key) => setState(() {
    switch (key) {
      case 'dl':
        _filter = _filter.copyWith(
            downloaded: !_filter.downloaded,
            podcasts: false);
      case 'played':
        _filter = _filter.copyWith(
            played: !_filter.played,
            podcasts: false);
      case 'az':
        _filter = _filter.copyWith(
          sort: _filter.sort == _SortMode.alphabetical
              ? _SortMode.none : _SortMode.alphabetical,
          podcasts: false,
        );
      case 'podcasts':
        _filter = _filter.togglePodcasts();
    }
  });

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final searchOpen =
        _mode == _FeedMode.discover || _mode == _FeedMode.searchEpisodes;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            _Toolbar(
              mode: _mode, searchOpen: searchOpen,
              searchCtrl: _searchCtrl, filter: _filter,
              l10n: l10n, cs: cs,
              onBack: _exitToFeed, onSearchChanged: _onSearchChanged,
              onClearSearch: () => setState(() {
                _searchQuery = ''; _searchCtrl.clear(); _piSearchResults = [];
              }),
              onSearchOpen: () => setState(() {
                _mode = _FeedMode.searchEpisodes;
                _searchQuery = ''; _searchCtrl.clear();
              }),
              onPlusPressed: _enterDiscover,
            ),

            if (_mode == _FeedMode.feed || _mode == _FeedMode.searchEpisodes)
              _FilterChipsRow(
                filter: _filter, l10n: l10n, cs: cs,
                onToggle: _onFilterToggle,
              ),

            Expanded(child: _buildBody(db, cs, l10n)),
            const MiniPlayer(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppDatabase db, ColorScheme cs, AppLocalizations l10n) {
    switch (_mode) {
      case _FeedMode.podcastFilter:
        return _PodcastFilteredFeed(
          db: db, cs: cs,
          podcastId: _filterPodcastId!, podcast: _filterPodcast,
          onClose: _exitToFeed, onCoverTap: _onCoverTap,
        );

      case _FeedMode.discover:
        return _DiscoverList(
          searchQuery: _searchQuery,
          trending: _trending, recommended: _recommended,
          piSearchResults: _piSearchResults,
          loadingTrending: _loadingTrending, loadingRec: _loadingRec,
          searchingPI: _searchingPI,
          cs: cs, l10n: l10n,
          onSubscribe: _subscribe,
          onPlayTemp: _playTempEpisode,
          onDownloadTemp: _downloadTempEpisode,
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
  final AppLocalizations l10n;
  final ColorScheme cs;
  final VoidCallback onBack;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onSearchOpen;
  final VoidCallback onPlusPressed;

  const _Toolbar({
    required this.mode, required this.searchOpen, required this.searchCtrl,
    required this.filter, required this.l10n, required this.cs,
    required this.onBack, required this.onSearchChanged, required this.onClearSearch,
    required this.onSearchOpen, required this.onPlusPressed,
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
        SvgPicture.asset('antpodlogo.svg', width: 26, height: 26),
        const SizedBox(width: 8),
        Text(l10n.appName, style: TextStyle(
          fontWeight: FontWeight.w800, fontSize: 20,
          color: cs.onSurface, letterSpacing: -0.5)),
        const Spacer(),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(Icons.tune_rounded,
                  color: filter.hasAny ? cs.primary : cs.onSurface),
              onPressed: () {},
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

  const _FilterChipsRow({
    required this.filter, required this.l10n,
    required this.cs, required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _Chip(label: l10n.filterPodcasts,
              active: filter.podcasts, cs: cs,
              icon: Icons.library_music_outlined,
              onTap: () => onToggle('podcasts')),
          const SizedBox(width: 8),
          _Chip(label: l10n.filterDownloaded,
              active: filter.downloaded && !filter.podcasts,
              cs: cs, icon: Icons.download_done,
              onTap: () => onToggle('dl')),
          const SizedBox(width: 8),
          _Chip(label: l10n.filterPlayed,
              active: filter.played && !filter.podcasts,
              cs: cs, icon: Icons.check_circle_outline,
              onTap: () => onToggle('played')),
          const SizedBox(width: 8),
          _Chip(label: l10n.filterAlphabetical,
              active: filter.sort == _SortMode.alphabetical && !filter.podcasts,
              cs: cs, icon: Icons.sort_by_alpha_rounded,
              onTap: () => onToggle('az')),
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
                const Text('🐜', style: TextStyle(fontSize: 52)),
                const SizedBox(height: 16),
                Text(l10n.emptyPodcastsTitle,
                    style: TextStyle(
                        fontSize: 16, color: cs.onSurfaceVariant)),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.78,
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
    final url = podcast.website ?? podcast.feedUrl;
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
// Episode feed
// ─────────────────────────────────────────────────────────────────────────────

class _EpisodeFeed extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return StreamBuilder<List<Episode>>(
      stream: filter.played
          ? db.watchAllSubscribedEpisodes()
          : db.watchUnfinishedEpisodes(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var eps = snap.data ?? [];

        if (searchQuery.isNotEmpty) {
          final q = searchQuery.toLowerCase();
          eps = eps.where((e) =>
              e.title.toLowerCase().contains(q) ||
              e.podcastTitle.toLowerCase().contains(q)).toList();
        }
        if (filter.downloaded) eps = eps.where((e) => e.isDownloaded).toList();
        if (filter.sort == _SortMode.alphabetical) {
          eps = List.of(eps)
            ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        }

        if (eps.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🐜', style: TextStyle(fontSize: 52)),
                const SizedBox(height: 16),
                Text(
                  searchQuery.isNotEmpty || filter.hasAny
                      ? l10n.emptySearchTitle : l10n.emptyFeedTitle,
                  style: TextStyle(
                      fontSize: 16, color: cs.onSurfaceVariant)),
                if (searchQuery.isEmpty && !filter.hasAny) ...[
                  const SizedBox(height: 6),
                  Text(l10n.emptyFeedSub,
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant)),
                ],
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.separated(
            itemCount: eps.length,
            separatorBuilder: (_, __) => Divider(
                height: 1, color: cs.outlineVariant.withValues(alpha:0.5), indent: 88),
            itemBuilder: (_, i) => EpisodeTile(
              episode: eps[i],
              onCoverTap: () => onCoverTap(eps[i], db),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Podcast-filtered feed
// ─────────────────────────────────────────────────────────────────────────────

class _PodcastFilteredFeed extends StatelessWidget {
  final AppDatabase db;
  final ColorScheme cs;
  final String podcastId;
  final Podcast? podcast;
  final VoidCallback onClose;
  final Future<void> Function(Episode, AppDatabase) onCoverTap;

  const _PodcastFilteredFeed({
    required this.db, required this.cs,
    required this.podcastId, required this.podcast,
    required this.onClose, required this.onCoverTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Episode>>(
      stream: db.watchEpisodesForPodcast(podcastId),
      builder: (context, snap) {
        final eps = snap.data ?? [];
        return Column(
          children: [
            if (podcast != null)
              PodcastHeader(podcast: podcast!, onClose: onClose),
            Expanded(
              child: ListView.separated(
                itemCount: eps.length,
                separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: cs.outlineVariant.withValues(alpha:0.5), indent: 88),
                itemBuilder: (_, i) => EpisodeTile(
                  episode: eps[i],
                  onCoverTap: () => onCoverTap(eps[i], db),
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

class _DiscoverEpisode {
  final String id, title, description, audioUrl;
  final int durationSeconds;
  final DateTime publishDate;
  const _DiscoverEpisode({
    required this.id, required this.title, required this.description,
    required this.audioUrl, required this.durationSeconds,
    required this.publishDate,
  });
}

class _DiscoverList extends StatefulWidget {
  final String searchQuery;
  final List<PodcastResult> trending;
  final List<PodcastResult> recommended;
  final List<PodcastResult> piSearchResults;
  final bool loadingTrending, loadingRec, searchingPI;
  final ColorScheme cs;
  final AppLocalizations l10n;
  final Future<void> Function(PodcastResult) onSubscribe;
  final Future<void> Function(PodcastResult, _DiscoverEpisode) onPlayTemp;
  final Future<void> Function(PodcastResult, _DiscoverEpisode) onDownloadTemp;
  final Future<void> Function() onRefresh;

  const _DiscoverList({
    required this.searchQuery, required this.trending, required this.recommended,
    required this.piSearchResults, required this.loadingTrending,
    required this.loadingRec, required this.searchingPI,
    required this.cs, required this.l10n,
    required this.onSubscribe, required this.onPlayTemp,
    required this.onDownloadTemp, required this.onRefresh,
  });

  @override
  State<_DiscoverList> createState() => _DiscoverListState();
}

class _DiscoverListState extends State<_DiscoverList> {
  @override
  Widget build(BuildContext context) {
    if (widget.searchQuery.trim().length >= 2) {
      return CustomScrollView(slivers: [
        _SectionHeader(
            title: widget.l10n.sectionSearchResults,
            cs: widget.cs),
        if (widget.searchingPI)
          const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator())))
        else if (widget.piSearchResults.isEmpty)
          SliverToBoxAdapter(
            child: Padding(padding: const EdgeInsets.all(24),
              child: Text(widget.l10n.searchNoResults,
                  style: TextStyle(color: widget.cs.onSurfaceVariant))))
        else
          SliverList(delegate: SliverChildBuilderDelegate(
            (_, i) => _DiscoverPodcastTile(
              result: widget.piSearchResults[i], rank: i + 1,
              cs: widget.cs, l10n: widget.l10n,
              onSubscribe: widget.onSubscribe,
              onPlayTemp: widget.onPlayTemp,
              onDownloadTemp: widget.onDownloadTemp,
            ),
            childCount: widget.piSearchResults.length,
          )),
      ]);
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: CustomScrollView(slivers: [
        _SectionHeader(title: widget.l10n.sectionTrending, cs: widget.cs),
        if (widget.loadingTrending)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator())))
        else
          SliverList(delegate: SliverChildBuilderDelegate(
            (_, i) => _DiscoverPodcastTile(
              result: widget.trending[i], rank: i + 1,
              cs: widget.cs, l10n: widget.l10n,
              onSubscribe: widget.onSubscribe,
              onPlayTemp: widget.onPlayTemp,
              onDownloadTemp: widget.onDownloadTemp,
            ),
            childCount: widget.trending.length,
          )),
        _SectionHeader(title: widget.l10n.sectionRecommended,
            subtitle: widget.l10n.sectionRecommendedSub,
            cs: widget.cs),
        if (widget.loadingRec)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator())))
        else
          SliverList(delegate: SliverChildBuilderDelegate(
            (_, i) => _DiscoverPodcastTile(
              result: widget.recommended[i], rank: i + 1,
              cs: widget.cs, l10n: widget.l10n,
              onSubscribe: widget.onSubscribe,
              onPlayTemp: widget.onPlayTemp,
              onDownloadTemp: widget.onDownloadTemp,
            ),
            childCount: widget.recommended.length,
          )),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
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
  final Future<void> Function(PodcastResult) onSubscribe;
  final Future<void> Function(PodcastResult, _DiscoverEpisode) onPlayTemp;
  final Future<void> Function(PodcastResult, _DiscoverEpisode) onDownloadTemp;

  const _DiscoverPodcastTile({
    required this.result, required this.rank, required this.cs,
    required this.l10n,
    required this.onSubscribe, required this.onPlayTemp,
    required this.onDownloadTemp,
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
      onTap: () => widget.onSubscribe(r),
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
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => widget.onSubscribe(r),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.primary, width: 1.5)),
                child: Icon(Icons.add, color: cs.primary, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header sliver
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final ColorScheme cs;

  const _SectionHeader({
    required this.title, required this.cs, this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(
              fontWeight: FontWeight.w800, fontSize: 16,
              color: cs.onSurface)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, style: TextStyle(
                  fontSize: 12, color: cs.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }
}
