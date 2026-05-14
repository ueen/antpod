// lib/player_provider.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:podcast_search/podcast_search.dart' as ps;
import 'app_database.dart';
import 'audio_handler.dart';

class PodcastChapter {
  final String title;
  final double startTimeSeconds;
  const PodcastChapter({required this.title, required this.startTimeSeconds});
}

class PlayerProvider extends ChangeNotifier {
  final AppDatabase _db;

  Episode? _currentEpisode;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isLoading = false;
  double? _downloadProgress;
  List<PodcastChapter> _chapters = [];
  List<AdSegment> _adSegments = [];

  StreamSubscription<Episode?>? _episodeWatchSub;

  static const _saveIntervalMs = 5000;
  int _lastSavedMs = 0;

  PlayerProvider(this._db) {
    final handler = audioHandler as AntPodAudioHandler;

    handler.playbackState.listen((state) {
      _isPlaying = state.playing;
      _position = state.updatePosition;
      // Suppress loading indicator for local files — seek + load is near-instant
      final isLocal = _currentEpisode?.localPath != null;
      _isLoading = !isLocal &&
          (state.processingState == AudioProcessingState.loading ||
           state.processingState == AudioProcessingState.buffering);

      if (state.processingState == AudioProcessingState.completed) {
        _isPlaying = false;
        if (_currentEpisode != null) {
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

  // ── Chapters ──────────────────────────────────────────────────────────────

  List<PodcastChapter> get chapters => _chapters;

  // ── Ad segments ───────────────────────────────────────────────────────────

  List<AdSegment> get adSegments => _adSegments;

  bool get isCurrentlyInAd {
    final posS = _position.inMilliseconds / 1000.0;
    return _adSegments.any(
        (s) => posS >= s.startSeconds && posS < s.endSeconds);
  }

  AdSegment? get currentAdSegment {
    final posS = _position.inMilliseconds / 1000.0;
    for (final s in _adSegments) {
      if (posS >= s.startSeconds && posS < s.endSeconds) return s;
    }
    return null;
  }

  void _loadAdSegments(String episodeId) async {
    _adSegments = await _db.getAdSegments(episodeId);
    notifyListeners();
  }

  int get currentChapterIndex {
    if (_chapters.isEmpty) return -1;
    final posSeconds = _position.inMilliseconds / 1000.0;
    for (int i = _chapters.length - 1; i >= 0; i--) {
      if (posSeconds >= _chapters[i].startTimeSeconds) return i;
    }
    return 0;
  }

  PodcastChapter? get currentChapter {
    final i = currentChapterIndex;
    return i >= 0 ? _chapters[i] : null;
  }

  Future<void> seekToChapter(PodcastChapter chapter) =>
      seekTo(Duration(milliseconds: (chapter.startTimeSeconds * 1000).round()));

  void skipToNextChapter() {
    final i = currentChapterIndex;
    if (i >= 0 && i < _chapters.length - 1) seekToChapter(_chapters[i + 1]);
  }

  void skipToPreviousChapter() {
    final i = currentChapterIndex;
    if (i > 0) seekToChapter(_chapters[i - 1]);
  }

  Future<void> _loadChapters(String? url) async {
    _chapters = [];
    if (url == null || url.isEmpty) return;
    try {
      final result = await ps.Feed.loadChaptersByUrl(url: url);
      _chapters = result.chapters
          .where((c) => c.toc && c.title.isNotEmpty)
          .map((c) => PodcastChapter(title: c.title, startTimeSeconds: c.startTime))
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  /// Load episode into player without starting playback.
  Future<void> load(Episode episode) async {
    if (_currentEpisode?.id == episode.id) return;
    _lastSavedMs = 0;
    _currentEpisode = episode;
    _chapters = [];
    _adSegments = [];
    final startMs = episode.isFinished ? 0 : episode.lastPositionMs;
    _position = Duration(milliseconds: startMs);
    _isLoading = episode.localPath == null;
    notifyListeners();
    _loadChapters(episode.chaptersUrl);
    _loadAdSegments(episode.id);
    _episodeWatchSub?.cancel();
    _episodeWatchSub = _db.watchEpisode(episode.id).listen(_onEpisodeUpdated);
    await (audioHandler as AntPodAudioHandler).loadEpisode(
      id: episode.id,
      title: episode.title,
      podcast: episode.podcastTitle,
      artUri: episode.podcastImageUrl,
      audioUrl: episode.audioUrl,
      localPath: episode.localPath,
      startPosition: Duration(milliseconds: startMs),
    );
    _isLoading = false;
    notifyListeners();
  }

  Future<void> play(Episode episode) async {
    if (_currentEpisode?.id == episode.id) {
      await audioHandler.play();
      return;
    }
    _lastSavedMs = 0;
    _currentEpisode = episode;
    _chapters = [];
    _adSegments = [];

    final startMs = episode.isFinished ? 0 : episode.lastPositionMs;
    // Pre-fill position so progress bar doesn't flash from zero
    _position = Duration(milliseconds: startMs);
    // Local file loads instantly — no spinner needed
    _isLoading = episode.localPath == null;
    notifyListeners();

    _loadChapters(episode.chaptersUrl);
    _loadAdSegments(episode.id);

    // Watch for download completion or deletion to pivot source mid-playback
    _episodeWatchSub?.cancel();
    _episodeWatchSub = _db.watchEpisode(episode.id).listen(_onEpisodeUpdated);

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

  void _onEpisodeUpdated(Episode? updated) {
    if (updated == null || _currentEpisode == null) return;
    final prevLocal = _currentEpisode!.localPath;
    final newLocal = updated.localPath;
    _currentEpisode = updated;

    if (prevLocal == null && newLocal != null) {
      // Download finished while streaming — switch to local file seamlessly
      _pivotSource(localPath: newLocal);
    } else if (prevLocal != null && newLocal == null) {
      // Local file deleted while playing — fall back to stream
      _pivotSource(audioUrl: updated.audioUrl);
    } else {
      notifyListeners();
    }
  }

  Future<void> _pivotSource({String? localPath, String? audioUrl}) async {
    final handler = audioHandler as AntPodAudioHandler;
    final wasPlaying = _isPlaying;
    final savedPos = _position;
    try {
      await handler.player.stop();
      if (localPath != null) {
        await handler.player.setFilePath(localPath);
      } else {
        await handler.player.setUrl(audioUrl!);
      }
      await handler.player.seek(savedPos);
      if (wasPlaying) await handler.player.play();
    } catch (_) {}
    _isLoading = localPath == null;
    notifyListeners();
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

  // ── Speed + skip config ───────────────────────────────────────────────────

  double get speed => (audioHandler as AntPodAudioHandler).player.speed;
  int get forwardSeconds => (audioHandler as AntPodAudioHandler).forwardSeconds;
  int get rewindSeconds => (audioHandler as AntPodAudioHandler).rewindSeconds;

  Future<void> cycleSpeed() async {
    const speeds = [1.0, 1.5, 2.0, 0.8];
    final current = speed;
    final idx = speeds.indexWhere((s) => (s - current).abs() < 0.05);
    final next = speeds[(idx < 0 ? 0 : idx + 1) % speeds.length];
    await (audioHandler as AntPodAudioHandler).setSpeed(next);
    notifyListeners();
  }

  void setForwardSeconds(int s) {
    (audioHandler as AntPodAudioHandler).setForwardSeconds(s);
    notifyListeners();
  }

  void setRewindSeconds(int s) {
    (audioHandler as AntPodAudioHandler).setRewindSeconds(s);
    notifyListeners();
  }

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
    _episodeWatchSub?.cancel();
    _flushPosition();
    super.dispose();
  }
}
