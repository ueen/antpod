// lib/feed_state.dart
import 'dart:math' as math;

import 'app_database.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sort mode
// ─────────────────────────────────────────────────────────────────────────────

enum SortMode { none, alphabetical, oldest, random }

List<Episode> sortEpisodes(List<Episode> eps, SortMode sort,
    {bool inProgress = false}) {
  List<Episode> result;
  switch (sort) {
    case SortMode.alphabetical:
      result = List.of(eps)
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    case SortMode.oldest:
      result = List.of(eps)
        ..sort((a, b) => a.publishDate.compareTo(b.publishDate));
    case SortMode.random:
      result = List.of(eps)..shuffle(math.Random());
    case SortMode.none:
      result = List.of(eps);
  }
  if (!inProgress) return result;
  // Float started (but not finished) episodes to top while preserving base sort.
  return [
    ...result.where((e) => e.lastPositionMs > 0 && !e.isFinished),
    ...result.where((e) => e.lastPositionMs <= 0 || e.isFinished),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter state
// ─────────────────────────────────────────────────────────────────────────────

class FilterState {
  final bool newOnly;
  final bool history;
  final bool downloaded;
  final SortMode sort;
  final bool inProgress;
  /// True when the user is viewing a specific podcast feed. The chip shows as
  /// active ("Podcasts" is selected); tapping it exits back to the main feed.
  final bool podcasts;

  const FilterState({
    this.newOnly = true,
    this.history = false,
    this.downloaded = false,
    this.sort = SortMode.none,
    this.inProgress = false,
    this.podcasts = false,
  });

  // Dot appears whenever any chip is visually active.
  bool get hasAny =>
      newOnly || history || downloaded || sort != SortMode.none || inProgress || podcasts;

  bool get isOldestFirst => sort == SortMode.oldest;

  FilterState copyWith({
    bool? newOnly, bool? history, bool? downloaded,
    SortMode? sort, bool? inProgress, bool? podcasts,
  }) =>
      FilterState(
        newOnly: newOnly ?? this.newOnly,
        history: history ?? this.history,
        downloaded: downloaded ?? this.downloaded,
        sort: sort ?? this.sort,
        inProgress: inProgress ?? this.inProgress,
        podcasts: podcasts ?? this.podcasts,
      );

  FilterState togglePodcasts() => podcasts
      ? const FilterState()
      : const FilterState(podcasts: true, newOnly: false);

  /// Toggles the chip [key]. "New" and "History" exclude each other; History
  /// also clears Downloaded and In progress. Sort chips toggle one sort mode.
  FilterState toggle(String key) {
    SortMode sortTo(SortMode m) => sort == m ? SortMode.none : m;
    return switch (key) {
      'new' => copyWith(newOnly: !newOnly, history: false),
      'history' => copyWith(
          history: !history, newOnly: false, downloaded: false, inProgress: false),
      'dl' => copyWith(downloaded: !downloaded),
      'az' => copyWith(sort: sortTo(SortMode.alphabetical)),
      'oldest' => copyWith(sort: sortTo(SortMode.oldest)),
      'random' => copyWith(sort: sortTo(SortMode.random)),
      'inprogress' => copyWith(inProgress: !inProgress),
      'podcasts' => copyWith(podcasts: !podcasts),
      _ => this,
    };
  }
}
