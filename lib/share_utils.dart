import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:share_plus/share_plus.dart';

import 'app_database.dart';

class ShareUtils {
  static const _base = 'https://antpod.eu/open';

  // Strip https:// to save 8 chars; mark http:// feeds with "h0:" prefix.
  // Also strip www. from the host — it's redundant for virtually all podcast feeds.
  static String _stripProto(String url) {
    String s;
    if (url.startsWith('https://')) {
      s = url.substring(8);
    } else if (url.startsWith('http://')) {
      s = 'h0:${url.substring(7)}';
    } else {
      return url;
    }
    if (s.startsWith('www.')) s = s.substring(4);
    return s;
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

  /// Undoes [_stripProto] for a feed from a share link.
  static String restoreProto(String s) {
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('h0:')) return 'http://${s.substring(3)}';
    return 'https://$s';
  }

  static String podcastUrl(String feedUrl) => '$_base?p=${_enc(_stripProto(feedUrl))}';

  static String episodeUrl(Episode episode) =>
      '$_base?p=${_enc(_stripProto(episode.podcastId))}&e=${guidHash(AppDatabase.guidOf(episode.id))}';

  static void sharePodcast(String title, String feedUrl) => SharePlus.instance.share(
      ShareParams(text: '$title\n${podcastUrl(feedUrl)}', subject: title));

  static void shareEpisode(Episode episode) => SharePlus.instance.share(ShareParams(
      text: '${episode.title} (${episode.podcastTitle})\n${episodeUrl(episode)}',
      subject: episode.title));
}
