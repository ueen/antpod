// lib/id3_chapters.dart
//
// Reads the chapters embedded in an episode's ID3v2 tag: CHAP frames with
// their TIT2 title and APIC image. They describe the exact file being played,
// which the chapters JSON may not: with dynamic ad insertion the CDN shifts
// the audio and rewrites these times to match, while the JSON keeps the
// ad-free ones. Only ID3v2.3 and v2.4 are supported.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef Id3Chapter = ({int startMs, String title, Uint8List? image});

const _maxTagBytes = 8 * 1024 * 1024;

/// Chapters from the ID3 tag at the start of the downloaded file at
/// [localPath], or else of the stream at [audioUrl]: one request, read up to
/// the end of the tag and then dropped. Sorted by start time; empty when the
/// file has none, null when it couldn't be read (worth retrying).
Future<List<Id3Chapter>?> readId3Chapters(
    {String? localPath, required String audioUrl}) async {
  http.Client? client;
  try {
    final Stream<List<int>> bytes;
    if (localPath != null) {
      bytes = File(localPath).openRead();
    } else {
      if (audioUrl.isEmpty) return const [];
      client = http.Client();
      final res = await client
          .send(http.Request('GET', Uri.parse(audioUrl)))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 && res.statusCode != 206) return null;
      bytes = res.stream;
    }
    final tag = await _readTag(bytes).timeout(const Duration(seconds: 30));
    if (tag == null) return const [];
    return await compute(_parseChapters, tag);
  } catch (e) {
    debugPrint('[chapters] ID3 read failed: $e');
    return null;
  } finally {
    client?.close();
  }
}

typedef _Tag = ({Uint8List body, int version, int flags});

/// The tag after its 10-byte header, or null when [bytes] doesn't start with
/// an ID3v2.3/2.4 tag. Stops reading (cancels the stream) once it's in.
Future<_Tag?> _readTag(Stream<List<int>> bytes) async {
  final buf = BytesBuilder(copy: false);
  int? end;
  int version = 0, flags = 0;
  await for (final chunk in bytes) {
    buf.add(chunk);
    if (end == null && buf.length >= 10) {
      final h = buf.toBytes();
      if (h[0] != 0x49 || h[1] != 0x44 || h[2] != 0x33) return null; // "ID3"
      version = h[3];
      if (version < 3 || version > 4) return null;
      flags = h[5];
      final size = _synchsafe(h, 6);
      if (size == 0 || size > _maxTagBytes) return null;
      end = 10 + size;
    }
    if (end != null && buf.length >= end) break;
  }
  if (end == null || buf.length < end) throw const FormatException('ID3 tag cut short');
  return (body: Uint8List.sublistView(buf.toBytes(), 10, end), version: version, flags: flags);
}

// Top-level so compute() can run it in an isolate.
List<Id3Chapter> _parseChapters(_Tag tag) {
  final d = tag.body;
  final v4 = tag.version == 4;
  int frameSize(int at) => v4 ? _synchsafe(d, at) : _uint32(d, at);

  var pos = 0;
  if (tag.flags & 0x40 != 0 && d.length >= 4) {
    // Extended header: v2.4's size counts itself, v2.3's leaves out its 4 bytes.
    pos = v4 ? _synchsafe(d, 0) : _uint32(d, 0) + 4;
  }

  Uint8List? cover; // the file's own artwork
  final chapters = <Id3Chapter>[];
  while (pos + 10 <= d.length && d[pos] != 0) {
    final id = String.fromCharCodes(d, pos, pos + 4);
    final start = pos + 10, end = start + frameSize(pos + 4);
    if (end <= start || end > d.length) break;
    if (id == 'CHAP') {
      final c = _chap(d, start, end, frameSize);
      if (c != null) chapters.add(c);
    } else if (id == 'APIC') {
      cover ??= _apicImage(d, start, end);
    }
    pos = end;
  }

  chapters.sort((a, b) => a.startMs.compareTo(b.startMs));
  // A chapter showing the episode artwork has no picture of its own.
  return [
    for (final c in chapters)
      (
        startMs: c.startMs,
        title: c.title,
        image: c.image != null && listEquals(c.image, cover) ? null : c.image,
      ),
  ];
}

/// One CHAP frame: element ID, start/end time and byte offsets, sub-frames.
Id3Chapter? _chap(Uint8List d, int pos, int end, int Function(int) frameSize) {
  while (pos < end && d[pos] != 0) { pos++; } // element ID
  pos++;
  if (pos + 16 > end) return null;
  final startMs = _uint32(d, pos);
  pos += 16;

  var title = '';
  Uint8List? image;
  while (pos + 10 <= end && d[pos] != 0) {
    final id = String.fromCharCodes(d, pos, pos + 4);
    final start = pos + 10, stop = start + frameSize(pos + 4);
    if (stop <= start || stop > end) break;
    if (id == 'TIT2') title = _text(d, start, stop);
    if (id == 'APIC') image ??= _apicImage(d, start, stop);
    pos = stop;
  }
  return (startMs: startMs, title: title, image: image);
}

/// A text frame's value: an encoding byte, then Latin-1, UTF-16 with BOM,
/// UTF-16BE or UTF-8.
String _text(Uint8List d, int start, int end) {
  if (start >= end) return '';
  final enc = d[start];
  final b = Uint8List.sublistView(d, start + 1, end);
  String s;
  switch (enc) {
    case 1 || 2:
      var bigEndian = enc == 2;
      var i = 0;
      if (enc == 1 && b.length >= 2) {
        if (b[0] == 0xFF && b[1] == 0xFE) { i = 2; }
        if (b[0] == 0xFE && b[1] == 0xFF) { bigEndian = true; i = 2; }
      }
      final units = <int>[];
      for (; i + 1 < b.length; i += 2) {
        units.add(bigEndian ? (b[i] << 8) | b[i + 1] : b[i] | (b[i + 1] << 8));
      }
      s = String.fromCharCodes(units);
    case 3:
      s = utf8.decode(b, allowMalformed: true);
    default:
      s = latin1.decode(b);
  }
  // Values may be null-terminated, or several null-separated: take the first.
  final nul = s.indexOf('\u0000');
  return (nul >= 0 ? s.substring(0, nul) : s).trim();
}

/// The picture data of an APIC frame: after encoding, MIME type, picture
/// type and description.
Uint8List? _apicImage(Uint8List d, int start, int end) {
  if (start >= end) return null;
  var pos = start;
  final enc = d[pos++];
  while (pos < end && d[pos] != 0) { pos++; } // MIME type
  pos += 2; // its null, picture type
  if (enc == 1 || enc == 2) {
    while (pos + 1 < end && !(d[pos] == 0 && d[pos + 1] == 0)) { pos += 2; }
    pos += 2;
  } else {
    while (pos < end && d[pos] != 0) { pos++; }
    pos++;
  }
  if (pos >= end) return null;
  return Uint8List.fromList(d.sublist(pos, end));
}

int _synchsafe(List<int> b, int at) =>
    (b[at] & 0x7F) << 21 | (b[at + 1] & 0x7F) << 14 | (b[at + 2] & 0x7F) << 7 | (b[at + 3] & 0x7F);

int _uint32(List<int> b, int at) =>
    b[at] << 24 | b[at + 1] << 16 | b[at + 2] << 8 | b[at + 3];
