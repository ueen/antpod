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
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app_database.dart';

class DownloadProvider extends ChangeNotifier {
  static const _notifChannel = MethodChannel('de.ueen.antpod/notifications');

  final AppDatabase _db;
  final Map<String, double> _progress = {}; // taskId → 0.0..1.0
  final Map<String, String> _episodeTask = {}; // episodeId → taskId
  Timer? _pollTimer;

  DownloadProvider(this._db) {
    _reconcileCompletedDownloads();
  }

  /// Progress for a task (0.0–1.0), or null if not actively downloading.
  double? progressForTask(String? taskId) =>
      taskId == null ? null : _progress[taskId];

  /// Progress by episodeId — fast path before the DB stream emits the new taskId.
  double? progressForEpisode(String episodeId) =>
      progressForTask(_episodeTask[episodeId]);

  /// Task ID for an episode — useful when the DB field hasn't synced yet.
  String? taskIdForEpisode(String episodeId) => _episodeTask[episodeId];

  /// Call this immediately after DownloadService.downloadEpisode() returns
  /// a taskId. Shows the ring at 0% right away and starts polling.
  void trackDownload(String taskId, {String? episodeId}) {
    _progress[taskId] = 0.0;
    if (episodeId != null) _episodeTask[episodeId] = taskId;
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
        _episodeTask.removeWhere((_, v) => v == taskId);
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
    List<DownloadTask>? completedTasks;
    try {
      completedTasks = await FlutterDownloader.loadTasksWithRawQuery(
        query: "SELECT * FROM task WHERE task_id='$taskId' AND status=3",
      );
    } catch (_) {}

    if (completedTasks != null && completedTasks.isNotEmpty) {
      // Download completed successfully — update DB using the actual filename.
      final task = completedTasks.first;
      final dir = await getApplicationDocumentsDirectory();
      final saveDir = p.join(dir.path, 'episodes');
      final fullPath = p.join(saveDir, task.filename);
      final episode = await (_db.select(_db.episodes)
            ..where((e) => e.downloadTaskId.equals(taskId)))
          .getSingleOrNull();
      if (episode != null && !episode.isDownloaded && File(fullPath).existsSync()) {
        await _db.updateEpisodeDownload(episode.id, true, fullPath, taskId);
      }
      // Dismiss the OS notification for this completed download.
      try { await FlutterDownloader.remove(taskId: taskId, shouldDeleteContent: false); } catch (_) {}
      try { await _notifChannel.invokeMethod('dismissDownloadNotifications'); } catch (_) {}
      return;
    }

    // Task is gone but not completed (failed, WiFi dropped, etc.).
    // Re-queue immediately so the dotted-bar state is restored in this session
    // rather than waiting until the next app restart.
    final episode = await (_db.select(_db.episodes)
          ..where((e) => e.downloadTaskId.equals(taskId)))
        .getSingleOrNull();
    if (episode != null && !episode.isDownloaded) {
      await _db.requeueEpisodeForDownload(episode.id);
      // Try to delete any partial file — query task for the actual filename first.
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
      // Dismiss notification for failed download.
      try { await FlutterDownloader.remove(taskId: taskId, shouldDeleteContent: false); } catch (_) {}
      try { await _notifChannel.invokeMethod('dismissDownloadNotifications'); } catch (_) {}
    }
  }

  // ── Cancel in-progress download ───────────────────────────────────────────

  Future<void> cancelDownload(String taskId, String episodeId) async {
    // Query the actual filename before cancelling (the task record is gone after cancel).
    String? taskFilename;
    try {
      final tasks = await FlutterDownloader.loadTasksWithRawQuery(
        query: "SELECT * FROM task WHERE task_id='$taskId'",
      );
      taskFilename = tasks?.firstOrNull?.filename;
    } catch (_) {}

    try { await FlutterDownloader.cancel(taskId: taskId); } catch (_) {}
    try { await _notifChannel.invokeMethod('dismissDownloadNotifications'); } catch (_) {}

    // Delete the partial file using the actual filename from the task record.
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = taskFilename ??
          '${episodeId.replaceAll(RegExp(r'[^\w]'), '_')}.mp3';
      final file = File(p.join(dir.path, 'episodes', fileName));
      if (file.existsSync()) await file.delete();
    } catch (_) {}

    // Clear DB state
    await _db.updateEpisodeDownload(episodeId, false, null, null);

    _progress.remove(taskId);
    _episodeTask.remove(episodeId);
    if (_progress.isEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
    notifyListeners();
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
