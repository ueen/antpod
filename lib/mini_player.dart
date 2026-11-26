// lib/mini_player.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_database.dart';
import 'html_utils.dart';
import 'l10n/app_localizations.dart';
import 'player_provider.dart';
import 'share_utils.dart';

class MiniPlayer extends StatefulWidget {
  final VoidCallback? onPodcastTap;
  const MiniPlayer({super.key, this.onPodcastTap});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  double _dragProgress = 0.0;
  bool _sheetOpen = false;

  void _onDragUpdate(DragUpdateDetails d) {
    final screenH = MediaQuery.of(context).size.height;
    if (d.delta.dy < 0) {
      setState(() {
        _dragProgress =
            (_dragProgress - d.delta.dy / (screenH * 0.35)).clamp(0.0, 1.0);
      });
    } else if (_dragProgress > 0) {
      setState(() {
        _dragProgress = (_dragProgress - d.delta.dy / 100.0).clamp(0.0, 1.0);
      });
    }
  }

  Future<void> _onDragEnd(DragEndDetails d) async {
    if (_dragProgress > 0.25 || (d.primaryVelocity ?? 0) < -500) {
      await _openSheet(context);
    } else {
      if (mounted) setState(() => _dragProgress = 0);
    }
  }

  Future<void> _openSheet(BuildContext context) async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    if (mounted) setState(() => _dragProgress = 0);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Stack(
        children: [
          // Tapping the dark area above the sheet dismisses it
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(ctx).pop(),
            child: const SizedBox.expand(),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {}, // absorb taps on the sheet itself
              child: ChangeNotifierProvider.value(
                value: context.read<PlayerProvider>(),
                child: _PlayerSheet(onPodcastTap: widget.onPodcastTap),
              ),
            ),
          ),
        ],
      ),
    );

    if (mounted) setState(() => _sheetOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    // select() avoids rebuilding the whole mini player on every position tick.
    // Only _MiniProgress (the thin bar) rebuilds at 5Hz during playback.
    final hasEpisode = context.select<PlayerProvider, bool>((p) => p.hasEpisode);

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      alignment: Alignment.bottomCenter,
      child: hasEpisode ? _buildContent(context) : const SizedBox.shrink(),
    );
  }

  Widget _buildContent(BuildContext context) {

    final imageUrl = context.select<PlayerProvider, String>(
        (p) => p.currentEpisode?.podcastImageUrl ?? '');
    final title = context.select<PlayerProvider, String>(
        (p) => p.currentEpisode?.title ?? '');
    final podcastTitle = context.select<PlayerProvider, String>(
        (p) => p.currentEpisode?.podcastTitle ?? '');
    final isPlaying = context.select<PlayerProvider, bool>((p) => p.isPlaying);
    final isLoading = context.select<PlayerProvider, bool>((p) => p.isLoading);
    final rewindSec = context.select<PlayerProvider, int>((p) => p.rewindSeconds);
    final forwardSec = context.select<PlayerProvider, int>((p) => p.forwardSeconds);
    final isOffline = context.select<PlayerProvider, bool>((p) => p.isOffline);
    final isDownloaded = context.select<PlayerProvider, bool>(
        (p) => p.currentEpisode?.localPath != null);
    final cs = Theme.of(context).colorScheme;
    final canPlay = !isOffline || isDownloaded;

    return Transform.translate(
      offset: Offset(0, -_dragProgress * 50),
      child: GestureDetector(
      onTap: () => _openSheet(context),
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Hero(
            tag: 'player_handle',
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                width: 32, height: 3,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
          ),
          Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        height: 64,
        decoration: BoxDecoration(
          color: cs.inverseSurface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 4))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              // Isolated widget — only this rebuilds on position ticks
              const Positioned(
                left: 0, right: 0, bottom: 0,
                child: _MiniProgress(),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 44, height: 44, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: cs.inversePrimary,
                          child: const Icon(Icons.podcasts_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: cs.inversePrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                          Text(
                            podcastTitle,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: cs.inversePrimary.withValues(alpha: 0.6),
                                fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    _iconBtn(cs, _skipRewindIcon(rewindSec),
                        () => context.read<PlayerProvider>().skipBackward()),
                    SizedBox(
                      width: 36, height: 36,
                      child: isLoading
                          ? Padding(
                              padding: const EdgeInsets.all(8),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: cs.inversePrimary),
                            )
                          : !canPlay
                              ? Icon(Icons.wifi_off_rounded,
                                  color: cs.inversePrimary.withValues(alpha: 0.5), size: 22)
                              : IconButton(
                                  onPressed: () => context.read<PlayerProvider>().togglePlayPause(),
                                  icon: Icon(
                                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: cs.inversePrimary, size: 28),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                    ),
                    _iconBtn(cs,
                        _skipForwardIconDirect(forwardSec) ?? _skipRewindIcon(forwardSec),
                        () => context.read<PlayerProvider>().skipForward(),
                        flipX: _skipForwardIconDirect(forwardSec) == null),
                  ],
                ),
              ),
            ],
          ),
        ),
          ), // Container (mini player card)
        ],   // Column children
      ),     // Column
      ),     // GestureDetector
    );       // Transform.translate
  }

  Widget _iconBtn(ColorScheme cs, IconData icon, VoidCallback onTap,
      {double size = 22, bool flipX = false}) {
    Widget ico = Icon(icon, color: cs.inversePrimary, size: size);
    if (flipX) ico = Transform.flip(flipX: true, child: ico);
    return IconButton(
      onPressed: onTap,
      icon: ico,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

// Isolated progress bar — only this widget rebuilds on position ticks (~5Hz).
// The rest of MiniPlayer stays still until episode/isPlaying changes.
class _MiniProgress extends StatelessWidget {
  const _MiniProgress();

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>();
    // Rebuild on a new duration too, not only on position ticks.
    context.select<PlayerProvider, Duration>((p) => p.duration);
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ValueListenableBuilder<Duration>(
        valueListenable: player.positionListenable,
        builder: (_, pos, __) => LinearProgressIndicator(
          value: player.progressAt(pos),
          minHeight: 5,
          backgroundColor: Colors.transparent,
          color: cs.inversePrimary,
        ),
      ),
    );
  }
}

