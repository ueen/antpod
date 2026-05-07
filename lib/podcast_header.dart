// lib/podcast_header.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'html_utils.dart';
import 'l10n/app_localizations.dart';

class PodcastHeader extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String author;
  final String description;
  final String shareUrl;

  /// Provide exactly one of these; the other should be null.
  final VoidCallback? onSubscribe;
  final VoidCallback? onUnsubscribe;

  const PodcastHeader({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.author,
    required this.description,
    required this.shareUrl,
    this.onSubscribe,
    this.onUnsubscribe,
  });

  @override
  State<PodcastHeader> createState() => _PodcastHeaderState();
}

class _PodcastHeaderState extends State<PodcastHeader> {
  bool _expanded = false;
  bool _subscribePressed = false;

  void _share() {
    SharePlus.instance.share(
        ShareParams(text: '${widget.title}\n${widget.shareUrl}', subject: widget.title));
  }

  Future<void> _confirmUnsubscribe(BuildContext context, AppLocalizations l10n) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.unsubscribe),
        content: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.unsubscribe,
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirm == true) widget.onUnsubscribe?.call();
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
                      ],
                    ),
                  ),
                  // Share button
                  Padding(
                    padding: const EdgeInsets.only(left: 6, right: 12),
                    child: GestureDetector(
                      onTap: _share,
                      child: Icon(Icons.share_outlined,
                          color: cs.onSurfaceVariant, size: 24),
                    ),
                  ),
                  // Subscribe / unsubscribe button
                  if (widget.onSubscribe != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: _subscribePressed ? null : () async {
                          setState(() => _subscribePressed = true);
                          await Future.delayed(const Duration(milliseconds: 380));
                          widget.onSubscribe?.call();
                        },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: _subscribePressed
                              ? Icon(Icons.check_circle,
                                  key: const ValueKey('check'),
                                  color: Colors.green, size: 32)
                              : Icon(Icons.add_circle_outline,
                                  key: const ValueKey('add'),
                                  color: cs.primary, size: 32),
                        ),
                      ),
                    ),
                  if (widget.onUnsubscribe != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => _confirmUnsubscribe(context, l10n),
                        child: Icon(Icons.remove_circle_outline,
                            color: cs.error, size: 32),
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
                child: Icon(Icons.keyboard_arrow_down,
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
