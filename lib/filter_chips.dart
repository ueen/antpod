// lib/filter_chips.dart
import 'package:flutter/material.dart';

import 'feed_state.dart';
import 'l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Filter chip row
// ─────────────────────────────────────────────────────────────────────────────

class FilterChipsRow extends StatelessWidget {
  final FilterState filter;
  final AppLocalizations l10n;
  final ColorScheme cs;
  final ValueChanged<String> onToggle;
  final bool showPodcastsChip;
  final bool podcastsFirst;

  const FilterChipsRow({
    super.key,
    required this.filter, required this.l10n,
    required this.cs, required this.onToggle,
    this.showPodcastsChip = true,
    this.podcastsFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final podcastsChip = _FeedChip(
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
          _FeedChip(label: l10n.filterNew,
              active: filter.newOnly,
              cs: cs, icon: Icons.headphones_rounded,
              onTap: () => onToggle('new')),
          const SizedBox(width: 8),
          _FeedChip(label: l10n.filterPlaying,
              active: filter.inProgress,
              cs: cs, icon: Icons.play_circle_rounded,
              onTap: () => onToggle('inprogress')),
          const SizedBox(width: 8),
          _FeedChip(label: l10n.filterDownloaded,
              active: filter.downloaded,
              cs: cs, icon: Icons.download_done_rounded,
              onTap: () => onToggle('dl')),
          const SizedBox(width: 8),
          _FeedChip(label: l10n.filterListened,
              active: filter.history,
              cs: cs, icon: Icons.check_circle_outline,
              onTap: () => onToggle('history')),
          if (showPodcastsChip && !podcastsFirst) ...[
            const SizedBox(width: 8),
            podcastsChip,
          ],
          const SizedBox(width: 8),
          _FeedChip(label: l10n.filterAlphabetical,
              active: filter.sort == SortMode.alphabetical,
              cs: cs, icon: Icons.sort_by_alpha_rounded,
              onTap: () => onToggle('az')),
          const SizedBox(width: 8),
          _FeedChip(label: l10n.filterOldest,
              active: filter.sort == SortMode.oldest,
              cs: cs, icon: Icons.arrow_upward_rounded,
              onTap: () => onToggle('oldest')),
          const SizedBox(width: 8),
          _FeedChip(label: l10n.filterRandom,
              active: filter.sort == SortMode.random,
              cs: cs, icon: Icons.shuffle_rounded,
              onTap: () => onToggle('random')),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual chip
// ─────────────────────────────────────────────────────────────────────────────

class _FeedChip extends StatelessWidget {
  final String label;
  final bool active;
  final ColorScheme cs;
  final IconData? icon;
  final VoidCallback onTap;

  const _FeedChip({
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
          color: active ? cs.primary : cs.surfaceContainerHighest.withValues(alpha: 0.7),
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