/// The sheet's slider and time labels. They follow the position on their
/// own (the rest of the sheet doesn't rebuild per tick), and while dragging
/// they follow the finger: the seek happens once, on release.
class _SeekBar extends StatefulWidget {
  final PlayerProvider player;
  final String Function(Duration) fmt;
  const _SeekBar({required this.player, required this.fmt});

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  /// 0..1 while the finger is on the slider.
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final cs = Theme.of(context).colorScheme;
    final label = TextStyle(fontSize: 11, color: cs.onSurfaceVariant);
    return ValueListenableBuilder<Duration>(
      valueListenable: player.positionListenable,
      builder: (context, pos, _) {
        final dur = player.duration;
        final shown = _drag != null ? dur * _drag! : pos;
        return Column(children: [
          SliderTheme(
            data: SliderThemeData(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              trackHeight: 3,
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.primary.withValues(alpha: 0.2),
              thumbColor: cs.primary,
            ),
            child: Slider(
              value: _drag ?? player.progressAt(pos),
              onChangeStart: (v) => setState(() => _drag = v),
              onChanged: (v) => setState(() => _drag = v),
              onChangeEnd: (v) {
                // Clear the drag after the seek is sent: the player already
                // reports the target, so the thumb doesn't spring back.
                player.seekTo(dur * v);
                setState(() => _drag = null);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.fmt(shown), style: label),
                Text(widget.fmt(dur), style: label),
              ],
            ),
          ),
        ]);
      },
    );
  }
}

// Shared skip-icon helpers (used by mini player and bottom sheet)

IconData _skipRewindIcon(int s) {
  if (s == 5)  return Icons.replay_5_rounded;
  if (s == 10) return Icons.replay_10_rounded;
  if (s == 30) return Icons.replay_30_rounded;
  return Icons.replay_rounded;
}

// Returns a dedicated forward icon (with number) if one exists, null otherwise.
// When null, callers should mirror the rewind icon with Transform.flip.
IconData? _skipForwardIconDirect(int s) {
  if (s == 5)  return Icons.forward_5_rounded;
  if (s == 10) return Icons.forward_10_rounded;
  if (s == 30) return Icons.forward_30_rounded;
  return null;
}


Future<void> showPlayerSheet(BuildContext context,
    {VoidCallback? onPodcastTap}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(ctx).pop(),
          child: const SizedBox.expand(),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: ChangeNotifierProvider.value(
              value: context.read<PlayerProvider>(),
              child: _PlayerSheet(onPodcastTap: onPodcastTap),
            ),
          ),
        ),
      ],
    ),
  );
}

// ── Player bottom sheet ───────────────────────────────────────────────────────

