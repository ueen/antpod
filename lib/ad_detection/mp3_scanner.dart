// lib/ad_detection/mp3_scanner.dart
//
// Pure-Dart MPEG Layer III frame scanner. No FFI, no platform channels.
//
// Two signals are extracted without decoding audio:
//   1. Encoding discontinuities — bitrate / sample-rate / channel-mode changes
//      between consecutive frames.  Dynamic ad insertion almost always splices
//      a differently-encoded segment into the feed audio.
//   2. Global-gain loudness estimate — the 8-bit global_gain field in the MPEG
//      side-information header scales the quantisation step.  Runs of frames
//      with global_gain < 25 reliably indicate silence (≥ ~-60 dBFS).

import 'dart:typed_data';

// ─── Public types ─────────────────────────────────────────────────────────────

class SpliceCandidate {
  const SpliceCandidate(this.timestampSeconds, this.reason);
  final double timestampSeconds;
  final String reason; // 'bitrate_change' | 'samplerate_change' | 'mode_change'
}

class SilenceRange {
  const SilenceRange(this.startSeconds, this.endSeconds);
  final double startSeconds;
  final double endSeconds;
  double get durationSeconds => endSeconds - startSeconds;
}

class Mp3ScanResult {
  const Mp3ScanResult({
    required this.spliceCandidates,
    required this.silenceRanges,
    required this.totalDurationSeconds,
  });
  final List<SpliceCandidate> spliceCandidates;
  final List<SilenceRange> silenceRanges;
  final double totalDurationSeconds;
}

// ─── Scanner ──────────────────────────────────────────────────────────────────

class Mp3Scanner {
  // Minimum silence duration to record (seconds).
  static const _minSilenceDuration = 0.25;
  // global_gain threshold below which a granule is considered silent.
  static const _silenceGainThreshold = 25;

  // MPEG1 Layer III bitrates (kbps), indexed by 4-bit bitrate field.
  static const _bitrateMpeg1 = [
    0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0
  ];
  // MPEG2/2.5 Layer III bitrates (kbps).
  static const _bitrateMpeg2 = [
    0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0
  ];
  // Sample rates (Hz) by [mpegVersion][srIndex].
  static const _sampleRates = [
    [44100, 48000, 32000, 0], // MPEG1
    [22050, 24000, 16000, 0], // MPEG2
    [11025, 12000, 8000, 0],  // MPEG2.5
  ];

  // ── Public entry point ────────────────────────────────────────────────────

  static Mp3ScanResult scan(Uint8List bytes) {
    int offset = _skipId3(bytes);

    final splices = <SpliceCandidate>[];
    final silences = <SilenceRange>[];

    double time = 0.0;
    int? prevBitrate, prevSampleRate;
    bool? prevMono;

    // Silence-run state
    double silenceStart = 0.0;
    bool inSilence = false;

    while (offset < bytes.length - 4) {
      // ── Sync word: 0xFF + top 3 bits of next byte set ──────────────────
      if (bytes[offset] != 0xFF || (bytes[offset + 1] & 0xE0) != 0xE0) {
        offset++;
        continue;
      }

      final h1 = bytes[offset + 1];
      final h2 = bytes[offset + 2];
      final h3 = bytes[offset + 3];

      // MPEG version (bits 20-19 of header)
      final versionBits = (h1 >> 3) & 0x03;
      if (versionBits == 1) { offset++; continue; } // reserved
      // 0 = MPEG1, 1 = MPEG2, 2 = MPEG2.5
      final mpegVer = versionBits == 3 ? 0 : (versionBits == 2 ? 1 : 2);

      // Layer (bits 18-17) — only Layer III supported
      final layerBits = (h1 >> 1) & 0x03;
      if (layerBits != 1) { offset++; continue; }

      // CRC protection (bit 16)
      final crcProtected = (h1 & 0x01) == 0;

      // Bitrate index (bits 15-12)
      final bitrateIdx = (h2 >> 4) & 0x0F;
      if (bitrateIdx == 0 || bitrateIdx == 15) { offset++; continue; }
      final bitrateKbps = mpegVer == 0
          ? _bitrateMpeg1[bitrateIdx]
          : _bitrateMpeg2[bitrateIdx];

      // Sample rate index (bits 11-10)
      final srIdx = (h2 >> 2) & 0x03;
      if (srIdx == 3) { offset++; continue; }
      final sampleRate = _sampleRates[mpegVer][srIdx];

      // Padding bit (bit 9)
      final padding = (h2 >> 1) & 0x01;

      // Channel mode (bits 7-6 of h3)
      final isMono = ((h3 >> 6) & 0x03) == 3;

      // Frame size in bytes
      final frameSize =
          (144 * bitrateKbps * 1000 ~/ sampleRate) + padding;
      if (frameSize < 4 || frameSize > 4096 ||
          offset + frameSize > bytes.length) {
        offset++;
        continue;
      }

      // ── Encoding discontinuity detection ─────────────────────────────
      if (prevBitrate != null) {
        if (prevBitrate != bitrateKbps) {
          splices.add(SpliceCandidate(time, 'bitrate_change'));
        } else if (prevSampleRate != sampleRate) {
          splices.add(SpliceCandidate(time, 'samplerate_change'));
        } else if (prevMono != isMono) {
          splices.add(SpliceCandidate(time, 'mode_change'));
        }
      }
      prevBitrate = bitrateKbps;
      prevSampleRate = sampleRate;
      prevMono = isMono;

      // ── Global-gain loudness estimate ─────────────────────────────────
      final gain = _readGlobalGain(bytes, offset, crcProtected, isMono, mpegVer);
      final silent = gain < _silenceGainThreshold;

      if (silent && !inSilence) {
        silenceStart = time;
        inSilence = true;
      } else if (!silent && inSilence) {
        final dur = time - silenceStart;
        if (dur >= _minSilenceDuration) {
          silences.add(SilenceRange(silenceStart, time));
        }
        inSilence = false;
      }

      // Frame duration (MPEG Layer III: 1152 samples per frame)
      final frameDuration = 1152.0 / sampleRate;
      time += frameDuration;
      offset += frameSize;
    }

    // Close an open silence run at EOF
    if (inSilence) {
      final dur = time - silenceStart;
      if (dur >= _minSilenceDuration) {
        silences.add(SilenceRange(silenceStart, time));
      }
    }

    return Mp3ScanResult(
      spliceCandidates: splices,
      silenceRanges: silences,
      totalDurationSeconds: time,
    );
  }

