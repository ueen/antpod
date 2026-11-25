// lib/file_chapters.dart
//
// Reads the chapters an episode's audio file carries itself:
//
//   MP3              ID3v2.3/2.4 CHAP frames, with TIT2 title, APIC picture
//   M4A, MP4         a QuickTime chapter track (titles, and pictures from a
//                    video track it also points to), else Nero chapters (chpl)
//   Ogg, Opus, FLAC  CHAPTERnnn and CHAPTERnnnNAME Vorbis comments
//
// These describe the exact file being played (chapters.dart says why that
// matters). A stream is read only as far as needed: the tag at the start of
// an MP3, Ogg or FLAC file; for an M4A its index (moov, often at the end,
// reached with a Range request) and the chapter samples that points to.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef FileChapter = ({int startMs, String title, Uint8List? image});

const _maxTagBytes = 8 << 20; // an ID3 tag, a Vorbis comment
const _maxIndexBytes = 32 << 20; // an M4A's moov box
const _maxSampleBytes = 24 << 20; // an M4A's chapter titles and pictures
const _maxChapters = 1000;
const _timeout = Duration(seconds: 15);

/// Chapters from the downloaded file at [localPath], or else from the stream
/// at [audioUrl], read on a background isolate. Sorted by start time; empty
/// when the file has none, null when it couldn't be read (worth retrying).
Future<List<FileChapter>?> readFileChapters(
    {String? localPath, required String audioUrl}) async {
  if (localPath == null && audioUrl.isEmpty) return const [];
  try {
    return await Isolate.run(() =>
        _read(localPath, audioUrl).timeout(const Duration(seconds: 45)));
  } catch (e) {
    debugPrint('[chapters] reading the file failed: $e');
    return null;
  }
}

Future<List<FileChapter>> _read(String? localPath, String audioUrl) async {
  final src = localPath != null
      ? await _FileSource.open(localPath)
      : _HttpSource(Uri.parse(audioUrl));
  try {
    final head = await src.read(0, 12);
    if (head.length < 12) return const [];
    if (_is(head, 0, 'ID3')) return await _id3(src, head);
    if (_is(head, 4, 'ftyp')) return await _mp4(src);
    if (_is(head, 0, 'OggS')) return await _ogg(src);
    if (_is(head, 0, 'fLaC')) return await _flac(src);
    return const [];
  } finally {
    await src.close();
  }
}

/// Sorted by start, leaving out pictures that are just the episode's
/// artwork: the file's [cover], or one picture every chapter has. Such a
/// chapter has no picture of its own.
List<FileChapter> _finish(List<FileChapter> chapters, [Uint8List? cover]) {
  final sorted = [...chapters]..sort((a, b) => a.startMs.compareTo(b.startMs));
  final first = sorted.firstOrNull?.image;
  final shared = sorted.length > 1 &&
      first != null &&
      sorted.every((c) => listEquals(c.image, first));
  return [
    for (final c in sorted)
      (
        startMs: c.startMs,
        title: c.title,
        image: shared || listEquals(c.image, cover) ? null : c.image,
      ),
  ];
}

// ── Reading ─────────────────────────────────────────────────────────────────

/// Random access to the audio file's bytes.
abstract class _Source {
  /// [length] bytes at [offset]; fewer only past the end of the file.
  Future<Uint8List> read(int offset, int length);
  Future<void> close();
}

class _FileSource implements _Source {
  _FileSource(this._file, this._length);
  final RandomAccessFile _file;
  final int _length;

  static Future<_FileSource> open(String path) async {
    final file = await File(path).open();
    return _FileSource(file, await file.length());
  }

  @override
  Future<Uint8List> read(int offset, int length) async {
    final out = Uint8List(max(0, min(length, _length - offset)));
    if (out.isEmpty) return out;
    await _file.setPosition(offset);
    var got = 0;
    while (got < out.length) {
      final n = await _file.readInto(out, got);
      if (n == 0) break;
      got += n;
    }
    return Uint8List.sublistView(out, 0, got);
  }

