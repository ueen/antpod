// lib/download_service.dart
//
// Thin wrapper around flutter_downloader: init, enqueue, remove. Progress and
// completion are observed by DownloadProvider (it polls the task table).
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_database.dart';
import 'share_utils.dart';

class DownloadService {
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await FlutterDownloader.initialize(debug: kDebugMode);
    _initialized = true;
  }

  // ── Download episode ──────────────────────────────────────────────────────

  /// Request POST_NOTIFICATIONS permission on Android 13+.
  /// No-op on older Android or iOS. Safe to call repeatedly.
  static Future<void> requestNotificationPermission() async {
    if (!Platform.isAndroid) return;
    final status = await Permission.notification.status;
    if (status.isDenied) await Permission.notification.request();
  }

  /// File name for an episode download: the readable title (Unicode letters
  /// kept, capped so the name stays under the 255-byte limit) plus a short
  /// hash of the episode id. The hash keeps same-titled episodes ("Trailer",
  /// "Bonus") apart: flutter_downloader fails a task whose file already exists.
  static String fileNameFor(String episodeId, String episodeTitle) {
    final clean = episodeTitle
        .replaceAll(RegExp(r'[^\p{L}\p{N} _-]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final title = String.fromCharCodes(clean.runes.take(60)).trim();
    final hash = ShareUtils.guidHash(episodeId).substring(0, 8);
    return title.isEmpty ? '$hash.mp3' : '$title $hash.mp3';
  }

  static Future<String?> downloadEpisode({
    required String episodeId,
    required String audioUrl,
    required String episodeTitle,
    required AppDatabase db,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final saveDir = Directory(p.join(dir.path, 'episodes'));
    if (!saveDir.existsSync()) saveDir.createSync(recursive: true);

    final fileName = fileNameFor(episodeId, episodeTitle);
    // A leftover partial file from an earlier attempt would make the task fail.
    final stale = File(p.join(saveDir.path, fileName));
    if (stale.existsSync()) {
      try { stale.deleteSync(); } catch (_) {}
    }

    // flutter_downloader's own notifications stay off: it posts one per task
    // plus "complete"/"failed" notices. DownloadProvider shows a single
    // notification for all active downloads instead (download_notification.dart).
    final taskId = await FlutterDownloader.enqueue(
      url: audioUrl,
      savedDir: saveDir.path,
      fileName: fileName,
      showNotification: false,
      openFileFromNotification: false,
    );

    if (taskId != null) {
      await db.updateEpisodeDownload(episodeId, false, null, taskId);
      debugPrint('[Download] enqueued $taskId for "$episodeTitle"');
    } else {
      debugPrint('[Download] enqueue returned null for "$episodeTitle" — URL: $audioUrl');
    }

    return taskId;
  }

  /// Stop a task (if still running), drop its record and delete its file.
  static Future<void> cancelAndCleanup(String taskId) async {
    try {
      await FlutterDownloader.remove(taskId: taskId, shouldDeleteContent: true);
    } catch (e) { debugPrint('[download] download remove error: $e'); }
  }

  /// Drop a finished task's record but keep its file.
  static Future<void> forget(String taskId) async {
    try {
      await FlutterDownloader.remove(taskId: taskId, shouldDeleteContent: false);
    } catch (e) { debugPrint('[download] download forget error: $e'); }
  }
}
