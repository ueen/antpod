// lib/episode_tile.dart
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'app_database.dart';
import 'download_provider.dart';
import 'download_service.dart';
import 'l10n/app_localizations.dart';
import 'player_provider.dart';
import 'share_utils.dart';

// ─── WiFi download helper ─────────────────────────────────────────────────────

/// Check connectivity and either download immediately (WiFi/ethernet) or show
/// a bottom sheet asking the user whether to download now or queue for WiFi.
Future<void> triggerDownload({
  required BuildContext context,
  required Episode episode,
  required AppDatabase db,
  required DownloadProvider downloads,
}) async {
  final result = await Connectivity().checkConnectivity();
  final isWifi = result.contains(ConnectivityResult.wifi) ||
      result.contains(ConnectivityResult.ethernet);

  if (!context.mounted) return;

  if (isWifi) {
    final taskId = await DownloadService.downloadEpisode(
      episodeId: episode.id, audioUrl: episode.audioUrl,
      episodeTitle: episode.title, db: db,
    );
    if (taskId != null && context.mounted) downloads.trackDownload(taskId);
    return;
  }

  // Mobile data — ask the user
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _WifiDownloadSheet(
      onDownloadNow: () async {
        Navigator.pop(ctx);
        final taskId = await DownloadService.downloadEpisode(
          episodeId: episode.id, audioUrl: episode.audioUrl,
          episodeTitle: episode.title, db: db,
        );
        if (taskId != null) downloads.trackDownload(taskId);
      },
      onSaveForWifi: () {
        Navigator.pop(ctx);
        db.markForDownload(episode.id);
      },
      onCancel: () => Navigator.pop(ctx),
    ),
  );
}

// ─── WiFi download bottom sheet ───────────────────────────────────────────────

class _WifiDownloadSheet extends StatelessWidget {
  final VoidCallback onDownloadNow;
  final VoidCallback onSaveForWifi;
  final VoidCallback onCancel;