  @override
  Future<void> close() => _file.close();
}

/// A stream, read through one GET from the start as far as needed, with
/// Range requests for parts further on. Those go to the URL the GET ended up
/// at, so tracking redirects in front of the host see a single request.
class _HttpSource implements _Source {
  _HttpSource(this._url);
  final Uri _url;
  final _client = http.Client();
  Uri? _finalUrl;
  StreamIterator<List<int>>? _body;
  Uint8List _head = Uint8List(0);
  int _len = 0;
  bool _complete = false; // the whole file is in _head

  static const _headMax = 16 << 20; // read through the GET at most
  static const _reach = 1 << 20; // a read this far past it continues the GET

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (length <= 0) return Uint8List(0);
    if (_body == null) await _open();
    final end = offset + length;
    if (end > _len && !_complete && end <= _headMax && offset <= _len + _reach) {
      await _fill(end);
    }
    if (end <= _len || _complete) {
      return Uint8List.sublistView(_head, min(offset, _len), min(end, _len));
    }
    return _range(offset, length);
  }

  Future<void> _open() async {
    final res = await _client.send(http.Request('GET', _url)).timeout(_timeout);
    if (res.statusCode != 200 && res.statusCode != 206) {
      unawaited(res.stream.listen(null).cancel());
      throw HttpException('HTTP ${res.statusCode}', uri: _url);
    }
    _finalUrl = switch (res) {
      http.BaseResponseWithUrl(:final url) => url,
      _ => _url,
    };
    _body = StreamIterator(res.stream);
  }

  Future<void> _fill(int upTo) async {
    final body = _body!;
    while (_len < upTo) {
      if (!await body.moveNext().timeout(_timeout)) {
        _complete = true;
        return;
      }
      final chunk = body.current;
      if (_len + chunk.length > _head.length) {
        final grown = Uint8List(max(_len + chunk.length,
            min(max(_head.length * 2, 256 << 10), _headMax)));
        grown.setRange(0, _len, _head);
        _head = grown;
      }
      _head.setRange(_len, _len + chunk.length, chunk);
      _len += chunk.length;
    }
  }

  Future<Uint8List> _range(int offset, int length) async {
    final url = _finalUrl ?? _url;
    final res = await _client
        .send(http.Request('GET', url)
          ..headers['Range'] = 'bytes=$offset-${offset + length - 1}')
        .timeout(_timeout);
    if (res.statusCode != 206) {
      unawaited(res.stream.listen(null).cancel());
      // Past the end of the file, or a server that only sends it whole.
      if (res.statusCode == 416 || res.statusCode == 200) return Uint8List(0);
      throw HttpException('HTTP ${res.statusCode}', uri: url);
    }
    final out = BytesBuilder(copy: false);
    await for (final chunk in res.stream.timeout(_timeout)) {
      out.add(chunk);
      if (out.length >= length) break;
    }
    final bytes = out.takeBytes();
    return bytes.length > length ? Uint8List.sublistView(bytes, 0, length) : bytes;
  }

  @override
  Future<void> close() async {
    unawaited(_body?.cancel());
    _client.close();
  }
}

// ── MP3: ID3v2 ──────────────────────────────────────────────────────────────

Future<List<FileChapter>> _id3(_Source src, Uint8List header) async {
  final version = header[3];
  final size = _synchsafe(header, 6);
  if (version < 3 || version > 4 || size == 0 || size > _maxTagBytes) {
    return const [];
  }
  final tag = await src.read(10, size);
  if (tag.length < size) throw const FormatException('ID3 tag cut short');
  return _id3Chapters(tag, version == 4, header[5]);
}

