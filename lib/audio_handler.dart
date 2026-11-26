// lib/audio_handler.dart
import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// The one instance, set in main.dart from AudioService.init().
late AntPodAudioHandler audioHandler;

/// Background playback (lock screen, notification, headset buttons) on
/// Android and iOS through audio_service. The only place that drives the
/// just_audio player; PlayerProvider goes through the methods here.
class AntPodAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  /// Errors the player reports while playing (stream dropped, source gone).
  /// Load errors are thrown by [loadEpisode]/[playEpisode]/[switchSource].
  void Function(Object error)? onPlayerError;

  AntPodAudioHandler() {
    // Playback events → audio_service state. listen + add, not pipe: pipe
    // holds the subject in addStream, so super.stop()'s own state update
    // would throw "Bad state: You cannot add items while items are being
    // added from addStream".
    // The warm-up clip's events stay here (see [warmUp]).
    _player.playbackEventStream.listen(
      (e) { if (!_warm) playbackState.add(_transformEvent(e)); },
      onError: (Object e, StackTrace st) {
        debugPrint('[audio] playback error: $e');
        if (!_warm) onPlayerError?.call(e);
      },
    );

    // When playback stopped, for [resumeRewind]: a pause, a call, unplugged
    // headphones, a load that mustn't play.
    _player.playingStream.listen((p) => _pausedAt = p ? null : DateTime.now());

    // The duration into the MediaItem once known (notification seek bar).
    _player.durationStream.listen((d) {
      if (d != null && !_warm && mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: d));
      }
    });
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Loads an episode and seeks to position but does NOT start playback.
  Future<void> loadEpisode({
    required String id, required String title, required String podcast,
    required String artUri, required String audioUrl,
    String? localPath, Duration startPosition = Duration.zero,
  }) => _setup(id: id, title: title, podcast: podcast, artUri: artUri,
        audioUrl: audioUrl, localPath: localPath, startPosition: startPosition);

  /// Loads and starts an episode. Called from [PlayerProvider].
  Future<void> playEpisode({
    required String id, required String title, required String podcast,
    required String artUri, required String audioUrl,
    String? localPath, Duration startPosition = Duration.zero,
  }) => _setup(id: id, title: title, podcast: podcast, artUri: artUri,
        audioUrl: audioUrl, localPath: localPath, startPosition: startPosition,
        andPlay: true);

  Future<void> _setup({
    required String id, required String title, required String podcast,
    required String artUri, required String audioUrl,
    String? localPath, Duration startPosition = Duration.zero,
    bool andPlay = false,
  }) async {
    mediaItem.add(MediaItem(
      id: id, title: title, artist: podcast, artUri: Uri.tryParse(artUri),
    ));
    await _load(localPath: localPath, audioUrl: audioUrl,
        position: startPosition, andPlay: andPlay);
  }

  /// Same episode, other source (download finished, file deleted): picks up
  /// at [position] and keeps playing if [andPlay].
  Future<void> switchSource({
    String? localPath, String? audioUrl,
    required Duration position, required bool andPlay,
  }) => _load(localPath: localPath, audioUrl: audioUrl ?? '',
        position: position, andPlay: andPlay);

  /// The native player is built on the first load and released by stop(), a
  /// few hundred ms either way. [warmUp] builds it ahead of the first play
  /// with a silent clip; [_warm] while that's the loaded source, [_hasSource]
  /// once an episode is.
  bool _warm = false;
  bool _hasSource = false;

  /// Loads the silent clip, paused, so the first tap only swaps the source
  /// in. No audio focus is taken (other apps keep playing), and its events
  /// reach neither audio_service nor PlayerProvider. No-op with an episode
  /// loaded; an episode loaded meanwhile simply replaces the clip.
  Future<void> warmUp() async {
    if (_warm || _hasSource) return;
    _warm = true;
    try {
      final f = File('${(await getTemporaryDirectory()).path}/warmup.mp3');
      if (!f.existsSync()) await f.writeAsBytes(_silentMp3(), flush: true);
      if (!_warm) return; // an episode came first
      await _player.setFilePath(f.path);
    } on PlayerInterruptedException {
      // An episode load took over — expected.
    } catch (e) {
      debugPrint('[audio] warm-up error: $e');
    }
  }

  /// 20 silent MPEG-1 Layer III frames, ~0.5 s (mono, 32 kbps, 44.1 kHz):
  /// MP3, like most episodes, so its decoder gets set up too. Each frame is
  /// a header and zeros; no side info or main data decodes to silence.
  static Uint8List _silentMp3() {
    const frameBytes = 104; // 144 × 32000 / 44100, no padding
    final b = Uint8List(frameBytes * 20);
    for (var i = 0; i < b.length; i += frameBytes) {
      b.setAll(i, const [0xFF, 0xFB, 0x10, 0xC0]);
    }
    return b;
  }

  Future<void> _load({
    String? localPath, required String audioUrl,
    required Duration position, required bool andPlay,
  }) async {
    _warm = false;
    _hasSource = true;
    // No stop() before the new source: stop() releases the native player, so
    // every switch rebuilt ExoPlayer (~0.5 s) and dropped `playing` for a
    // moment (play icon flicker). A loaded player takes the new source in
    // place and keeps its playing flag — so pause first when this load
    // mustn't start playback.
    if (!andPlay && _player.playing) await _player.pause();
    try {
      // initialPosition: just_audio seeks during load instead of after,
      // saving a separate seek() round-trip.
      if (localPath != null) {
        await _player.setFilePath(localPath, initialPosition: position);
      } else {
        await _player.setUrl(audioUrl, initialPosition: position);
      }
      // Not awaited: just_audio's play() future only completes once playback
      // pauses or stops, and callers wait for the source to be loaded.
      if (andPlay) {
        unawaited(_player.play().catchError((Object e) {
          debugPrint('[audio] play error: $e');
        }));
      }
    } on PlayerInterruptedException {
      // A newer load interrupted this one — expected, ignore.
    } catch (e) {
      debugPrint('[audio] load error: $e');
      rethrow;
    }
  }

  // ── BaseAudioHandler ──────────────────────────────────────────────────────

  /// How far back to start when playback resumes after a pause of the given
  /// length (the settings' rewind on resume). Set by PlayerProvider.
  Duration Function(Duration pausedFor)? resumeRewind;

  /// Since when the player hasn't been playing; null while it plays. A seek
  /// while paused restarts it: the user picked that spot.
  DateTime? _pausedAt;

  /// Nothing to play while only the warm-up clip is loaded (a headset button
  /// right after launch or after closing the player). App, notification and
  /// headset all resume through here, so they all get [resumeRewind].
  @override
  Future<void> play() async {
    if (_warm) return;
    if (_pausedAt case final since?) {
      final back = resumeRewind?.call(DateTime.now().difference(since)) ?? Duration.zero;
      if (back > Duration.zero) await _player.seek(_clamped(_player.position - back));
    }
    await _player.play();
  }

  /// Called after a pause the user asked for: app, notification, lock screen
  /// or headset button. Interruptions (a call, unplugged headphones) pause
  /// the player directly and don't come through here.
  VoidCallback? onUserPause;

  @override
  Future<void> pause() async {
    await _player.pause();
    onUserPause?.call();
  }

  @override
  Future<void> stop() async {
    _warm = false;
    _hasSource = false;
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _seek(position);

  @override
  Future<void> fastForward() =>
      _seek(_clamped(_player.position + Duration(seconds: _forwardSeconds)));

  @override
  Future<void> rewind() =>
      _seek(_clamped(_player.position - Duration(seconds: _rewindSeconds)));

  /// The user's seeks: one while paused restarts the pause (see [_pausedAt]).
  Future<void> _seek(Duration position) {
    if (!_player.playing) _pausedAt = DateTime.now();
    return _player.seek(position);
  }

  /// [t] within the episode: not before 0, not past the end once it's known
  /// (a stream may not report its duration yet; seek then goes as asked).
  Duration _clamped(Duration t) {
    if (t < Duration.zero) return Duration.zero;
    final d = _player.duration;
    return d != null && d > Duration.zero && t > d ? d : t;
  }

  // ── Skip configuration ────────────────────────────────────────────────────

  int _forwardSeconds = 30;
  int _rewindSeconds = 10;

  int get forwardSeconds => _forwardSeconds;
  int get rewindSeconds => _rewindSeconds;

  void setForwardSeconds(int s) => _forwardSeconds = s;
  void setRewindSeconds(int s) => _rewindSeconds = s;

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  // ── Getter ────────────────────────────────────────────────────────────────

  AudioPlayer get player => _player;

  // ── Helpers ───────────────────────────────────────────────────────────────

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.rewind,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