  // ── ID3v2 tag skip ────────────────────────────────────────────────────────

  static int _skipId3(Uint8List b) {
    if (b.length < 10) return 0;
    // ID3 magic
    if (b[0] != 0x49 || b[1] != 0x44 || b[2] != 0x33) return 0;
    // Syncsafe integer (7 bits per byte)
    final size = ((b[6] & 0x7F) << 21) |
        ((b[7] & 0x7F) << 14) |
        ((b[8] & 0x7F) << 7) |
        (b[9] & 0x7F);
    final hasFooter = (b[5] & 0x10) != 0;
    return 10 + size + (hasFooter ? 10 : 0);
  }

  // ── global_gain extraction from MPEG side information ────────────────────
  //
  // The side information follows the 4-byte frame header (and optional 2-byte
  // CRC).  We read the global_gain of granule 0 / channel 0 only — sufficient
  // as a per-frame loudness proxy.
  //
  // Bit offsets of global_gain (8 bits) within the side information block:
  //   MPEG1 stereo  → bit 43   (after 9+5+4+4+12+9 = 43 preceding bits)
  //   MPEG1 mono    → bit 37   (after 9+3+4+12+9  = 37 preceding bits)
  //   MPEG2 stereo  → bit 31   (after 8+2+12+9    = 31 preceding bits)
  //   MPEG2 mono    → bit 30   (after 8+1+12+9    = 30 preceding bits)

  static int _readGlobalGain(
    Uint8List bytes,
    int frameOffset,
    bool crcProtected,
    bool isMono,
    int mpegVer,
  ) {
    final sideOffset = frameOffset + 4 + (crcProtected ? 2 : 0);
    final bitStart = _gainBitOffset(isMono, mpegVer);
    return _readBits(bytes, sideOffset, bitStart, 8);
  }

  static int _gainBitOffset(bool isMono, int mpegVer) {
    if (mpegVer == 0) return isMono ? 37 : 43; // MPEG1
    return isMono ? 30 : 31;                    // MPEG2 / MPEG2.5
  }

  static int _readBits(Uint8List data, int byteOffset, int bitStart, int n) {
    int result = 0;
    for (int i = 0; i < n; i++) {
      final absBit = bitStart + i;
      final idx = byteOffset + (absBit >> 3);
      if (idx >= data.length) break;
      final bitInByte = 7 - (absBit & 7);
      result = (result << 1) | ((data[idx] >> bitInByte) & 1);
    }
    return result;
  }
}
