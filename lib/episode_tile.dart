// lib/episode_tile.dart
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'app_database.dart';
import 'download_provider.dart';
import 'download_service.dart';
import 'l10n/app_localizations.dart';
import 'player_provider.dart';
import 'share_utils.dart';

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

  void _showContextMenu(BuildContext context, AppDatabase db, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _EpisodeContextMenu(
        episode: episode,
        cs: cs,
        l10n: l10n,
        onMarkUnplayed: (episode.isFinished || episode.lastPositionMs > 0)
            ? () {
                db.markUnfinished(episode.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.markUnplayed),
                      duration: const Duration(seconds: 2)));
              }
            : null,
        onShare: () {
          Navigator.pop(context);
          final text = '${episode.title}\n${ShareUtils.episodeUrl(episode)}';
          SharePlus.instance.share(ShareParams(text: text, subject: episode.title));
        },
        onDeleteDownload: episode.isDownloaded
            ? () { Navigator.pop(context); db.deleteLocalFile(episode.id); }
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

    final downloads = context.watch<DownloadProvider>();
    final db = context.read<AppDatabase>();
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final dimmed = episode.isFinished && !isCurrent;
    final opacity = dimmed ? _kFinishedOpacity : 1.0;

    final dlProgress = downloads.progressForTask(episode.downloadTaskId);
    // If a task ID exists but isn't tracked yet (download just finished, DB
    // hasn't flipped isDownloaded yet), hold the ring at 1.0 to avoid a flash.
    final ringProgress = episode.isDownloaded
        ? 1.0
        : (dlProgress ?? (episode.downloadTaskId != null ? 1.0 : null));

    final activeTaskId = episode.downloadTaskId;
    final isDownloading = activeTaskId != null &&
        downloads.progressForTask(activeTaskId) != null;

    return _StickySwipeable(
      startBackground: _PlayedSwipeBackground(episode: episode, cs: cs, l10n: l10n),
      endBackground: _DownloadSwipeBackground(
          episode: episode, cs: cs, l10n: l10n, isDownloading: isDownloading),
      onSwipeStart: () async {
        if (episode.isFinished) {
          await db.markUnfinished(episode.id);
        } else {
          await db.markFinished(episode.id);
        }
      },
      onSwipeEnd: () async {
        if (isDownloading) {
          await downloads.cancelDownload(activeTaskId, episode.id);
        } else if (episode.isDownloaded) {
          await db.deleteLocalFile(episode.id);
        } else {
          final taskId = await DownloadService.downloadEpisode(
            episodeId: episode.id, audioUrl: episode.audioUrl,
            episodeTitle: episode.title, db: db,
          );
          if (taskId != null) downloads.trackDownload(taskId);
        }
      },
      child: GestureDetector(
        onLongPress: () => _showContextMenu(context, db, l10n),
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
                    child: Opacity(
                      opacity: opacity,
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
                  child: Opacity(
                    opacity: opacity,
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

  static const _maxFraction = 0.45;
  // trigger at 40% of max drag distance (~18% of screen width)
  static const _triggerFraction = _maxFraction * 0.40;

  @override
  void initState() {
    super.initState();
    // Wide bounds so the spring simulation can drive _snapCtrl.value freely
    _snapCtrl = AnimationController(vsync: this, lowerBound: -500, upperBound: 500)
      ..addListener(_onSnapTick);
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onSnapTick() {
    if (mounted) setState(() => _dx = _snapCtrl.value);
  }

  double get _screenWidth => MediaQuery.of(context).size.width;

  void _onUpdate(DragUpdateDetails d) {
    _snapCtrl.stop();
    final max = _screenWidth * _maxFraction;
    setState(() => _dx = (_dx + d.delta.dx).clamp(-max, max));
  }

  Future<void> _onEnd(DragEndDetails _) async {
    final trigger = _screenWidth * _triggerFraction;
    if (_dx > trigger) {
      await widget.onSwipeStart();
    } else if (_dx < -trigger) {
      await widget.onSwipeEnd();
    }
    _snapBack();
  }

  void _snapBack() {
    _snapCtrl.stop();
    // Slightly underdamped spring (ratio ≈ 0.7) — smooth with a gentle settle
    _snapCtrl.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 400, damping: 28),
      _dx,
      0.0,
      0.0,
    ));
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
  const _DownloadSwipeBackground({
    required this.episode, required this.cs, required this.l10n,
    required this.isDownloading,
  });

  @override
  Widget build(BuildContext context) {
    final isDelete = episode.isDownloaded || isDownloading;
    final bg = isDelete ? cs.error : cs.primary;
    final fg = isDelete ? cs.onError : cs.onPrimary;
    final icon = isDownloading
        ? Icons.cancel_outlined
        : (episode.isDownloaded ? Icons.delete_outline : Icons.download);
    final label = isDownloading
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
    child: const Icon(Icons.podcasts, size: 28));
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
                child: Icon(Icons.check_circle, size: 12,
                    color: cs.onSurfaceVariant))
            else if (episode.isDownloaded)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.download_done, size: 12, color: cs.primary)),
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
  final bool isCurrent, isPlaying, isLoading, dimmed;
  final double? ringProgress;
  final ColorScheme cs;
  final VoidCallback onPlayTap;

  const _ActionArea({
    required this.episode, required this.isCurrent, required this.isPlaying,
    required this.isLoading, required this.ringProgress, required this.dimmed,
    required this.cs, required this.onPlayTap,
  });

  @override
  State<_ActionArea> createState() => _ActionAreaState();
}

