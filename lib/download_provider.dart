// lib/download_provider.dart
//
// Single source of truth for active download state, keyed by episodeId.
// Polls flutter_downloader's task DB every second while downloads are active.
// Polling is more robust than the IsolateNameServer callback, which silently
// drops messages.
// Also drives the single download notification (see download_notification.dart):
// it mirrors [_downloads] and disappears once that map is empty.
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app_database.dart';
import 'download_notification.dart';

class _EpDownload {
  final String taskId;
  final String title;
  final double progress;
  const _EpDownload(this.taskId, this.title, this.progress);
}

class DownloadProvider extends ChangeNotifier {
  final AppDatabase _db;
  // episodeId → active download state. Non-null means actively downloading.
  final Map<String, _EpDownload> _downloads = {};
  Timer? _pollTimer;

  DownloadProvider(this._db) {
    _reconcileTerminalTasks();
  }

  bool isDownloading(String episodeId) => _downloads.containsKey(episodeId);
  double? progressForEpisode(String episodeId) => _downloads[episodeId]?.progress;

  /// Call immediately after DownloadService.downloadEpisode() returns a taskId.
  void trackDownload(String taskId,
      {required String episodeId, required String title}) {
    _downloads[episodeId] = _EpDownload(taskId, title, 0.0);
    notifyListeners();
    _syncNotification();
    _ensurePolling();
  }

  /// Mirror the active downloads into the one notification; empty → gone.
  void _syncNotification() {
    DownloadNotification.update([
      for (final d in _downloads.values)
        DownloadNotificationItem(d.title, d.progress),
    ]);
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

    final taskProgress = <String, double>{
      for (final t in active ?? []) t.taskId: t.progress / 100.0,
    };

    bool changed = false;
    for (final entry in _downloads.entries.toList()) {
      final prog = taskProgress[entry.value.taskId];
      if (prog == null) {
        // Task left the active set → download finished or failed.
        final taskId = entry.value.taskId;
        final episodeId = entry.key;
        _downloads.remove(episodeId);
        await _markComplete(taskId, episodeId: episodeId);
        changed = true;
      } else if (entry.value.progress != prog) {
        final d = entry.value;
        _downloads[entry.key] = _EpDownload(d.taskId, d.title, prog);
        changed = true;
      }
    }

    if (_downloads.isEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
    if (changed) {
      notifyListeners();
      _syncNotification();
    }
  }

  // ── Mark complete ──────────────────────────────────────────────────────────

  Future<void> _markComplete(String taskId, {String? episodeId}) async {
    List<DownloadTask>? completedTasks;
    try {
      completedTasks = await FlutterDownloader.loadTasksWithRawQuery(
        query: "SELECT * FROM task WHERE task_id='$taskId' AND status=3",
      );
    } catch (_) {}

    if (completedTasks != null && completedTasks.isNotEmpty) {
      final task = completedTasks.first;
      final dir = await getApplicationDocumentsDirectory();
      final fullPath = p.join(dir.path, 'episodes', task.filename);
      final episode = await _findEpisode(episodeId: episodeId, taskId: taskId);
      if (episode != null && !episode.isDownloaded && File(fullPath).existsSync()) {
        await _db.updateEpisodeDownload(episode.id, true, fullPath, taskId);
      }
      await _removeTask(taskId);
      return;
    }

    // Task is gone but not completed (failed, WiFi dropped, etc.).
    final episode = await _findEpisode(episodeId: episodeId, taskId: taskId);
    if (episode != null && !episode.isDownloaded) {
      await _db.requeueEpisodeForDownload(episode.id);
      try {
        final tasks = await FlutterDownloader.loadTasksWithRawQuery(
          query: "SELECT * FROM task WHERE task_id='$taskId'",
        );
        final dir = await getApplicationDocumentsDirectory();
        final fileName = tasks != null && tasks.isNotEmpty
            ? tasks.first.filename
            : '${episode.id.replaceAll(RegExp(r'[^\w]'), '_')}.mp3';
        final file = File(p.join(dir.path, 'episodes', fileName));
        if (file.existsSync()) await file.delete();
      } catch (_) {}
      await _removeTask(taskId);
    }
  }

  Future<Episode?> _findEpisode({String? episodeId, required String taskId}) async {
    if (episodeId != null) {
      return (_db.select(_db.episodes)..where((e) => e.id.equals(episodeId)))
          .getSingleOrNull();
    }
    return (_db.select(_db.episodes)..where((e) => e.downloadTaskId.equals(taskId)))
        .getSingleOrNull();
  }

  /// Drop the finished task record (the file stays).
  Future<void> _removeTask(String taskId) async {
    try { await FlutterDownloader.remove(taskId: taskId, shouldDeleteContent: false); } catch (_) {}
  }

  // ── Cancel in-progress download ───────────────────────────────────────────

  /// Cancel by episodeId. Pass [fallbackTaskId] when the download was started
  /// in a previous session and may not be in the in-memory map.
  Future<void> cancelDownload(String episodeId, [String? fallbackTaskId]) async {
    final taskId = _downloads[episodeId]?.taskId ?? fallbackTaskId;
    if (taskId == null) return;

    String? taskFilename;
    try {
      final tasks = await FlutterDownloader.loadTasksWithRawQuery(
        query: "SELECT * FROM task WHERE task_id='$taskId'",
      );
      taskFilename = tasks?.firstOrNull?.filename;
    } catch (_) {}

    try { await FlutterDownloader.cancel(taskId: taskId); } catch (_) {}

    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = taskFilename ??
          '${episodeId.replaceAll(RegExp(r'[^\w]'), '_')}.mp3';
      final file = File(p.join(dir.path, 'episodes', fileName));
      if (file.existsSync()) await file.delete();
    } catch (_) {}

    await _db.updateEpisodeDownload(episodeId, false, null, null);

    _downloads.remove(episodeId);
    if (_downloads.isEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
    notifyListeners();
    _syncNotification();
  }

  // ── Startup reconciliation ─────────────────────────────────────────────────

  Future<void> _reconcileTerminalTasks() async {
    try {
      // Handle both completed (3) and failed (4) tasks left from a previous run.
      final tasks = await FlutterDownloader.loadTasksWithRawQuery(
        query: 'SELECT * FROM task WHERE status IN (3, 4)',
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
    DownloadNotification.clear();
    super.dispose();
  }
}
