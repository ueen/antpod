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

  // Cluster splice candidates into events: all splices within 5 s of each other
  // belong to one event.  A tight cluster at the same timestamp is a reliable
  // splice boundary; isolated VBR bitrate-change noise stays scattered.
  final events = _clusterSplices(scan.spliceCandidates, windowSeconds: 5.0);

  // For each pair of consecutive events, the gap between them is a candidate
  // ad segment.  Score confidence by:
  //   • base 60 for any encoding-based pair
  //   • +20 if the cluster contains a mode_change or samplerate_change (strong signals)
  //   • +15 if both events have ≥3 splice candidates (dense cluster = real splice)
  //   • +15 if duration is within 5 s of a standard ad length (15/30/60/90 s)
  //   • +8  if duration is within 15 s of a standard ad length
  // Capped at 88 (chapter detection at 95 stays strictly above encoding).
  for (int i = 0; i < events.length - 1; i++) {
    final segStart = events[i].centerSeconds;
    final segEnd   = events[i + 1].centerSeconds;
    final dur = segEnd - segStart;
    if (dur < 10 || dur > 130) continue;

    // Skip if already covered by a chapter-based result.
    final covered = results.any((r) =>
        (r.startSeconds - segStart).abs() < 8.0 &&
        (r.endSeconds   - segEnd).abs()   < 8.0);
    if (covered) continue;

    int conf = 60;
    if (events[i].hasStrongSignal || events[i + 1].hasStrongSignal) conf += 20;
    if (events[i].count >= 3 && events[i + 1].count >= 3) conf += 15;
    conf += _adLengthBonus(dur);

    results.add(_DetectedSegment(
      startSeconds: segStart,
      endSeconds:   segEnd,
      confidence:   conf.clamp(0, 88),
      source: 'encoding',
    ));
  }

  return results;
}

// ─── Splice-event clustering ──────────────────────────────────────────────────

class _SpliceEvent {
  _SpliceEvent(this.centerSeconds, this.count, this.hasStrongSignal);
  final double centerSeconds;
  final int count;
  final bool hasStrongSignal; // mode_change or samplerate_change present
}

List<_SpliceEvent> _clusterSplices(
  List<SpliceCandidate> candidates, {
  required double windowSeconds,
}) {
  if (candidates.isEmpty) return [];
  final events = <_SpliceEvent>[];
  int start = 0;
  while (start < candidates.length) {
    int end = start;
    bool strong = false;
    double sum = 0;
    while (end < candidates.length &&
        candidates[end].timestampSeconds - candidates[start].timestampSeconds <= windowSeconds) {
      sum += candidates[end].timestampSeconds;
      if (candidates[end].reason == 'mode_change' ||
          candidates[end].reason == 'samplerate_change') { strong = true; }
      end++;
    }
    final count = end - start;
    events.add(_SpliceEvent(sum / count, count, strong));
    start = end;
  }
  return events;
}

// ─── Ad-length duration bonus ─────────────────────────────────────────────────

int _adLengthBonus(double dur) {
  const targets = [15.0, 30.0, 60.0, 90.0];
  double minDist = double.infinity;
  for (final t in targets) {
    final d = (dur - t).abs();
    if (d < minDist) minDist = d;
  }
  if (minDist <= 5)  return 15;
  if (minDist <= 15) return 8;
  return 0;
}