class _ActionAreaState extends State<_ActionArea>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drainCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didUpdateWidget(_ActionArea old) {
    super.didUpdateWidget(old);
    // Download deleted: animate ring draining 1.0 → 0.0
    if (old.episode.isDownloaded &&
        !widget.episode.isDownloaded &&
        widget.ringProgress == null) {
      _drainCtrl.forward(from: 0.0);
    }
    // Re-download started while drain was running: cancel drain
    if (widget.ringProgress != null && _drainCtrl.isAnimating) {
      _drainCtrl.stop();
      _drainCtrl.reset();
    }
  }

  @override
  void dispose() {
    _drainCtrl.dispose();
    super.dispose();
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
            progress: (1.0 - CurvedAnimation(
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
    } else {
      final effectiveProgress = widget.ringProgress;
      ringPainter = TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: effectiveProgress ?? 0.0),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOut,
        builder: (_, animValue, __) => CustomPaint(
          size: const Size(44, 44),
          painter: _RingPainter(
            progress: effectiveProgress == null ? null : animValue,
            color: ringColor,
            trackColor: widget.cs.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return Opacity(
      opacity: widget.dimmed ? _kFinishedOpacity : 1.0,
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
                  if (widget.isLoading)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: widget.cs.primary))
                  else
                    Icon(
                      widget.isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 22,
                      color: widget.isCurrent ? widget.cs.primary : widget.cs.onSurface,
                    ),
                ],
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOut,
            margin: EdgeInsets.only(top: widget.episode.isDownloaded ? 3 : 0),
            width: widget.episode.isDownloaded ? 20 : 0,
            height: widget.episode.isDownloaded ? 2 : 0,
            decoration: BoxDecoration(
              color: widget.cs.primary,
              borderRadius: BorderRadius.circular(1),
            ),
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
  final VoidCallback? onMarkUnplayed;
  final VoidCallback onShare;
  final VoidCallback? onDeleteDownload;

  const _EpisodeContextMenu({
    required this.episode, required this.cs, required this.l10n,
    required this.onShare, this.onMarkUnplayed, this.onDeleteDownload,
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
          _MenuItem(icon: Icons.share_outlined, label: l10n.shareEpisode, cs: cs, onTap: onShare),
          if (onMarkUnplayed != null)
            _MenuItem(icon: Icons.mark_email_unread_outlined, label: l10n.markUnplayed, cs: cs, onTap: onMarkUnplayed!),
          if (onDeleteDownload != null)
            _MenuItem(icon: Icons.delete_outline, label: l10n.deleteDownload, cs: cs, color: cs.error, onTap: onDeleteDownload!),
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
