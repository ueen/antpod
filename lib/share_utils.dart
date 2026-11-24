import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'app_database.dart';
import 'podcast_service.dart';

class ShareUtils {
  static const _base = 'https://antpod.eu/open';

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

  static String podcastUrl(Podcast podcast) =>
      '$_base?f=${_enc(_stripProto(podcast.feedUrl))}';

  static String podcastResultUrl(PodcastResult result) =>
      '$_base?f=${_enc(_stripProto(result.feedUrl))}';

  static String episodeUrl(Episode episode) =>
      '$_base?f=${_enc(_stripProto(episode.podcastId))}&e=${guidHash(episode.id)}';
}
