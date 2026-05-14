// lib/ad_detection/ad_detection_service.dart
//
// Self-contained ad-detection module.  Entry point for the rest of the app.
//
// Call AdDetectionService.analyzeEpisode() after a download completes.
// It runs entirely in a background isolate and writes results to the Drift
// AdSegments table.  It never throws — all errors are swallowed and logged.
//
// The only two files outside this directory that change:
//   • app_database.dart  — adds AdSegments table (schema v6)
//   • download_provider.dart — one unawaited() call in _markComplete

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../app_database.dart';
import 'chapter_scanner.dart';
import 'mp3_scanner.dart';

// ─── Isolate data transfer objects (must be sendable) ─────────────────────────

class _Params {
  const _Params({
    required this.episodeId,
    required this.localPath,
    this.chaptersUrl,
  });
  final String episodeId;
  final String localPath;
  final String? chaptersUrl;
}

class _DetectedSegment {
  const _DetectedSegment({
    required this.startSeconds,
    required this.endSeconds,
    required this.confidence,
    required this.source,
  });
  final double startSeconds;
  final double endSeconds;
  final int confidence;   // 0-100
  final String source;    // 'chapters' | 'encoding' | 'silence'
}

// ─── Service ──────────────────────────────────────────────────────────────────

class AdDetectionService {
  const AdDetectionService(this._db);
  final AppDatabase _db;

  /// Analyse a downloaded episode and persist results.
  /// Fire-and-forget; caller should use `unawaited()`.
  Future<void> analyzeEpisode(Episode episode) async {
    if (episode.localPath == null) return;
    debugPrint('[AdDetect] ▶ starting analysis for "${episode.title}"');
    try {
      final segments = await compute(
        _runAnalysis,
        _Params(
          episodeId: episode.id,
          localPath: episode.localPath!,
          chaptersUrl: episode.chaptersUrl,
        ),
      );
      if (segments.isEmpty) {
        debugPrint('[AdDetect] ✓ "${episode.title}" — no ad segments found');
        return;
      }
      await _db.replaceAdSegments(
        episode.id,
        segments
            .map((s) => AdSegmentsCompanion.insert(
                  episodeId: episode.id,
                  startSeconds: s.startSeconds,
                  endSeconds: s.endSeconds,
                  confidence: s.confidence,
                  source: s.source,
                ))
            .toList(),
      );
      final details = segments.map((s) =>
          '  [${s.source}] ${s.startSeconds.toStringAsFixed(1)}s'
          '–${s.endSeconds.toStringAsFixed(1)}s'
          ' (${s.confidence}%)').join('\n');
      debugPrint('[AdDetect] ✓ "${episode.title}"'
          ' — ${segments.length} ad segment(s) found:\n$details');
    } catch (e) {
      debugPrint('[AdDetect] ✗ error for "${episode.title}": $e');
    }
  }
}

// ─── Isolate worker (top-level, no closures) ──────────────────────────────────

Future<List<_DetectedSegment>> _runAnalysis(_Params p) async {
  final results = <_DetectedSegment>[];

  // ── Phase 1: chapter-based (exact, free) ──────────────────────────────────
  if (p.chaptersUrl != null) {
    final chapters = await ChapterScanner.scan(p.chaptersUrl!);
    for (final ch in chapters) {
      results.add(_DetectedSegment(
        startSeconds: ch.startSeconds,
        endSeconds: ch.endSeconds,
        confidence: 95,
        source: 'chapters',
      ));
    }
  }

  // ── Phase 2: MP3 frame analysis ───────────────────────────────────────────
  final file = File(p.localPath);
  if (!file.existsSync()) return results;

  late final Mp3ScanResult scan;
  try {
    final bytes = await file.readAsBytes();
    scan = Mp3Scanner.scan(bytes);
  } catch (_) {
    return results;
  }

  // 2a. Encoding splice candidates:
  //     Each pair of consecutive splice points whose gap is a plausible ad
  //     length is a candidate segment.
  final spliceTimes = scan.spliceCandidates
      .map((c) => c.timestampSeconds)
      .toList();

  for (int i = 0; i < spliceTimes.length - 1; i++) {
    final dur = spliceTimes[i + 1] - spliceTimes[i];
    if (dur < 10 || dur > 120) continue;
    results.add(_DetectedSegment(
      startSeconds: spliceTimes[i],
      endSeconds: spliceTimes[i + 1],
      confidence: 70,
      source: 'encoding',
    ));
  }

  // 2b. Silence-bounded segments:
  //     Look for content regions between two silence gaps that match ad length.
  //     A gap after a splice candidate upgrades its confidence.
  final silences = scan.silenceRanges;
  for (int i = 0; i < silences.length - 1; i++) {
    final segStart = silences[i].endSeconds;
    final segEnd = silences[i + 1].startSeconds;
    final dur = segEnd - segStart;
    if (dur < 10 || dur > 120) continue;

    // Deduplicate: skip if already covered by an encoding-based segment.
    final alreadyCovered = results.any((r) =>
        (r.startSeconds - segStart).abs() < 5.0 &&
        (r.endSeconds - segEnd).abs() < 5.0);
    if (alreadyCovered) {
      // Upgrade confidence on the existing match instead.
      continue;
    }

    results.add(_DetectedSegment(
      startSeconds: segStart,
      endSeconds: segEnd,
      confidence: 60,
      source: 'silence',
    ));
  }

  return results;
}
