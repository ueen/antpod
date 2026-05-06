// lib/episode_tile.dart
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'app_database.dart';
import 'download_service.dart';
import 'l10n/app_localizations.dart';
import 'player_provider.dart';

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
        onMarkUnplayed: episode.isFinished
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
          final text = '${episode.title}\n${episode.audioUrl}';
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
    final player = context.watch<PlayerProvider>();
    final db = context.read<AppDatabase>();
    final l10n = AppLocalizations.of(context);
    final isCurrent = player.currentEpisode?.id == episode.id;
    final isPlaying = isCurrent && player.isPlaying;
    final cs = Theme.of(context).colorScheme;
    final dimmed = episode.isFinished && !isCurrent;
    final opacity = dimmed ? _kFinishedOpacity : 1.0;

    return Dismissible(
      key: Key('tile_${episode.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        if (episode.isDownloaded) {
          await db.deleteLocalFile(episode.id);
        } else {
          await DownloadService.downloadEpisode(
            episodeId: episode.id, audioUrl: episode.audioUrl,
            episodeTitle: episode.title, db: db,
          );
        }
        return false;
      },
      background: _SwipeBackground(episode: episode, cs: cs, l10n: l10n),
      child: GestureDetector(
        onLongPress: () => _showContextMenu(context, db, l10n),
        child: InkWell(
          onTap: () => player.play(episode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            color: isCurrent ? cs.primary.withValues(alpha:0.07) : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Opacity(
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
                const SizedBox(width: 12),

                Expanded(
                  child: Opacity(
                    opacity: opacity,
                    child: _EpisodeMetadata(
                      episode: episode,
                      isCurrent: isCurrent,
                      cs: cs,
                      formatDuration: _fmt,
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                _ActionArea(
                  episode: episode,
                  isCurrent: isCurrent,
                  isPlaying: isPlaying,
                  isLoading: player.isLoading && isCurrent,
                  downloadProgress: isCurrent ? player.downloadProgress : null,
                  dimmed: dimmed,
                  cs: cs,
                  onPlayTap: () {
                    if (isCurrent) {
                      player.togglePlayPause();
                    } else {
                      player.play(episode);
                    }
                  },
                  onDeleteTap: episode.isDownloaded
                      ? () => db.deleteLocalFile(episode.id) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Swipe background ─────────────────────────────────────────────────────────

class _SwipeBackground extends StatelessWidget {
  final Episode episode;
  final ColorScheme cs;
  final AppLocalizations l10n;
  const _SwipeBackground({required this.episode, required this.cs, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      color: episode.isDownloaded ? cs.error : cs.primary,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            episode.isDownloaded ? Icons.delete_outline : Icons.download,
            color: episode.isDownloaded ? cs.onError : cs.onPrimary,
            size: 28,
          ),
          const SizedBox(height: 4),
          Text(
            episode.isDownloaded ? l10n.deleteDownload : l10n.downloading,
            style: TextStyle(
              color: episode.isDownloaded ? cs.onError : cs.onPrimary,
              fontSize: 11, fontWeight: FontWeight.w600,
            ),
          ),
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

  const _EpisodeMetadata({
    required this.episode, required this.isCurrent,
    required this.cs, required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
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
        const SizedBox(height: 4),
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
              DateFormat('d. MMM yyyy').format(episode.publishDate),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            if (episode.durationSeconds > 0)
              Text(
                '  ·  ${formatDuration(episode.durationSeconds)}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
          ],
        ),
        if (!episode.isFinished && episode.lastPositionMs > 0 && episode.durationSeconds > 0) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (episode.lastPositionMs / 1000) / episode.durationSeconds,
            minHeight: 2,
            backgroundColor: cs.primary.withValues(alpha:0.15),
            valueColor: AlwaysStoppedAnimation(cs.primary),
          ),
        ],
      ],
    );
  }
}

// ─── Action area ──────────────────────────────────────────────────────────────

class _ActionArea extends StatelessWidget {
  final Episode episode;
  final bool isCurrent, isPlaying, isLoading, dimmed;
  final double? downloadProgress;
  final ColorScheme cs;
  final VoidCallback onPlayTap;
  final VoidCallback? onDeleteTap;

  const _ActionArea({
    required this.episode, required this.isCurrent, required this.isPlaying,
    required this.isLoading, required this.downloadProgress, required this.dimmed,
    required this.cs,
    required this.onPlayTap, this.onDeleteTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (episode.isDownloaded && onDeleteTap != null)
          GestureDetector(
            onTap: onDeleteTap,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Opacity(
                opacity: dimmed ? _kFinishedOpacity : 1.0,
                child: Icon(Icons.delete_outline, size: 18,
                    color: cs.onSurfaceVariant),
              ),
            ),
          ),
        Opacity(
          opacity: dimmed ? _kFinishedOpacity : 1.0,
          child: GestureDetector(
            onTap: onPlayTap,
            child: SizedBox(
              width: 44, height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(44, 44),
                    painter: _RingPainter(
                      progress: downloadProgress,
                      color: isCurrent ? cs.primary : cs.outlineVariant,
                      trackColor: cs.outlineVariant.withValues(alpha:0.25),
                    ),
                  ),
                  if (isLoading)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.primary))
                  else
                    Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 22,
                      color: isCurrent ? cs.primary : cs.onSurface,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
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
          _MenuItem(
            icon: Icons.share_outlined,
            label: l10n.shareEpisode,
            cs: cs,
            onTap: onShare,
          ),
          if (onMarkUnplayed != null)
            _MenuItem(
              icon: Icons.mark_email_unread_outlined,
              label: l10n.markUnplayed,
              cs: cs,
              onTap: onMarkUnplayed!,
            ),
          if (onDeleteDownload != null)
            _MenuItem(
              icon: Icons.delete_outline,
              label: l10n.deleteDownload,
              cs: cs,
              color: cs.error,
              onTap: onDeleteDownload!,
            ),
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
      old.progress != progress || old.color != color;
}
