// lib/download_provider.dart
//
// Tracks download progress by polling flutter_downloader's task DB every
// second while downloads are active. This is more robust than the
// IsolateNameServer callback, which can silently drop messages.
//
// Usage:
//   After calling DownloadService.downloadEpisode(), call trackDownload(taskId)
//   so the ring appears immediately at 0% before the first poll.
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app_database.dart';

class DownloadProvider extends ChangeNotifier {
  final AppDatabase _db;
  final Map<String, double> _progress = {}; // taskId → 0.0..1.0
  Timer? _pollTimer;

  DownloadProvider(this._db) {
    _reconcileCompletedDownloads();
  }

  /// Progress for a task (0.0–1.0), or null if not actively downloading.
  double? progressForTask(String? taskId) =>
      taskId == null ? null : _progress[taskId];

  /// Call this immediately after DownloadService.downloadEpisode() returns
  /// a taskId. Shows the ring at 0% right away and starts polling.
  void trackDownload(String taskId) {
    _progress[taskId] = 0.0;
    notifyListeners();
    _ensurePolling();
  }

  // ── Polling ────────────────────────────────────────────────────────────────

  void _ensurePolling() {
    if (_pollTimer?.isActive == true) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  Future<void> _poll() async {
    List<DownloadTask>? active;
    try {
      active = await FlutterDownloader.loadTasksWithRawQuery(
        query: 'SELECT * FROM task WHERE status IN (1, 2)',
      );
    } catch (_) {
      return;
    }

    bool changed = false;
    final activeIds = <String>{};

    for (final task in active ?? []) {
      activeIds.add(task.taskId);
      final prog = task.progress / 100.0;
      if (_progress[task.taskId] != prog) {
        _progress[task.taskId] = prog;
        changed = true;
      }
    }

    // Any taskId we were tracking that is no longer active has finished
    for (final taskId in _progress.keys.toList()) {
      if (!activeIds.contains(taskId)) {
        _progress.remove(taskId);
        await _markComplete(taskId);
        changed = true;
      }
    }

    if (_progress.isEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }

    if (changed) notifyListeners();
  }

  // ── Mark complete in our DB ────────────────────────────────────────────────

  Future<void> _markComplete(String taskId) async {
    // Verify the task actually completed (not failed/cancelled)
    List<DownloadTask>? tasks;
    try {
      tasks = await FlutterDownloader.loadTasksWithRawQuery(
        query: "SELECT * FROM task WHERE task_id='$taskId' AND status=3",
      );
    } catch (_) {}
    if (tasks == null || tasks.isEmpty) return;

    final dir = await getApplicationDocumentsDirectory();
    final saveDir = p.join(dir.path, 'episodes');
    final episode = await (_db.select(_db.episodes)
          ..where((e) => e.downloadTaskId.equals(taskId)))
        .getSingleOrNull();
    if (episode != null && !episode.isDownloaded) {
      final fileName =
          '${episode.id.replaceAll(RegExp(r'[^\w]'), '_')}.mp3';
      final fullPath = p.join(saveDir, fileName);
      if (File(fullPath).existsSync()) {
        await _db.updateEpisodeDownload(episode.id, true, fullPath, taskId);
      }
    }
  }

  // ── Startup reconciliation ─────────────────────────────────────────────────

  Future<void> _reconcileCompletedDownloads() async {
    try {
      final tasks = await FlutterDownloader.loadTasksWithRawQuery(
        query: 'SELECT * FROM task WHERE status=3',
      );
      if (tasks == null || tasks.isEmpty) return;
      for (final task in tasks) {
        await _markComplete(task.taskId);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
