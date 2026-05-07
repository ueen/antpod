// lib/mini_player.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'l10n/app_localizations.dart';
import 'player_provider.dart';
// gestures and url_launcher are used by _ShowNotes below

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  double _dragProgress = 0.0;
  bool _sheetOpen = false;

  void _onDragUpdate(DragUpdateDetails d) {
    if (d.delta.dy < 0) {
      final screenH = MediaQuery.of(context).size.height;
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
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<PlayerProvider>(),
        child: const _PlayerSheet(),
      ),
    );

    if (mounted) setState(() => _sheetOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    if (!player.hasEpisode) return const SizedBox.shrink();

    final episode = player.currentEpisode!;
    final cs = Theme.of(context).colorScheme;

    return Transform.translate(
      offset: Offset(0, -_dragProgress * 50),
      child: GestureDetector(
      onTap: () => _openSheet(context),
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle — Hero so it morphs up into the sheet handle
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
              // Thin progress bar at the bottom of the card
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LinearProgressIndicator(
                    value: player.progress.clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: Colors.transparent,
                    color: cs.inversePrimary.withValues(alpha: 0.7),
                  ),
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
                        width: 44, height: 44, fit: BoxFit.cover,
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
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: cs.onInverseSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                          Text(
                            episode.podcastTitle,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: cs.onInverseSurface.withValues(alpha: 0.6),
                                fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    _iconBtn(cs, _skipRewindIcon(player.rewindSeconds), player.skipBackward),
                    SizedBox(
                      width: 36, height: 36,
                      child: player.isLoading
                          ? Padding(
                              padding: const EdgeInsets.all(8),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: cs.onInverseSurface),
                            )
                          : IconButton(
                              onPressed: player.togglePlayPause,
                              icon: Icon(
                                player.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: cs.onInverseSurface, size: 28),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                    ),
                    _iconBtn(cs, _skipForwardIcon(player.forwardSeconds), player.skipForward),
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
      {double size = 22}) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: cs.onInverseSurface, size: size),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

// ── Shared skip-icon helpers (used by mini player and bottom sheet) ───────────

IconData _skipRewindIcon(int s) {
  if (s <= 5) return Icons.replay_5;
  if (s <= 10) return Icons.replay_10;
  return Icons.replay_30;
}

IconData _skipForwardIcon(int s) {
  if (s <= 10) return Icons.forward_10;
  return Icons.forward_30;
}

// ── Player bottom sheet ───────────────────────────────────────────────────────

class _PlayerSheet extends StatelessWidget {
  const _PlayerSheet();

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  String _fmtSpeed(double speed) =>
      speed % 1 == 0 ? '${speed.toInt()}×' : '$speed×';

  void _share(BuildContext context, dynamic ep) {
    final text = '${ep.title}\n${ep.audioUrl}';
    SharePlus.instance.share(ShareParams(text: text, subject: ep.title));
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

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.95,
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: ep.podcastImageUrl,
                  width: 220, height: 220, fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 24),

            Text(ep.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 18,
                    color: cs.onSurface)),
            const SizedBox(height: 4),
            Text(ep.podcastTitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),

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
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),

                // Skip back (long press → choose seconds)
                GestureDetector(
                  onLongPress: () =>
                      _showSkipDialog(context, player, isForward: false),
                  onTap: player.skipBackward,
                  child: SizedBox(
                    width: 44, height: 48,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_skipRewindIcon(player.rewindSeconds), size: 28, color: cs.onSurface),
                        Text('${player.rewindSeconds}s',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface)),
                      ],
                    ),
                  ),
                ),

                // Play / pause
                Container(
                  width: 64, height: 64,
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
                            color: cs.onPrimary, size: 34,
                          ),
                        ),
                ),

                // Skip forward (long press → choose seconds)
                GestureDetector(
                  onLongPress: () =>
                      _showSkipDialog(context, player, isForward: true),
                  onTap: player.skipForward,
                  child: SizedBox(
                    width: 44, height: 48,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_skipForwardIcon(player.forwardSeconds), size: 28, color: cs.onSurface),
                        Text('${player.forwardSeconds}s',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface)),
                      ],
                    ),
                  ),
                ),

                // Share
                IconButton(
                  onPressed: () => _share(context, ep),
                  icon: Icon(Icons.share_outlined,
                      size: 22, color: cs.onSurfaceVariant),
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
            _ShowNotes(description: ep.description, cs: cs),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ── Shownotes renderer ────────────────────────────────────────────────────────
// Strips HTML to plain text, auto-links bare URLs, selectable via SelectionArea.

class _ShowNotes extends StatefulWidget {
  final String description;
  final ColorScheme cs;
  const _ShowNotes({required this.description, required this.cs});

  @override
  State<_ShowNotes> createState() => _ShowNotesState();
}

class _ShowNotesState extends State<_ShowNotes> {
  List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan> _spans = [];

  static final _urlRe = RegExp(r'https?://[^\s\)<>\]"]+', caseSensitive: false);

  static String _htmlToText(String html) {
    var t = html;

    // 1. Preserve links: <a href="URL">label</a> → "label (URL)" or just "URL"
    t = t.replaceAllMapped(
      RegExp(r"""<a\b[^>]*\bhref=['"]([^'"]+)['"][^>]*>(.*?)</a>""",
          caseSensitive: false, dotAll: true),
      (m) {
        final url = m.group(1) ?? '';
        final label = m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        if (label.isEmpty || label == url) return url;
        return '$label ($url)';
      },
    );

    // 2. Block-level elements → paragraph / line breaks
    t = t
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</?p[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</?div[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<h[1-6][^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
      .replaceAll(RegExp(r'</li>', caseSensitive: false), '')
      .replaceAll(RegExp(r'</?[uod]l[^>]*>', caseSensitive: false), '\n');

    // 3. Strip all remaining tags
    t = t.replaceAll(RegExp(r'<[^>]+>'), '');

    // 4. Named HTML entities
    t = t
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&mdash;', '—')
      .replaceAll('&ndash;', '–')
      .replaceAll('&hellip;', '…')
      .replaceAll('&laquo;', '«')
      .replaceAll('&raquo;', '»')
      .replaceAll('&bull;', '•')
      .replaceAll('&middot;', '·')
      .replaceAll('&copy;', '©')
      .replaceAll('&reg;', '®')
      .replaceAll('&trade;', '™');

    // 5. Numeric entities  &#NNN;  and  &#xHHH;
    t = t.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
    t = t.replaceAllMapped(RegExp(r'&#([0-9]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)));

    // 6. Collapse whitespace, trim blank lines
    t = t
      .replaceAll(RegExp(r'[^\S\n]+'), ' ')  // non-newline whitespace → single space
      .replaceAll(RegExp(r'\n +'), '\n')       // leading spaces after newline
      .replaceAll(RegExp(r' +\n'), '\n')       // trailing spaces before newline
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')  // max two consecutive newlines
      .trim();

    return t;
  }

  void _buildSpans() {
    for (final r in _recognizers) { r.dispose(); }
    _recognizers = [];

    final raw = widget.description;
    final text = raw.contains('<') ? _htmlToText(raw) : raw;

    final newSpans = <InlineSpan>[];
    var lastEnd = 0;
    for (final m in _urlRe.allMatches(text)) {
      if (m.start > lastEnd) {
        newSpans.add(TextSpan(text: text.substring(lastEnd, m.start)));
      }
      final url = m.group(0)!;
      final rec = TapGestureRecognizer()
        ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      _recognizers.add(rec);
      newSpans.add(TextSpan(
        text: url,
        style: TextStyle(
          color: widget.cs.primary,
          decoration: TextDecoration.underline,
          decorationColor: widget.cs.primary,
        ),
        recognizer: rec,
      ));
      lastEnd = m.end;
    }
    if (lastEnd < text.length) {
      newSpans.add(TextSpan(text: text.substring(lastEnd)));
    }
    _spans = newSpans;
  }

  @override
  void initState() {
    super.initState();
    _buildSpans();
  }

  @override
  void didUpdateWidget(_ShowNotes old) {
    super.didUpdateWidget(old);
    if (old.description != widget.description || old.cs != widget.cs) {
      _buildSpans();
    }
  }

  @override
  void dispose() {
    for (final r in _recognizers) { r.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontSize: 13,
            color: widget.cs.onSurfaceVariant,
            height: 1.6,
          ),
          children: _spans,
        ),
      ),
    );
  }
}
