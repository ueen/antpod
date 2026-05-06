// lib/player_provider.dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'app_database.dart';
import 'audio_handler.dart';

class PlayerProvider extends ChangeNotifier {
  final AppDatabase _db;

  Episode? _currentEpisode;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isLoading = false;
  double? _downloadProgress;

  /// How often to persist the resume position to the DB (every N ms).
  static const _saveIntervalMs = 5000;
  int _lastSavedMs = 0;

  PlayerProvider(this._db) {
    final handler = audioHandler as AntPodAudioHandler;

    handler.playbackState.listen((state) {
      _isPlaying = state.playing;
      _position = state.updatePosition;
      _isLoading = state.processingState == AudioProcessingState.loading ||
          state.processingState == AudioProcessingState.buffering;

      if (state.processingState == AudioProcessingState.completed) {
        _isPlaying = false;
        if (_currentEpisode != null) {
          // Mark finished + save final position
          _db.updatePlaybackPosition(
            _currentEpisode!.id,
            positionMs: _duration.inMilliseconds,
            durationMs: _duration.inMilliseconds,
          );
          _db.markFinished(_currentEpisode!.id);
          _db.cleanupTempEpisode(_currentEpisode!.id);
        }
      }
      notifyListeners();
    });

    handler.player.durationStream.listen((d) {
      if (d != null) { _duration = d; notifyListeners(); }
    });

    handler.player.positionStream.listen((p) {
      _position = p;
      // Throttled DB save (every 5 s)
      final ms = p.inMilliseconds;
      if (ms - _lastSavedMs >= _saveIntervalMs && _currentEpisode != null) {
        _lastSavedMs = ms;
        _db.updatePlaybackPosition(
          _currentEpisode!.id,
          positionMs: ms,
          durationMs: _duration.inMilliseconds,
        );
      }
      notifyListeners();
    });
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  Episode? get currentEpisode => _currentEpisode;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isLoading => _isLoading;
  double? get downloadProgress => _downloadProgress;
  bool get hasEpisode => _currentEpisode != null;

  double get progress =>
      _duration.inMilliseconds > 0
          ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;

  // ── Playback ──────────────────────────────────────────────────────────────

  Future<void> play(Episode episode) async {
    if (_currentEpisode?.id == episode.id) {
      await audioHandler.play();
      return;
    }
    _lastSavedMs = 0;
    _currentEpisode = episode;
    _isLoading = true;
    notifyListeners();

    // Resume from saved position (ms precision)
    final startMs = episode.isFinished ? 0 : episode.lastPositionMs;

    await (audioHandler as AntPodAudioHandler).playEpisode(
      id: episode.id,
      title: episode.title,
      podcast: episode.podcastTitle,
      artUri: episode.podcastImageUrl,
      audioUrl: episode.audioUrl,
      localPath: episode.localPath,
      startPosition: Duration(milliseconds: startMs),
    );
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await audioHandler.pause();
      _flushPosition();
    } else {
      await audioHandler.play();
    }
  }

  Future<void> seekTo(Duration pos) async {
    await audioHandler.seek(pos);
    _flushPosition();
  }

  Future<void> skipForward() => audioHandler.fastForward();
  Future<void> skipBackward() => audioHandler.rewind();

  // ── Download progress ─────────────────────────────────────────────────────

  void setDownloadProgress(double? progress) {
    _downloadProgress = progress;
    notifyListeners();
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _flushPosition() {
    if (_currentEpisode != null) {
      _lastSavedMs = _position.inMilliseconds;
      _db.updatePlaybackPosition(
        _currentEpisode!.id,
        positionMs: _position.inMilliseconds,
        durationMs: _duration.inMilliseconds,
      );
    }
  }

  @override
  void dispose() {
    _flushPosition();
    super.dispose();
  }
}