/// Marks the playing episode as a favourite, or not.
class _FavoriteButton extends StatefulWidget {
  final String episodeId;
  const _FavoriteButton({required this.episodeId});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  // Kept across rebuilds: the sheet rebuilds with every player change.
  late Stream<bool> _favorite;

  @override
  void initState() {
    super.initState();
    _favorite = context.read<AppDatabase>().watchFavorite(widget.episodeId);
  }

  @override
  void didUpdateWidget(_FavoriteButton old) {
    super.didUpdateWidget(old);
    if (old.episodeId != widget.episodeId) {
      _favorite = context.read<AppDatabase>().watchFavorite(widget.episodeId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return StreamBuilder<bool>(
      stream: _favorite,
      builder: (context, snap) {
        final fav = snap.data ?? false;
        return IconButton(
          onPressed: () => context
              .read<AppDatabase>()
              .setFavorite(widget.episodeId, !fav),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, a) =>
                ScaleTransition(scale: a, child: child),
            child: Icon(
              fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey(fav),
              size: 24, color: cs.primary),
          ),
          tooltip: fav ? l10n.removeFavorite : l10n.addFavorite,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        );
      },
    );
  }
}

class _PlayerSheet extends StatelessWidget {
  final VoidCallback? onPodcastTap;
  const _PlayerSheet({this.onPodcastTap});

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  String _fmtSpeed(double speed) =>
      speed % 1 == 0 ? '${speed.toInt()}x' : '${speed}x';

