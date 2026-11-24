// lib/podcast_header.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'html_utils.dart';
import 'l10n/app_localizations.dart';
import 'share_utils.dart';

class PodcastHeader extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String author;
  final String description;
  /// Shared as the podcast's antpod.eu link.
  final String feedUrl;

  /// Provide exactly one of these; the other should be null.
  /// [onUnsubscribe] is called on tap — the caller shows the confirmation.
  final VoidCallback? onSubscribe;
  final VoidCallback? onUnsubscribe;

  /// Subscribed podcast that doesn't load new episodes.
  final bool syncPaused;

  /// Unsubscribed feed with episodes left to finish (started or downloaded);
  /// it tidies itself up once they're played.
  final bool finishing;

  /// Icons for the two states; the unsubscribe sheet uses them too.
  static const stopNewEpisodesIcon = Icons.update_disabled_rounded;
  static const finishEpisodesIcon = Icons.sports_score_rounded;

  const PodcastHeader({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.author,
    required this.description,
    required this.feedUrl,
    this.onSubscribe,
    this.onUnsubscribe,
    this.syncPaused = false,
    this.finishing = false,
  });

  @override
  State<PodcastHeader> createState() => _PodcastHeaderState();
}

class _PodcastHeaderState extends State<PodcastHeader> {
  bool _expanded = false;
  bool _subscribePressed = false;
  /// Which note was shown last, kept so it can collapse with its text intact.
  late bool _notePaused = widget.syncPaused;

  bool get _showNote => widget.syncPaused || widget.finishing;

  @override
  void didUpdateWidget(PodcastHeader old) {
    super.didUpdateWidget(old);
    // The header outlives subscription changes (the list below updates in
    // place), so re-arm + once it's gone, ready for the next time it shows.
    if (widget.onSubscribe == null) _subscribePressed = false;
    if (_showNote) _notePaused = widget.syncPaused;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: widget.imageUrl,
                      width: 60, height: 60, fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 300),
                      fadeOutDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) => Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(Icons.podcasts_rounded, size: 28,
                              color: cs.onSurfaceVariant)),
                      errorWidget: (_, __, ___) => Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(Icons.podcasts_rounded, size: 28,
                              color: cs.onSurfaceVariant)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: cs.onSurface)),
                        if (widget.author.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(widget.author,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant)),
                        ],
                        // State note ("new episodes stopped" / "finishing"):
                        // grows and fades in, and on resubscribe shrinks and
                        // fades out at the same time, like the filter bar.
                        ClipRect(
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeInOutCubic,
                            alignment: AlignmentDirectional.topStart,
                            heightFactor: _showNote ? 1.0 : 0.0,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: _showNote ? 1.0 : 0.0,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                        _notePaused
                                            ? PodcastHeader.stopNewEpisodesIcon
                                            : PodcastHeader.finishEpisodesIcon,
                                        size: 14, color: cs.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                          _notePaused
                                              ? l10n.newEpisodesStopped
                                              : l10n.finishingEpisodes,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: cs.onSurfaceVariant)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Share button
                  Padding(
                    padding: const EdgeInsets.only(left: 6, right: 12),
                    child: GestureDetector(
                      onTap: () => ShareUtils.sharePodcast(widget.title, widget.feedUrl),
                      child: Icon(Icons.share_rounded,
                          color: cs.onSurfaceVariant, size: 24),
                    ),
                  ),
                  // Subscribe (+, then ✓) / unsubscribe (−) button
                  if (widget.onSubscribe != null || widget.onUnsubscribe != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: widget.onSubscribe != null
                            ? GestureDetector(
                                key: ValueKey(_subscribePressed ? 'check' : 'add'),
                                onTap: _subscribePressed ? null : () async {
                                  setState(() => _subscribePressed = true);
                                  await Future.delayed(const Duration(milliseconds: 380));
                                  widget.onSubscribe?.call();
                                },
                                child: _subscribePressed
                                    ? const Icon(Icons.check_circle_rounded,
                                        color: Colors.green, size: 32)
                                    : Icon(Icons.add_circle_outline_rounded,
                                        color: cs.primary, size: 32),
                              )
                            : GestureDetector(
                                key: const ValueKey('remove'),
                                onTap: widget.onUnsubscribe,
                                child: Icon(Icons.remove_circle_outline_rounded,
                                    color: cs.error, size: 32),
                              ),
                      ),
                    ),
                ],
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: ShowNotes(description: widget.description, cs: cs),
                  ),
                ),
              ),
            // Expand arrow
            Center(
              child: AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    color: cs.onSurfaceVariant, size: 20),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
