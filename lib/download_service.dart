// lib/download_service.dart
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app_database.dart';

/// Port name used to receive download progress updates in the UI isolate.
const _kDownloadPort = 'antpod_downloads';

class DownloadService {
  static bool _initialized = false;
  static ReceivePort? _receivePort;

  // Callbacks registered by the UI
  static void Function(String taskId, int status, int progress)? onProgress;

  static Future<void> init() async {
    if (_initialized) return;
    await FlutterDownloader.initialize(debug: false);
    _initialized = true;
  }

  /// Register the background callback AND set up a ReceivePort
  /// so the UI isolate gets progress updates.
  static void registerCallback() {
    FlutterDownloader.registerCallback(downloadCallback, step: 1);

    // Register a ReceivePort in the UI isolate
    _receivePort?.close();
    _receivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping(_kDownloadPort);
    IsolateNameServer.registerPortWithName(
        _receivePort!.sendPort, _kDownloadPort);

    _receivePort!.listen((data) {
      if (data is List && data.length == 3) {
        final taskId = data[0] as String;
        final status = data[1] as int;
        final progress = data[2] as int;
        onProgress?.call(taskId, status, progress);
      }
    });
  }

  static void dispose() {
    IsolateNameServer.removePortNameMapping(_kDownloadPort);
    _receivePort?.close();
    _receivePort = null;
  }

  // ── Download episode ──────────────────────────────────────────────────────

  static Future<String?> downloadEpisode({
    required String episodeId,
    required String audioUrl,
    required String episodeTitle,
    required AppDatabase db,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final saveDir = Directory(p.join(dir.path, 'episodes'));
    if (!saveDir.existsSync()) saveDir.createSync(recursive: true);

    final fileName = '${episodeId.replaceAll(RegExp(r'[^\w]'), '_')}.mp3';

    final taskId = await FlutterDownloader.enqueue(
      url: audioUrl,
      savedDir: saveDir.path,
      fileName: fileName,
      showNotification: true,
      openFileFromNotification: false,
    );

    if (taskId != null) {
      await db.updateEpisodeDownload(episodeId, false, null, taskId);
    }
    return taskId;
  }

  /// Mark a completed download as done in the DB.
  static Future<void> markCompleted({
    required String taskId,
    required String savedDir,
    required String fileName,
    required AppDatabase db,
  }) async {
    final fullPath = p.join(savedDir, fileName);
    final result = await (db.select(db.episodes)
          ..where((e) => e.downloadTaskId.equals(taskId)))
        .getSingleOrNull();
    if (result != null) {
      await db.updateEpisodeDownload(result.id, true, fullPath, taskId);
    }
  }

  // ── Background callback (runs in bg isolate) ──────────────────────────────

  @pragma('vm:entry-point')
  static void downloadCallback(String id, int status, int progress) {
    final port = IsolateNameServer.lookupPortByName(_kDownloadPort);
    port?.send([id, status, progress]);
  }
}