  void _showCoverFullscreen(BuildContext context, PlayerProvider player, String fallbackUrl) {
    final screenWidth = MediaQuery.of(context).size.width;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              // Follows the playback into the next chapter's picture.
              child: ListenableBuilder(
                listenable: player,
                builder: (_, __) => _ChapterCover(
                    player: player, fallbackUrl: fallbackUrl, size: screenWidth),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSkipDialog(BuildContext context, PlayerProvider player,
      {required bool isForward}) {
    final options = [5, 10, 15, 30, 60, 90];
    final current = isForward ? player.forwardSeconds : player.rewindSeconds;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isForward ? 'Skip forward' : 'Skip backward'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((s) {
            return ChoiceChip(
              label: Text('${s}s'),
              selected: current == s,
              onSelected: (_) {
                if (isForward) {
                  player.setForwardSeconds(s);
                } else {
                  player.setRewindSeconds(s);
                }
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final ep = player.currentEpisode;
    if (ep == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    // expand: false keeps the widget sized to its rendered height so the
    // transparent area above it passes taps through to the modal barrier.
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),

            Center(
              // A chapter's own picture opens big; the podcast cover opens
              // the podcast.
              child: GestureDetector(
                onTap: player.hasChapterImage
                    ? () => _showCoverFullscreen(context, player, ep.podcastImageUrl)
                    : (onPodcastTap != null
                        ? () {
                            Navigator.of(context).pop();
                            onPodcastTap!();
                          }
                        : null),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _ChapterCover(
                    player: player,
                    fallbackUrl: ep.podcastImageUrl,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // The heart beside the titles; the space on the left keeps them
            // centred.
            Row(
              children: [
                const SizedBox(width: 44),
                Expanded(
                  child: Column(
                    children: [
                      Text(ep.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 18,
                              color: cs.onSurface)),
                      const SizedBox(height: 4),
                      Text(ep.podcastTitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                _FavoriteButton(episodeId: ep.id),
              ],
            ),
            SizedBox(height: player.chapters.isNotEmpty ? 4 : 24),

            // Chapter navigation — only shown when the episode has chapters
            if (player.chapters.isNotEmpty) ...[
              _ChapterNavRow(player: player),
              const SizedBox(height: 4),
            ],

            _SeekBar(player: player, fmt: _fmtDur),
            const SizedBox(height: 8),

            // Controls row: speed | skip-back | play | skip-fwd | share
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Speed dial
                GestureDetector(
                  onTap: player.cycleSpeed,
                  child: SizedBox(
                    width: 44, height: 44,
                    child: Center(
                      child: Text(
                        _fmtSpeed(player.speed),
                        style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                ),

                // Skip back (long press to choose seconds)
                GestureDetector(
                  onLongPress: () =>
                      _showSkipDialog(context, player, isForward: false),
                  onTap: player.skipBackward,
                  child: SizedBox(
                    width: 44, height: 44,
                    child: Icon(_skipRewindIcon(player.rewindSeconds), size: 28, color: cs.primary),
                  ),
                ),

                // Play / pause
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: cs.primary),
                  child: player.isLoading
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cs.onPrimary),
                        )
                      : (player.isOffline && ep.localPath == null)
                          ? Icon(Icons.wifi_off_rounded,
                              color: cs.onPrimary.withValues(alpha: 0.6), size: 30)
                          : IconButton(
                              onPressed: player.togglePlayPause,
                              icon: Icon(
                                player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: cs.onPrimary, size: 34,
                              ),
                            ),
                ),

                // Skip forward (long press to choose seconds)
                GestureDetector(
                  onLongPress: () =>
                      _showSkipDialog(context, player, isForward: true),
                  onTap: player.skipForward,
                  child: SizedBox(
                    width: 44, height: 44,
                    child: _skipForwardIconDirect(player.forwardSeconds) != null
                        ? Icon(_skipForwardIconDirect(player.forwardSeconds)!, size: 28, color: cs.primary)
                        : Transform.flip(
                            flipX: true,
                            child: Icon(_skipRewindIcon(player.forwardSeconds), size: 28, color: cs.primary),
                          ),
                  ),
                ),

                // Share
                IconButton(
                  onPressed: () => ShareUtils.shareEpisode(ep),
                  icon: Icon(Icons.share_rounded,
                      size: 22, color: cs.primary),
                  tooltip: l10n.shareEpisode,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Text(l10n.shownotes,
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15,
                    color: cs.onSurface)),
            const SizedBox(height: 8),
            ShowNotes(description: ep.description, cs: cs),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ── Chapter navigation row ────────────────────────────────────────────────────

class _ChapterNavRow extends StatelessWidget {
  final PlayerProvider player;
  const _ChapterNavRow({required this.player});

  void _showChapterList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: player,
        child: _ChapterListSheet(cs: cs),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = player.currentChapterIndex;
    final chapter = player.currentChapter;
    final hasPrev = idx > 0;
    final hasNext = idx >= 0 && idx < player.chapters.length - 1;

    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.skip_previous_rounded,
              color: hasPrev ? cs.primary : cs.primary.withValues(alpha: 0.3)),
          onPressed: hasPrev ? player.skipToPreviousChapter : null,
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => _showChapterList(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.list_rounded, size: 14, color: cs.onPrimaryContainer),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      chapter?.title ?? '',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.skip_next_rounded,
              color: hasNext ? cs.primary : cs.primary.withValues(alpha: 0.3)),
          onPressed: hasNext ? player.skipToNextChapter : null,
        ),
      ],
    );
  }
}

// ── Chapter list popup ────────────────────────────────────────────────────────

class _ChapterListSheet extends StatelessWidget {
  final ColorScheme cs;
  const _ChapterListSheet({required this.cs});

  String _fmt(double secs) {
    final total = secs.toInt();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final chapters = player.chapters;
    final currentIdx = player.currentChapterIndex;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2)),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: chapters.length,
              itemBuilder: (ctx, i) {
                final chapter = chapters[i];
                final isActive = i == currentIdx;
                return ListTile(
                  leading: SizedBox(
                    width: 20,
                    child: isActive
                        ? Icon(Icons.play_arrow_rounded, color: cs.primary, size: 18)
                        : null,
                  ),
                  title: Text(
                    chapter.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      color: isActive ? cs.primary : cs.onSurface,
                    ),
                  ),
                  trailing: Text(
                    _fmt(chapter.startTimeSeconds),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  onTap: () {
                    player.seekToChapter(chapter);
                    Navigator.pop(ctx);
                  },
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}

// ── Chapter cover image with crossfade ───────────────────────────────────────

class _ChapterCover extends StatelessWidget {
  final PlayerProvider player;
  final String fallbackUrl;
  final double? size;
  const _ChapterCover({required this.player, required this.fallbackUrl, this.size});

  @override
  Widget build(BuildContext context) {
    final bytes = player.currentChapterImageBytes;
    final url = player.currentCoverImageUrl;
    final idx = player.currentChapterIndex;
    final dim = size ?? 220.0;

    Widget image;
    if (bytes != null) {
      image = Image.memory(
        bytes,
        key: ValueKey('chap_$idx'),
        width: dim, height: dim, fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else {
      final src = url.isNotEmpty ? url : fallbackUrl;
      image = CachedNetworkImage(
        key: ValueKey('cover_$src'),
        imageUrl: src,
        width: dim, height: dim, fit: BoxFit.cover,
        errorWidget: (_, __, ___) => SizedBox(width: dim, height: dim),
      );
    }

    return image;
  }
}
