// lib/player_provider.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:podcast_search/podcast_search.dart' as ps;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_database.dart';
import 'audio_handler.dart';
import 'id3_chapters.dart';

class PodcastChapter {
  final String title;
  final double startTimeSeconds;
  final String? imageUrl;
  const PodcastChapter({required this.title, required this.startTimeSeconds, this.imageUrl});
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
  // startTimeMs → image bytes, populated from ID3v2 CHAP tags when JSON has no images
  Map<int, Uint8List> _id3ChapterImages = {};

  StreamSubscription<Episode?>? _episodeWatchSub;

  static const _saveIntervalMs = 5000;
  static const _prefLastEpisodeId = 'player_last_episode_id';
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
          _db.deleteLocalFile(_currentEpisode!.id);
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

  String get currentCoverImageUrl =>
      currentChapter?.imageUrl ?? _currentEpisode?.podcastImageUrl ?? '';

  /// Image bytes from ID3v2 CHAP tag for the current chapter, or null.
  Uint8List? get currentChapterImageBytes {
    final idx = currentChapterIndex;
    if (idx < 0 || _chapters.isEmpty) return null;
    final startMs = (_chapters[idx].startTimeSeconds * 1000).round();
    // Find the closest ID3 chapter within 2 s tolerance
    int? best;
    int bestDiff = 2001;
    for (final ms in _id3ChapterImages.keys) {
      final diff = (ms - startMs).abs();
      if (diff < bestDiff) { bestDiff = diff; best = ms; }
    }
    return best != null ? _id3ChapterImages[best] : null;
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

  Future<void> _loadChapters(String? url, String audioUrl) async {
    _chapters = [];
    _id3ChapterImages = {};
    if (url == null || url.isEmpty) {
      debugPrint('[chapters] no chaptersUrl — skipping');
      return;
    }
    try {
      final result = await ps.Feed.loadChaptersByUrl(url: url);
      _chapters = result.chapters
          .where((c) => c.toc && c.title.isNotEmpty)
          .map((c) => PodcastChapter(
                title: c.title,
                startTimeSeconds: c.startTime,
                imageUrl: c.imageUrl.isNotEmpty ? c.imageUrl : null,
              ))
          .toList();
      debugPrint('[chapters] loaded ${_chapters.length} chapters; '
          'withImage=${_chapters.where((c) => c.imageUrl != null).length}');
      notifyListeners();
    } catch (e) {
      debugPrint('[chapters] loadChaptersByUrl error: $e');
    }

    // If no JSON chapter images, try ID3v2 CHAP tags embedded in the audio file
    if (_chapters.isNotEmpty && _chapters.every((c) => c.imageUrl == null)) {
      debugPrint('[chapters] fetching ID3 images from $audioUrl');
      _id3ChapterImages = await fetchId3ChapterImages(audioUrl);
      debugPrint('[chapters] ID3 images: ${_id3ChapterImages.length} found '
          '(keys=${_id3ChapterImages.keys.toList()})');
      if (_id3ChapterImages.isNotEmpty) notifyListeners();
    } else {
      debugPrint('[chapters] skipping ID3 fetch: chapters=${_chapters.length}, '
          'allNullImages=${_chapters.every((c) => c.imageUrl == null)}');
    }
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  /// Restore the last-played episode on startup (silent load, no playback).
  /// Skips if the episode is finished or no longer in the DB.
  Future<void> restoreLastEpisode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_prefLastEpisodeId);
      if (id == null) return;
      final ep = await _db.getEpisode(id);
      if (ep == null || ep.isFinished) return;
      await load(ep);
    } catch (_) {}
  }

  void _persistLastEpisode(String id) {
    SharedPreferences.getInstance()
        .then((p) => p.setString(_prefLastEpisodeId, id));
  }

  /// Stop playback and clear the current episode (e.g. on podcast unsubscribe).
  Future<void> stopAndClear() async {
    await audioHandler.stop();
    _episodeWatchSub?.cancel();
    _episodeWatchSub = null;
    _currentEpisode = null;
    _chapters = [];
    notifyListeners();
  }

  /// Load episode into player without starting playback.
  Future<void> load(Episode episode) async {
    if (_currentEpisode?.id == episode.id) return;
    _lastSavedMs = 0;
    _currentEpisode = episode;
    _persistLastEpisode(episode.id);
    _chapters = [];
    final startMs = episode.isFinished ? 0 : episode.lastPositionMs;
    _position = Duration(milliseconds: startMs);
    _isLoading = episode.localPath == null;
    notifyListeners();
    _loadChapters(episode.chaptersUrl, episode.audioUrl);
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
    _persistLastEpisode(episode.id);
    _chapters = [];

    final startMs = episode.isFinished ? 0 : episode.lastPositionMs;
    // Pre-fill position so progress bar doesn't flash from zero
    _position = Duration(milliseconds: startMs);
    // Local file loads instantly — no spinner needed
    _isLoading = episode.localPath == null;
    notifyListeners();

    _loadChapters(episode.chaptersUrl, episode.audioUrl);

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
    if (_currentEpisode == null) return;
    if (updated == null) {
      // Episode was deleted from DB (e.g. unsubscribe) — stop and clear.
      audioHandler.stop();
      _episodeWatchSub?.cancel();
      _episodeWatchSub = null;
      _currentEpisode = null;
      _chapters = [];
      notifyListeners();
      return;
    }
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
      _maybeComplete();
    } else {
      await audioHandler.play();
    }
  }

  void _maybeComplete() {
    if (_currentEpisode == null) return;
    if (_duration.inSeconds <= 0) return;
    if (_position.inSeconds < _duration.inSeconds - 60) return;
    _db.updatePlaybackPosition(_currentEpisode!.id,
        positionMs: _duration.inMilliseconds,
        durationMs: _duration.inMilliseconds);
    _db.markFinished(_currentEpisode!.id);
    _db.cleanupTempEpisode(_currentEpisode!.id);
    _db.deleteLocalFile(_currentEpisode!.id);
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
