// lib/ad_detection/chapter_scanner.dart
//
// Fetches a PodcastIndex / Podlove chapters JSON and finds sponsor segments.
// Returns zero results on any network or parse error — caller never throws.

import 'dart:convert';
import 'package:http/http.dart' as http;

class ChapterAdSegment {
  const ChapterAdSegment({
    required this.startSeconds,
    required this.endSeconds,
    required this.title,
  });
  final double startSeconds;
  final double endSeconds;
  final String title;
}

class ChapterScanner {
  static const _sponsorKeywords = [
    'sponsor',
    'advertisement',
    ' ad ',
    'promo',
    'commercial',
    'brought to you',
    'support',
    'partner',
    'message from',
  ];

  // Returns sponsor/ad chapter segments, empty list on failure or no matches.
  static Future<List<ChapterAdSegment>> scan(String chaptersUrl) async {
    try {
      final response = await http
          .get(Uri.parse(chaptersUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return const [];

      final body = jsonDecode(response.body) as Map<String, dynamic>?;
      final rawChapters = body?['chapters'] as List<dynamic>?;
      if (rawChapters == null || rawChapters.isEmpty) return const [];

      final results = <ChapterAdSegment>[];

      for (int i = 0; i < rawChapters.length; i++) {
        final ch = rawChapters[i] as Map<String, dynamic>;
        final title = (ch['title'] as String? ?? '');
        final lowerTitle = title.toLowerCase();
        final toc = ch['toc'] as bool? ?? true;
        final startTime = (ch['startTime'] as num?)?.toDouble() ?? 0.0;

        final isSponsor =
            !toc || _sponsorKeywords.any(lowerTitle.contains);
        if (!isSponsor) continue;

        // End = next chapter's startTime, or +60 s as a conservative fallback.
        final nextCh = i + 1 < rawChapters.length
            ? rawChapters[i + 1] as Map<String, dynamic>?
            : null;
        final endTime =
            (nextCh?['startTime'] as num?)?.toDouble() ?? startTime + 60.0;

        final duration = endTime - startTime;
        // Sanity: typical ads are 10–120 s.
        if (duration < 10 || duration > 120) continue;

        results.add(ChapterAdSegment(
          startSeconds: startTime,
          endSeconds: endTime,
          title: title,
        ));
      }

      return results;
    } catch (_) {
      return const [];
    }
  }
}
