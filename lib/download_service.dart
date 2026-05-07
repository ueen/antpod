// lib/download_service.dart
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app_database.dart';

const _kDownloadPort = 'antpod_downloads';

class DownloadService {
  static bool _initialized = false;
  static ReceivePort? _receivePort;

  // Optional fast-path callback (IsolateNameServer). DownloadProvider polling
  // is the primary mechanism; this is a bonus for faster UI updates.
  static void Function(String taskId, int status, int progress)? onProgress;

  static Future<void> init() async {
    if (_initialized) return;
    await FlutterDownloader.initialize(debug: kDebugMode);
    _initialized = true;
  }

  static void registerCallback() {
    FlutterDownloader.registerCallback(downloadCallback, step: 1);

    _receivePort?.close();
    _receivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping(_kDownloadPort);
    IsolateNameServer.registerPortWithName(
        _receivePort!.sendPort, _kDownloadPort);

    _receivePort!.listen((data) {
      if (data is List && data.length == 3) {
        onProgress?.call(
            data[0] as String, data[1] as int, data[2] as int);
      }
    });
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
      showNotification: false, // avoids POST_NOTIFICATIONS runtime prompt
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

  // ── Background callback (runs in bg isolate) ──────────────────────────────

  @pragma('vm:entry-point')
  static void downloadCallback(String id, int status, int progress) {
    IsolateNameServer.lookupPortByName(_kDownloadPort)
        ?.send([id, status, progress]);
  }
}
