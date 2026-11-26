// lib/chapters.dart
//
// An episode's chapters can come from the feed or from the audio file.
//
//   Feed  a podcast:chapters JSON file (Podcasting 2.0), else Podlove Simple
//         Chapters listed in the item itself; those are kept as a data: URI
//         holding the same JSON, so both load the same way.
//   File  what the audio carries (see file_chapters.dart): ID3 in MP3s,
//         chapter tracks in M4As, Vorbis comments in Ogg, Opus and FLAC.
//
// Feed chapters are small and quick, so they show first. The file's take
// over once read: they describe the audio actually played, while hosts with
// dynamic ad insertion shift the audio (and its tag) but not the feed. Where
// one has what the other lacks, a title or a picture, the two are merged.
//
// Episodes with neither often list timestamps in their show notes; those
// make the chapters then (see notesChapters).

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'file_chapters.dart';
import 'html_utils.dart';

class PodcastChapter {
  final String title;
  final double startTimeSeconds;
  final String? imageUrl;
  /// Picture embedded in the audio file; wins over [imageUrl].
  final Uint8List? imageBytes;
  const PodcastChapter({
    required this.title,
    required this.startTimeSeconds,
    this.imageUrl,
    this.imageBytes,
  });
}

/// The chapters behind an episode's chaptersUrl: a podcast:chapters JSON
/// file, or the data: URI made by [podloveChaptersUri]. Null when they
/// couldn't be loaded (worth retrying).
Future<List<PodcastChapter>?> loadFeedChapters(String url) async {
  try {
    final String body;
    if (url.startsWith('data:')) {
      body = UriData.parse(url).contentAsString();
    } else {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'AntPod/1.0',
      }).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      body = utf8.decode(res.bodyBytes, allowMalformed: true);
    }
    final list = (jsonDecode(body) as Map<String, dynamic>)['chapters'];
    if (list is! List) return const [];
    return [
      for (final c in list)
        if (c is Map && c['toc'] != false)
          if (_seconds(c['startTime']) case final start?)
            PodcastChapter(
              title: '${c['title'] ?? ''}'.trim(),
              startTimeSeconds: start,
              imageUrl: c['img'] is String && (c['img'] as String).trim().isNotEmpty
                  ? (c['img'] as String).trim()
                  : null,
            ),
    ]..sort((a, b) => a.startTimeSeconds.compareTo(b.startTimeSeconds));
  } catch (e) {
    debugPrint('[chapters] ${url.length > 80 ? url.substring(0, 80) : url}: $e');
    return null;
  }
}

/// Seconds as a JSON number, or a string in either form.
double? _seconds(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => parseClockTime(s),
      _ => null,
    };

