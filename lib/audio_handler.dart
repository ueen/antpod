// lib/audio_handler.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

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
    _player.playbackEventStream.listen(
      (e) => playbackState.add(_transformEvent(e)),
      onError: (Object e, StackTrace st) {
        debugPrint('[audio] playback error: $e');
        onPlayerError?.call(e);
      },
    );

    // The duration into the MediaItem once known (notification seek bar).
    _player.durationStream.listen((d) {
      if (d != null && mediaItem.value != null) {
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

  Future<void> _load({
    String? localPath, required String audioUrl,
    required Duration position, required bool andPlay,
  }) async {
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

  @override
  Future<void> play() => _player.play();

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
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> fastForward() =>
      _player.seek(_clamped(_player.position + Duration(seconds: _forwardSeconds)));

  @override
  Future<void> rewind() =>
      _player.seek(_clamped(_player.position - Duration(seconds: _rewindSeconds)));

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
