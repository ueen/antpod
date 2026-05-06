// lib/podcast_header.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'app_database.dart';
import 'l10n/app_localizations.dart';

class PodcastHeader extends StatefulWidget {
  final Podcast podcast;
  final VoidCallback onClose;
  const PodcastHeader({super.key, required this.podcast, required this.onClose});
  @override
  State<PodcastHeader> createState() => _PodcastHeaderState();
}

class _PodcastHeaderState extends State<PodcastHeader> {
  bool _expanded = false;

  void _share() {
    final url = widget.podcast.website ?? widget.podcast.feedUrl;
    SharePlus.instance.share(ShareParams(
      text: '${widget.podcast.title}\n$url',
      subject: widget.podcast.title,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: widget.podcast.imageUrl,
                      width: 60, height: 60, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                          color: cs.surfaceContainerHighest, child: const Icon(Icons.podcasts, size: 28)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.podcast.title,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                        if (widget.podcast.author.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(widget.podcast.author,
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
                  Tooltip(
                    message: l10n.sharePodcast,
                    child: IconButton(
                      onPressed: _share,
                      icon: Icon(Icons.share_outlined, color: cs.onSurfaceVariant, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(Icons.keyboard_arrow_down, color: cs.onSurfaceVariant),
                  ),
                  IconButton(
                    onPressed: widget.onClose,
                    icon: Icon(Icons.close, color: cs.onSurfaceVariant, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
                child: Text(widget.podcast.description,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5)),
              ),
          ],
        ),
      ),
    );
  }
}
