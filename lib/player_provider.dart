// lib/player_provider.dart
import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_database.dart';
import 'audio_handler.dart';
import 'chapters.dart';
import 'file_chapters.dart';
import 'network.dart';

class PlayerProvider extends ChangeNotifier with WidgetsBindingObserver {
  final AppDatabase _db;

  Episode? _currentEpisode;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  bool _isLoading = false;
  // False after restoreLastEpisode() — audio source is not configured until
  // the user taps play. True once load() or play() sets up the audio handler.
  bool _audioReady = false;
  List<PodcastChapter> _chapters = [];
  /// What [_chapters] were read for (episode, chapters link, file): the same
  /// again is skipped, and a newer load makes an older one drop its result.
  String? _chaptersKey;

  StreamSubscription<Episode?>? _episodeWatchSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isOffline = false;

  static const _prefLastEpisodeId = 'player_last_episode_id';

  /// The position, on its own channel: it ticks once a second, and only
  /// the widgets showing it (progress bars, time labels) listen. The provider
  /// itself notifies for real state changes, and when the chapter changes.
  final _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  int _notifiedChapter = -1;

  Duration get _position => _positionNotifier.value;
  set _position(Duration p) {
    _positionNotifier.value = p;
    final i = currentChapterIndex;
    if (i != _notifiedChapter) {
      _notifiedChapter = i;
      notifyListeners();
    }
  }

  /// Positions are saved when something happens (pause, seek, skip, episode
  /// switch, close, app sent to the background), so this timer only guards
  /// against the process being killed mid-playback.
  static const _saveEvery = Duration(seconds: 30);
  Timer? _saveTimer;

  /// True while a new source loads (episode switch, source pivot): the
  /// player's position/duration events then still belong to the old source
  /// (or are the 0 from stop()), so they're neither shown nor saved.
  bool _settling = false;
  /// Bumped per source load, so only the latest one ends [_settling].
  int _sourceGen = 0;

  bool get isOffline => _isOffline;

  AudioPlayer get _player => (audioHandler as AntPodAudioHandler).player;

