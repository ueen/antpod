// lib/episode_feed.dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'app_database.dart';
import 'episode_tile.dart';
import 'feed_state.dart';
import 'l10n/app_localizations.dart';
import 'player_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Episode feed — animated list with diff
// ─────────────────────────────────────────────────────────────────────────────

class EpisodeFeed extends StatefulWidget {
  final AppDatabase db;
  final ColorScheme cs;
  final AppLocalizations l10n;
  final String searchQuery;
  final FilterState filter;
  final Future<void> Function(Episode, AppDatabase) onCoverTap;
  final Future<void> Function() onRefresh;
  final VoidCallback? onSearchOnline;
  final VoidCallback? onShowAllDownloads;
  final String? podcastIdFilter;
  final List<Widget>? headerSlivers;
  final bool refreshing;
  final bool isLoading;

  const EpisodeFeed({
    super.key,
    required this.db, required this.cs,
    required this.l10n, required this.filter,
    required this.onCoverTap, required this.onRefresh,
    this.searchQuery = '',
    this.onSearchOnline,
    this.onShowAllDownloads,
    this.podcastIdFilter,
    this.headerSlivers,
    this.refreshing = false,
    this.isLoading = false,
  });

  @override
  State<EpisodeFeed> createState() => _EpisodeFeedState();
}

