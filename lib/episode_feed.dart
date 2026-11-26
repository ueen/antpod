// lib/episode_feed.dart
import 'dart:async';
import 'dart:math' show pi, cos, sin;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderSliverToBoxAdapter, SliverGeometry;
import 'package:provider/provider.dart';

import 'app_database.dart';
import 'episode_tile.dart';
import 'feed_state.dart';
import 'l10n/app_localizations.dart';
import 'player_provider.dart';
import 'network.dart';

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
  List<Episode> _displayed = [];

  // Pull-to-refresh state
  bool _pullEligible = false;
  bool _localRefreshing = false;
  // Drag distance lives in a notifier so pointer moves only rebuild the banner,
  // not the whole feed (a setState per move made scrolling lag).
  final _pullDrag = ValueNotifier<double>(0.0);
  static const double _pullThreshold = 55.0;
  static const double _pullMax = 70.0;
  Timer? _diffDebounce;
  List<Episode> _raw = [];
  StreamSubscription<List<Episode>>? _sub;
  StreamSubscription<int>? _markedSub;
  StreamSubscription<int>? _downloadedCountSub;
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
    _scrollCtrl.dispose();
    _pullDrag.dispose();
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

  // Refresh banner — first sliver, so it scrolls with the list.
  Widget _refreshBanner() => ValueListenableBuilder<double>(
        valueListenable: _pullDrag,
        builder: (_, drag, __) {
          final active = widget.refreshing || _localRefreshing;
          final height =
              active ? 52.0 : (drag / _pullMax * 52.0).clamp(0.0, 52.0);
          return AnimatedContainer(
            duration: drag > 0 && !active
                ? Duration.zero
                : const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            height: height,
            color: widget.cs.surfaceContainerHighest,
            child: height > 20
                ? Center(child: _AntSpinner(color: widget.cs.primary))
                : null,
          );
        },
      );

  // Scroll-to-top FAB, positioned inside a Stack above the feed.
  Widget _scrollTopFab(ColorScheme cs) {
    final hasMiniPlayer = context.select<PlayerProvider, bool>((p) => p.hasEpisode);
    final fabBottom = hasMiniPlayer ? 88.0 : 16.0; // mini player top (64 + 8) + 16
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

    final child = Listener(
      onPointerDown: (e) {
        _pullEligible = _scrollCtrl.hasClients && _scrollCtrl.offset <= 0;
        if (_pullEligible) _pullDrag.value = 0;
      },
      onPointerMove: (e) {
        if (!_pullEligible) return;
        if (!_scrollCtrl.hasClients || _scrollCtrl.offset > 1) {
          _pullEligible = false;
          _pullDrag.value = 0;
          return;
        }
        final dy = e.delta.dy;
        final cur = _pullDrag.value;
        if (dy == 0 || (dy < 0 && cur == 0)) return;
        final next = (cur + dy * 0.5).clamp(0.0, _pullMax);
        if ((next - cur).abs() > 0.5) _pullDrag.value = next;
      },
      onPointerUp: (e) {
        if (!_pullEligible) return;
        _pullEligible = false;
        if (_pullDrag.value >= _pullThreshold && !_localRefreshing) {
          _pullDrag.value = 0;
          setState(() => _localRefreshing = true);
          Connectivity().checkConnectivity().then((results) {
            if (results.isOffline) {
              if (mounted) setState(() => _localRefreshing = false);
              return;
            }
            widget.onRefresh().whenComplete(() {
              if (mounted) setState(() => _localRefreshing = false);
            });
          });
        } else {
          _pullDrag.value = 0;
        }
      },
      onPointerCancel: (e) {
        _pullEligible = false;
        _pullDrag.value = 0;
      },
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: const _SmoothScrollPhysics(),
        slivers: [
          _StableTopSliver(child: _refreshBanner()),
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
          if (widget.isLoading && _displayed.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
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
        if (_showScrollTop) _scrollTopFab(cs),
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

// ─────────────────────────────────────────────────────────────────────────────
// Refresh banner sliver — keeps the content still when the banner resizes
// while it is scrolled out of view
// ─────────────────────────────────────────────────────────────────────────────

/// Like [SliverToBoxAdapter], but when its height changes while it is
/// completely scrolled past (e.g. a refresh starts or ends while the user is
/// further down the list) it reports a scroll-offset correction so the
/// visible content does not jump. While it is visible at the top it grows and
/// shrinks normally, pushing the list as the pull gesture expects.
class _StableTopSliver extends SingleChildRenderObjectWidget {
  const _StableTopSliver({required Widget super.child});

  @override
  RenderSliverToBoxAdapter createRenderObject(BuildContext context) =>
      _RenderStableTopSliver();
}

class _RenderStableTopSliver extends RenderSliverToBoxAdapter {
  double? _lastExtent;

  @override
  void performLayout() {
    final box = child;
    if (box == null) {
      super.performLayout();
      return;
    }
    box.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final extent = box.size.height;
    final last = _lastExtent;
    _lastExtent = extent;
    if (last != null &&
        extent != last &&
        constraints.scrollOffset > 0 &&
        constraints.scrollOffset >= last) {
      // Viewport applies the correction and lays out again.
      geometry = SliverGeometry(scrollOffsetCorrection: extent - last);
      return;
    }
    super.performLayout();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pull-to-refresh spinner — a ring of 8 dots turning slowly clockwise while
// the "prominent" highlight hops dot-to-dot counterclockwise, each hop a
// short crossfade (next dot fades in while the previous one fades out).
// ─────────────────────────────────────────────────────────────────────────────

class _AntSpinner extends StatefulWidget {
  final Color color;
  const _AntSpinner({required this.color});

  @override
  State<_AntSpinner> createState() => _AntSpinnerState();
}

class _AntSpinnerState extends State<_AntSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          size: const Size(22, 22),
          painter: _AntsPainter(progress: _ctrl.value, color: widget.color),
        ),
      );
}

class _AntsPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _AntsPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width * 0.40;
    final paint = Paint()..style = PaintingStyle.fill;

    const dotCount = 8;
    // Ring turns 2 dot-positions clockwise per cycle…
    final ringPhase = progress * 0.25;
    // …while the highlight steps 10 dots counterclockwise relative to the
    // ring, so the cycle loops seamlessly (net: one CCW turn per cycle).
    final step = progress * 10;

    for (int j = 0; j < dotCount; j++) {
      final angle = (j / dotCount + ringPhase) * 2 * pi - pi / 2;
      final p = _prominence((step + j) % dotCount);
      paint.color = color.withValues(alpha: 0.3 + 0.7 * p);
      canvas.drawCircle(
          Offset(cx + cos(angle) * radius, cy + sin(angle) * radius),
          1.5 + 1.4 * p,
          paint);
    }
  }

  /// Prominence (0–1) of a dot at phase [tau] ∈ [0, 8): quick fade-in just
  /// before its turn, a short hold, then a slower fade-out that overlaps the
  /// next dot's fade-in.
  static double _prominence(double tau) {
    double smooth(double x) {
      final t = x.clamp(0.0, 1.0);
      return t * t * (3 - 2 * t);
    }

    if (tau >= 7.6) return smooth((tau - 7.6) / 0.4);
    if (tau < 0.4) return 1;
    if (tau < 1.4) return 1 - smooth(tau - 0.4);
    return 0;
  }

  @override
  bool shouldRepaint(_AntsPainter old) => old.progress != progress;
}