  const _WifiDownloadSheet({
    required this.onDownloadNow,
    required this.onSaveForWifi,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2)),
          ),
          Icon(Icons.wifi_off_rounded, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(l10n.noWifi,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          const SizedBox(height: 4),
          Text(l10n.onMobileData,
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onSaveForWifi,
              child: Text(l10n.saveForWifi),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onDownloadNow,
              child: Text(l10n.downloadNow),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onCancel,
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }
}

const _kFinishedOpacity = 0.45;

class EpisodeTile extends StatelessWidget {
  final Episode episode;
  final VoidCallback onCoverTap;
  final bool isSubscribedContext;

  const EpisodeTile({
    super.key,
    required this.episode,
    required this.onCoverTap,
    this.isSubscribedContext = true,
  });

  String _fmt(int s) {
    if (s <= 0) return '';
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}min';
    if (m > 0) return '${m}min';
    return '${s % 60}s';
  }

  void _showContextMenu(BuildContext context, AppDatabase db, AppLocalizations l10n,
      {required bool isDownloading, required DownloadProvider downloads}) {
    final cs = Theme.of(context).colorScheme;
    final isMarked = episode.markedForDownload;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _EpisodeContextMenu(
        episode: episode,
        cs: cs,
        l10n: l10n,
        onMarkPlayed: !episode.isFinished
            ? () { Navigator.pop(context); db.markFinished(episode.id); }
            : null,
        onMarkUnplayed: (episode.isFinished || episode.lastPositionMs > 0)
            ? () {
                final messenger = ScaffoldMessenger.of(context);
                db.markUnfinished(episode.id);
                Navigator.pop(context);
                messenger.showSnackBar(SnackBar(
                    content: Text(l10n.markUnplayed),
                    duration: const Duration(seconds: 2)));
              }
            : null,
        onDownload: (!episode.isDownloaded && !isDownloading && !isMarked)
            ? () async {
                Navigator.pop(context);
                await triggerDownload(
                  context: context, episode: episode, db: db, downloads: downloads);
              }
            : null,
        onCancelWifiQueue: isMarked
            ? () { Navigator.pop(context); db.clearMarkedForDownload(episode.id); }
            : null,
        onShare: () {
          Navigator.pop(context);
          final text = '${episode.title} (${episode.podcastTitle})\n${ShareUtils.episodeUrl(episode)}';
          SharePlus.instance.share(ShareParams(text: text, subject: episode.title));
        },
        onExportFile: episode.isDownloaded && episode.localPath != null
            ? () {
                Navigator.pop(context);
                SharePlus.instance.share(ShareParams(
                  files: [XFile(episode.localPath!)],
                  subject: episode.title,
                ));
              }
            : null,
        onDeleteDownload: episode.isDownloaded
            ? () { Navigator.pop(context); db.deleteLocalFile(episode.id); }
            : null,
        onRemoveEpisode: !episode.isSubscribed
            ? () { Navigator.pop(context); db.cleanupTempEpisode(episode.id); }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // select() instead of watch(): tiles only rebuild on episode/playing state changes,
    // never on position ticks. List progress bar reads episode.lastPositionMs (DB-saved
    // every ~5s) — live position is only needed in the mini player.
    final isCurrent = context.select<PlayerProvider, bool>(
        (p) => p.currentEpisode?.id == episode.id);
    final isPlaying = context.select<PlayerProvider, bool>(
        (p) => p.currentEpisode?.id == episode.id && p.isPlaying);
    final isLoading = context.select<PlayerProvider, bool>(
        (p) => p.currentEpisode?.id == episode.id && p.isLoading && episode.localPath == null);

    // select() instead of watch(): only rebuilds when THIS episode's download progress changes,
    // not on every progress tick from any other episode's download.
    final dlProgress = context.select<DownloadProvider, double?>(
        (d) => d.progressForTask(episode.downloadTaskId));
    final db = context.read<AppDatabase>();
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final dimmed = episode.isFinished && !isCurrent;
    final opacity = dimmed ? _kFinishedOpacity : 1.0;

    final ringProgress = episode.isDownloaded ? 1.0 : dlProgress;
    final activeTaskId = episode.downloadTaskId;
    final isDownloading = activeTaskId != null && dlProgress != null;
    final isMarked = episode.markedForDownload;

    return _StickySwipeable(
      startBackground: _PlayedSwipeBackground(episode: episode, cs: cs, l10n: l10n),
      endBackground: _DownloadSwipeBackground(
          episode: episode, cs: cs, l10n: l10n,
          isDownloading: isDownloading, isMarked: isMarked),
      onSwipeStart: () async {
        if (episode.isFinished) {
          await db.markUnfinished(episode.id);
        } else {
          await db.markFinished(episode.id);
        }
      },
      onSwipeEnd: () async {
        final downloads = context.read<DownloadProvider>();
        if (isDownloading) {
          await downloads.cancelDownload(activeTaskId, episode.id);
        } else if (episode.isDownloaded) {
          await db.deleteLocalFile(episode.id);
        } else if (isMarked) {
          await db.clearMarkedForDownload(episode.id);
        } else {
          await triggerDownload(
            context: context, episode: episode, db: db, downloads: downloads);
        }
      },
      child: GestureDetector(
        onLongPress: () => _showContextMenu(context, db, l10n,
            isDownloading: isDownloading, downloads: context.read<DownloadProvider>()),
        child: InkWell(
          onTap: () => context.read<PlayerProvider>().play(episode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            color: isCurrent
                ? Color.alphaBlend(cs.primary.withValues(alpha: 0.07), cs.surface)
                : cs.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // SizedBox height 68 forces the Row (and thus the metadata
                // column) to 68px — enough room for 2-line title + progress bar.
                SizedBox(
                  width: 60, height: 68,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: opacity,
                      duration: const Duration(milliseconds: 200),
                      child: GestureDetector(
                        onTap: onCoverTap,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: episode.podcastImageUrl,
                            width: 60, height: 60, fit: BoxFit.cover,
                            placeholder: (_, __) => _CoverPlaceholder(cs: cs),
                            errorWidget: (_, __, ___) => _CoverPlaceholder(cs: cs),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedOpacity(
                    opacity: opacity,
                    duration: const Duration(milliseconds: 200),
                    child: _EpisodeMetadata(
                      episode: episode,
                      isCurrent: isCurrent,
                      cs: cs,
                      formatDuration: _fmt,
                      effectivePositionMs: episode.lastPositionMs,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _ActionArea(
                  episode: episode,
                  isCurrent: isCurrent,
                  isPlaying: isPlaying,
                  isLoading: isLoading,
                  ringProgress: ringProgress,
                  isMarked: isMarked,
                  dimmed: dimmed,
                  cs: cs,
                  onPlayTap: () {
                    final p = context.read<PlayerProvider>();
                    if (isCurrent) {
                      p.togglePlayPause();
                    } else {
                      p.play(episode);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sticky swipe wrapper ─────────────────────────────────────────────────────

class _StickySwipeable extends StatefulWidget {
  final Widget child;
  final Widget startBackground;
  final Widget endBackground;
  final Future<void> Function() onSwipeStart;
  final Future<void> Function() onSwipeEnd;

  const _StickySwipeable({
    required this.child,
    required this.startBackground,
    required this.endBackground,
    required this.onSwipeStart,
    required this.onSwipeEnd,
  });

  @override
  State<_StickySwipeable> createState() => _StickySwipeableState();
}

class _StickySwipeableState extends State<_StickySwipeable>
    with SingleTickerProviderStateMixin {
  late AnimationController _snapCtrl;

  double _dx = 0;

  static const _maxFraction = 0.40;
  static const _triggerFraction = 0.40;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      lowerBound: -500,
      upperBound: 500,
      value: 0.0,
    )..addListener(_onSnapTick);
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onSnapTick() {
    if (mounted) setState(() => _dx = _snapCtrl.value);
  }

  void _onUpdate(DragUpdateDetails d) {
    _snapCtrl.stop();
    final max = MediaQuery.of(context).size.width * _maxFraction;
    setState(() => _dx = (_dx + d.delta.dx).clamp(-max, max));
  }

  void _onEnd(DragEndDetails _) {
    final trigger = MediaQuery.of(context).size.width * _triggerFraction;
    final didStart = _dx >= trigger;
    final didEnd = _dx <= -trigger;
    _snapCtrl.value = _dx; // sync controller with current drag position
    _snapCtrl.animateTo(
      0.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeIn,
    ).then((_) {
      if (mounted && didStart) widget.onSwipeStart();
      if (mounted && didEnd) widget.onSwipeEnd();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          if (_dx > 4) Positioned.fill(child: widget.startBackground),
          if (_dx < -4) Positioned.fill(child: widget.endBackground),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// ─── Swipe backgrounds ────────────────────────────────────────────────────────

class _PlayedSwipeBackground extends StatelessWidget {
  final Episode episode;
  final ColorScheme cs;
  final AppLocalizations l10n;
  const _PlayedSwipeBackground({required this.episode, required this.cs, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final finished = episode.isFinished;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 24),
      color: finished ? cs.secondaryContainer : cs.tertiaryContainer,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            finished ? Icons.mark_email_unread_outlined : Icons.check_circle_outline,
            color: finished ? cs.onSecondaryContainer : cs.onTertiaryContainer,
            size: 28,
          ),
          const SizedBox(height: 4),
          Text(
            finished ? l10n.markUnplayed : l10n.markPlayed,
            style: TextStyle(
              color: finished ? cs.onSecondaryContainer : cs.onTertiaryContainer,
              fontSize: 11, fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadSwipeBackground extends StatelessWidget {
  final Episode episode;
  final ColorScheme cs;
  final AppLocalizations l10n;
  final bool isDownloading;
  final bool isMarked;
  const _DownloadSwipeBackground({
    required this.episode, required this.cs, required this.l10n,
    required this.isDownloading, required this.isMarked,
  });

  @override
  Widget build(BuildContext context) {
    final isDelete = episode.isDownloaded || isDownloading || isMarked;
    final bg = isDelete ? cs.error : cs.primary;
    final fg = isDelete ? cs.onError : cs.onPrimary;
    final icon = (isDownloading || isMarked)
        ? Icons.cancel_rounded
        : (episode.isDownloaded ? Icons.delete_rounded : Icons.download_rounded);
    final label = (isDownloading || isMarked)
        ? l10n.cancel
        : (episode.isDownloaded ? l10n.deleteDownload : l10n.downloading);

    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      color: bg,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: fg, size: 28),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─── Cover placeholder ────────────────────────────────────────────────────────

class _CoverPlaceholder extends StatelessWidget {
  final ColorScheme cs;
  const _CoverPlaceholder({required this.cs});
  @override
  Widget build(BuildContext context) => Container(
    width: 60, height: 60, color: cs.surfaceContainerHighest,
    child: const Icon(Icons.podcasts_rounded, size: 28));
}

// ─── Episode metadata ─────────────────────────────────────────────────────────

class _EpisodeMetadata extends StatelessWidget {
  final Episode episode;
  final bool isCurrent;
  final ColorScheme cs;
  final String Function(int) formatDuration;
  final int effectivePositionMs;

  const _EpisodeMetadata({
    required this.episode, required this.isCurrent,
    required this.cs, required this.formatDuration,
    required this.effectivePositionMs,
  });

  @override
  Widget build(BuildContext context) {
    final showProgress = !episode.isFinished &&
        episode.durationSeconds > 0 &&
        (effectivePositionMs > 0 || isCurrent);
    final progressValue =
        showProgress ? (effectivePositionMs / 1000) / episode.durationSeconds : 0.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          episode.title,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600, fontSize: 14,
            color: isCurrent ? cs.primary : cs.onSurface,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            if (episode.isFinished)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.check_circle_rounded, size: 12,
                    color: cs.onSurfaceVariant))
            else if (episode.isDownloaded)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.download_done_rounded, size: 12, color: cs.primary))
            else if (episode.markedForDownload)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.download_rounded, size: 12, color: cs.primary)),
            Text(
              DateFormat('d. MMM yyyy',
                      Localizations.localeOf(context).toString())
                  .format(episode.publishDate),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            if (episode.durationSeconds > 0)
              Text(
                '  ·  ${formatDuration(episode.durationSeconds)}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: showProgress
              ? Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: LinearProgressIndicator(
                    value: progressValue.clamp(0.0, 1.0),
                    minHeight: 2,
                    backgroundColor: cs.primary.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(cs.primary),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ─── Action area ──────────────────────────────────────────────────────────────

class _ActionArea extends StatefulWidget {
  final Episode episode;
  final bool isCurrent, isPlaying, isLoading, dimmed, isMarked;
  final double? ringProgress;
  final ColorScheme cs;
  final VoidCallback onPlayTap;

  const _ActionArea({
    required this.episode, required this.isCurrent, required this.isPlaying,
    required this.isLoading, required this.ringProgress, required this.isMarked,
    required this.dimmed, required this.cs, required this.onPlayTap,
  });

  @override
  State<_ActionArea> createState() => _ActionAreaState();
}

class _ActionAreaState extends State<_ActionArea>
    with TickerProviderStateMixin {
  late AnimationController _drainCtrl;
  late AnimationController _dotsCtrl;
  double _drainFrom = 1.0;
  double? _lastRealProgress;
  bool _dotsBuiltUp = false;

  bool get _isPending =>
      widget.ringProgress != null &&
      !widget.episode.isDownloaded &&
      widget.ringProgress! < 0.10;

  void _onFirstDotsComplete(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _dotsCtrl.removeStatusListener(_onFirstDotsComplete);
      _dotsBuiltUp = true; // AnimatedBuilder repaints each tick — no setState needed
      _dotsCtrl.repeat();
    }
  }

  void _startDots() {
    _dotsBuiltUp = false;
    _dotsCtrl.addStatusListener(_onFirstDotsComplete);
    _dotsCtrl.forward(from: 0.0);
  }

  @override
  void initState() {
    super.initState();
    _drainCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _dotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (_isPending) _startDots();
  }

  @override
  void didUpdateWidget(_ActionArea old) {
    super.didUpdateWidget(old);
    // Slot was reused for a different episode — don't carry over drain/dots state.
    if (old.episode.id != widget.episode.id) return;
    if (widget.ringProgress != null && !widget.episode.isDownloaded && widget.ringProgress! < 0.99) {
      _lastRealProgress = widget.ringProgress;
    }
    if (widget.ringProgress != null && _drainCtrl.isAnimating) {
      _drainCtrl.stop();
      _drainCtrl.reset();
      return;
    }
    if (old.episode.isDownloaded && !widget.episode.isDownloaded && widget.ringProgress == null) {
      _drainFrom = 1.0;
      _drainCtrl.forward(from: 0.0);
    } else if (old.ringProgress != null && widget.ringProgress == null && !widget.episode.isDownloaded) {
      _drainFrom = _lastRealProgress ?? 0.0;
      _lastRealProgress = null;
      _drainCtrl.forward(from: 0.0);
    }
    if (_isPending && !_dotsCtrl.isAnimating) {
      _startDots();
    } else if (!_isPending && _dotsCtrl.isAnimating) {
      _dotsCtrl.removeStatusListener(_onFirstDotsComplete);
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) { _dotsCtrl.stop(); _dotsCtrl.reset(); _dotsBuiltUp = false; }
      });
    }
  }

  @override
  void dispose() {
    _dotsCtrl.removeStatusListener(_onFirstDotsComplete);
    _drainCtrl.dispose();
    _dotsCtrl.dispose();
    super.dispose();
  }

  // 3 phases per pill (each 1/3 of the cycle), staggered by 1/3:
  //   extend: arc grows 0→full at full opacity
  //   hold:   full arc, full opacity
  //   fade:   full arc, fades to 50%  (starts when next-next pill begins extending)
  // First cycle: pills 2 & 3 hidden until their phase starts.
  (double sweep, double opacity) _dotParams(double t, int index) {
    const third = 1.0 / 3.0;
    if (!_dotsBuiltUp && t < index * third) return (0.0, 0.0);
    final phase = (t - index * third) % 1.0;
    if (phase < third) return (phase / third, 1.0);
    if (phase < 2 * third) return (1.0, 1.0);
    return (1.0, 1.0 - (phase - 2 * third) / third);
  }

  @override
  Widget build(BuildContext context) {
    final isDownloading = widget.ringProgress != null && !widget.episode.isDownloaded;
    final isDraining = _drainCtrl.isAnimating;
    final ringColor = (widget.episode.isDownloaded || isDownloading || isDraining)
        ? widget.cs.primary
        : (widget.isCurrent ? widget.cs.primary : widget.cs.outlineVariant);

    Widget ringPainter;
    if (isDraining) {
      // Drain: full ring animates down to empty
      ringPainter = AnimatedBuilder(
        animation: _drainCtrl,
        builder: (_, __) => CustomPaint(
          size: const Size(44, 44),
          painter: _RingPainter(
            progress: _drainFrom * (1.0 - CurvedAnimation(
                parent: _drainCtrl, curve: Curves.easeIn).value),
            color: widget.cs.primary,
            trackColor: widget.cs.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      );
    } else if (widget.episode.isDownloaded) {
      ringPainter = CustomPaint(
        size: const Size(44, 44),
        painter: _RingPainter(
          progress: 1.0,
          color: ringColor,
          trackColor: widget.cs.outlineVariant.withValues(alpha: 0.5),
        ),
      );
    } else if (isDownloading) {
      // Active download only: smooth fill as progress increases.
      // Isolated to this branch so non-download updates never trigger animation.
      final effectiveProgress = widget.ringProgress!;
      final showProgress = effectiveProgress >= 0.10;
      ringPainter = TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: showProgress ? effectiveProgress : 0.0),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOut,
        builder: (_, animValue, __) => CustomPaint(
          size: const Size(44, 44),
          painter: _RingPainter(
            progress: showProgress ? animValue : null,
            color: ringColor,
            trackColor: widget.cs.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      );
    } else {
      // Not downloading, not downloaded, not draining: static empty ring, no animation.
      ringPainter = CustomPaint(
        size: const Size(44, 44),
        painter: _RingPainter(
          progress: null,
          color: ringColor,
          trackColor: widget.cs.outlineVariant.withValues(alpha: 0.5),
        ),
      );
    }

    return AnimatedOpacity(
      opacity: widget.dimmed ? _kFinishedOpacity : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: widget.onPlayTap,
            child: SizedBox(
              width: 44, height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ringPainter,
                  AnimatedOpacity(
                    opacity: _isPending ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: AnimatedBuilder(
                      animation: _dotsCtrl,
                      builder: (_, __) => CustomPaint(
                        size: const Size(44, 44),
                        painter: _RingDotsPainter(
                          color: widget.cs.primary,
                          dots: [
                            _dotParams(_dotsCtrl.value, 0),
                            _dotParams(_dotsCtrl.value, 1),
                            _dotParams(_dotsCtrl.value, 2),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (widget.isLoading)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: widget.cs.primary))
                  else
                    Icon(
                      widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 22,
                      color: widget.isCurrent ? widget.cs.primary : widget.cs.onSurface,
                    ),
                ],
              ),
            ),
          ),
          // Underline bar for downloaded; dotted bar for marked-for-download.
          // AnimatedSwitcher handles fade + height for all three states.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
              child: SizeTransition(
                sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                axisAlignment: -1.0,
                child: child,
              ),
            ),
            child: widget.episode.isDownloaded
                ? Container(
                    key: const ValueKey('dl'),
                    margin: const EdgeInsets.only(top: 3),
                    width: 20, height: 2,
                    decoration: BoxDecoration(
                      color: widget.cs.primary,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  )
                : widget.isMarked
                    ? Padding(
                        key: const ValueKey('marked'),
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(4, (i) => Container(
                            margin: EdgeInsets.only(left: i == 0 ? 0 : 1.5),
                            width: 3.5, height: 2,
                            decoration: BoxDecoration(
                              color: widget.cs.primary,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          )),
                        ),
                      )
                    : const SizedBox(key: ValueKey('empty')),
          ),
        ],
      ),
    );
  }
}

// ─── Context menu bottom sheet ────────────────────────────────────────────────

class _EpisodeContextMenu extends StatelessWidget {
  final Episode episode;
  final ColorScheme cs;
  final AppLocalizations l10n;
  final VoidCallback? onMarkPlayed;
  final VoidCallback? onMarkUnplayed;
  final VoidCallback? onDownload;
  final VoidCallback? onCancelWifiQueue;
  final VoidCallback onShare;
  final VoidCallback? onExportFile;
  final VoidCallback? onDeleteDownload;
  final VoidCallback? onRemoveEpisode;

  const _EpisodeContextMenu({
    required this.episode, required this.cs, required this.l10n,
    required this.onShare,
    this.onMarkPlayed, this.onMarkUnplayed, this.onDownload,
    this.onCancelWifiQueue,
    this.onExportFile, this.onDeleteDownload, this.onRemoveEpisode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(
              episode.title,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14,
                color: cs.onSurface),
            ),
          ),
          const Divider(height: 1),
          if (onMarkPlayed != null)
            _MenuItem(icon: Icons.check_circle_outline, label: l10n.markPlayed, cs: cs, onTap: onMarkPlayed!),
          if (onMarkUnplayed != null)
            _MenuItem(icon: Icons.mark_email_unread_outlined, label: l10n.markUnplayed, cs: cs, onTap: onMarkUnplayed!),
          if (onDownload != null)
            _MenuItem(icon: Icons.download_rounded, label: l10n.downloading, cs: cs, onTap: onDownload!),
          if (onCancelWifiQueue != null)
            _MenuItem(icon: Icons.wifi_off_rounded, label: l10n.cancelWifiQueue, cs: cs, color: cs.error, onTap: onCancelWifiQueue!),
          _MenuItem(icon: Icons.share_rounded, label: l10n.shareEpisode, cs: cs, onTap: onShare),
          if (onExportFile != null)
            _MenuItem(icon: Icons.save_alt_outlined, label: l10n.exportFile, cs: cs, onTap: onExportFile!),
          if (onDeleteDownload != null)
            _MenuItem(icon: Icons.delete_rounded, label: l10n.deleteDownload, cs: cs, color: cs.error, onTap: onDeleteDownload!),
          if (onRemoveEpisode != null)
            _MenuItem(icon: Icons.remove_circle_rounded, label: l10n.removeEpisode, cs: cs, color: cs.error, onTap: onRemoveEpisode!),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme cs;
  final Color? color;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon, required this.label,
    required this.cs, required this.onTap, this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? cs.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: effectiveColor, size: 22),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(fontSize: 15, color: effectiveColor)),
          ],
        ),
      ),
    );
  }
}

// ─── Ring painter ─────────────────────────────────────────────────────────────

class _RingDotsPainter extends CustomPainter {
  final Color color;
  final List<(double sweep, double opacity)> dots;
  const _RingDotsPainter({required this.color, required this.dots});

  // StrokeCap.round caps extend each pill by cap ≈ strokeWidth/(2r) ≈ 0.061 rad per end.
  // Target: visual pill:gap = 6:5, arc stops slightly before 3 o'clock (~82° visual).
  // With V = visual pill, visual gap = 5V/6, total visual = 14V/3 → V ≈ 0.318 rad.
  // drawn_pill = V − 2·cap ≈ 0.196 rad (~11°), drawn_gap = 5V/6 + 2·cap ≈ 0.387 rad.
  static const _maxSweep = 0.196; // ~11° drawn pill → ~18° visual (pill slightly larger)
  static const _spacing  = 0.583; // ~33° start-to-start (drawn_pill + drawn_gap)

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.width - 3) / 2;
    final rect = Rect.fromCircle(center: Offset(size.width / 2, size.height / 2), radius: r);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < dots.length; i++) {
      final (sweepFraction, opacity) = dots[i];
      if (sweepFraction < 0.001 || opacity < 0.01) continue;
      canvas.drawArc(rect, -math.pi / 2 + i * _spacing, _maxSweep * sweepFraction, false,
          paint..color = color.withValues(alpha: opacity));
    }
  }

  @override
  bool shouldRepaint(_RingDotsPainter old) {
    if (old.color != color) return true;
    for (int i = 0; i < dots.length; i++) {
      if (old.dots[i] != dots[i]) return true;
    }
    return false;
  }
}

class _RingPainter extends CustomPainter {
  final double? progress;
  final Color color, trackColor;
  const _RingPainter({required this.progress, required this.color, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = (size.width - 3) / 2;
    canvas.drawCircle(Offset(cx, cy), r,
        Paint()..color = trackColor..style = PaintingStyle.stroke..strokeWidth = 1.5);
    if (progress == null) return;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -math.pi / 2, 2 * math.pi * progress!.clamp(0.0, 1.0), false,
      Paint()..color = color..style = PaintingStyle.stroke
            ..strokeWidth = 2.5..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.trackColor != trackColor;
}
