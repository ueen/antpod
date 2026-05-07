// lib/html_utils.dart
//
// Shared HTML-to-text conversion and rich text rendering used by the player
// bottom sheet (show notes) and the podcast header (description).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ── HTML → plain text ─────────────────────────────────────────────────────────

final htmlUrlRe = RegExp(
  r'(?:https?://[^\s\)<>\]"]+|www\.[^\s\)<>\]"]+|[a-zA-Z0-9][-a-zA-Z0-9.]+\.[a-zA-Z]{2,}/[^\s\)<>\]"]*)',
  caseSensitive: false,
);

String htmlToText(String html) {
  var t = html;

  // 0. Remove entire <style> and <script> blocks
  t = t.replaceAll(RegExp(r'<style\b[^>]*>.*?</style>', caseSensitive: false, dotAll: true), '');
  t = t.replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', caseSensitive: false, dotAll: true), '');

  // 1. Preserve links: <a href="URL">label</a> => "label (URL)" or just "URL"
  t = t.replaceAllMapped(
    RegExp(r"""<a\b[^>]*\bhref=['"]([^'"]+)['"][^>]*>(.*?)</a>""",
        caseSensitive: false, dotAll: true),
    (m) {
      final url = m.group(1) ?? '';
      final label = m.group(2)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (label.isEmpty || label == url) return url;
      return '$label ($url)';
    },
  );

  // 2. Block-level elements => line breaks
  t = t
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</?p[^>]*>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</?div[^>]*>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</?section[^>]*>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</?article[^>]*>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</?blockquote[^>]*>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<hr[^>]*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<h[1-6][^>]*>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
    .replaceAll(RegExp(r'</li>', caseSensitive: false), '')
    .replaceAll(RegExp(r'</?[uod]l[^>]*>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</tr>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<t[dh][^>]*>', caseSensitive: false), '\t');

  // 3. Strip all remaining tags
  t = t.replaceAll(RegExp(r'<[^>]*>'), '');

  // 4. Named HTML entities
  t = t
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&mdash;', '—')
    .replaceAll('&ndash;', '–')
    .replaceAll('&hellip;', '…')
    .replaceAll('&laquo;', '«')
    .replaceAll('&raquo;', '»')
    .replaceAll('&bull;', '•')
    .replaceAll('&middot;', '·')
    .replaceAll('&copy;', '©')
    .replaceAll('&reg;', '®')
    .replaceAll('&trade;', '™')
    .replaceAll('&rsquo;', '’')
    .replaceAll('&lsquo;', '‘')
    .replaceAll('&rdquo;', '”')
    .replaceAll('&ldquo;', '“')
    .replaceAll('&sbquo;', '‚')
    .replaceAll('&bdquo;', '„')
    .replaceAll('&euro;', '€')
    .replaceAll('&pound;', '£')
    .replaceAll('&yen;', '¥')
    .replaceAll('&cent;', '¢')
    .replaceAll('&auml;', 'ä')
    .replaceAll('&ouml;', 'ö')
    .replaceAll('&uuml;', 'ü')
    .replaceAll('&Auml;', 'Ä')
    .replaceAll('&Ouml;', 'Ö')
    .replaceAll('&Uuml;', 'Ü')
    .replaceAll('&szlig;', 'ß')
    .replaceAll('&eacute;', 'é')
    .replaceAll('&egrave;', 'è')
    .replaceAll('&ecirc;', 'ê')
    .replaceAll('&agrave;', 'à')
    .replaceAll('&aacute;', 'á')
    .replaceAll('&acirc;', 'â')
    .replaceAll('&iacute;', 'í')
    .replaceAll('&oacute;', 'ó')
    .replaceAll('&ntilde;', 'ñ')
    .replaceAll('&ccedil;', 'ç');

  // 5. Numeric entities &#NNN; and &#xHHH;
  t = t.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
    try { return String.fromCharCode(int.parse(m.group(1)!, radix: 16)); }
    catch (_) { return ''; }
  });
  t = t.replaceAllMapped(RegExp(r'&#([0-9]+);'), (m) {
    try { return String.fromCharCode(int.parse(m.group(1)!)); }
    catch (_) { return ''; }
  });

  // 5b. Second pass for double-encoded ampersands
  t = t.replaceAll('&amp;', '&');

  // 6. Collapse whitespace
  t = t
    .replaceAll(RegExp(r'[^\S\n]+'), ' ')
    .replaceAll(RegExp(r'\n +'), '\n')
    .replaceAll(RegExp(r' +\n'), '\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

  return t;
}

// ── Rich text renderer with clickable links ───────────────────────────────────

class ShowNotes extends StatefulWidget {
  final String description;
  final ColorScheme cs;
  const ShowNotes({super.key, required this.description, required this.cs});

  @override
  State<ShowNotes> createState() => _ShowNotesState();
}

class _ShowNotesState extends State<ShowNotes> {
  List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan> _spans = [];

  void _buildSpans() {
    for (final r in _recognizers) { r.dispose(); }
    _recognizers = [];

    final text = htmlToText(widget.description);
    final newSpans = <InlineSpan>[];
    var lastEnd = 0;
    for (final m in htmlUrlRe.allMatches(text)) {
      if (m.start > lastEnd) {
        newSpans.add(TextSpan(text: text.substring(lastEnd, m.start)));
      }
      final url = m.group(0)!;
      final uriStr = url.startsWith('http') ? url : 'https://$url';
      final rec = TapGestureRecognizer()
        ..onTap = () => launchUrl(Uri.parse(uriStr), mode: LaunchMode.externalApplication);
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
  void didUpdateWidget(ShowNotes old) {
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
