// lib/id3_chapters.dart
//
// Reads chapter images embedded as APIC sub-frames inside ID3v2 CHAP tags.
// Only v2.3 and v2.4 are supported. Range requests are used so only the ID3
// header is fetched (typically < 1 MB even for heavily-tagged episodes).
//
// Usage:
//   final images = await fetchId3ChapterImages(audioUrl);
//   // images: Map<startTimeMs, jpegBytes>
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Fetches the ID3v2 tag from [audioUrl] via HTTP range requests and returns
/// a map of chapter-start-time (ms) → embedded image bytes.
/// Returns an empty map on any error or unsupported format.
Future<Map<int, Uint8List>> fetchId3ChapterImages(String audioUrl) async {
  try {
    // ── Step 1: read 10-byte ID3v2 header ───────────────────────────────────
    final headResp = await http.get(
      Uri.parse(audioUrl),
      headers: {'Range': 'bytes=0-9'},
    ).timeout(const Duration(seconds: 10));
    if (headResp.statusCode != 206 && headResp.statusCode != 200) return {};

    final hdr = headResp.bodyBytes;
    if (hdr.length < 10) return {};

    // Magic "ID3"
    if (hdr[0] != 0x49 || hdr[1] != 0x44 || hdr[2] != 0x33) return {};

    final version = hdr[3]; // 3 = v2.3, 4 = v2.4
    if (version < 3 || version > 4) return {};

    final flags = hdr[5];
    final hasExtHeader = (flags & 0x40) != 0;

    // Synchsafe 28-bit size (7 bits per byte)
    int tagSize = 0;
    for (int i = 6; i < 10; i++) { tagSize = (tagSize << 7) | (hdr[i] & 0x7F); }
    if (tagSize == 0 || tagSize > 8 * 1024 * 1024) return {}; // max 8 MB

    // ── Step 2: fetch tag body ───────────────────────────────────────────────
    final bodyResp = await http.get(
      Uri.parse(audioUrl),
      headers: {'Range': 'bytes=10-${10 + tagSize - 1}'},
    ).timeout(const Duration(seconds: 20));
    if (bodyResp.statusCode != 206 && bodyResp.statusCode != 200) return {};

    final tagBytes = Uint8List.fromList(bodyResp.bodyBytes);

    // ── Step 3: parse in background isolate ─────────────────────────────────
    return compute(_parseChapImages,
        (bytes: tagBytes, version: version, hasExtHeader: hasExtHeader));
  } catch (_) {
    return {};
  }
}

// Top-level so compute() can serialize it.
Map<int, Uint8List> _parseChapImages(
    ({Uint8List bytes, int version, bool hasExtHeader}) args) {
  final data = args.bytes;
  final v = args.version;
  final result = <int, Uint8List>{};
  int pos = 0;

  // Skip extended header
  if (args.hasExtHeader && pos + 4 <= data.length) {
    int extSize = 0;
    if (v == 4) {
      for (int i = 0; i < 4; i++) { extSize = (extSize << 7) | (data[pos + i] & 0x7F); }
    } else {
      for (int i = 0; i < 4; i++) { extSize = (extSize << 8) | data[pos + i]; }
    }
    pos += extSize;
  }

  // Walk frames
  while (pos + 10 <= data.length) {
    final b0 = data[pos], b1 = data[pos+1], b2 = data[pos+2], b3 = data[pos+3];
    // Padding / end of frames
    if (b0 == 0 && b1 == 0 && b2 == 0 && b3 == 0) break;

    final frameId = String.fromCharCodes([b0, b1, b2, b3]);
    int frameSize = 0;
    if (v == 4) {
      for (int i = 0; i < 4; i++) { frameSize = (frameSize << 7) | (data[pos + 4 + i] & 0x7F); }
    } else {
      for (int i = 0; i < 4; i++) { frameSize = (frameSize << 8) | data[pos + 4 + i]; }
    }
    pos += 10;
    if (frameSize <= 0 || pos + frameSize > data.length) break;

    if (frameId == 'CHAP') {
      final parsed = _parseChap(data, pos, pos + frameSize, v);
      if (parsed != null) { result[parsed.$1] = parsed.$2; }
    }

    pos += frameSize;
  }

  return result;
}

/// Parses one CHAP frame in [data] from [start]..[end].
/// Returns (startTimeMs, imageBytes) or null.
(int, Uint8List)? _parseChap(Uint8List data, int start, int end, int v) {
  int pos = start;

  // Skip element ID (null-terminated)
  while (pos < end && data[pos] != 0) { pos++; }
  pos++; // skip null

  if (pos + 16 > end) return null;
  final startMs = (data[pos] << 24) | (data[pos+1] << 16) | (data[pos+2] << 8) | data[pos+3];
  pos += 16; // start(4) + end(4) + startOffset(4) + endOffset(4)

  // Sub-frames
  while (pos + 10 <= end) {
    final b0 = data[pos], b1 = data[pos+1], b2 = data[pos+2], b3 = data[pos+3];
    if (b0 == 0 && b1 == 0 && b2 == 0 && b3 == 0) break;
    final subId = String.fromCharCodes([b0, b1, b2, b3]);

    int subSize = 0;
    if (v == 4) {
      for (int i = 0; i < 4; i++) { subSize = (subSize << 7) | (data[pos + 4 + i] & 0x7F); }
    } else {
      for (int i = 0; i < 4; i++) { subSize = (subSize << 8) | data[pos + 4 + i]; }
    }
    pos += 10;
    if (subSize <= 0 || pos + subSize > end) break;

    if (subId == 'APIC') {
      final img = _extractApic(data, pos, pos + subSize);
      if (img != null) { return (startMs, img); }
    }
    pos += subSize;
  }
  return null;
}

/// Extracts raw image bytes from an APIC frame in [data] from [start]..[end].
Uint8List? _extractApic(Uint8List data, int start, int end) {
  if (start >= end) return null;
  int pos = start;
  final encoding = data[pos++];

  // Skip MIME type (null-terminated ASCII)
  while (pos < end && data[pos] != 0) { pos++; }
  pos++; // null
  if (pos >= end) return null;

  pos++; // picture type byte

  // Skip description (encoding-dependent null terminator)
  if (encoding == 1 || encoding == 2) {
    // UTF-16: 2-byte null
    while (pos + 1 < end && !(data[pos] == 0 && data[pos+1] == 0)) { pos += 2; }
    pos += 2;
  } else {
    while (pos < end && data[pos] != 0) { pos++; }
    pos++;
  }

  if (pos >= end) return null;
  return Uint8List.fromList(data.sublist(pos, end));
}
