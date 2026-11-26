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
import 'app_settings.dart';
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

  /// The position, on its own channel: it ticks 5 times a second, and only
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
  /// (or are a transient 0), so they're neither shown nor saved.
  bool _settling = false;
  /// Bumped per source load, so only the latest one ends [_settling].
  int _sourceGen = 0;

  bool get isOffline => _isOffline;

  AudioPlayer get _player => audioHandler.player;

  /// The settings sheet's switches: [markPlayedNearEnd] is read here.
  final AppSettings _settings;

  PlayerProvider(this._db, this._settings) {
    WidgetsBinding.instance.addObserver(this);
    // Track connectivity for offline indicators in UI.
    Connectivity().checkConnectivity().then((results) => _isOffline = results.isOffline);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.isOffline != _isOffline) {
        _isOffline = results.isOffline;
        notifyListeners();
      }
    });

    audioHandler.onUserPause = _maybeComplete;
    audioHandler.resumeRewind = _settings.resumeRewind;
    audioHandler.onPlayerError = _onPlayerError;
    _restoreSettings();

    audioHandler.playbackState.listen((state) {
      var playing = state.playing;
      var loading = _isLoading;
      // Skip idle — fired transiently while a source loads or the platform
      // player is rebuilt, which would clear _isLoading and cause the
      // spinner to flash off and back on.
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

    // Not while nothing's loaded: the duration is then the warm-up clip's.
    _player.durationStream.listen((d) {
      if (d == null || _settling || !_audioReady || d == _duration) return;
      _duration = d;
      notifyListeners();
    });

    _player.positionStream.listen((p) {
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
    final retry = _chapters.isEmpty && (file == null || feedFailed);

    // Neither has chapters: timestamps in the show notes, if any. An episode
    // from a list comes without its notes (see AppDatabase._watchList).
    if (_chapters.isEmpty) {
      final description = episode.description.isNotEmpty
          ? episode.description
          : (await _db.getEpisode(episode.id))?.description ?? '';
      if (stale()) return;
      final secs = episode.durationSeconds > _duration.inSeconds
          ? episode.durationSeconds
          : _duration.inSeconds;
      final notes = notesChapters(description, secs);
      if (notes.isNotEmpty) {
        _chapters = notes;
        notifyListeners();
      }
    }
    if (retry) _chaptersKey = null;
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  /// Builds the native player ahead of the first play, so that only loads
  /// the episode (see AntPodAudioHandler.warmUp).
  Future<void> warmUp() => audioHandler.warmUp();

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
    } catch (e) { debugPrint('[player] restore error: $e'); }
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
      } catch (e) { debugPrint('[player] final save error: $e'); }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefLastEpisodeId);
    } catch (e) { debugPrint('[player] prefs error: $e'); }
    try {
      await audioHandler.stop();
      // stop() released the native player; have it ready for the next play.
      unawaited(audioHandler.warmUp());
    } catch (e) {
      debugPrint('[player] stop error: $e');
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
      await audioHandler.loadEpisode(
        id: episode.id,
        title: episode.title,
        podcast: episode.podcastTitle,
        artUri: episode.podcastImageUrl,
        audioUrl: episode.audioUrl,
        localPath: localPath,
        startPosition: Duration(milliseconds: startMs),
      );
    } catch (e) {
      if (gen == _sourceGen) _loadFailed(e);
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
    // Again after a failed load (or a restore): from where it was, which the
    // episode row may not have caught up with.
    final again = _currentEpisode?.id == episode.id;
    // When it was last played, for the rewind on resume: the row the player
    // watches is newer than one from a list.
    final lastPlayed = (again ? _currentEpisode! : episode).lastPlayed;
    _switchTo(episode);
    _currentEpisode = episode;
    _persistLastEpisode(episode.id);
    _loadChapters(episode);

    final startMs = episode.isFinished
        ? 0
        : _resumeAt(again ? _position.inMilliseconds : episode.lastPositionMs, lastPlayed);
    final gen = _beginSettle(startMs, episode.durationSeconds);
    final localPath = _resolveLocalPath(episode.localPath);
    _isLoading = localPath == null && episode.audioUrl.isNotEmpty;
    _audioReady = true;
    notifyListeners();

    // Watch for download completion or deletion to pivot source mid-playback
    _episodeWatchSub?.cancel();
    _episodeWatchSub = _db.watchEpisode(episode.id).listen(_onEpisodeUpdated);

    if (episode.audioUrl.isEmpty && localPath == null) {
      _loadFailed('no audio source for episode ${episode.id}');
      return;
    }

    try {
      await audioHandler.playEpisode(
        id: episode.id,
        title: episode.title,
        podcast: episode.podcastTitle,
        artUri: episode.podcastImageUrl,
        audioUrl: episode.audioUrl,
        localPath: localPath,
        startPosition: Duration(milliseconds: startMs),
      );
    } catch (e) {
      if (gen == _sourceGen) _loadFailed(e);
    } finally {
      _endSettle(gen);
    }
  }

  /// Where a load picks an episode up that stopped at [ms]: a little earlier
  /// when it was last played long ago (the settings' rewind on resume).
  int _resumeAt(int ms, DateTime? lastPlayed) {
    if (ms <= 0 || lastPlayed == null) return ms;
    final back = _settings.resumeRewind(DateTime.now().difference(lastPlayed));
    return (ms - back.inMilliseconds).clamp(0, ms);
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
    // Also the first row after play(): an episode from a list comes without
    // its show notes, which the player shows.
    notifyListeners();

    // Nothing loaded (restored, or the load failed): no source to swap, the
    // next play() picks the file or the stream itself.
    if (!_audioReady) return;
    if (prevLocal == null && newLocal != null) {
      // Download finished while streaming — switch to local file seamlessly
      _pivotSource(localPath: newLocal);
    } else if (prevLocal != null && newLocal == null) {
      // Local file deleted while playing — fall back to stream
      _pivotSource(audioUrl: updated.audioUrl);
    }
  }

  Future<void> _pivotSource({String? localPath, String? audioUrl}) async {
    final wasPlaying = _isPlaying;
    final savedPos = _exactPosition;
    final gen = _beginSettle(
        savedPos.inMilliseconds, _duration.inSeconds);
    try {
      await audioHandler.switchSource(
        localPath: localPath,
        audioUrl: audioUrl,
        position: savedPos,
        andPlay: wasPlaying,
      );
    } catch (e) {
      if (gen == _sourceGen) _loadFailed(e);
    } finally {
      _endSettle(gen);
    }
    // The spinner follows the player's own state (playbackState listener);
    // the episode, and so local or not, was updated before the pivot.
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

  /// A pause in the last minute counts as played (outros, trailers), unless
  /// it's switched off in the settings.
  void _maybeComplete() {
    if (!_settings.markPlayedNearEnd) return;
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
    if (!_audioReady) return _moveHeld(pos);
    await audioHandler.seek(pos);
    _flushPosition();
  }

  /// Nothing loaded (restored, or the load failed): the player can't seek,
  /// so the held position moves instead. The next play() starts there, and
  /// it's saved like any seek.
  void _moveHeld(Duration t) {
    final ep = _currentEpisode;
    if (ep == null) return;
    if (t < Duration.zero) t = Duration.zero;
    if (_duration > Duration.zero && t > _duration) t = _duration;
    _position = t;
    _db.updatePlaybackPosition(ep.id,
        positionMs: t.inMilliseconds, durationMs: _duration.inMilliseconds);
  }

  Future<void> skipForward() async {
    if (!_audioReady) {
      return _moveHeld(_position + Duration(seconds: forwardSeconds));
    }
    await audioHandler.fastForward();
    _flushPosition();
  }

  Future<void> skipBackward() async {
    if (!_audioReady) {
      return _moveHeld(_position - Duration(seconds: rewindSeconds));
    }
    await audioHandler.rewind();
    _flushPosition();
  }

  // ── Speed + skip config ───────────────────────────────────────────────────

  double get speed => audioHandler.player.speed;
  int get forwardSeconds => audioHandler.forwardSeconds;
  int get rewindSeconds => audioHandler.rewindSeconds;

  static const _prefSpeed = 'player_speed';
  static const _prefForward = 'player_forward_seconds';
  static const _prefRewind = 'player_rewind_seconds';

  /// The player's keys, for the backup: speed, skip intervals and the
  /// episode it was last on.
  static const prefKeys = [_prefSpeed, _prefForward, _prefRewind, _prefLastEpisodeId];

  /// After a backup import wrote [prefKeys]: speed and skips take them on,
  /// and an empty player opens the imported last episode.
  Future<void> reloadSettings() async {
    await _restoreSettings();
    if (_currentEpisode == null) await restoreLastEpisode();
  }

  /// Speed and skip intervals as the user last set them.
  Future<void> _restoreSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final speed = prefs.getDouble(_prefSpeed);
      final fwd = prefs.getInt(_prefForward);
      final rew = prefs.getInt(_prefRewind);
      if (fwd != null && fwd > 0) audioHandler.setForwardSeconds(fwd);
      if (rew != null && rew > 0) audioHandler.setRewindSeconds(rew);
      if (speed != null && speed > 0) await audioHandler.setSpeed(speed);
      notifyListeners();
    } catch (e) {
      debugPrint('[player] settings restore error: $e');
    }
  }

  void _saveSetting(void Function(SharedPreferences p) write) {
    SharedPreferences.getInstance().then(write).catchError((Object e) {
      debugPrint('[player] settings save error: $e');
    });
  }

  Future<void> cycleSpeed() async {
    const speeds = [1.0, 1.5, 2.0, 0.8];
    final current = speed;
    final idx = speeds.indexWhere((s) => (s - current).abs() < 0.05);
    final next = speeds[(idx < 0 ? 0 : idx + 1) % speeds.length];
    await audioHandler.setSpeed(next);
    _saveSetting((p) => p.setDouble(_prefSpeed, next));
    notifyListeners();
  }

  void setForwardSeconds(int s) {
    audioHandler.setForwardSeconds(s);
    _saveSetting((p) => p.setInt(_prefForward, s));
    notifyListeners();
  }

  void setRewindSeconds(int s) {
    audioHandler.setRewindSeconds(s);
    _saveSetting((p) => p.setInt(_prefRewind, s));
    notifyListeners();
  }

  // ── Errors ────────────────────────────────────────────────────────────────

  final _errors = StreamController<Object>.broadcast();

  /// Playback that failed (load error, stream dropped, no audio): the home
  /// screen shows a message for each.
  Stream<Object> get errors => _errors.stream;

  /// An error the player reported while playing. During a load it belongs
  /// to the old source, or the load's own catch reports it.
  void _onPlayerError(Object e) {
    final ep = _currentEpisode;
    if (ep == null || _settling || !_audioReady) return;
    // The player may already have lost its position: the last tick is it.
    final ms = _position.inMilliseconds;
    if (ms > 0) {
      _db.updatePlaybackPosition(ep.id,
          positionMs: ms, durationMs: _duration.inMilliseconds);
    }
    _audioReady = false;
    _playingChanged(false);
    _player.pause();
    _reportError(e);
  }

  /// The source didn't load: the player has nothing (its position is 0), so
  /// nothing of it is shown or saved. The start position stays in
  /// [_position], and the next tap loads again from there.
  void _loadFailed(Object e) {
    _audioReady = false;
    _settling = false;
    _reportError(e);
  }

  void _reportError(Object e) {
    debugPrint('[player] error: $e');
    // The idle state that follows an error is skipped by the playbackState
    // listener (see there), so the spinner would otherwise stay on.
    _isLoading = false;
    notifyListeners();
    if (!_errors.isClosed) _errors.add(e);
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  /// Where playback is to the millisecond: the player's own position, not
  /// the last 200 ms tick. While a source loads (or before the first play
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
    _errors.close();
    super.dispose();
  }
}