final _pscChapter = RegExp(r'''<psc:chapter\b((?:[^>"']|"[^"]*"|'[^']*')*)>''');
final _attribute = RegExp(r'''([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');

/// The Podlove Simple Chapters in one feed item's XML, as a data: URI of
/// the equivalent podcast:chapters JSON; null when it has none.
String? podloveChaptersUri(String itemXml) {
  final chapters = <Map<String, Object>>[];
  for (final m in _pscChapter.allMatches(itemXml)) {
    final a = {
      for (final x in _attribute.allMatches(m.group(1)!))
        x.group(1)!: _unescape(x.group(2) ?? x.group(3)!).trim(),
    };
    final start = parseClockTime(a['start'] ?? '');
    if (start == null) continue;
    chapters.add({
      'startTime': start,
      'title': a['title'] ?? '',
      if (a['image']?.isNotEmpty ?? false) 'img': a['image']!,
      if (a['href']?.isNotEmpty ?? false) 'url': a['href']!,
    });
  }
  if (chapters.isEmpty) return null;
  return UriData.fromString(
    jsonEncode({'version': '1.2.0', 'chapters': chapters}),
    mimeType: 'application/json+chapters',
    encoding: utf8,
    base64: true,
  ).toString();
}

final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);');

String _unescape(String s) => s.replaceAllMapped(_entity, (m) {
      final e = m.group(1)!;
      switch (e) {
        case 'amp': return '&';
        case 'lt': return '<';
        case 'gt': return '>';
        case 'quot': return '"';
        case 'apos': return "'";
      }
      final code = e.startsWith('#x')
          ? int.tryParse(e.substring(2), radix: 16)
          : int.tryParse(e.substring(1));
      return code != null && code > 0 && code <= 0x10FFFF
          ? String.fromCharCode(code)
          : m.group(0)!;
    });

/// One list from the feed's chapters and the file's, either possibly
/// missing. The same number of chapters means the same chapters: times come
/// from the file, titles and pictures from the file, else the feed. Otherwise
/// one list is taken whole: the one with pictures, else the file's.
/// Untitled chapters are left out, and a single chapter isn't a list of
/// chapters: an editor's cue mark carried into the tag ("Marker 1 - 1",
/// 0.4 s long, in Talk ohne Gast's MP3s) next to untitled ones.
List<PodcastChapter> mergeChapters(
    List<PodcastChapter>? feed, List<FileChapter>? file) {
  final fromFile = [
    for (final c in file ?? const <FileChapter>[])
      PodcastChapter(
          title: c.title, startTimeSeconds: c.startMs / 1000, imageBytes: c.image),
  ];
  final fromFeed = feed ?? const <PodcastChapter>[];

  final List<PodcastChapter> merged;
  if (fromFile.isEmpty || fromFeed.isEmpty) {
    merged = fromFile.isEmpty ? fromFeed : fromFile;
  } else if (fromFile.length == fromFeed.length) {
    merged = [
      for (var i = 0; i < fromFile.length; i++)
        PodcastChapter(
          title: fromFile[i].title.isNotEmpty ? fromFile[i].title : fromFeed[i].title,
          startTimeSeconds: fromFile[i].startTimeSeconds,
          imageBytes: fromFile[i].imageBytes,
          imageUrl: fromFile[i].imageBytes == null ? fromFeed[i].imageUrl : null,
        ),
    ];
  } else {
    final filePictures = fromFile.any((c) => c.imageBytes != null);
    final feedPictures = fromFeed.any((c) => c.imageUrl != null);
    merged = feedPictures && !filePictures ? fromFeed : fromFile;
  }
  final titled = merged.where((c) => c.title.isNotEmpty).toList();
  return titled.length >= 2 ? titled : const [];
}

// A line opening with a timestamp, "1:02:03", "12:34", "(12:34)", "[12:34]",
// "▶ 12:34", then the title; whatever isn't a letter or digit around the time
// is skipped ("(01:20) - Title"). A range's end is skipped too ("00:00:00 –
// 00:02:12 – Title", "00:22:33 – End – Title"). A letter right after the
// time ("20:15h") means it isn't one; so does a clock word after it, see
// [_clockWord].
final _notesLine = RegExp(
    r'^[^\p{L}\p{N}]*(?:(\d{1,2}):)?(\d{1,3}):(\d{2})(?![\p{L}\p{N}_]|:\d)'
    r'(?:\s*[\-–—~]\s*(?:(?:\d{1,2}:)?\d{1,3}:\d{2}(?![\p{L}\p{N}_]|:\d)'
    r'|[Ee]nde?(?=\s*[\-–—:|])))?'
    // An opening bracket or quote belongs to the title.
    r'''[^\p{L}\p{N}(\["'“„‚‘«¿¡]*(.+)$''',
    unicode: true);
// A time of day: "20:15 Uhr", "8:30 am" (but "Am Ende" is a title).
final _clockWord = RegExp(r"^(?:uhr|h|a\.m\.|p\.m\.|o'?clock)(?!\p{L})",
    caseSensitive: false, unicode: true);
final _amPm = RegExp(r'^(?:am|pm|AM|PM)(?!\p{L})', unicode: true);
final _hasWord = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Chapters from timestamps listed in the show notes, one per line: at
/// least three, in order, all within [durationSeconds] when that's known.
/// Empty when the notes don't have such a list. Time going back starts
/// another list (some notes list the chapters twice, as ranges and again as
/// starts; or a time of day stands before them): the longest one counts, the
/// last of equally long ones.
List<PodcastChapter> notesChapters(String description, int durationSeconds) {
  if (!description.contains(':')) return const [];
  // Timestamps are often links (to the web player's position): keep the text.
  final text = htmlToText(
      description.replaceAll(RegExp(r'</?a\b[^>]*>', caseSensitive: false), ''));
  var best = const <PodcastChapter>[];
  var chapters = <PodcastChapter>[];
  void endList() {
    final fits = durationSeconds <= 0 ||
        chapters.last.startTimeSeconds < durationSeconds;
    if (chapters.length >= 3 && fits && chapters.length >= best.length) {
      best = chapters;
    }
    chapters = [];
  }
  for (final line in text.split('\n')) {
    final m = _notesLine.firstMatch(line.trim());
    if (m == null) continue;
    final h = int.parse(m.group(1) ?? '0');
    final min = int.parse(m.group(2)!);
    final sec = int.parse(m.group(3)!);
    if (sec >= 60 || (m.group(1) != null && min >= 60)) continue;
    var title = m.group(4)!.trim();
    if (_clockWord.hasMatch(title) || _amPm.hasMatch(title)) continue;
    if (!_hasWord.hasMatch(title)) continue;
    if (title.length > 120) title = '${title.substring(0, 119)}…';
    final start = (h * 3600 + min * 60 + sec).toDouble();
    if (chapters.isNotEmpty && start <= chapters.last.startTimeSeconds) {
      endList();
    }
    chapters.add(PodcastChapter(title: title, startTimeSeconds: start));
  }
  if (chapters.isNotEmpty) endList();
  return best;
}