class _EpisodeFeedState extends State<EpisodeFeed> {
  GlobalKey<SliverAnimatedListState> _listKey = GlobalKey<SliverAnimatedListState>();
  final GlobalKey<RefreshIndicatorState> _refreshKey = GlobalKey<RefreshIndicatorState>();
  List<Episode> _displayed = [];
  Timer? _diffDebounce;
  Timer? _markedDebounce;
  Timer? _downloadedCountDebounce;
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
    _markedSub = widget.db.watchMarkedForDownloadEpisodes().listen((eps) {
      _markedDebounce?.cancel();
      _markedDebounce = Timer(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        final c = eps.length;
        if (c != _markedCount) setState(() => _markedCount = c);
      });
    });
    _downloadedCountSub = widget.db.watchAllFeedEpisodes(downloadedOnly: true).listen((eps) {
      _downloadedCountDebounce?.cancel();
      _downloadedCountDebounce = Timer(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        final c = eps.length;
        if (c != _totalDownloadedCount) setState(() => _totalDownloadedCount = c);
      });
    });
    _scrollCtrl.addListener(() {
      final show = _scrollCtrl.offset > 300;
      if (show != _showScrollTop) setState(() => _showScrollTop = show);
    });
  }

  @override
  void didUpdateWidget(EpisodeFeed old) {
    super.didUpdateWidget(old);
    if (!widget.filter.downloaded && _showMarked) {
      _showMarked = false;
    }
    if (old.podcastIdFilter != widget.podcastIdFilter ||
        old.filter.downloaded != widget.filter.downloaded) {
      _subscribe();
      return;
    }
    if (old.filter != widget.filter || old.searchQuery != widget.searchQuery) {
      _diffUpdate(_applyFilters(_raw));
    }
    if (!old.refreshing && widget.refreshing) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _refreshKey.currentState?.show());
    }
  }

  @override
  void dispose() {
    _diffDebounce?.cancel();
    _markedDebounce?.cancel();
    _downloadedCountDebounce?.cancel();
    _sub?.cancel();
    _markedSub?.cancel();
    _downloadedCountSub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = (widget.podcastIdFilter != null
            ? widget.db.watchEpisodesForPodcast(widget.podcastIdFilter!)
            : widget.filter.downloaded
                ? widget.db.watchDownloadedOrMarkedEpisodes()
                : widget.db.watchAllFeedEpisodes(downloadedOnly: false))
        .listen(_onData);
  }

  void _revealMarked() {
    setState(() => _showMarked = true);
    _diffUpdate(_applyFilters(_raw));
  }

  // Unified filter path — same behavior in home feed and podcast feed.
  // The podcast feed merely adds a podcastIdFilter scope on top.
  List<Episode> _applyFilters(List<Episode> raw) {
    var eps = raw;

    // Narrow to this podcast (no-op when not set).
    if (widget.podcastIdFilter != null) {
      eps = eps.where((e) => e.podcastId == widget.podcastIdFilter).toList();
    }

    // Narrow by text query (no-op when empty).
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

    // When showing downloaded + marked: downloaded group first, marked group second.
    if (_showMarked && widget.filter.downloaded) {
      final downloaded = sortEpisodes(
        eps.where((e) => e.isDownloaded).toList(),
        widget.filter.sort, inProgress: widget.filter.inProgress,
      );
      final marked = sortEpisodes(
        eps.where((e) => !e.isDownloaded && e.markedForDownload).toList(),
        widget.filter.sort, inProgress: widget.filter.inProgress,
      );
      return [...downloaded, ...marked];
    }

    // History: default to most-recently-finished first; respect manual sort if set.
    if (widget.filter.history && widget.filter.sort == SortMode.none) {
      return List.of(eps)..sort((a, b) =>
          (b.lastPlayed ?? DateTime(0)).compareTo(a.lastPlayed ?? DateTime(0)));
    }

    return sortEpisodes(eps, widget.filter.sort, inProgress: widget.filter.inProgress);
  }

  void _onData(List<Episode> raw) {
    _raw = raw;
    if (_initialLoad) {
      final filtered = _applyFilters(raw);
      setState(() {
        _displayed = List.of(filtered);
        _initialLoad = false;
      });
      return;
    }
    _diffDebounce?.cancel();
    _diffDebounce = Timer(const Duration(milliseconds: 80), () {
      _diffUpdate(_applyFilters(_raw));
    });
  }

  void _diffUpdate(List<Episode> next) {
    final state = _listKey.currentState;
    if (state == null) {
      setState(() => _displayed = List.of(next));
      return;
    }

    final nextIds = {for (final e in next) e.id};
    final displayedIds = {for (final e in _displayed) e.id};

    final removeCount = _displayed.where((e) => !nextIds.contains(e.id)).length;
    final addCount = next.where((e) => !displayedIds.contains(e.id)).length;

    // Large structural change (e.g. switching filter modes removes hundreds of
    // items). Animating each one with insertItem/removeItem blocks the UI thread
    // and causes ANR. Reset the list key for an instant replace instead.
    if (removeCount + addCount > 20) {
      setState(() {
        _displayed = List.of(next);
        _listKey = GlobalKey<SliverAnimatedListState>();
      });
      return;
    }

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

    final byId = {for (final e in next) e.id: e};
    for (int i = 0; i < _displayed.length; i++) {
      _displayed[i] = byId[_displayed[i].id] ?? _displayed[i];
    }

    if (removedCount + addedCount == 0) {
      final nextPos = {for (int i = 0; i < next.length; i++) next[i].id: i};
      _displayed.sort((a, b) => (nextPos[a.id] ?? 0).compareTo(nextPos[b.id] ?? 0));
    }
    // Always rebuild so updated Episode data (lastPositionMs, isFinished, etc.)
    // is pushed to existing tiles — SliverAnimatedList only refreshes the
    // specific inserted/removed slot, not the rest of the visible list.
    setState(() {});
  }

  Widget _tile(Episode ep) => RepaintBoundary(
        child: Column(
          children: [
            EpisodeTile(episode: ep, onCoverTap: () => widget.onCoverTap(ep, widget.db)),
            Divider(height: 1, color: widget.cs.outlineVariant.withValues(alpha: 0.5), indent: 88),
          ],
        ),
      );

  Widget _animatedTile(Episode ep, Animation<double> anim) => SizeTransition(
        key: ValueKey(ep.id),
        sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: _tile(ep),
        ),
      );

  Widget _exitTile(Episode ep, Animation<double> anim) => SizeTransition(
        sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeIn),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
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

  // Scroll-to-top FAB, positioned inside a Stack above the feed.
  Widget _scrollTopFab(ColorScheme cs) {
    final hasMiniPlayer = context.select<PlayerProvider, bool>((p) => p.hasEpisode);
    final fabBottom = hasMiniPlayer ? 76.0 : 16.0;
    return AnimatedPositioned(
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
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
          ),
          child: Icon(Icons.arrow_upward_rounded, color: cs.onPrimaryContainer, size: 22),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoad) return const Center(child: CircularProgressIndicator());

    final cs = widget.cs;
    final isSearching = widget.searchQuery.isNotEmpty;
    final hasSearchFooter = isSearching && widget.onSearchOnline != null;
    final hasDownloadFooter = !isSearching &&
        widget.filter.downloaded &&
        widget.onShowAllDownloads != null &&
        (widget.filter.newOnly || widget.filter.history || widget.filter.inProgress) &&
        _totalDownloadedCount > _displayed.length;
    final hasMarkedFooter = !isSearching &&
        !hasDownloadFooter &&
        widget.filter.downloaded &&
        !_showMarked &&
        _markedCount > 0;

    final child = RefreshIndicator(
      key: _refreshKey,
      onRefresh: widget.onRefresh,
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: const _SmoothScrollPhysics(),
        slivers: [
          if (widget.headerSlivers != null)
            for (final w in widget.headerSlivers!)
              SliverToBoxAdapter(child: w),
          SliverAnimatedList(
            key: _listKey,
            initialItemCount: _displayed.length,
            itemBuilder: (ctx, i, anim) => _animatedTile(_displayed[i], anim),
          ),
          if (_displayed.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 320,
                child: Center(
                  child: widget.isLoading
                      ? const CircularProgressIndicator()
                      : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.podcasts_rounded, size: 52,
                          color: cs.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text(
                        isSearching || widget.filter.hasAny || widget.podcastIdFilter != null
                            ? widget.l10n.emptySearchTitle
                            : widget.l10n.emptyFeedTitle,
                        style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                      ),
                      if (!isSearching && !widget.filter.hasAny && widget.podcastIdFilter == null) ...[
                        const SizedBox(height: 6),
                        Text(widget.l10n.emptyFeedSub,
                            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
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
          if (hasSearchFooter && _displayed.isNotEmpty)
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
          if (hasDownloadFooter && _displayed.isNotEmpty)
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
          if (hasMarkedFooter && _displayed.isNotEmpty)
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

    if (!_showScrollTop) return child;
    return Stack(
      children: [
        child,
        _scrollTopFab(cs),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Smooth scroll physics
// ─────────────────────────────────────────────────────────────────────────────

// Scrolls ~40% further than Android default (friction 0.015 → 0.007) while
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
