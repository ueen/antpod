// lib/about.dart
//
// AntPod's about bubble, and the ant that strolls across the toolbar.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n/app_localizations.dart';

/// AntPod's about bubble, under the logo; its Settings button closes it
/// and calls [onSettings].
void showAboutBubble(BuildContext context, {required VoidCallback onSettings}) {
  final topPad = MediaQuery.of(context).padding.top;

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppLocalizations.of(context)!.aboutAntpod,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      // cs comes from the dialog's own context so it respects the live theme
      final cs = Theme.of(ctx).colorScheme;
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(ctx),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.only(
                top: topPad + 46,
                left: 12,
                right: 12,
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: 300,
                    child: CustomPaint(
                      painter: _BubblePainter(cs: cs),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Title row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ClipOval(child: SvgPicture.asset(
                                    'antpodlogo.svg', width: 24, height: 24)),
                                const SizedBox(width: 8),
                                Text('AntPod',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: cs.onPrimaryContainer,
                                    letterSpacing: -0.4,
                                  )),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Body text
                            Text(
                              AppLocalizations.of(ctx)!.aboutText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: cs.onPrimaryContainer,
                                fontSize: 12.5,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // GitHub and Settings, half the width each;
                            // Settings, the main one, on the right.
                            Row(
                              children: [
                                Expanded(
                                  child: _BubbleButton(
                                    icon: SvgPicture.string(
                                      _kGithubSvg,
                                      width: 16, height: 16,
                                      colorFilter: ColorFilter.mode(
                                          cs.onPrimaryContainer, BlendMode.srcIn),
                                    ),
                                    label: 'GitHub',
                                    color: cs.onPrimaryContainer,
                                    fill: cs.onPrimaryContainer.withValues(alpha: 0.1),
                                    border: BorderSide(
                                        color: cs.onPrimaryContainer.withValues(alpha: 0.25)),
                                    onTap: () => launchUrl(
                                      Uri.parse('https://github.com/ueen/antpod'),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _BubbleButton(
                                    icon: Icon(Icons.settings_rounded,
                                        size: 18, color: cs.onPrimary),
                                    label: AppLocalizations.of(ctx)!.settings,
                                    color: cs.onPrimary,
                                    fill: cs.primary,
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      onSettings();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// A pill button in the about bubble. A long label shrinks to fit rather
/// than wrapping ("Einstellungen" is long next to a half-width button).
class _BubbleButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final Color color;
  final Color fill;
  final BorderSide border;
  final VoidCallback onTap;

  const _BubbleButton({
    required this.icon, required this.label, required this.color,
    required this.fill, this.border = BorderSide.none, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: fill,
        shape: StadiumBorder(side: border),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label,
                          maxLines: 1,
                          style: TextStyle(
                              color: color, fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Speech-bubble painter for the About dialog
// ─────────────────────────────────────────────────────────────────────────────

const _kGithubSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
  <path fill="#000000" fill-rule="evenodd" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38
    0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01
    1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95
    0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0
    1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15
    0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38
    A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/>
</svg>
''';

class _BubblePainter extends CustomPainter {
  final ColorScheme cs;
  const _BubblePainter({required this.cs});

  @override
  void paint(Canvas canvas, Size size) {
    const r = 14.0;
    const triW = 18.0;
    const triH = 11.0;
    const triX = 36.0; // triangle tip x, aligned near top-left logo

    final path = Path()
      ..moveTo(r, triH)
      ..lineTo(triX - triW / 2, triH)
      ..lineTo(triX, 0)
      ..lineTo(triX + triW / 2, triH)
      ..lineTo(size.width - r, triH)
      ..arcToPoint(Offset(size.width, triH + r), radius: const Radius.circular(r))
      ..lineTo(size.width, size.height - r)
      ..arcToPoint(Offset(size.width - r, size.height), radius: const Radius.circular(r))
      ..lineTo(r, size.height)
      ..arcToPoint(Offset(0, size.height - r), radius: const Radius.circular(r))
      ..lineTo(0, triH + r)
      ..arcToPoint(Offset(r, triH), radius: const Radius.circular(r))
      ..close();

    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    final fill = Paint()
      ..shader = LinearGradient(
        colors: [cs.primaryContainer, cs.secondaryContainer, cs.tertiaryContainer],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds)
      ..style = PaintingStyle.fill;

    canvas.drawShadow(path, cs.primary.withValues(alpha: 0.3), 12, false);
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.cs != cs;
}

// ─────────────────────────────────────────────────────────────────────────────
// Ant walker — decorative ant that occasionally strolls across the toolbar
// ─────────────────────────────────────────────────────────────────────────────

class AntWalker extends StatefulWidget {
  const AntWalker({super.key});

  @override
  State<AntWalker> createState() => AntWalkerState();
}

class AntWalkerState extends State<AntWalker> with TickerProviderStateMixin {
  late final AnimationController _legCtrl;
  late final AnimationController _pathCtrl;
  Timer? _timer;
  _AntPath? _path;
  bool _walking = false;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _legCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    // _legCtrl only runs during a walk — stopped the rest of the time
    // so it doesn't hold a continuous animation frame callback.

    _pathCtrl = AnimationController(vsync: this);
    _pathCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        _legCtrl.stop();
        setState(() => _walking = false);
        _scheduleNext();
      }
    });

    _scheduleNext();
  }

  @override
  void dispose() {
    _legCtrl.dispose();
    _pathCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleNext() {
    // Random gap between 8 and 20 minutes
    final ms = 480000 + _rng.nextInt(720001);
    _timer = Timer(Duration(milliseconds: ms), () {
      if (mounted) startWalk();
    });
  }

  void startWalk() {
    _timer?.cancel();
    if (_walking) return;
    final w = MediaQuery.sizeOf(context).width;
    const toolbarH = 56.0;
    const margin = 10.0;

    final fromLeft = _rng.nextBool();
    final startX = fromLeft ? -20.0 : w + 20.0;
    final endX   = fromLeft ? w + 20.0 : -20.0;

    double randY() => margin + _rng.nextDouble() * (toolbarH - 2 * margin);

    // 2–4 interior waypoints for an organic, meandering path
    final numInterior = 2 + _rng.nextInt(3);
    final pts = <Offset>[Offset(startX, randY())];
    for (int i = 0; i < numInterior; i++) {
      final baseFrac = (i + 1) / (numInterior + 1);
      // Slight X jitter so progress isn't perfectly linear
      final xJitter = (endX - startX) * (_rng.nextDouble() - 0.5) * 0.16;
      final x = (startX + (endX - startX) * baseFrac + xJitter)
          .clamp(math.min(startX, endX), math.max(startX, endX)) as double;
      pts.add(Offset(x, randY()));
    }
    pts.add(Offset(endX, randY()));

    _path = _AntPath(pts);
    _pathCtrl.duration = Duration(milliseconds: 4000 + _rng.nextInt(3000));
    _pathCtrl.reset();
    _legCtrl.repeat();
    setState(() => _walking = true);
    _pathCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (!_walking || _path == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: Listenable.merge([_legCtrl, _pathCtrl]),
      builder: (_, __) {
        final pos   = _path!.evaluate(_pathCtrl.value);
        final angle = _path!.angle(_pathCtrl.value);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            const SizedBox.expand(), // gives the Stack its size from tight constraints
            Positioned(
              left: pos.dx - 14,
              top:  pos.dy - 14,
              width: 28, height: 28,
              child: Transform.rotate(
                angle: angle,
                child: CustomPaint(
                  painter: _AntPainter(
                    legPhase: _legCtrl.value,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFFD4956A)
                        : const Color(0xFF7B3F00),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// Multi-waypoint Catmull-Rom spline — smooth curves through arbitrary waypoints.
class _AntPath {
  final List<Offset> _pts;
  final List<double> _cumT; // cumulative t per segment (straight-line length proxy)

  _AntPath(List<Offset> pts)
      : _pts = pts,
        _cumT = _buildCumT(pts);

  static List<double> _buildCumT(List<Offset> pts) {
    double total = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      total += (pts[i + 1] - pts[i]).distance;
    }
    final result = [0.0];
    double acc = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      acc += (pts[i + 1] - pts[i]).distance;
      result.add(total > 0 ? acc / total : (i + 1) / (pts.length - 1).toDouble());
    }
    return result;
  }

  // Catmull-Rom bezier control points for segment i → i+1
  (Offset, Offset) _cp(int i) {
    final p0 = _pts[i];
    final p1 = _pts[i + 1];
    final prev = i > 0 ? _pts[i - 1] : p0 * 2 - p1;
    final next = i + 2 < _pts.length ? _pts[i + 2] : p1 * 2 - p0;
    return (p0 + (p1 - prev) * (1 / 6), p1 - (next - p0) * (1 / 6));
  }

  Offset evaluate(double t) {
    t = t.clamp(0.0, 1.0);
    for (int i = 0; i < _pts.length - 1; i++) {
      if (t <= _cumT[i + 1] || i == _pts.length - 2) {
        final span = _cumT[i + 1] - _cumT[i];
        final u = span > 1e-6 ? ((t - _cumT[i]) / span).clamp(0.0, 1.0) : 0.0;
        final (cp1, cp2) = _cp(i);
        final p0 = _pts[i]; final p1 = _pts[i + 1];
        final s = 1 - u;
        return p0 * (s*s*s) + cp1 * (3*s*s*u) + cp2 * (3*s*u*u) + p1 * (u*u*u);
      }
    }
    return _pts.last;
  }

  double angle(double t) {
    const dt = 0.002;
    final a = evaluate((t - dt).clamp(0.0, 1.0));
    final b = evaluate((t + dt).clamp(0.0, 1.0));
    final d = b - a;
    if (d.distanceSquared < 1e-10) return 0;
    return math.atan2(d.dy, d.dx) + math.pi / 2;
  }
}

// Ant drawn top-down, centered at (0,0) in local coords, facing -y
class _AntPainter extends CustomPainter {
  final double legPhase;
  final Color color;

  const _AntPainter({required this.legPhase, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);

    final fill = Paint()..color = color..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 0.85
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final t = legPhase * math.pi * 2;

    // Abdomen (largest, rear)
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 5.5), width: 5.5, height: 7),
      fill,
    );
    // Thorax (tiny waist in the middle)
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 3.2, height: 3.5),
      fill,
    );
    // Head (front)
    canvas.drawCircle(const Offset(0, -5.5), 2.8, fill);

    // Antennae — subtly wiggle
    canvas.drawLine(const Offset(0, -8.3),
        Offset(-3 + math.sin(t) * 0.25, -12.5), stroke);
    canvas.drawLine(const Offset(0, -8.3),
        Offset( 3 - math.sin(t) * 0.25, -12.5), stroke);

    // Six legs (3 pairs) with alternating-tripod gait
    for (var i = 0; i < 3; i++) {
      final yA = (i - 1) * 2.2; // –2.2, 0, +2.2 along the thorax

      // Right leg — tripod A swings on even indices
      final rP = (i.isEven) ? t : t + math.pi;
      final rSwing = math.sin(rP) * 2.2;
      canvas.drawLine(Offset(1.6, yA), Offset(7, yA + rSwing), stroke);

      // Left leg — opposite tripod
      final lP = (i.isOdd) ? t : t + math.pi;
      final lSwing = math.sin(lP) * 2.2;
      canvas.drawLine(Offset(-1.6, yA), Offset(-7, yA + lSwing), stroke);
    }
  }

  @override
  bool shouldRepaint(_AntPainter old) => old.legPhase != legPhase || old.color != color;
}