  PlayerProvider(this._db) {
    WidgetsBinding.instance.addObserver(this);
    // Track connectivity for offline indicators in UI.
    Connectivity().checkConnectivity().then((results) => _isOffline = results.isOffline);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.isOffline != _isOffline) {
        _isOffline = results.isOffline;
        notifyListeners();
      }
    });

    final handler = audioHandler as AntPodAudioHandler;
    handler.onUserPause = _maybeComplete;

    handler.playbackState.listen((state) {
      var playing = state.playing;
      var loading = _isLoading;
      // Skip idle — fired transiently by _player.stop() before setUrl(), which
      // would clear _isLoading and cause the spinner to flash off and back on.
      if (state.processingState != AudioProcessingState.idle) {
        final isLocal = _currentEpisode?.localPath != null;
        loading = !isLocal &&
            (state.processingState == AudioProcessingState.loading ||
             state.processingState == AudioProcessingState.buffering);
      }
      final completed =
          state.processingState == AudioProcessingState.completed && !_settling;
      if (completed) playing = false;

      if (playing != _isPlaying) {
        // Any stop of playback (user, call, headphones unplugged) saves.
        if (!playing) _flushPosition();
        _playingChanged(playing);
      }
      if (completed) _finishCurrent();
      // Playback events also fire for buffer progress: only notify on change.
      if (playing != _isPlaying || loading != _isLoading) {
        _isPlaying = playing;
        _isLoading = loading;
        notifyListeners();
      }
    });

    _player.durationStream.listen((d) {
      if (d == null || _settling || d == _duration) return;
      _duration = d;
      notifyListeners();
    });

    // Once a second is plenty for bars and m:ss labels; seeks, pauses and
    // other playback events still report at once.
    _player
        .createPositionStream(
            minPeriod: const Duration(seconds: 1),
            maxPeriod: const Duration(seconds: 1))
        .listen((p) {
      if (!_settling && _audioReady) _position = p;
    });
  }

  void _playingChanged(bool playing) {
    _saveTimer?.cancel();
    _saveTimer = playing
        ? Timer.periodic(_saveEvery, (_) => _flushPosition())
        : null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _flushPosition();
    }
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  Episode? get currentEpisode => _currentEpisode;
  bool get isPlaying => _isPlaying;
  /// The position right now; widgets that show it listen to
  /// [positionListenable] instead of rebuilding with the whole provider.
  Duration get position => _position;
  ValueListenable<Duration> get positionListenable => _positionNotifier;
  Duration get duration => _duration;
  bool get isLoading => _isLoading;
  bool get hasEpisode => _currentEpisode != null;

  /// [pos] (default: now) as a share of the duration, 0..1.
  double progressAt([Duration? pos]) =>
      _duration.inMilliseconds > 0
          ? ((pos ?? _position).inMilliseconds / _duration.inMilliseconds)
              .clamp(0.0, 1.0)
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

  /// The current chapter's picture from the audio file's tag, or null.
  Uint8List? get currentChapterImageBytes => currentChapter?.imageBytes;

  /// Whether the current chapter has a picture of its own, not the podcast
  /// cover: only then does tapping the cover enlarge it.
  bool get hasChapterImage {
    final c = currentChapter;
    if (c == null) return false;
    return c.imageBytes != null ||
        (c.imageUrl != null && c.imageUrl != _currentEpisode?.podcastImageUrl);
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

  /// The episode's chapters from the feed and from the audio file, read at
  /// once: the feed's show first, then the two merged (see chapters.dart).
  /// Without either, timestamps listed in the show notes.
  Future<void> _loadChapters(Episode episode) async {
    final localPath = _resolveLocalPath(episode.localPath);
    final url = episode.chaptersUrl;
    final key = '${episode.id}|$url|$localPath';
    if (key == _chaptersKey) return;
    // Read again for the same episode (new link, new file): what's shown
    // stays until the new chapters are in.
    final again = _chaptersKey?.startsWith('${episode.id}|') ?? false;
    _chaptersKey = key;
    if (!again) _chapters = [];
    bool stale() => _chaptersKey != key;

    final fileFuture =
        readFileChapters(localPath: localPath, audioUrl: episode.audioUrl);

    final hasFeed = url != null && url.isNotEmpty;
    List<PodcastChapter>? feed;
    if (hasFeed) {
      feed = await loadFeedChapters(url);
      if (stale()) return;
      if (!again && feed != null && feed.isNotEmpty) {
        _chapters = mergeChapters(feed, null);
        notifyListeners();
      }
    }

    final file = await fileFuture;
    if (stale()) return;
    if (file != null || (!again && feed != null)) {
      _chapters = mergeChapters(feed, file);
      notifyListeners();
    }
    // Nothing read because a fetch failed (offline?): the next play retries.
    final feedFailed = hasFeed && feed == null;
    if (_chapters.isEmpty && (file == null || feedFailed)) _chaptersKey = null;

    // Neither has chapters: timestamps in the show notes, if any.
    if (_chapters.isEmpty) {
      final secs = episode.durationSeconds > _duration.inSeconds
          ? episode.durationSeconds
          : _duration.inSeconds;
      final notes = notesChapters(episode.description, secs);
      if (notes.isNotEmpty) {
        _chapters = notes;
        notifyListeners();
      }
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
      // No audio until the user taps play: the audio handler is configured
      // lazily in play(). Chapters load now, so the player shows them.
      _currentEpisode = ep;
      _position = Duration(milliseconds: ep.lastPositionMs);
      _duration = Duration(seconds: ep.durationSeconds);
      _audioReady = false;
      _settling = false;
      _sourceGen++;
      _loadChapters(ep);
      _db.livePositionEpisodeId = ep.id;
      _episodeWatchSub?.cancel();
      _episodeWatchSub = _db.watchEpisode(ep.id).listen(_onEpisodeUpdated);
      notifyListeners();
    } catch (_) {}
  }

  /// Start loading a new source: from now until [_endSettle] the shown
  /// position stays at [startMs] and the duration at [durationSeconds] (the
  /// feed's, until the audio reports its own). Returns the load's token.
  int _beginSettle(int startMs, int durationSeconds) {
    _settling = true;
    _position = Duration(milliseconds: startMs);
    if (durationSeconds > 0) _duration = Duration(seconds: durationSeconds);
    return ++_sourceGen;
  }

  /// The source of load [gen] is in: take the player's position and
  /// duration again. A newer load (or closing the player) has its own say.
  void _endSettle(int gen) {
    if (gen != _sourceGen || !_settling) return;
    _settling = false;
    _position = _player.position;
    final d = _player.duration;
    if (d != null && d > Duration.zero) _duration = d;
    notifyListeners();
  }

  /// Switching episodes: save exactly where the outgoing one stopped (the
  /// 5-second saves can be a few seconds behind) and hand the live slot to
  /// [next], so the outgoing tile gets its final position.
  void _switchTo(Episode next) {
    final prev = _currentEpisode;
    if (prev != null && prev.id != next.id &&
        _exactPosition.inMilliseconds > 0) {
      _flushPosition();
    }
    _db.livePositionEpisodeId = next.id;
  }

  void _persistLastEpisode(String id) {
    SharedPreferences.getInstance()
        .then((p) => p.setString(_prefLastEpisodeId, id));
  }

  /// Stop playback and close the player (e.g. on podcast unsubscribe).
  /// Saves the position first (awaited, so callers can read it back right
  /// away) and forgets the episode so it isn't restored on the next launch.
  Future<void> stopAndClear() => _closePlayer(savePosition: true);

  /// Mark an episode as played (into Listened; a temp episode is deleted,
  /// see AppDatabase.markPlayedByUser) or unplayed (back to New, progress
  /// cleared). Either way, if it's the episode in the player, the player
  /// closes first, so no position save can land after the write and undo it.
  Future<void> setPlayed(String id, bool played) async {
    // _closePlayer() clears the player state synchronously, before its
    // first await, so the write below is the last one either way.
    final closing = _currentEpisode?.id == id ? _closePlayer() : null;
    await (played ? _db.markPlayedByUser(id) : _db.markUnfinished(id));
    await closing;
  }

  /// Remove a temp episode (see AppDatabase.resetTempEpisode), closing the
  /// player first if it's this episode, as [setPlayed] does.
  Future<void> resetTemp(String id) async {
    final closing = _currentEpisode?.id == id ? _closePlayer() : null;
    await _db.resetTempEpisode(id);
    await closing;
  }

  /// Single teardown path for every "close the player" case: unsubscribe,
  /// episode marked as played or unplayed, episode deleted from the DB.
  ///
  /// [savePosition] must stay false when the episode was just marked as
  /// played: updatePlaybackPosition() un-marks an episode saved before its
  /// last minute. It is pointless for deleted episodes.
  Future<void> _closePlayer({bool savePosition = false}) async {
    final ep = _currentEpisode;
    if (ep == null) return;
    final wasReady = _audioReady;
    final ms = _exactPosition.inMilliseconds;
    final durationMs = _duration.inMilliseconds;
    // Clear state first: detaches the episode watch (so our own position write
    // below can't re-enter _onEpisodeUpdated) and stops the position listener
    // from saving any further ticks for this episode.
    _episodeWatchSub?.cancel();
    _episodeWatchSub = null;
    _currentEpisode = null;
    _audioReady = false;
    _settling = false;
    _sourceGen++;
    _playingChanged(false);
    _chapters = [];
    _chaptersKey = null;
    // Before the save below, so the lists pick up the final position.
    _db.livePositionEpisodeId = null;
    notifyListeners();

    if (savePosition && wasReady && ms > 0) {
      try {
        await _db.updatePlaybackPosition(ep.id,
            positionMs: ms, durationMs: durationMs);
      } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefLastEpisodeId);
    } catch (_) {}
    try {
      await audioHandler.stop();
    } catch (_) {
      // audio_service can throw "Bad state: You cannot add items while items are
      // being added from addStream" if the player is mid-stream. State is
      // already cleared above, so nothing else to do.
    }
  }

  /// Load episode into player without starting playback.
  Future<void> load(Episode episode) async {
    if (_currentEpisode?.id == episode.id) return;
    _switchTo(episode);
    _currentEpisode = episode;
    _persistLastEpisode(episode.id);
    _loadChapters(episode);
    final startMs = episode.isFinished ? 0 : episode.lastPositionMs;
    final gen = _beginSettle(startMs, episode.durationSeconds);
    final localPath = _resolveLocalPath(episode.localPath);
    _isLoading = localPath == null;
    _audioReady = true;
    notifyListeners();
    _episodeWatchSub?.cancel();
    _episodeWatchSub = _db.watchEpisode(episode.id).listen(_onEpisodeUpdated);
    try {
      await (audioHandler as AntPodAudioHandler).loadEpisode(
        id: episode.id,
        title: episode.title,
        podcast: episode.podcastTitle,
        artUri: episode.podcastImageUrl,
        audioUrl: episode.audioUrl,
        localPath: localPath,
        startPosition: Duration(milliseconds: startMs),
      );
    } catch (e) {
      debugPrint('[player] load error: $e');
    } finally {
      _endSettle(gen);
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Returns localPath only if the file exists on disk; null otherwise.
  /// Guards against DB entries pointing to files cleared by the OS or user.
  String? _resolveLocalPath(String? path) {
    if (path == null || path.isEmpty) return null;
    if (!File(path).existsSync()) {
      debugPrint('[player] localPath missing on disk, falling back to stream: $path');
      return null;
    }
    return path;
  }

  Future<void> play(Episode episode) async {
    // Only short-circuit if the audio handler has actually been configured
    // (i.e. not just restored from prefs without buffering).
    if (_currentEpisode?.id == episode.id && _audioReady) {
      await audioHandler.play();
      return;
    }
    _switchTo(episode);
    _currentEpisode = episode;
    _persistLastEpisode(episode.id);
    _loadChapters(episode);

    final startMs = episode.isFinished ? 0 : episode.lastPositionMs;
    final gen = _beginSettle(startMs, episode.durationSeconds);
    final localPath = _resolveLocalPath(episode.localPath);
    _isLoading = localPath == null && episode.audioUrl.isNotEmpty;
    _audioReady = true;
    notifyListeners();

    // Watch for download completion or deletion to pivot source mid-playback
    _episodeWatchSub?.cancel();
    _episodeWatchSub = _db.watchEpisode(episode.id).listen(_onEpisodeUpdated);

    if (episode.audioUrl.isEmpty && localPath == null) {
      debugPrint('[player] no audio source for episode ${episode.id}');
      _settling = false;
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      await (audioHandler as AntPodAudioHandler).playEpisode(
        id: episode.id,
        title: episode.title,
        podcast: episode.podcastTitle,
        artUri: episode.podcastImageUrl,
        audioUrl: episode.audioUrl,
        localPath: localPath,
        startPosition: Duration(milliseconds: startMs),
      );
    } catch (e) {
      debugPrint('[player] play error: $e');
      _isLoading = false;
      notifyListeners();
    } finally {
      _endSettle(gen);
    }
  }

  void _onEpisodeUpdated(Episode? updated) {
    if (_currentEpisode == null) return;
    // Episode deleted from the DB (temp episode removed, unsubscribe) or
    // marked as played elsewhere (natural end, feed sync) — close the
    // player. Swipe and menu go through setPlayed(), which closes first.
    // No position save: see _closePlayer.
    if (updated == null ||
        (!_currentEpisode!.isFinished && updated.isFinished)) {
      _closePlayer();
      return;
    }
    final prevLocal = _currentEpisode!.localPath;
    final newLocal = updated.localPath;
    final chaptersMoved = updated.chaptersUrl != _currentEpisode!.chaptersUrl ||
        prevLocal != newLocal;
    _currentEpisode = updated;
    // A feed refresh can bring a chapters link, and a download a file whose
    // tag (another ad variation) has its own times.
    if (chaptersMoved) _loadChapters(updated);

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
    final savedPos = _exactPosition;
    final gen = _beginSettle(
        savedPos.inMilliseconds, _duration.inSeconds);
    try {
      await handler.player.stop();
      if (localPath != null) {
        await handler.player.setFilePath(localPath, initialPosition: savedPos);
      } else {
        await handler.player.setUrl(audioUrl!, initialPosition: savedPos);
      }
      // Not awaited: play()'s future only completes once playback pauses.
      if (wasPlaying) unawaited(handler.player.play().catchError((_) {}));
    } catch (_) {}
    _endSettle(gen);
    _isLoading = localPath == null;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (!_audioReady && _currentEpisode != null) {
      await play(_currentEpisode!);
      return;
    }
    if (_isPlaying) {
      await audioHandler.pause(); // saves, and may complete: see onUserPause
    } else {
      await audioHandler.play();
    }
  }

  /// A pause in the last minute counts as played (outros, trailers).
  void _maybeComplete() {
    if (_currentEpisode == null) return;
    if (_duration.inSeconds <= 0) return;
    if (_exactPosition.inSeconds < _duration.inSeconds - 60) return;
    _finishCurrent();
  }

  /// Record the current episode as fully played; marking it closes the
  /// player (_onEpisodeUpdated). The download, temp or not, is deleted by the
  /// startup cleanup 2 days later; a temp episode and its feed go after a week.
  Future<void> _finishCurrent() async {
    final ep = _currentEpisode;
    if (ep == null) return;
    await _db.updatePlaybackPosition(ep.id,
        positionMs: _duration.inMilliseconds,
        durationMs: _duration.inMilliseconds);
    await _db.markFinished(ep.id);
  }

  /// Seeks and saves the new position (saved only once the player is there,
  /// so a quick save can't land the old one). The bar moves at once: the
  /// player reports a seek's target before it gets there.
  Future<void> seekTo(Duration pos) async {
    await audioHandler.seek(pos);
    _flushPosition();
  }

  Future<void> skipForward() async {
    await audioHandler.fastForward();
    _flushPosition();
  }

  Future<void> skipBackward() async {
    await audioHandler.rewind();
    _flushPosition();
  }

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

  // ── Internal ──────────────────────────────────────────────────────────────

  /// Where playback is to the millisecond: the player's own position, not
  /// the last 1 s tick. While a source loads (or before the first play
  /// after a restore) it's the start position held in [_position].
  Duration get _exactPosition =>
      _audioReady && !_settling ? _player.position : _position;

  /// Save the current episode's position. Not while a source loads: the
  /// player has nothing new to say yet, and the start position is saved.
  void _flushPosition() {
    final ep = _currentEpisode;
    if (ep == null || !_audioReady || _settling) return;
    _db.updatePlaybackPosition(
      ep.id,
      positionMs: _exactPosition.inMilliseconds,
      durationMs: _duration.inMilliseconds,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _episodeWatchSub?.cancel();
    _connectivitySub?.cancel();
    _flushPosition();
    _positionNotifier.dispose();
    super.dispose();
  }
}
