// lib/podcast_header.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'app_database.dart';
import 'l10n/app_localizations.dart';
import 'podcast_service.dart';

class PodcastHeader extends StatefulWidget {
  final Podcast? podcast;
  final PodcastResult? previewResult;
  final VoidCallback onClose;
  final VoidCallback? onUnsubscribe;
  final VoidCallback? onSubscribe;

  const PodcastHeader({
    super.key,
    this.podcast,
    this.previewResult,
    required this.onClose,
    this.onUnsubscribe,
    this.onSubscribe,
  }) : assert(podcast != null || previewResult != null);

  @override
  State<PodcastHeader> createState() => _PodcastHeaderState();
}

class _PodcastHeaderState extends State<PodcastHeader> {
  bool _expanded = false;

  String get _imageUrl => widget.podcast?.imageUrl ?? widget.previewResult?.imageUrl ?? '';
  String get _title    => widget.podcast?.title    ?? widget.previewResult?.title    ?? '';
  String get _author   => widget.podcast?.author   ?? widget.previewResult?.author   ?? '';
  String get _description => widget.podcast?.description ?? widget.previewResult?.description ?? '';

  void _share() {
    final url = widget.podcast?.website ?? widget.podcast?.feedUrl
        ?? widget.previewResult?.feedUrl ?? '';
    SharePlus.instance.share(ShareParams(text: '$_title\n$url', subject: _title));
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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
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
                      imageUrl: _imageUrl,
                      width: 60, height: 60, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                          color: cs.surfaceContainerHighest,
                          child: const Icon(Icons.podcasts, size: 28)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_title,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                        if (_author.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(_author,
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
                  if (widget.onSubscribe != null)
                    Tooltip(
                      message: l10n.subscribeDialogTitle,
                      child: IconButton(
                        onPressed: widget.onSubscribe,
                        icon: Icon(Icons.add_circle_outline, color: cs.primary, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ),
                  if (widget.onUnsubscribe != null)
                    Tooltip(
                      message: l10n.unsubscribe,
                      child: IconButton(
                        onPressed: widget.onUnsubscribe,
                        icon: Icon(Icons.remove_circle_outline, color: cs.error, size: 20),
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
                child: Text(_description,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5)),
              ),
          ],
        ),
      ),
    );
  }
}
