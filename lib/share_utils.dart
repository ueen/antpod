import 'dart:convert';

import 'app_database.dart';
import 'podcast_service.dart';

class ShareUtils {
  static const _base = 'https://antpod.eu/open';

  // Clip to max chars for display-only params (title, podcast name).
  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  // Strip https:// to save 8 chars; mark http:// feeds with "h0:" prefix.
  static String _stripProto(String url) {
    if (url.startsWith('https://')) return url.substring(8);
    if (url.startsWith('http://')) return 'h0:${url.substring(7)}';
    return url;
  }

  // Minimal query-value encoding: only encode chars that truly break URL parsing.
  // Leaves : and / unencoded — the biggest savings vs Uri.encodeQueryComponent.
  // Spaces → + (1 char vs %20's 3 chars).
  static String _enc(String s) {
    final buf = StringBuffer();
    for (final b in utf8.encode(s)) {
      if (b == 32) {
        buf.write('+');
      } else if (_safe(b)) {
        buf.writeCharCode(b);
      } else {
        buf.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return buf.toString();
  }

  // Safe in a query-parameter value: unreserved chars + : / @ ! $ ' ( ) * , ;
  // NOT safe: % (37), & (38), = (61), + (43), # (35), space (32)
  static bool _safe(int b) {
    if (b >= 65 && b <= 90) return true;   // A-Z
    if (b >= 97 && b <= 122) return true;  // a-z
    if (b >= 48 && b <= 57) return true;   // 0-9
    const ok = {45, 95, 46, 126, 58, 47, 64, 33, 36, 39, 40, 41, 42, 44, 59};
    return ok.contains(b);
  }

  static String podcastUrl(Podcast podcast) {
    final b = StringBuffer('$_base?f=${_enc(_stripProto(podcast.feedUrl))}');
    if (podcast.title.isNotEmpty) b.write('&t=${_enc(_clip(podcast.title, 20))}');
    return b.toString();
  }

  static String podcastResultUrl(PodcastResult result) {
    final b = StringBuffer('$_base?f=${_enc(_stripProto(result.feedUrl))}');
    if (result.title.isNotEmpty) b.write('&t=${_enc(_clip(result.title, 20))}');
    return b.toString();
  }

  static String episodeUrl(Episode episode) {
    // Strip protocol from guid too — GUIDs are often audio URLs, which would
    // appear as a second hyperlink in messaging apps if left as https://...
    final b = StringBuffer('$_base?f=${_enc(_stripProto(episode.podcastId))}'
        '&g=${_enc(_stripProto(episode.id))}');
    if (episode.title.isNotEmpty) b.write('&t=${_enc(_clip(episode.title, 20))}');
    return b.toString();
  }
}
