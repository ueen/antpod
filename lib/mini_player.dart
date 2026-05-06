// lib/mini_player.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'player_provider.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    if (!player.hasEpisode) return const SizedBox.shrink();

    final episode = player.currentEpisode!;
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _showSheet(context),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        height: 64,
        decoration: BoxDecoration(
          color: cs.inverseSurface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha:0.25),
                blurRadius: 16,
                offset: const Offset(0, 4))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              // Progress bar background
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: player.progress,
                  child: Container(
                      color: cs.inversePrimary.withValues(alpha:0.35)),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: episode.podcastImageUrl,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: cs.onInverseSurface,
                          child: const Icon(Icons.podcasts),
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
                            episode.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: cs.onInverseSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                          Text(
                            episode.podcastTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: cs.onInverseSurface.withValues(alpha:0.6),
                                fontSize: 11),
                          ),
                        ],
                      ),
                    ),

                    _iconBtn(cs, Icons.replay_10, player.skipBackward),
                    player.isLoading
                        ? SizedBox(
                            width: 36,
                            height: 36,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onInverseSurface),
                            ),
                          )
                        : _iconBtn(
                            cs,
                            player.isPlaying ? Icons.pause : Icons.play_arrow,
                            player.togglePlayPause,
                            size: 28),
                    _iconBtn(cs, Icons.forward_30, player.skipForward),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(ColorScheme cs, IconData icon, VoidCallback onTap,
      {double size = 22}) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: cs.onInverseSurface, size: size),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  void _showSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<PlayerProvider>(),
        child: const _PlayerSheet(),
      ),
    );
  }
}

// ── Player bottom sheet ───────────────────────────────────────────────────────

class _PlayerSheet extends StatelessWidget {
  const _PlayerSheet();

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final ep = player.currentEpisode;
    if (ep == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),

            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: ep.podcastImageUrl,
                  width: 220,
                  height: 220,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 24),

            Text(
              ep.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: cs.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              ep.podcastTitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),

            SliderTheme(
              data: SliderThemeData(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                trackHeight: 3,
                activeTrackColor: cs.primary,
                inactiveTrackColor: cs.primary.withValues(alpha:0.2),
                thumbColor: cs.primary,
              ),
              child: Slider(
                value: player.progress,
                onChanged: (v) => player.seekTo(
                  Duration(seconds: (v * player.duration.inSeconds).round()),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmtDur(player.position),
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  Text(_fmtDur(player.duration),
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: player.skipBackward,
                  icon: Icon(Icons.replay_10, size: 32, color: cs.onSurface),
                ),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: cs.primary),
                  child: player.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : IconButton(
                          onPressed: player.togglePlayPause,
                          icon: Icon(
                            player.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: cs.onPrimary,
                            size: 34,
                          ),
                        ),
                ),
                IconButton(
                  onPressed: player.skipForward,
                  icon: Icon(Icons.forward_30, size: 32, color: cs.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Text(AppLocalizations.of(context).shownotes,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: cs.onSurface)),
            const SizedBox(height: 8),
            Text(
              ep.description.replaceAll(RegExp(r'<[^>]*>'), ''),
              style: TextStyle(
                  fontSize: 13, color: cs.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
