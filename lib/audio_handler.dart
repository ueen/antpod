// lib/audio_handler.dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Globale Instanz – wird in main.dart über AudioService.init() gesetzt.
late AudioHandler audioHandler;

/// Implementiert Background-Playback (Lock-Screen, Notification, Headset-Tasten)
/// für Android und iOS über das audio_service-Paket.
class AntPodAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  AntPodAudioHandler() {
    // Playback-Events → audio_service-State weiterleiten
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Laufzeit sobald bekannt ins MediaItem schreiben
    _player.durationStream.listen((d) {
      if (d != null && mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: d));
      }
    });
  }

  // ── Öffentliche API ───────────────────────────────────────────────────────

  /// Loads an episode and seeks to position but does NOT start playback.
  Future<void> loadEpisode({
    required String id, required String title, required String podcast,
    required String artUri, required String audioUrl,
    String? localPath, Duration startPosition = Duration.zero,
  }) => _setup(id: id, title: title, podcast: podcast, artUri: artUri,
        audioUrl: audioUrl, localPath: localPath, startPosition: startPosition);

  /// Lädt und startet eine Episode. Wird aus [PlayerProvider] aufgerufen.
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
    // Skip stop() when the player is already idle — saves a round-trip on
    // first play after launch.
    if (_player.processingState != ProcessingState.idle) await _player.stop();
    try {
      // Pass initialPosition so just_audio seeks during load instead of after,
      // saving a separate seek() round-trip.
      if (localPath != null) {
        await _player.setFilePath(localPath, initialPosition: startPosition);
      } else {
        await _player.setUrl(audioUrl, initialPosition: startPosition);
      }
      if (andPlay) await _player.play();
    } on PlayerInterruptedException {
      // A newer _setup() call interrupted this one — expected, ignore.
    } catch (e) {
      debugPrint('[audio] _setup error: $e');
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
  Future<void> fastForward() => _player.seek(
        Duration(
          seconds: (_player.position.inSeconds + _forwardSeconds)
              .clamp(0, _player.duration?.inSeconds ?? 0),
        ),
      );

  @override
  Future<void> rewind() => _player.seek(
        Duration(
          seconds: (_player.position.inSeconds - _rewindSeconds).clamp(0, 9999),
        ),
      );

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

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

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
