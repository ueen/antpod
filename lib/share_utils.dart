import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'app_database.dart';
import 'podcast_service.dart';

class ShareUtils {
  static const _base = 'https://antpod.eu/open';

  // Podcast name: clip at natural separator within 20 chars, else hard-clip at 20.
  static String _clipPodcast(String s) {
    for (final sep in [': ', ' - ', ' – ', ' — ', ' | ']) {
      final i = s.indexOf(sep);
      if (i > 0 && i < 20) return s.substring(0, i);
    }
    return s.length <= 20 ? s : '${s.substring(0, 20)}…';
  }

  // Episode title: plain 50-char clip.
  static String _clipTitle(String s) =>
      s.length <= 50 ? s : '${s.substring(0, 50)}…';

  // Strip https:// to save 8 chars; mark http:// feeds with "h0:" prefix.
  static String _stripProto(String url) {
    if (url.startsWith('https://')) return url.substring(8);
    if (url.startsWith('http://')) return 'h0:${url.substring(7)}';
    return url;
  }

  // First 8 bytes of SHA-1 → 11-char base64url. Fixed short ID for any GUID.
  // SHA-1 used because browsers support it natively via Web Crypto (MD5 does not).
  static String guidHash(String guid) {
    final bytes = sha1.convert(utf8.encode(guid)).bytes.sublist(0, 8);
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  // Minimal query-value encoding: only encode chars that truly break URL parsing.
  // Leaves : and / unencoded — the biggest savings vs Uri.encodeQueryComponent.
  static String _enc(String s) {
    final buf = StringBuffer();
    for (final b in utf8.encode(s)) {
      if (b == 32) {
        buf.write('+');        // space → + (saves 2 chars vs %20); literal + → %2B below
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
    if (podcast.title.isNotEmpty) b.write('&t=${_enc(_clipPodcast(podcast.title))}');
    return b.toString();
  }

  static String podcastResultUrl(PodcastResult result) {
    final b = StringBuffer('$_base?f=${_enc(_stripProto(result.feedUrl))}');
    if (result.title.isNotEmpty) b.write('&t=${_enc(_clipPodcast(result.title))}');
    return b.toString();
  }

  static String episodeUrl(Episode episode) {
    final b = StringBuffer('$_base?f=${_enc(_stripProto(episode.podcastId))}'
        '&h=${guidHash(episode.id)}');
    if (episode.title.isNotEmpty) b.write('&t=${_enc(_clipTitle(episode.title))}');
    if (episode.podcastTitle.isNotEmpty) b.write('&p=${_enc(_clipPodcast(episode.podcastTitle))}');
    return b.toString();
  }
}
