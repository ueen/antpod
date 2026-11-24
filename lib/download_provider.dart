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
import 'download_service.dart';

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
  bool _polling = false;
  Future<void>? _restore;

  DownloadProvider(this._db);

  bool isDownloading(String episodeId) => _downloads.containsKey(episodeId);
  double? progressForEpisode(String episodeId) => _downloads[episodeId]?.progress;

  /// Call immediately after DownloadService.downloadEpisode() returns a taskId.
  void trackDownload(String taskId,
      {required String episodeId, required String title}) {
    _downloads[episodeId] = _EpDownload(taskId, title, 0.0);
    _changed();
    _ensurePolling();
  }

  void _changed() {
    notifyListeners();
    _syncNotification();
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

  void _stopPollingIfIdle() {
    if (_downloads.isNotEmpty) return;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _poll() async {
    // A slow DB round-trip must not overlap with the next tick.
    if (_polling) return;
    _polling = true;
    try {
      await _pollOnce();
    } finally {
      _polling = false;
    }
  }

  Future<void> _pollOnce() async {
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
      // Canceled (or replaced) while an earlier iteration was awaiting.
      if (_downloads[entry.key]?.taskId != entry.value.taskId) continue;
      final prog = taskProgress[entry.value.taskId];
      if (prog == null) {
        // Task left the active set → download finished or failed.
        _downloads.remove(entry.key);
        await _markComplete(entry.value.taskId, episodeId: entry.key);
        changed = true;
      } else if (entry.value.progress != prog) {
        final d = entry.value;
        _downloads[entry.key] = _EpDownload(d.taskId, d.title, prog);
        changed = true;
      }
    }

    _stopPollingIfIdle();
    if (changed) _changed();
  }

  // ── Mark complete ──────────────────────────────────────────────────────────

  Future<void> _markComplete(String taskId, {String? episodeId}) async {
    List<DownloadTask>? completedTasks;
    try {
      completedTasks = await FlutterDownloader.loadTasksWithRawQuery(
        query: "SELECT * FROM task WHERE task_id='$taskId' AND status=3",
      );
    } catch (_) {}

    final episode = await _findEpisode(episodeId: episodeId, taskId: taskId);

    if (completedTasks != null && completedTasks.isNotEmpty) {
      final task = completedTasks.first;
      final dir = await getApplicationDocumentsDirectory();
      final fullPath = p.join(dir.path, 'episodes', task.filename);
      if (episode != null && !episode.isDownloaded && File(fullPath).existsSync()) {
        await _db.updateEpisodeDownload(episode.id, true, fullPath, taskId);
        await DownloadService.forget(taskId);
        return;
      }
      // Nobody wants this file (episode gone or already downloaded elsewhere).
      if (episode == null) {
        await DownloadService.cancelAndCleanup(taskId);
      } else {
        await DownloadService.forget(taskId);
      }
      return;
    }

    // Task is gone but not completed (failed, WiFi dropped, etc.): drop the
    // partial file and put the episode back in the WiFi queue.
    await DownloadService.cancelAndCleanup(taskId);
    if (episode != null && !episode.isDownloaded) {
      await _db.requeueEpisodeForDownload(episode.id);
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

  // ── Cancel in-progress download ───────────────────────────────────────────

  /// Cancel by episodeId. Pass [fallbackTaskId] when the download was started
  /// in a previous session and may not be in the in-memory map.
  Future<void> cancelDownload(String episodeId, [String? fallbackTaskId]) async {
    // Leave the map first, synchronously: a poll running meanwhile would
    // otherwise see the canceled task as failed and re-queue the episode.
    final taskId = _downloads.remove(episodeId)?.taskId ?? fallbackTaskId;
    if (taskId == null) return;
    _stopPollingIfIdle();
    _changed();

    await DownloadService.cancelAndCleanup(taskId);
    await _db.updateEpisodeDownload(episodeId, false, null, null);
  }

  // ── Startup ───────────────────────────────────────────────────────────────

  /// Settle what happened to downloads while the app wasn't running, once per
  /// launch. Finished and failed tasks are recorded, tasks WorkManager is
  /// still running are tracked again, and everything else (paused, canceled,
  /// task record gone) is cleaned up and put back in the WiFi queue.
  Future<void> restore() => _restore ??= _doRestore();

  Future<void> _doRestore() async {
    List<DownloadTask> tasks = [];
    try {
      tasks = await FlutterDownloader.loadTasks() ?? [];
    } catch (_) {}
    final byId = {for (final t in tasks) t.taskId: t};

    for (final ep in await _db.getPendingDownloads()) {
      final task = byId.remove(ep.downloadTaskId);
      switch (task?.status) {
        case DownloadTaskStatus.enqueued:
        case DownloadTaskStatus.running:
          _downloads[ep.id] =
              _EpDownload(task!.taskId, ep.title, task.progress / 100.0);
        case DownloadTaskStatus.complete:
        case DownloadTaskStatus.failed:
          await _markComplete(task!.taskId, episodeId: ep.id);
        default:
          if (task != null) await DownloadService.cancelAndCleanup(task.taskId);
          await _db.requeueEpisodeForDownload(ep.id);
      }
    }

    // Task records no pending episode points at any more.
    for (final t in byId.values) {
      if (t.status == DownloadTaskStatus.complete) {
        await _markComplete(t.taskId);
      } else {
        await DownloadService.cancelAndCleanup(t.taskId);
      }
    }

    if (_downloads.isNotEmpty) {
      _changed();
      _ensurePolling();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    DownloadNotification.clear();
    super.dispose();
  }
}
