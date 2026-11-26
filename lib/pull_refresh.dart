// lib/pull_refresh.dart
import 'dart:math' show pi, cos, sin;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderSliverToBoxAdapter, SliverGeometry;

// ─────────────────────────────────────────────────────────────────────────────
// Pull-to-refresh — a banner that grows as the list is pulled down from the
// top; letting go past the threshold refreshes
// ─────────────────────────────────────────────────────────────────────────────

/// Pull-to-refresh for a [CustomScrollView] driven by [controller]: [builder]
/// gets the banner sliver, to put first among the view's slivers. Use
/// [SmoothScrollPhysics] (or other clamping physics) so the pull doesn't
/// bounce the list.
class PullToRefresh extends StatefulWidget {
  final ScrollController controller;
  final Future<void> Function() onRefresh;
  /// A refresh started elsewhere: the banner shows its spinner meanwhile.
  final bool refreshing;
  /// Keep the banner and its spinner open until [onRefresh] completes. Off,
  /// the banner shows an arrow that turns with the pull and folds away as
  /// soon as the pull triggers: for a page that shows its own progress.
  final bool holdWhileRefreshing;
  final Widget Function(Widget banner) builder;

  const PullToRefresh({
    super.key,
    required this.controller,
    required this.onRefresh,
    required this.builder,
    this.refreshing = false,
    this.holdWhileRefreshing = true,
  });

  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<PullToRefresh> {
  static const double _threshold = 55.0;
  static const double _max = 70.0;
  static const double _height = 52.0;

  bool _eligible = false;
  bool _refreshing = false;
  // Drag distance lives in a notifier so pointer moves only rebuild the banner,
  // not the whole list (a setState per move made scrolling lag).
  final _drag = ValueNotifier<double>(0.0);

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  ScrollController get _ctrl => widget.controller;

  void _release() {
    if (!_eligible) return;
    _eligible = false;
    final pulled = _drag.value >= _threshold;
    _drag.value = 0;
    if (!pulled || _refreshing) return;
    setState(() => _refreshing = true);
    widget.onRefresh().whenComplete(() {
      if (mounted) setState(() => _refreshing = false);
    });
  }

  Widget _banner(ColorScheme cs) => ValueListenableBuilder<double>(
        valueListenable: _drag,
        builder: (_, drag, __) {
          final active = widget.holdWhileRefreshing &&
              (widget.refreshing || _refreshing);
          final height =
              active ? _height : (drag / _max * _height).clamp(0.0, _height);
          return AnimatedContainer(
            duration: drag > 0 && !active
                ? Duration.zero
                : const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            height: height,
            color: cs.surfaceContainerHighest,
            child: height <= 20
                ? null
                : Center(
                    child: widget.holdWhileRefreshing
                        ? AntSpinner(color: cs.primary)
                        : _arrow(cs, drag)),
          );
        },
      );

  /// Turns with the pull, three quarters round at the threshold; past it,
  /// fully opaque and a little larger: letting go refreshes.
  Widget _arrow(ColorScheme cs, double drag) {
    final t = (drag / _threshold).clamp(0.0, 1.0);
    final armed = drag >= _threshold;
    return AnimatedScale(
      scale: armed ? 1.15 : 1,
      duration: const Duration(milliseconds: 150),
      child: Transform.rotate(
        angle: drag / _threshold * 1.5 * pi,
        child: Icon(Icons.refresh_rounded, size: 24,
            color: cs.primary.withValues(alpha: 0.35 + 0.65 * t)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (e) {
          _eligible = _ctrl.hasClients && _ctrl.offset <= 0;
          if (_eligible) _drag.value = 0;
        },
        onPointerMove: (e) {
          if (!_eligible) return;
          if (!_ctrl.hasClients || _ctrl.offset > 1) {
            _eligible = false;
            _drag.value = 0;
            return;
          }
          final dy = e.delta.dy;
          final cur = _drag.value;
          if (dy == 0 || (dy < 0 && cur == 0)) return;
          final next = (cur + dy * 0.5).clamp(0.0, _max);
          if ((next - cur).abs() > 0.5) _drag.value = next;
        },
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) {
          _eligible = false;
          _drag.value = 0;
        },
        child: widget.builder(
            _StableTopSliver(child: _banner(Theme.of(context).colorScheme))),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Smooth scroll physics
// ─────────────────────────────────────────────────────────────────────────────

// Scrolls ~40% further than Android default (friction 0.015 → 0.007) while
// keeping a clean exponential decay — no spring tail.
class SmoothScrollPhysics extends ClampingScrollPhysics {
  const SmoothScrollPhysics()
      : super(parent: const AlwaysScrollableScrollPhysics());

  @override
  SmoothScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      const SmoothScrollPhysics();

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    final tolerance = toleranceFor(position);
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    if (velocity.abs() < tolerance.velocity) return null;
    if (velocity > 0 && position.pixels >= position.maxScrollExtent) return null;
    if (velocity < 0 && position.pixels <= position.minScrollExtent) return null;
    return ClampingScrollSimulation(
      position: position.pixels,
      velocity: velocity,
      friction: 0.007,
      tolerance: tolerance,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Refresh banner sliver — keeps the content still when the banner resizes
// while it is scrolled out of view
// ─────────────────────────────────────────────────────────────────────────────

/// Like [SliverToBoxAdapter], but when its height changes while it is
/// completely scrolled past (e.g. a refresh starts or ends while the user is
/// further down the list) it reports a scroll-offset correction so the
/// visible content does not jump. While it is visible at the top it grows and
/// shrinks normally, pushing the list as the pull gesture expects.
class _StableTopSliver extends SingleChildRenderObjectWidget {
  const _StableTopSliver({required Widget super.child});

  @override
  RenderSliverToBoxAdapter createRenderObject(BuildContext context) =>
      _RenderStableTopSliver();
}

class _RenderStableTopSliver extends RenderSliverToBoxAdapter {
  double? _lastExtent;

  @override
  void performLayout() {
    final box = child;
    if (box == null) {
      super.performLayout();
      return;
    }
    box.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final extent = box.size.height;
    final last = _lastExtent;
    _lastExtent = extent;
    if (last != null &&
        extent != last &&
        constraints.scrollOffset > 0 &&
        constraints.scrollOffset >= last) {
      // Viewport applies the correction and lays out again.
      geometry = SliverGeometry(scrollOffsetCorrection: extent - last);
      return;
    }
    super.performLayout();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ant spinner — a ring of 8 dots turning slowly clockwise while two
// "prominent" highlights hop dot-to-dot, each hop a short crossfade (next dot
// fades in while the previous one fades out). One circles counterclockwise,
// the other clockwise from a quarter turn further on, at two thirds its speed,
// so where they cross wanders round the ring.
// ─────────────────────────────────────────────────────────────────────────────

class AntSpinner extends StatefulWidget {
  final Color color;
  final double size;
  const AntSpinner({super.key, required this.color, this.size = 22});

  @override
  State<AntSpinner> createState() => _AntSpinnerState();
}

class _AntSpinnerState extends State<AntSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5250),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          size: Size.square(widget.size),
          painter: AntsPainter(progress: _ctrl.value, color: widget.color),
        ),
      );
}

class AntsPainter extends CustomPainter {
  final double progress;
  final Color color;

  const AntsPainter({required this.progress, required this.color});

  static const dotCount = 8;

  /// Prominence (0–1) of ring dot [j] at [progress]. Dot j sits at
  /// (j + 6·progress) eighths of a turn clockwise from the top.
  static double prominenceOf(int j, double progress) {
    // The ring turns 6 dot-positions clockwise per cycle. The first highlight
    // steps 30 dots counterclockwise against it (net: three turns
    // counterclockwise per cycle); the second, starting 2 dots (a quarter
    // turn) on, steps 10 dots clockwise with it (net: two turns clockwise).
    // Both loop seamlessly: each step count matches the ring's mod 8.
    final ccw = _prominence((progress * 30 + j) % dotCount);
    final cw = _prominence((progress * 10 - j + 2) % dotCount);
    return ccw > cw ? ccw : cw;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width * 0.40;
    final scale = size.width / 22;
    final paint = Paint()..style = PaintingStyle.fill;

    final ringPhase = progress * 6 / dotCount;
    for (int j = 0; j < dotCount; j++) {
      final angle = (j / dotCount + ringPhase) * 2 * pi - pi / 2;
      final p = prominenceOf(j, progress);
      paint.color = color.withValues(alpha: 0.3 + 0.7 * p);
      canvas.drawCircle(
          Offset(cx + cos(angle) * radius, cy + sin(angle) * radius),
          (1.5 + 1.4 * p) * scale,
          paint);
    }
  }

  /// Prominence (0–1) of a dot at phase [tau] ∈ [0, 8): quick fade-in just
  /// before its turn, a short hold, then a slower fade-out that overlaps the
  /// next dot's fade-in.
  static double _prominence(double tau) {
    double smooth(double x) {
      final t = x.clamp(0.0, 1.0);
      return t * t * (3 - 2 * t);
    }

    if (tau >= 7.6) return smooth((tau - 7.6) / 0.4);
    if (tau < 0.4) return 1;
    if (tau < 1.4) return 1 - smooth(tau - 0.4);
    return 0;
  }

  @override
  bool shouldRepaint(AntsPainter old) =>
      old.progress != progress || old.color != color;
}
