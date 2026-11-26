// lib/episode_feed.dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_database.dart';
import 'episode_tile.dart';
import 'feed_state.dart';
import 'l10n/app_localizations.dart';
import 'player_provider.dart';
import 'network.dart';
import 'pull_refresh.dart';

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
  /// Clears the chips that hide episodes; offered when they hide some.
  final VoidCallback? onShowAll;
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
    this.onShowAll,
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
  List<Episode> _displayed = [];

  Timer? _diffDebounce;
  List<Episode> _raw = [];
  StreamSubscription<List<Episode>>? _sub;
  StreamSubscription<int>? _markedSub;
  StreamSubscription<int>? _downloadedCountSub;
  StreamSubscription<List<Podcast>>? _podcastsSub;
  /// Subscribed podcasts: their temp episodes are off the feed.
  Set<String> _subscribed = const {};
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
    _markedSub = widget.db.watchMarkedForDownloadCount().listen((c) {
      if (c != _markedCount) setState(() => _markedCount = c);
    });
    _downloadedCountSub = widget.db.watchDownloadedEpisodeCount().listen((c) {
      if (c != _totalDownloadedCount) setState(() => _totalDownloadedCount = c);
    });
    _podcastsSub = widget.db.watchAllPodcasts().listen((pods) {
      final ids = {for (final p in pods) p.id};
      if (ids.length != _subscribed.length || !ids.containsAll(_subscribed)) {
        setState(() => _subscribed = ids);
      }
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
    if (old.refreshing != widget.refreshing) {
      setState(() {});
    }

  }

  @override
  void dispose() {
    _diffDebounce?.cancel();
    _sub?.cancel();
    if (_openFeed != null) widget.db.openFeeds.remove(_openFeed);
    _markedSub?.cancel();
    _downloadedCountSub?.cancel();
    _podcastsSub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// The podcast this list shows, registered in AppDatabase.openFeeds.
  String? _openFeed;

  void _subscribe() {
    _sub?.cancel();
    if (_openFeed != null) widget.db.openFeeds.remove(_openFeed);
    _openFeed = widget.podcastIdFilter;
    if (_openFeed != null) widget.db.openFeeds.add(_openFeed!);
    _sub = (widget.podcastIdFilter != null
            ? widget.db.watchEpisodesForPodcast(widget.podcastIdFilter!)
            : widget.filter.downloaded
                ? widget.db.watchDownloadedOrMarkedEpisodes()
                : widget.db.watchAllFeedEpisodes())
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
    if (widget.filter.favorites) {
      eps = eps.where((e) => e.isFavorite).toList();
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

  // Returns full animation duration for items in the visible viewport,
  // zero for off-screen items (instant, no visual impact or jank).
  Duration _animDuration(int index) {
    if (!_scrollCtrl.hasClients) return const Duration(milliseconds: 250);
    final pos = _scrollCtrl.position;
    const h = 90.0;
    final first = (pos.pixels / h).floor() - 1;
    final last = ((pos.pixels + pos.viewportDimension) / h).ceil() + 1;
    return index >= first && index <= last
        ? const Duration(milliseconds: 250)
        : Duration.zero;
  }

  void _diffUpdate(List<Episode> next) {
    final state = _listKey.currentState;
    if (state == null) {
      setState(() => _displayed = List.of(next));
      return;
    }

    final nextIds = {for (final e in next) e.id};
    final displayedIds = {for (final e in _displayed) e.id};

    // Pathological case: hundreds of inserts+removes at once (e.g. switching
    // podcast context on a huge list). Reset the key for an instant replace.
    final removeCount = _displayed.where((e) => !nextIds.contains(e.id)).length;
    final addCount = next.where((e) => !displayedIds.contains(e.id)).length;
    if (removeCount + addCount > 300) {
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
            duration: _animDuration(i));
        removedCount++;
      }
    }

    int addedCount = 0;
    for (int i = 0; i < next.length; i++) {
      if (!displayedIds.contains(next[i].id)) {
        _displayed.insert(i, next[i]);
        state.insertItem(i, duration: _animDuration(i));
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
            EpisodeTile(
              episode: ep,
              onCoverTap: () => widget.onCoverTap(ep, widget.db),
              offFeed: !ep.isSubscribed && _subscribed.contains(ep.podcastId),
            ),
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
                EpisodeTile(
              episode: ep,
              onCoverTap: () => widget.onCoverTap(ep, widget.db),
              offFeed: !ep.isSubscribed && _subscribed.contains(ep.podcastId),
            ),
                Divider(height: 1, color: widget.cs.outlineVariant.withValues(alpha: 0.5), indent: 88),
              ],
            ),
          ),
        ),
      );

  /// Pull-to-refresh: offline, the banner just folds away again.
  Future<void> _pullRefresh() async {
    if ((await Connectivity().checkConnectivity()).isOffline) return;
    await widget.onRefresh();
  }

  // Scroll-to-top FAB, positioned inside a Stack above the feed.
  Widget _scrollTopFab(ColorScheme cs) {
    final hasMiniPlayer = context.select<PlayerProvider, bool>((p) => p.hasEpisode);
    final fabBottom = hasMiniPlayer ? 88.0 : 16.0; // mini player top (64 + 8) + 16
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      right: 16,
      bottom: fabBottom,
      // Always there, so it fades and grows in rather than popping up.
      child: IgnorePointer(
        ignoring: !_showScrollTop,
        child: AnimatedOpacity(
          opacity: _showScrollTop ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedScale(
            scale: _showScrollTop ? 1 : 0.6,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
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
          ),
        ),
      ),
    );
  }

  /// The first load fades into the list.
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _initialLoad
            ? Center(
                key: const ValueKey('loading'),
                child: AntSpinner(color: widget.cs.primary, size: 36))
            : KeyedSubtree(key: const ValueKey('feed'), child: _feed(context)),
      );

  Widget _feed(BuildContext context) {

    final cs = widget.cs;
    final isSearching = widget.searchQuery.isNotEmpty;
    // Favourites filter on and none at all (not just none matching a search).
    // (The downloads list holds only downloads: favourites may be elsewhere.)
    final noFavorites = widget.filter.favorites && !isSearching &&
        !widget.filter.downloaded && !_raw.any((e) => e.isFavorite);
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
    // The downloads list has its own way back (above); elsewhere, offered
    // only when the chips hide episodes there are.
    final hasShowAllFooter = !isSearching &&
        !widget.filter.downloaded &&
        widget.filter.narrows &&
        widget.onShowAll != null &&
        (widget.podcastIdFilter == null
                ? _raw.length
                : _raw.where((e) => e.podcastId == widget.podcastIdFilter).length) >
            _displayed.length;

    final child = PullToRefresh(
      controller: _scrollCtrl,
      refreshing: widget.refreshing,
      onRefresh: _pullRefresh,
      builder: (banner) => CustomScrollView(
        controller: _scrollCtrl,
        physics: const SmoothScrollPhysics(),
        slivers: [
          banner,
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
                  child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: widget.isLoading
                      ? AntSpinner(
                          key: const ValueKey('loading'),
                          color: widget.cs.primary, size: 36)
                      : Column(
                    key: const ValueKey('empty'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.podcasts_rounded, size: 52,
                          color: cs.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text(
                        noFavorites
                            ? widget.l10n.emptyFavoritesTitle
                            : isSearching || widget.filter.hasAny || widget.podcastIdFilter != null
                                ? widget.l10n.emptySearchTitle
                                : widget.l10n.emptyFeedTitle,
                        style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                      ),
                      if (noFavorites) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(widget.l10n.emptyFavoritesSub,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                        ),
                      ],
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
                      if (hasShowAllFooter) ...[
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: widget.onShowAll,
                          icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                          label: Text(widget.l10n.showAllEpisodes),
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
          if (hasShowAllFooter && _displayed.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: OutlinedButton.icon(
                  onPressed: widget.onShowAll,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                  label: Text(widget.l10n.showAllEpisodes),
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
          if (widget.isLoading && _displayed.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child: AntSpinner(color: widget.cs.primary, size: 36)),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 88)),
        ],
      ),
    );

    // Keep the tree shape stable: toggling the FAB must not recreate the
    // scroll view (that reset the scroll position mid-fling → "skip").
    return Stack(
      children: [
        child,
        _scrollTopFab(cs),
      ],
    );
  }
}
