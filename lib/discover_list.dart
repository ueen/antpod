// lib/discover_list.dart
//
// The Discover page: trending podcasts, search results (podcasts and episodes
// interleaved) and adding a feed by URL.
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'app_database.dart';
import 'episode_tile.dart';
import 'l10n/app_localizations.dart';
import 'podcast_service.dart';
import 'pull_refresh.dart';
import 'trends_country.dart';

/// A search hit: a podcast or an episode, interleaved in one list.
class UnifiedResult {
  final PodcastResult? podcast;
  final Episode? episode;
  const UnifiedResult({this.podcast, this.episode});
}

class DiscoverList extends StatefulWidget {
  final String searchQuery;
  final List<PodcastResult> trending;
  final List<UnifiedResult> unifiedSearchResults;
  final bool loadingTrending, searchingPI;
  final bool searchHasMore, loadingMoreSearch;
  final bool isOffline;
  final bool trendingFailed;
  final ColorScheme cs;
  final AppLocalizations l10n;
  /// Opens a podcast: its page when subscribed, a preview otherwise.
  final void Function(PodcastResult) onOpen;
  final Future<void> Function() onRefresh;
  /// The country of the trends (ISO code, lowercase), in their title.
  final String trendsCountry;
  /// Another country picked in the title's sheet.
  final ValueChanged<String> onTrendsCountry;
  /// Apple Podcasts on; off, a note with [onAppleApiOn] takes the trends'
  /// place.
  final bool appleApi;
  final VoidCallback onAppleApiOn;
  final Future<void> Function() onLoadMore;

  const DiscoverList({
    super.key,
    required this.searchQuery, required this.trending,
    required this.unifiedSearchResults,
    required this.loadingTrending, required this.searchingPI,
    required this.searchHasMore, required this.loadingMoreSearch,
    this.isOffline = false,
    this.trendingFailed = false,
    required this.cs, required this.l10n,
    required this.onOpen, required this.onRefresh,
    required this.trendsCountry, required this.onTrendsCountry,
    required this.appleApi, required this.onAppleApiOn,
    required this.onLoadMore,
  });

  @override
  State<DiscoverList> createState() => _DiscoverListState();
}

class _DiscoverListState extends State<DiscoverList> {
  final _searchScrollCtrl = ScrollController();
  final _trendsScrollCtrl = ScrollController();

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
    _trendsScrollCtrl.dispose();
    super.dispose();
  }

  bool _isUrl(String q) {
    final lower = q.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  void _showRssDialog(BuildContext context) {
    // No controller: the field owns (and disposes) its own.
    var typed = '';
    void open(BuildContext ctx, String url) {
      url = url.trim();
      if (url.isEmpty) return;
      if (!url.contains('://')) url = 'https://$url';
      Navigator.pop(ctx);
      widget.onOpen(PodcastResult.feed(url));
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.l10n.addRssFeed),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://...',
            prefixIcon: Icon(Icons.rss_feed_rounded),
          ),
          keyboardType: TextInputType.url,
          onChanged: (url) => typed = url,
          onSubmitted: (url) => open(ctx, url),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(widget.l10n.cancel)),
          FilledButton(
            onPressed: () => open(ctx, typed),
            child: Text(widget.l10n.openFeed),
          ),
        ],
      ),
    );
  }

  Widget _unifiedList(List<UnifiedResult> results) {
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
            onPreview: widget.onOpen,
          );
        }
        final ep = r.episode!;
        return Column(children: [
          EpisodeTile(
            episode: ep,
            isSubscribedContext: false,
            onCoverTap: () => widget.onOpen(PodcastResult.fromEpisode(ep)),
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
                  onPressed: () => widget.onOpen(PodcastResult.feed(url)),
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
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: widget.appleApi ? _trends(cs, l10n) : _appleOff(cs, l10n),
          ),
        ),
      ],
    );
  }

  /// In place of the trends while Apple is off: why, and a way back.
  Widget _appleOff(ColorScheme cs, AppLocalizations l10n) => CustomScrollView(
        key: const ValueKey('apple-off'),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 32, 32, 88),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.travel_explore_rounded, size: 44, color: cs.primary),
                    const SizedBox(height: 14),
                    Text(l10n.trendsAppleOff,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w600,
                            fontSize: 16, color: cs.onSurface)),
                    const SizedBox(height: 6),
                    Text(l10n.trendsAppleOffSub,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: widget.onAppleApiOn,
                      child: Text(l10n.trendsAppleOn),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );

  // The pull only triggers the refresh; the spinner in the middle shows it
  // loading.
  Widget _trends(ColorScheme cs, AppLocalizations l10n) => PullToRefresh(
        key: const ValueKey('trends'),
        controller: _trendsScrollCtrl,
        onRefresh: widget.onRefresh,
        holdWhileRefreshing: false,
        // One scroll view in every state: the title scrolls away with the
        // list, and pull-to-refresh also works while loading/empty/error.
        builder: (banner) => CustomScrollView(
          controller: _trendsScrollCtrl,
          physics: const SmoothScrollPhysics(),
          slivers: [
            banner,
            SliverToBoxAdapter(child: _trendsTitle(cs)),
            if (widget.loadingTrending)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: AntSpinner(color: cs.primary, size: 36)),
              )
            else if (widget.trendingFailed)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(children: [
                    Icon(Icons.wifi_off_rounded,
                        size: 40, color: cs.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(l10n.trendingError,
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ]),
                ),
              )
            else if (widget.trending.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(l10n.trendingEmpty,
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
                    onPreview: widget.onOpen,
                  ),
                ),
              ),
          ],
        ),
      );

  Future<void> _pickCountry() async {
    final code = await showTrendsCountrySheet(context, widget.trendsCountry);
    if (code != null && code != widget.trendsCountry) widget.onTrendsCountry(code);
  }

  // Tab-like pill so the section title reads as a label, not body text.
  // Tapping it picks the country.
  Widget _trendsTitle(ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Center(
          child: Material(
            // The active filter chip's color: border and title, over a
            // light tint of it.
            color: cs.primary.withValues(alpha: 0.12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: cs.primary, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('trends-title'),
              onTap: _pickCountry,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Text('Apple Trends (${widget.trendsCountry.toUpperCase()})',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                        color: cs.primary)),
              ),
            ),
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
