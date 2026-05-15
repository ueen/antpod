// lib/ad_detection/mp3_scanner.dart
//
// Pure-Dart MPEG Layer III frame scanner. No FFI, no platform channels.
//
// Extracts encoding discontinuities — bitrate / sample-rate / channel-mode
// changes between consecutive frames.  Dynamic ad insertion almost always
// splices a differently-encoded segment into the feed audio.
//
// Silence detection has been intentionally removed: global_gain thresholding
// produces too many false positives on quiet-but-non-silent content.

import 'dart:typed_data';

// ─── Public types ─────────────────────────────────────────────────────────────

class SpliceCandidate {
  const SpliceCandidate(this.timestampSeconds, this.reason);
  final double timestampSeconds;
  final String reason; // 'bitrate_change' | 'samplerate_change' | 'mode_change'
}

class Mp3ScanResult {
  const Mp3ScanResult({
    required this.spliceCandidates,
    required this.totalDurationSeconds,
  });
  final List<SpliceCandidate> spliceCandidates;
  final double totalDurationSeconds;
}

// ─── Scanner ──────────────────────────────────────────────────────────────────

class Mp3Scanner {
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

    double time = 0.0;
    int? prevBitrate, prevSampleRate;
    bool? prevMono;

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
      final mpegVer = versionBits == 3 ? 0 : (versionBits == 2 ? 1 : 2);

      // Layer (bits 18-17) — only Layer III supported
      final layerBits = (h1 >> 1) & 0x03;
      if (layerBits != 1) { offset++; continue; }

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
        if (prevSampleRate != sampleRate) {
          // Sample-rate changes are the strongest signal — almost never happen
          // in a continuous recording, almost always indicate an inserted segment.
          splices.add(SpliceCandidate(time, 'samplerate_change'));
        } else if (prevMono != isMono) {
          // Channel-mode flips (stereo↔mono) are likewise very reliable.
          splices.add(SpliceCandidate(time, 'mode_change'));
        } else if (prevBitrate != bitrateKbps) {
          // Bitrate changes are common in VBR — only useful when corroborated
          // by clustering (many changes near the same timestamp).
          splices.add(SpliceCandidate(time, 'bitrate_change'));
        }
      }
      prevBitrate = bitrateKbps;
      prevSampleRate = sampleRate;
      prevMono = isMono;

      // Frame duration (MPEG Layer III: 1152 samples per frame)
      final frameDuration = 1152.0 / sampleRate;
      time += frameDuration;
      offset += frameSize;
    }

    return Mp3ScanResult(
      spliceCandidates: splices,
      totalDurationSeconds: time,
    );
  }

  // ── ID3v2 tag skip ────────────────────────────────────────────────────────

  static int _skipId3(Uint8List b) {
    if (b.length < 10) return 0;
    if (b[0] != 0x49 || b[1] != 0x44 || b[2] != 0x33) return 0;
    final size = ((b[6] & 0x7F) << 21) |
        ((b[7] & 0x7F) << 14) |
        ((b[8] & 0x7F) << 7) |
        (b[9] & 0x7F);
    final hasFooter = (b[5] & 0x10) != 0;
    return 10 + size + (hasFooter ? 10 : 0);
  }
}