List<FileChapter> _id3Chapters(Uint8List d, bool v4, int flags) {
  int frameSize(int at) => v4 ? _synchsafe(d, at) : _u32(d, at);

  var pos = 0;
  if ((flags & 0x40) != 0 && d.length >= 4) {
    // Extended header: v2.4's size counts itself, v2.3's leaves out its 4 bytes.
    pos = v4 ? _synchsafe(d, 0) : _u32(d, 0) + 4;
  }

  Uint8List? cover; // the file's own artwork
  final chapters = <FileChapter>[];
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
  return _finish(chapters, cover);
}

/// One CHAP frame: element ID, start/end time and byte offsets, sub-frames.
FileChapter? _chap(Uint8List d, int pos, int end, int Function(int) frameSize) {
  while (pos < end && d[pos] != 0) { pos++; } // element ID
  pos++;
  if (pos + 16 > end) return null;
  final startMs = _u32(d, pos);
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
  final String s;
  switch (enc) {
    case 1 || 2:
      final bom = enc == 1 && b.length >= 2;
      if (bom && b[0] == 0xFF && b[1] == 0xFE) {
        s = _utf16(b, 2, bigEndian: false);
      } else if (bom && b[0] == 0xFE && b[1] == 0xFF) {
        s = _utf16(b, 2, bigEndian: true);
      } else {
        s = _utf16(b, 0, bigEndian: enc == 2);
      }
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
  return pos < end ? d.sublist(pos, end) : null;
}

// ── M4A: QuickTime chapter track, Nero chapters ─────────────────────────────

/// A box's type and contents, after its header.
typedef _Box = ({String type, int start, int end});

/// Where a sample is in the file and when it starts.
typedef _Sample = ({int ms, int offset, int size});

Future<List<FileChapter>> _mp4(_Source src) async {
  final moov = await _moov(src);
  if (moov == null) return const [];
  final tracks = <int, _Track>{};
  var nero = <FileChapter>[];
  Uint8List? cover;
  for (final b in _boxes(moov, 0, moov.length)) {
    if (b.type == 'trak') {
      final t = _track(moov, b);
      tracks[t.id] = t;
    } else if (b.type == 'udta') {
      final chpl = _child(moov, b, 'chpl');
      if (chpl != null) nero = _nero(moov, chpl);
      cover = _cover(moov, b);
    }
  }
  // Tracks another one names as its chapters: titles in a text track,
  // pictures in a video track.
  final named = {for (final t in tracks.values) ...t.chapters}
      .map((id) => tracks[id])
      .nonNulls;
  final text = named.where((t) => t.handler != 'vide' && t.handler != 'soun').firstOrNull;
  final video = named.where((t) => t.handler == 'vide').firstOrNull;
  final fromTrack =
      text == null ? const <FileChapter>[] : await _trackChapters(src, text, video);
  return _finish(fromTrack.isNotEmpty ? fromTrack : nero, cover);
}

/// The contents of the top-level moov box, or null.
Future<Uint8List?> _moov(_Source src) async {
  var pos = 0;
  for (var i = 0; i < 64; i++) {
    final h = await src.read(pos, 16);
    if (h.length < 8) return null;
    var size = _u32(h, 0), header = 8;
    if (size == 1 && h.length == 16) {
      size = _u64(h, 8);
      header = 16;
    }
    if (size < header) return null; // 0: runs to the end of the file
    if (_is(h, 4, 'moov')) {
      if (size > _maxIndexBytes) return null;
      final body = await src.read(pos + header, size - header);
      if (body.length < size - header) throw const FormatException('moov cut short');
      return body;
    }
    pos += size;
  }
  return null;
}

Iterable<_Box> _boxes(Uint8List d, int start, int end) sync* {
  var p = start;
  while (p + 8 <= end) {
    var size = _u32(d, p), header = 8;
    if (size == 1) {
      if (p + 16 > end) return;
      size = _u64(d, p + 8);
      header = 16;
    } else if (size == 0) {
      size = end - p;
    }
    if (size < header || size > end - p) return;
    yield (type: String.fromCharCodes(d, p + 4, p + 8), start: p + header, end: p + size);
    p += size;
  }
}

_Box? _child(Uint8List d, _Box parent, String type, {int skip = 0}) {
  for (final b in _boxes(d, parent.start + skip, parent.end)) {
    if (b.type == type) return b;
  }
  return null;
}

class _Track {
  _Track(this.d);
  final Uint8List d;
  int id = 0, timescale = 0;
  String handler = '';
  List<int> chapters = const []; // IDs of the tracks with its chapters
  _Box? stts, stsc, stsz, stco;
  bool co64 = false;

  bool _has(_Box b, int at, int width) => b.start + at + width <= b.end;

  /// The track's samples, at most [_maxChapters].
  List<_Sample> samples() {
    final stts = this.stts, stsc = this.stsc, stsz = this.stsz, stco = this.stco;
    if (stts == null || stsc == null || stsz == null || stco == null ||
        timescale == 0 || !_has(stsz, 4, 8) || !_has(stts, 4, 4) ||
        !_has(stsc, 4, 4) || !_has(stco, 4, 4)) {
      return const [];
    }
    // Each table: version and flags, entry count, then the entries.
    final fixedSize = _u32(d, stsz.start + 4);
    final count = min(_u32(d, stsz.start + 8), _maxChapters);
    int sizeOf(int i) => fixedSize != 0
        ? fixedSize
        : _has(stsz, 12 + 4 * i, 4) ? _u32(d, stsz.start + 12 + 4 * i) : 0;

    final starts = <int>[];
    var time = 0;
    final timeEntries = _u32(d, stts.start + 4);
    for (var e = 0; e < timeEntries && starts.length < count && _has(stts, 8 + 8 * e, 8); e++) {
      final n = _u32(d, stts.start + 8 + 8 * e), delta = _u32(d, stts.start + 12 + 8 * e);
      for (var k = 0; k < n && starts.length < count; k++) {
        starts.add(time * 1000 ~/ timescale);
        time += delta;
      }
    }

    final width = co64 ? 8 : 4;
    final chunks = _u32(d, stco.start + 4);
    int? chunkOffset(int c) => c < chunks && _has(stco, 8 + width * c, width)
        ? (co64 ? _u64(d, stco.start + 8 + 8 * c) : _u32(d, stco.start + 8 + 4 * c))
        : null;

    // Sample-to-chunk runs: from this chunk on, this many samples each.
    final out = <_Sample>[];
    final runs = _u32(d, stsc.start + 4);
    for (var e = 0; e < runs && out.length < count && _has(stsc, 8 + 12 * e, 12); e++) {
      final first = max(_u32(d, stsc.start + 8 + 12 * e) - 1, 0);
      final perChunk = _u32(d, stsc.start + 12 + 12 * e);
      final next = e + 1 < runs && _has(stsc, 20 + 12 * e, 4)
          ? _u32(d, stsc.start + 20 + 12 * e) - 1
          : chunks;
      for (var c = first; c < next && out.length < count; c++) {
        var offset = chunkOffset(c);
        if (offset == null) break;
        for (var k = 0; k < perChunk && out.length < count; k++) {
          final i = out.length, size = sizeOf(i);
          out.add((ms: i < starts.length ? starts[i] : 0, offset: offset!, size: size));
          offset += size;
        }
      }
    }
    return out;
  }
}

_Track _track(Uint8List d, _Box trak) {
  final t = _Track(d);
  for (final b in _boxes(d, trak.start, trak.end)) {
    switch (b.type) {
      case 'tkhd':
        t.id = _afterTimes(d, b) ?? 0;
      case 'tref':
        final chap = _child(d, b, 'chap');
        if (chap != null) {
          t.chapters = [for (var p = chap.start; p + 4 <= chap.end; p += 4) _u32(d, p)];
        }
      case 'mdia':
        for (final m in _boxes(d, b.start, b.end)) {
          switch (m.type) {
            case 'mdhd':
              t.timescale = _afterTimes(d, m) ?? 0;
            case 'hdlr':
              if (m.start + 12 <= m.end) {
                t.handler = String.fromCharCodes(d, m.start + 8, m.start + 12);
              }
            case 'minf':
              final stbl = _child(d, m, 'stbl');
              if (stbl == null) break;
              for (final s in _boxes(d, stbl.start, stbl.end)) {
                switch (s.type) {
                  case 'stts': t.stts = s;
                  case 'stsc': t.stsc = s;
                  case 'stsz': t.stsz = s;
                  case 'stco': t.stco = s;
                  case 'co64': t.stco = s; t.co64 = true;
                }
              }
          }
        }
    }
  }
  return t;
}

/// The field after a tkhd's or mdhd's creation and modification times (the
/// track ID, the timescale): those are 4 bytes each in version 0, 8 in 1.
int? _afterTimes(Uint8List d, _Box b) {
  if (b.end - b.start < 4) return null;
  final at = b.start + 4 + (d[b.start] == 1 ? 16 : 8);
  return at + 4 <= b.end ? _u32(d, at) : null;
}

/// Chapters from a text track's samples (a 2-byte length, then the title),
/// each with the picture the video track shows by then. Untitled samples
/// only fill gaps (the track has to cover the whole timeline): left out.
Future<List<FileChapter>> _trackChapters(
    _Source src, _Track text, _Track? video) async {
  final titles = text.samples();
  if (titles.isEmpty) return const [];
  final pictures = video?.samples() ?? const <_Sample>[];
  _Sample? pictureAt(int ms) {
    _Sample? shown;
    for (final p in pictures) {
      if (p.ms > ms + 1000) break;
      shown = p;
    }
    return shown;
  }

  final chosen = [for (final t in titles) pictureAt(t.ms)];
  final data = await _readSamples(src, [...titles, ...chosen.nonNulls]);
  return [
    for (var i = 0; i < titles.length; i++)
      if (_sampleText(data[titles[i].offset]) case final title
          when title.isNotEmpty)
        (
          startMs: titles[i].ms,
          title: title,
          image: _picture(data[chosen[i]?.offset]),
        ),
  ];
}

/// The bytes of each sample, by offset. Neighbours are read together, so a
/// chapter track takes a few requests rather than one per chapter.
Future<Map<int, Uint8List>> _readSamples(_Source src, List<_Sample> samples) async {
  final sorted = samples.where((s) => s.size > 0 && s.size <= 4 << 20).toSet().toList()
    ..sort((a, b) => a.offset.compareTo(b.offset));
  final out = <int, Uint8List>{};
  var total = 0;
  for (var i = 0; i < sorted.length;) {
    final start = sorted[i].offset;
    var end = start + sorted[i].size, j = i + 1;
    while (j < sorted.length &&
        sorted[j].offset - end <= 64 << 10 &&
        sorted[j].offset + sorted[j].size - start <= 8 << 20) {
      end = max(end, sorted[j].offset + sorted[j].size);
      j++;
    }
    total += end - start;
    if (total > _maxSampleBytes) break;
    final run = await src.read(start, end - start);
    for (final s in sorted.sublist(i, j)) {
      final at = s.offset - start;
      if (at + s.size <= run.length) {
        out[s.offset] = Uint8List.sublistView(run, at, at + s.size);
      }
    }
    i = j;
  }
  return out;
}

String _sampleText(Uint8List? b) {
  if (b == null || b.length < 2) return '';
  final t = Uint8List.sublistView(b, 2, 2 + min(b[0] << 8 | b[1], b.length - 2));
  if (t.length >= 2 && t[0] == 0xFE && t[1] == 0xFF) {
    return _utf16(t, 2, bigEndian: true).trim();
  }
  if (t.length >= 2 && t[0] == 0xFF && t[1] == 0xFE) {
    return _utf16(t, 2, bigEndian: false).trim();
  }
  return utf8.decode(t, allowMalformed: true).trim();
}

/// JPEG or PNG data, copied out of the larger read it came in.
Uint8List? _picture(Uint8List? b) {
  if (b == null || b.length < 8) return null;
  final jpeg = b[0] == 0xFF && b[1] == 0xD8;
  final png = b[0] == 0x89 && _is(b, 1, 'PNG');
  return jpeg || png ? Uint8List.fromList(b) : null;
}

/// Nero chapters: version, flags (and 4 more bytes if versioned), a count,
/// then each start in 100 ns units and a length-prefixed UTF-8 title.
List<FileChapter> _nero(Uint8List d, _Box chpl) {
  var p = chpl.start;
  final end = chpl.end;
  if (p + 5 > end) return [];
  p += d[p] != 0 ? 8 : 4;
  if (p >= end) return [];
  final n = d[p++];
  final out = <FileChapter>[];
  for (var i = 0; i < n && p + 9 <= end; i++) {
    final start = _u64(d, p);
    final len = d[p + 8];
    p += 9;
    if (p + len > end) break;
    final title = utf8.decode(Uint8List.sublistView(d, p, p + len), allowMalformed: true);
    out.add((startMs: start ~/ 10000, title: title.trim(), image: null));
    p += len;
  }
  return out;
}

/// The artwork in an M4A's iTunes metadata (udta/meta/ilst/covr).
Uint8List? _cover(Uint8List d, _Box udta) {
  final meta = _child(d, udta, 'meta');
  if (meta == null) return null;
  // meta is a full box (version and flags first), except in some files.
  final ilst = _child(d, meta, 'ilst', skip: 4) ?? _child(d, meta, 'ilst');
  final covr = ilst == null ? null : _child(d, ilst, 'covr');
  final data = covr == null ? null : _child(d, covr, 'data');
  if (data == null || data.end - data.start <= 8) return null;
  return Uint8List.sublistView(d, data.start + 8, data.end); // after type, locale
}

// ── Ogg (Opus, Vorbis), FLAC: Vorbis comments ───────────────────────────────

/// The Ogg stream's second packet holds its comments: reassembled from the
/// pages of the first logical stream.
Future<List<FileChapter>> _ogg(_Source src) async {
  final packet = BytesBuilder(copy: false);
  var pos = 0, serial = -1, packets = 0;
  for (var page = 0; page < 1024; page++) {
    final h = await src.read(pos, 27);
    if (h.length < 27 || !_is(h, 0, 'OggS')) return const [];
    final segments = await src.read(pos + 27, h[26]);
    final size = segments.fold(0, (a, b) => a + b);
    final body = await src.read(pos + 27 + h[26], size);
    if (segments.length < h[26] || body.length < size) return const [];
    pos += 27 + h[26] + size;
    final s = _u32le(h, 14);
    if (serial == -1) serial = s;
    if (s != serial) continue;
    var at = 0;
    for (final len in segments) {
      packet.add(Uint8List.sublistView(body, at, at + len));
      at += len;
      if (packet.length > _maxTagBytes) return const [];
      if (len < 255 && ++packets == 2) {
        return _finish(_commentChapters(packet.takeBytes()));
      }
      if (len < 255) packet.clear();
    }
  }
  return const [];
}

/// Opus's or Vorbis's comment header, or FLAC-in-Ogg's comment block.
List<FileChapter> _commentChapters(Uint8List d) {
  if (_is(d, 0, 'OpusTags')) return _vorbisChapters(d, 8);
  if (d.length > 7 && d[0] == 3 && _is(d, 1, 'vorbis')) return _vorbisChapters(d, 7);
  if (d.length > 4 && (d[0] & 0x7F) == 4) return _vorbisChapters(d, 4);
  return const [];
}

/// FLAC's metadata blocks follow "fLaC"; the comments are block type 4.
Future<List<FileChapter>> _flac(_Source src) async {
  var pos = 4;
  for (var i = 0; i < 128; i++) {
    final h = await src.read(pos, 4);
    if (h.length < 4) return const [];
    final size = h[1] << 16 | h[2] << 8 | h[3];
    if ((h[0] & 0x7F) == 4) {
      if (size > _maxTagBytes) return const [];
      final block = await src.read(pos + 4, size);
      return block.length < size ? const [] : _finish(_vorbisChapters(block, 0));
    }
    if ((h[0] & 0x80) != 0) return const []; // that was the last block
    pos += 4 + size;
  }
  return const [];
}

final _chapterKey = RegExp(r'^CHAPTER(\d+)(NAME)?$');

/// Vendor string, then KEY=value entries, all little-endian length-prefixed:
/// CHAPTER001=00:00:00.000, CHAPTER001NAME=Title.
List<FileChapter> _vorbisChapters(Uint8List d, int p) {
  if (p + 4 > d.length) return const [];
  p += 4 + _u32le(d, p);
  if (p + 4 > d.length) return const [];
  final count = _u32le(d, p);
  p += 4;
  final starts = <int, int>{}, names = <int, String>{};
  for (var i = 0; i < count && p + 4 <= d.length; i++) {
    final len = _u32le(d, p);
    p += 4;
    if (len > d.length - p) break;
    final entry = utf8.decode(Uint8List.sublistView(d, p, p + len), allowMalformed: true);
    p += len;
    final eq = entry.indexOf('=');
    final m = eq < 0 ? null : _chapterKey.firstMatch(entry.substring(0, eq).toUpperCase());
    if (m == null) continue;
    final n = int.parse(m.group(1)!);
    final value = entry.substring(eq + 1).trim();
    if (m.group(2) != null) {
      names[n] = value;
    } else if (parseClockTime(value) case final s?) {
      starts[n] = (s * 1000).round();
    }
  }
  return [
    for (final MapEntry(key: n, value: ms) in starts.entries)
      (startMs: ms, title: names[n] ?? '', image: null),
  ];
}

/// Seconds from "HH:MM:SS.mmm", "MM:SS" or plain seconds, the chapter times
/// of Vorbis comments and Podlove feeds; null if it's none of these.
double? parseClockTime(String s) {
  var t = s.trim();
  if (t.startsWith('npt:')) t = t.substring(4);
  final parts = t.split(':');
  if (parts.length > 3) return null;
  var seconds = 0.0;
  for (final p in parts) {
    final v = double.tryParse(p);
    if (v == null || v < 0 || !v.isFinite) return null;
    seconds = seconds * 60 + v;
  }
  return seconds;
}

// ── Bytes ───────────────────────────────────────────────────────────────────

bool _is(Uint8List b, int at, String ascii) {
  if (at + ascii.length > b.length) return false;
  for (var i = 0; i < ascii.length; i++) {
    if (b[at + i] != ascii.codeUnitAt(i)) return false;
  }
  return true;
}

String _utf16(Uint8List b, int from, {required bool bigEndian}) {
  final units = <int>[];
  for (var i = from; i + 1 < b.length; i += 2) {
    units.add(bigEndian ? b[i] << 8 | b[i + 1] : b[i] | b[i + 1] << 8);
  }
  return String.fromCharCodes(units);
}

int _synchsafe(List<int> b, int at) =>
    (b[at] & 0x7F) << 21 | (b[at + 1] & 0x7F) << 14 | (b[at + 2] & 0x7F) << 7 | (b[at + 3] & 0x7F);

int _u32(List<int> b, int at) =>
    b[at] << 24 | b[at + 1] << 16 | b[at + 2] << 8 | b[at + 3];

int _u64(List<int> b, int at) => _u32(b, at) << 32 | _u32(b, at + 4);

int _u32le(List<int> b, int at) =>
    b[at] | b[at + 1] << 8 | b[at + 2] << 16 | b[at + 3] << 24;
