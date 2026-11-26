// lib/podcast_feed.dart
import 'package:flutter/material.dart';

import 'app_database.dart';
import 'episode_feed.dart';
import 'feed_state.dart';
import 'filter_chips.dart';
import 'l10n/app_localizations.dart';
import 'podcast_header.dart';

/// One podcast's page: header (subscribe, description) and filter chips above
/// its episodes. Used for subscribed podcasts and for previews.
class PodcastFeed extends StatelessWidget {
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

  const PodcastFeed({
    super.key,
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
        _FlagWatcher(
          podcastId: feedId,
          watch: db.watchHasEpisodesToFinish,
          enabled: !isSubscribed,
          builder: (finishing) => _FlagWatcher(
            podcastId: feedId,
            watch: db.watchFeedFailing,
            // A paused feed isn't refreshed, so its count stands still.
            enabled: isSubscribed && !syncPaused,
            builder: (failing) => PodcastHeader(
              imageUrl: imageUrl,
              title: title,
              author: author,
              description: description,
              feedUrl: feedId,
              onSubscribe: onSubscribe,
              onUnsubscribe: onUnsubscribe,
              syncPaused: syncPaused,
              finishing: finishing,
              failing: failing,
            ),
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

/// Rebuilds [builder] with a podcast's flag from [watch], e.g. whether an
/// unsubscribed feed still has episodes left to finish (started or
/// downloaded). Keeps one stream per podcast.
class _FlagWatcher extends StatefulWidget {
  final String podcastId;
  /// A database method (tear-offs of the same one compare equal).
  final Stream<bool> Function(String podcastId) watch;
  final bool enabled;
  final Widget Function(bool flag) builder;

  const _FlagWatcher({
    required this.podcastId, required this.watch,
    required this.enabled, required this.builder,
  });

  @override
  State<_FlagWatcher> createState() => _FlagWatcherState();
}

class _FlagWatcherState extends State<_FlagWatcher> {
  Stream<bool>? _stream;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(_FlagWatcher old) {
    super.didUpdateWidget(old);
    if (old.podcastId != widget.podcastId || old.enabled != widget.enabled ||
        old.watch != widget.watch) {
      _subscribe();
    }
  }

  void _subscribe() =>
      _stream = widget.enabled ? widget.watch(widget.podcastId) : null;

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
