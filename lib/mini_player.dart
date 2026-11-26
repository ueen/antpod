// lib/mini_player.dart
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_binding.dart';
import 'app_database.dart';
import 'html_utils.dart';
import 'l10n/app_localizations.dart';
import 'player_provider.dart';
import 'share_utils.dart';

class MiniPlayer extends StatefulWidget {
  final VoidCallback? onPodcastTap;
  const MiniPlayer({super.key, this.onPodcastTap});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  /// The open (or opening) player sheet pushed from here.
  PlayerSheetRoute? _route;

  /// The sheet out or on its way, until its transition has run out: the
  /// mini player hides meanwhile, its stand-in rides the sheet's edge.
  PlayerSheetRoute? _shown;

  /// The finger last down on the mini player.
  int? _pointer;

  /// Pushes the sheet; [tracking]: the finger moves it, from closed, and
  /// stays on it through the push.
  PlayerSheetRoute? _push({required bool tracking}) {
    if (_route != null) return null;
    final route = _playerRoute(context,
        onPodcastTap: widget.onPodcastTap, tracking: tracking, locate: _locate);
    _route = route;
    final nav = Navigator.of(context);
    AppBinding.keepPointer(tracking ? _pointer : null, () => nav.push(route))
        .whenComplete(() {
      if (identical(_route, route)) _route = null;
    });
    setState(() => _shown = route);
    route.completed.whenComplete(() {
      if (mounted && identical(_shown, route)) setState(() => _shown = null);
    });
    return route;
  }

  /// Where the mini player is in the navigator, when it's laid out.
  Rect? _locate() {
    if (!mounted) return null;
    final box = context.findRenderObject();
    final nav = Navigator.of(context).context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize ||
        box.size.isEmpty || nav is! RenderBox) {
      return null;
    }
    return box.localToGlobal(Offset.zero, ancestor: nav) & box.size;
  }

  // An upward drag pushes the sheet at once and it follows the finger; one
  // that starts downward does nothing.
  void _onDragUpdate(DragUpdateDetails d) {
    var r = _route;
    if (r == null) {
      if (d.delta.dy >= 0) return;
      r = _push(tracking: true);
      if (r == null) return;
    }
    r.drag(-d.delta.dy);
  }

  void _onDragEnd(DragEndDetails d) =>
      _route?.release(-(d.primaryVelocity ?? 0));

  @override
  Widget build(BuildContext context) {
    // select() avoids rebuilding the whole mini player on every position tick.
    // Only _MiniProgress (the thin bar) rebuilds at 5Hz during playback.
    final hasEpisode = context.select<PlayerProvider, bool>((p) => p.hasEpisode);
    final sheet = _shown?.animation ?? kAlwaysDismissedAnimation;

    // Hidden while the sheet is out: its stand-in moves instead. Built the
    // same way either way, so the drag that opens the sheet goes on.
    return AnimatedBuilder(
      animation: sheet,
      builder: (_, child) =>
          Opacity(opacity: sheet.value > 0 ? 0 : 1, child: child),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        alignment: Alignment.bottomCenter,
        child: hasEpisode
            ? Listener(
                onPointerDown: (e) => _pointer = e.pointer,
                child: RawGestureDetector(
                gestures: {
                  TapGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    () => TapGestureRecognizer(debugOwner: this),
                    (r) => r.onTap = () => _push(tracking: false),
                  ),
                  // Every release counts, however slow: the sheet goes on
                  // at the finger's speed.
                  VerticalDragGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          VerticalDragGestureRecognizer>(
                    () => VerticalDragGestureRecognizer(debugOwner: this),
                    (r) => r
                      ..minFlingDistance = 0
                      ..minFlingVelocity = 0
                      ..onUpdate = _onDragUpdate
                      ..onEnd = _onDragEnd
                      ..onCancel = () => _route?.release(0),
                  ),
                },
                child: const _MiniCard(),
              ))
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// The mini player as it looks: a handle over the card. Its stand-in on
/// the sheet's edge is [bare]: the sheet's frame is its card.
class _MiniCard extends StatelessWidget {
  const _MiniCard({this.bare = false});

  final bool bare;

  /// The card within the mini player, and its corners.
  static const insets = EdgeInsets.fromLTRB(12, 7, 12, 8);
  static const radius = 12.0;

  @override
  Widget build(BuildContext context) {
    final imageUrl = context.select<PlayerProvider, String>(
        (p) => p.currentEpisode?.podcastImageUrl ?? '');
    final title = context.select<PlayerProvider, String>(
        (p) => p.currentEpisode?.title ?? '');
    final podcastTitle = context.select<PlayerProvider, String>(
        (p) => p.currentEpisode?.podcastTitle ?? '');
    final isPlaying = context.select<PlayerProvider, bool>((p) => p.isPlaying);
    final isLoading = context.select<PlayerProvider, bool>((p) => p.isLoading);
    final rewindSec = context.select<PlayerProvider, int>((p) => p.rewindSeconds);
    final forwardSec = context.select<PlayerProvider, int>((p) => p.forwardSeconds);
    final isOffline = context.select<PlayerProvider, bool>((p) => p.isOffline);
    final isDownloaded = context.select<PlayerProvider, bool>(
        (p) => p.currentEpisode?.localPath != null);
    final cs = Theme.of(context).colorScheme;
    final canPlay = !isOffline || isDownloaded;

    return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            width: 32, height: 3,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          Container(
        // Below the handle's 3 + 4: insets.
        margin: EdgeInsets.fromLTRB(insets.left, 0, insets.right, insets.bottom),
        height: 68,
        decoration: bare
            ? null
            : BoxDecoration(
                color: cs.inverseSurface,
                borderRadius: BorderRadius.circular(radius),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4))
                ],
              ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: [
              // Isolated widget — only this rebuilds on position ticks
              const Positioned(
                left: 0, right: 0, bottom: 0,
                child: _MiniProgress(),
              ),

              Padding(
                // The cover centered above the progress bar: as far from
                // it as from the card's top.
                padding:
                    const EdgeInsets.fromLTRB(12, 0, 12, _MiniProgress.height),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 44, height: 44, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: cs.inversePrimary,
                          child: const Icon(Icons.podcasts_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: cs.inversePrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                          Text(
                            podcastTitle,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: cs.inversePrimary.withValues(alpha: 0.6),
                                fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    _iconBtn(cs, _skipRewindIcon(rewindSec),
                        () => context.read<PlayerProvider>().skipBackward()),
                    SizedBox(
                      width: 44, height: 44,
                      child: _playSwitch(isLoading
                          ? Padding(
                              key: const ValueKey('loading'),
                              padding: const EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                  strokeWidth: 3, strokeCap: StrokeCap.round,
                                  color: cs.inversePrimary),
                            )
                          : !canPlay
                              ? Icon(Icons.wifi_off_rounded,
                                  key: const ValueKey('offline'),
                                  color: cs.inversePrimary.withValues(alpha: 0.5), size: 26)
                              : IconButton(
                                  key: ValueKey(isPlaying),
                                  onPressed: () => context.read<PlayerProvider>().togglePlayPause(),
                                  icon: Icon(
                                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: cs.inversePrimary, size: 34),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                )),
                    ),
                    _iconBtn(cs,
                        _skipForwardIconDirect(forwardSec) ?? _skipRewindIcon(forwardSec),
                        () => context.read<PlayerProvider>().skipForward(),
                        flipX: _skipForwardIconDirect(forwardSec) == null),
                  ],
                ),
              ),
            ],
          ),
        ),
          ), // Container (mini player card)
        ],   // Column children
      );     // Column
  }

  Widget _iconBtn(ColorScheme cs, IconData icon, VoidCallback onTap,
      {double size = 26, bool flipX = false}) {
    Widget ico = Icon(icon, color: cs.inversePrimary, size: size);
    if (flipX) ico = Transform.flip(flipX: true, child: ico);
    return IconButton(
      onPressed: onTap,
      icon: ico,
      padding: EdgeInsets.zero,
      // Narrow, so the three buttons sit close together on the right.
      constraints: const BoxConstraints(minWidth: 34, minHeight: 44),
    );
  }
}

// Isolated progress bar — only this widget rebuilds on position ticks (~5Hz).
// The rest of MiniPlayer stays still until episode/isPlaying changes.
class _MiniProgress extends StatelessWidget {
  const _MiniProgress();

  /// The spinner's and the episode tiles' progress stroke.
  static const height = 3.0;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>();
    // Rebuild on a new duration too, not only on position ticks.
    context.select<PlayerProvider, Duration>((p) => p.duration);
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ValueListenableBuilder<Duration>(
        valueListenable: player.positionListenable,
        builder: (_, pos, __) => LinearProgressIndicator(
          value: player.progressAt(pos),
          minHeight: height,
          backgroundColor: Colors.transparent,
          color: cs.inversePrimary,
        ),
      ),
    );
  }
}

/// The sheet's slider and time labels. They follow the position on their
/// own (the rest of the sheet doesn't rebuild per tick), and while dragging
/// they follow the finger: the seek happens once, on release.
class _SeekBar extends StatefulWidget {
  final PlayerProvider player;
  final String Function(Duration) fmt;
  const _SeekBar({required this.player, required this.fmt});

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  /// 0..1 while the finger is on the slider.
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final cs = Theme.of(context).colorScheme;
    final label = TextStyle(fontSize: 11, color: cs.onSurfaceVariant);
    return ValueListenableBuilder<Duration>(
      valueListenable: player.positionListenable,
      builder: (context, pos, _) {
        final dur = player.duration;
        final shown = _drag != null ? dur * _drag! : pos;
        return Column(children: [
          SliderTheme(
            data: SliderThemeData(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              trackHeight: 3,
              // The accent, like the mini player's bar.
              activeTrackColor: cs.tertiary,
              inactiveTrackColor: cs.tertiary.withValues(alpha: 0.2),
              thumbColor: cs.tertiary,
              overlayColor: cs.tertiary.withValues(alpha: 0.12),
            ),
            child: Slider(
              value: _drag ?? player.progressAt(pos),
              onChangeStart: (v) => setState(() => _drag = v),
              onChanged: (v) => setState(() => _drag = v),
              onChangeEnd: (v) {
                // Clear the drag after the seek is sent: the player already
                // reports the target, so the thumb doesn't spring back.
                player.seekTo(dur * v);
                setState(() => _drag = null);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.fmt(shown), style: label),
                Text(widget.fmt(dur), style: label),
              ],
            ),
          ),
        ]);
      },
    );
  }
}

/// Play, pause, loading and offline cross-fade with a slight zoom; each
/// state's child carries its own key. Passthrough keeps the button's tight
/// size, so its tap area stays as it was.
Widget _playSwitch(Widget child) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.center,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
            scale: Tween(begin: 0.7, end: 1.0).animate(anim), child: child),
      ),
      child: child,
    );

// Shared skip-icon helpers (used by mini player and bottom sheet)

IconData _skipRewindIcon(int s) {
  if (s == 5)  return Icons.replay_5_rounded;
  if (s == 10) return Icons.replay_10_rounded;
  if (s == 30) return Icons.replay_30_rounded;
  return Icons.replay_rounded;
}

// Returns a dedicated forward icon (with number) if one exists, null otherwise.
// When null, callers should mirror the rewind icon with Transform.flip.
IconData? _skipForwardIconDirect(int s) {
  if (s == 5)  return Icons.forward_5_rounded;
  if (s == 10) return Icons.forward_10_rounded;
  if (s == 30) return Icons.forward_30_rounded;
  return null;
}


/// Opens the player sheet from elsewhere (a link): it rises from the
/// bottom edge.
Future<void> showPlayerSheet(BuildContext context,
        {VoidCallback? onPodcastTap}) =>
    Navigator.of(context).push(
        _playerRoute(context, onPodcastTap: onPodcastTap, tracking: false));

PlayerSheetRoute _playerRoute(BuildContext context,
    {VoidCallback? onPodcastTap,
    required bool tracking,
    Rect? Function()? locate}) {
  final player = context.read<PlayerProvider>();
  final cs = Theme.of(context).colorScheme;
  final themes = InheritedTheme.capture(
      from: context, to: Navigator.of(context).context);
  Widget wrap(Widget child) => themes
      .wrap(ChangeNotifierProvider.value(value: player, child: child));
  return PlayerSheetRoute(
    tracking: tracking,
    openSize: _PlayerSheet.initialSize,
    maxSize: _PlayerSheet.maxSize,
    color: cs.surface,
    fromColor: cs.inverseSurface,
    fromInsets: _MiniCard.insets,
    fromRadius: _MiniCard.radius,
    locate: locate,
    standIn: locate == null ? null : (_) => wrap(const _MiniCard(bare: true)),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    builder: (_, scroll) =>
        wrap(_PlayerSheet(onPodcastTap: onPodcastTap, scroll: scroll)),
  );
}

/// The player sheet over a dark barrier. It grows out of the mini player's
/// card: the card's frame stretches into the sheet's, its colour gives way
/// to the sheet's only near the top, and the sheet's content shows only
/// once it's nearly open. Closing, the same backwards.
///
/// A tap opens it on its own. A drag, on the mini player or on the sheet,
/// moves it 1:1 with the finger, and on release it goes on at the finger's
/// speed and eases out to rest: any motion goes its way (open or closed),
/// a still release goes to the nearer end. Open, a drag up grows it to
/// [maxSize] before its content scrolls; a drag down scrolls the content
/// back first, then shrinks it.
class PlayerSheetRoute extends PopupRoute<void> {
  PlayerSheetRoute({
    super.settings,
    required this.builder,
    required this.barrierLabel,
    required bool tracking,
    this.openSize = 0.6,
    this.maxSize = 0.95,
    this.color,
    this.fromColor,
    this.fromInsets = EdgeInsets.zero,
    this.fromRadius = 0,
    this.locate,
    this.standIn,
  }) : _tracking = tracking;

  /// The sheet's content: a scroll view on the given controller, with
  /// [scrollPhysics]. A drag on it moves the sheet first.
  final Widget Function(BuildContext, ScrollController) builder;

  /// The open sheet's height, of the navigator's.
  final double openSize;

  /// Its height dragged all the way up.
  final double maxSize;

  /// The sheet's background; default: the theme's surface.
  final Color? color;

  /// The mini player card's, where the sheet's starts.
  final Color? fromColor;

  /// The card within [locate]'s rect, and its corners.
  final EdgeInsets fromInsets;
  final double fromRadius;

  /// Where the mini player is in the navigator; the sheet starts there.
  /// None: from the bottom edge.
  final Rect? Function()? locate;

  /// The mini player's look-alike, without its card: it rides the frame.
  final WidgetBuilder? standIn;

  /// For the content's scroll view: any release counts, however slow, and
  /// short content still drags.
  static const ScrollPhysics scrollPhysics =
      _LetGoPhysics(parent: AlwaysScrollableScrollPhysics());

  /// Slower than this, in pixels per second, a release is still.
  static const _still = 20.0;

  /// A release this slow against the finger's way is it lifting, not
  /// sending the sheet back.
  static const _wobble = 150.0;

  /// The finger opens it: no motion of its own on push.
  final bool _tracking;

  Rect? _from;

  /// The finger's way since it last turned: where it set out and the
  /// furthest it went, as [controller] values. Null with no finger on it.
  double? _origin, _peak;

  /// Pixels the open sheet is dragged up beyond [openSize].
  final _expand = ValueNotifier<double>(0);

  /// Moves [_expand] after a release.
  AnimationController? _drift;

  /// Where the drift hands its speed on when it reaches the top.
  ValueChanged<double>? _onTop;

  /// The closing motion a release sets off, for the pop.
  Simulation? _leave;

  late final _scroll = _SheetScrollController(this);

  Size get _size => navigator?.context.size ?? Size.zero;

  /// Pixels the frame's top moves from the card to open.
  double get _travel {
    final h = _size.height;
    final f = _from;
    final start = f == null ? h : f.top + fromInsets.top;
    return math.max(1.0, start - h * (1 - openSize));
  }

  /// How far up a release that isn't sent back opens: twice the mini
  /// player's height, at most half the way.
  double get _reach {
    final f = _from;
    return f == null ? _travel / 4 : math.min(_travel / 2, 2 * f.height);
  }

  double get _maxExpand => math.max(0.0, _size.height * (maxSize - openSize));

  bool get _atTop =>
      controller!.value >= 1 && _expand.value >= _maxExpand - 1e-6;

  @override
  final String? barrierLabel;
  @override
  Color get barrierColor => Colors.black54;
  @override
  bool get barrierDismissible => true;
  @override
  Curve get barrierCurve => Curves.linear;
  // Only for a push the finger takes over at once: every motion is a _Settle.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  void install() {
    _from = locate?.call();
    _drift = AnimationController.unbounded(vsync: navigator!)
      ..addListener(_onDrift);
    super.install();
  }

  @override
  Simulation? createSimulation({required bool forward}) {
    if (forward) return _tracking ? null : _Settle(controller!.value, 1, 0);
    final leave = _leave ?? _Settle(controller!.value, 0, 0);
    _leave = null;
    return leave;
  }

  @override
  TickerFuture didPush() {
    final pushed = super.didPush();
    if (_tracking) controller!.stop(); // the finger moves it
    return pushed;
  }

  @override
  bool didPop(void result) {
    // Back to where the mini player is now.
    _from = locate?.call() ?? _from;
    _drift?.stop();
    _onTop = null;
    return super.didPop(result);
  }

  @override
  void dispose() {
    _drift?.dispose();
    _expand.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A finger is on it: whatever moves it stops there.
  void _grab() {
    if (!isCurrent) return;
    final c = controller!;
    if (c.isAnimating) c.stop();
    _drift?.stop();
    _onTop = null;
  }

  /// A finger takes it, the way it goes yet to be seen.
  void _setOut() {
    _grab();
    _origin = _peak = null;
  }

  /// The finger moved it from [from] to [to]: on its way, or turned back
  /// by more than a touch slop.
  void _track(double from, double to) {
    final o = _origin ??= from;
    final p = _peak ??= from;
    if (p == o || (p > o ? to >= p : to <= p)) {
      _peak = to;
    } else if ((to - p).abs() * _travel > kTouchSlop) {
      _origin = p;
      _peak = to;
    }
  }

  void _onDrift() {
    final d = _drift!;
    final max = _maxExpand;
    if (d.value >= max) {
      final speed = d.velocity;
      _expand.value = max;
      d.stop();
      final top = _onTop;
      _onTop = null;
      if (speed > 0) top?.call(speed);
    } else if (d.value <= 0) {
      _expand.value = 0;
      d.stop();
    } else {
      _expand.value = d.value;
    }
  }

  static double _snap(double x) => x.abs() < 1e-6 ? 0 : x;

  /// The finger moved [dy] pixels, up positive. Up, the sheet opens, then
  /// grows; down, it shrinks back, then closes. Returns what it didn't take.
  double drag(double dy) {
    if (!isCurrent) return dy;
    _grab();
    final c = controller!;
    final t0 = c.value;
    var rest = dy;
    if (rest > 0) {
      final t = c.value;
      if (t < 1) {
        final to = math.min(1.0, t + rest / _travel);
        c.value = to;
        rest = _snap(rest - (to - t) * _travel);
      }
      if (rest > 0) {
        final e = _expand.value;
        final to = math.min(_maxExpand, e + rest);
        _expand.value = to;
        rest = _snap(rest - (to - e));
      }
    } else if (rest < 0) {
      final e = _expand.value;
      if (e > 0) {
        final to = math.max(0.0, e + rest);
        _expand.value = to;
        rest = _snap(rest + (e - to));
      }
      if (rest < 0) {
        final t = c.value;
        final to = math.max(0.0, t + rest / _travel);
        c.value = to;
        rest = _snap(rest + (t - to) * _travel);
      }
    }
    _track(t0, c.value);
    return rest;
  }

  /// The finger let go at [vy] pixels per second, up positive. Reaching
  /// the top while still on its way, it hands the rest of its speed to
  /// [onTop] (the content's scroll).
  void release(double vy, {ValueChanged<double>? onTop}) {
    if (!isCurrent) return;
    _grab();
    final c = controller!;
    final t = c.value;
    final still = vy.abs() < _still;
    final o = _origin ?? t, p = _peak ?? t;
    _origin = _peak = null;
    // Either way the same glide, at the finger's speed or the slowest.
    if (t < 1) {
      final bool open;
      if (p > o) {
        // On its way up: let go anywhere moving up, or still (or lifting)
        // past [_reach], it opens.
        open = vy > _still || (t * _travel >= _reach && vy > -_wobble);
      } else if (p < o) {
        // On its way down: moving down, or still below half way, it closes.
        open = !(vy < -_still || (t < 0.5 && vy < _wobble));
      } else {
        open = still ? t >= 0.5 : vy > 0;
      }
      if (open) {
        c.animateWith(_Glide(t, 1, vy / _travel));
      } else {
        _leave = _Glide(t, 0, vy / _travel);
        navigator?.pop();
      }
      return;
    }
    // Open: it grows or shrinks as a scroll would, and a fling down far
    // enough closes it.
    if (still) return;
    final e = _expand.value;
    final end =
        e + ClampingScrollSimulation(position: 0, velocity: vy).x(1e9);
    if (vy < 0 && end < -_travel / 2) {
      _leave = _Glide(1, 0, vy / (_travel + e));
      navigator?.pop();
    } else if (end < 0) {
      _drift!.animateWith(_Settle(e, 0, vy, span: _travel));
    } else {
      _onTop = onTop;
      _drift!.animateWith(ClampingScrollSimulation(position: e, velocity: vy));
    }
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return Material(
        type: MaterialType.transparency, child: builder(context, _scroll));
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final sheetColor = color ?? Theme.of(context).colorScheme.surface;
    final cardColor = fromColor ?? sheetColor;
    final card = standIn == null
        ? null
        : IgnorePointer(
            child: Material(
                type: MaterialType.transparency, child: standIn!(context)));
    final motion = Listenable.merge([animation, _expand]);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      // As wide as the screen, up to a bottom sheet's 640.
      final sw = math.min(w, 640.0);
      final left = (w - sw) / 2;
      return AnimatedBuilder(
        animation: motion,
        child: child,
        builder: (context, child) {
          final t = animation.value.clamp(0.0, 1.0);
          final f = _from;
          final top = h * (1 - openSize) - _expand.value;
          final open = Rect.fromLTRB(left, top, left + sw, h);
          final frame = f == null
              ? Rect.fromLTRB(left, h + (top - h) * t, left + sw, h)
              : Rect.lerp(fromInsets.deflateRect(f), open, t)!;
          final corners = f == null
              ? const BorderRadius.vertical(top: Radius.circular(20))
              : BorderRadius.vertical(
                  top: Radius.circular(fromRadius + (20 - fromRadius) * t),
                  bottom: Radius.circular(fromRadius * (1 - t)));
          // The card's colour holds most of the way, the content shows
          // only near the top: the sheet is all there once it's open.
          final bg = f == null
              ? sheetColor
              : Color.lerp(cardColor, sheetColor, t * t * t)!;
          final q = f == null ? 1.0 : ((t - 0.5) / 0.5).clamp(0.0, 1.0);
          final shadow = f == null ? 0.0 : 0.25 * (1 - t);
          final clip = corners.toRRect(Rect.fromLTRB(
              frame.left - left, 0, frame.right - left, frame.bottom - frame.top));
          return Stack(children: [
            Positioned.fromRect(
              rect: frame,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: corners,
                  boxShadow: shadow <= 0
                      ? null
                      : [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: shadow),
                              blurRadius: 16,
                              offset: const Offset(0, 4))
                        ],
                ),
              ),
            ),
            // Laid out once at its full height; it moves with the frame
            // and shows only within it.
            Positioned(
              left: left,
              top: frame.top,
              width: sw,
              height: h * maxSize,
              child: ClipRRect(
                clipper: _FrameClip(clip),
                child: Opacity(opacity: q * q, child: child),
              ),
            ),
            if (card != null && f != null && t < 0.4)
              Positioned(
                left: f.left,
                top: frame.top - fromInsets.top,
                width: f.width,
                height: f.height,
                child: Opacity(opacity: 1 - t / 0.4, child: card),
              ),
          ]);
        },
      );
    });
  }
}

class _FrameClip extends CustomClipper<RRect> {
  _FrameClip(this.rrect);
  final RRect rrect;
  @override
  RRect getClip(Size size) => rrect;
  @override
  bool shouldReclip(_FrameClip old) => old.rrect != rrect;
}

/// From [from] to [to], coming to rest there on an ease-out cubic. It sets
/// off at [velocity] when that's on its way and quicker than its own pace
/// (so it goes on at the finger's speed), at that pace otherwise. [span]:
/// the full way, for the pace.
class _Settle extends Simulation {
  _Settle(this.from, this.to, double velocity, {double span = 1})
      : _time = _duration((to - from).abs(), velocity * (to - from).sign, span);

  final double from, to;
  final double _time;

  static double _duration(double d, double v, double span) {
    if (d <= 0) return 0;
    final pace = 0.25 + 0.15 * (d / span).clamp(0.0, 1.0);
    return v > 0 ? math.min(pace, 3 * d / v) : pace;
  }

  @override
  double x(double time) {
    if (time >= _time) return to;
    final s = 1 - time / _time;
    return to + (from - to) * s * s * s;
  }

  @override
  double dx(double time) {
    if (time >= _time) return 0;
    final s = 1 - time / _time;
    return 3 * (to - from) * s * s / _time;
  }

  @override
  bool isDone(double time) => time >= _time;
}

/// From [from] to [to] as in a vacuum: on at [velocity] (but never slower
/// than [minSpeed], the full way in 2 s), then coming to rest on an
/// ease-out cubic of [_brake] seconds, but over the last third of the way
/// at most. However slowly the finger let go, it goes on as slowly; however
/// fast, it keeps that speed most of the way.
class _Glide extends Simulation {
  _Glide(this.from, this.to, double velocity)
      : _d = (to - from).abs(),
        _v = math.max(velocity * (to - from).sign, minSpeed) {
    _b = math.min(_d / 3, _v * _brake / 3);
    _cruise = (_d - _b) / _v;
    _end = _cruise + 3 * _b / _v;
  }

  static const minSpeed = 0.5;
  static const _brake = 0.3;

  final double from, to;
  final double _d, _v;
  late final double _b, _cruise, _end;

  double get _sign => (to - from).sign;

  @override
  double x(double time) {
    if (time >= _end) return to;
    if (time <= _cruise) return from + _sign * _v * time;
    final s = 1 - (time - _cruise) / (_end - _cruise);
    return to - _sign * _b * s * s * s;
  }

  @override
  double dx(double time) {
    if (time >= _end) return 0;
    if (time <= _cruise) return _sign * _v;
    final s = 1 - (time - _cruise) / (_end - _cruise);
    return _sign * _v * s * s;
  }

  @override
  bool isDone(double time) => time >= _end;
}

/// Every release is a fling, however slow or short: the sheet goes on at
/// the finger's speed.
class _LetGoPhysics extends ScrollPhysics {
  const _LetGoPhysics({super.parent});

  @override
  _LetGoPhysics applyTo(ScrollPhysics? ancestor) =>
      _LetGoPhysics(parent: buildParent(ancestor));

  @override
  double get minFlingDistance => 0;

  @override
  double get minFlingVelocity => 0;
}

/// The sheet content's controller: its drags move the sheet first.
class _SheetScrollController extends ScrollController {
  _SheetScrollController(this.route);
  final PlayerSheetRoute route;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
          ScrollContext context, ScrollPosition? oldPosition) =>
      _SheetScrollPosition(route,
          physics: physics, context: context, oldPosition: oldPosition);
}

class _SheetScrollPosition extends ScrollPositionWithSingleContext {
  _SheetScrollPosition(this.route,
      {required super.physics, required super.context, super.oldPosition});

  final PlayerSheetRoute route;

  /// A finger is on it; its release is the sheet's.
  bool _held = false;

  @override
  ScrollHoldController hold(VoidCallback holdCancelCallback) {
    _held = true;
    route._setOut();
    return super.hold(holdCancelCallback);
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    _held = true;
    route._setOut();
    return super.drag(details, dragCancelCallback);
  }

  @override
  void applyUserOffset(double delta) {
    final up = -delta;
    if (up > 0) {
      // Open and grow first, then scroll.
      final rest = route.drag(up);
      if (rest > 0) super.applyUserOffset(-rest);
    } else if (up < 0) {
      // Scroll back to the top first, then shrink and close.
      final back = math.min(math.max(0.0, pixels - minScrollExtent), -up);
      if (back > 0) super.applyUserOffset(back);
      if (-up > back) route.drag(up + back);
    }
  }

  @override
  void goBallistic(double velocity) {
    if (!_held) return super.goBallistic(velocity);
    _held = false;
    if (pixels > minScrollExtent || (velocity >= 0 && route._atTop)) {
      return super.goBallistic(velocity);
    }
    route.release(velocity, onTop: (v) => super.goBallistic(v));
    goIdle();
  }
}

// ── Player bottom sheet ───────────────────────────────────────────────────────

/// Marks the playing episode as a favourite, or not.
class _FavoriteButton extends StatefulWidget {
  final String episodeId;
  const _FavoriteButton({required this.episodeId});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  // Kept across rebuilds: the sheet rebuilds with every player change.
  late Stream<bool> _favorite;

  @override
  void initState() {
    super.initState();
    _favorite = context.read<AppDatabase>().watchFavorite(widget.episodeId);
  }

  @override
  void didUpdateWidget(_FavoriteButton old) {
    super.didUpdateWidget(old);
    if (old.episodeId != widget.episodeId) {
      _favorite = context.read<AppDatabase>().watchFavorite(widget.episodeId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return StreamBuilder<bool>(
      stream: _favorite,
      builder: (context, snap) {
        final fav = snap.data ?? false;
        return IconButton(
          onPressed: () => context
              .read<AppDatabase>()
              .setFavorite(widget.episodeId, !fav),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, a) =>
                ScaleTransition(scale: a, child: child),
            child: Icon(
              fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey(fav),
              size: 24, color: fav ? cs.tertiary : cs.primary),
          ),
          tooltip: fav ? l10n.removeFavorite : l10n.addFavorite,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        );
      },
    );
  }
}

class _PlayerSheet extends StatelessWidget {
  final VoidCallback? onPodcastTap;

  /// The route's: a drag on the list moves the sheet first.
  final ScrollController scroll;
  const _PlayerSheet({this.onPodcastTap, required this.scroll});

  /// The sheet's height when it opens, of the screen's.
  static const initialSize = 0.6;

  /// Dragged all the way up.
  static const maxSize = 0.95;

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  String _fmtSpeed(double speed) =>
      speed % 1 == 0 ? '${speed.toInt()}x' : '${speed}x';

  void _showCoverFullscreen(BuildContext context, PlayerProvider player, String fallbackUrl) {
    final screenWidth = MediaQuery.of(context).size.width;
    showDialog(
      context: context,
      barrierColor: const Color(0xDE180B07), // the darkest brown, 87 %
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              // Follows the playback into the next chapter's picture.
              child: ListenableBuilder(
                listenable: player,
                builder: (_, __) => _ChapterCover(
                    player: player, fallbackUrl: fallbackUrl, size: screenWidth),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSkipDialog(BuildContext context, PlayerProvider player,
      {required bool isForward}) {
    final options = [5, 10, 15, 30, 60, 90];
    final current = isForward ? player.forwardSeconds : player.rewindSeconds;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isForward ? 'Skip forward' : 'Skip backward'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((s) {
            return ChoiceChip(
              label: Text('${s}s'),
              selected: current == s,
              onSelected: (_) {
                if (isForward) {
                  player.setForwardSeconds(s);
                } else {
                  player.setRewindSeconds(s);
                }
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final ep = player.currentEpisode;
    if (ep == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    // The route paints the sheet's background and moves it.
    return ListView(
          controller: scroll,
          physics: PlayerSheetRoute.scrollPhysics,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),

            Center(
              // A chapter's own picture opens big; the podcast cover opens
              // the podcast.
              child: GestureDetector(
                onTap: player.hasChapterImage
                    ? () => _showCoverFullscreen(context, player, ep.podcastImageUrl)
                    : (onPodcastTap != null
                        ? () {
                            Navigator.of(context).pop();
                            onPodcastTap!();
                          }
                        : null),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _ChapterCover(
                    player: player,
                    fallbackUrl: ep.podcastImageUrl,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // The heart beside the titles; the space on the left keeps them
            // centred.
            Row(
              children: [
                const SizedBox(width: 44),
                Expanded(
                  child: Column(
                    children: [
                      Text(ep.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 18,
                              color: cs.onSurface)),
                      const SizedBox(height: 4),
                      Text(ep.podcastTitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                _FavoriteButton(episodeId: ep.id),
              ],
            ),
            SizedBox(height: player.chapters.isNotEmpty ? 4 : 24),

            // Chapter navigation — only shown when the episode has chapters
            if (player.chapters.isNotEmpty) ...[
              _ChapterNavRow(player: player),
              const SizedBox(height: 4),
            ],

            _SeekBar(player: player, fmt: _fmtDur),
            const SizedBox(height: 8),

            // Controls row: speed | skip-back | play | skip-fwd | share
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Speed dial
                GestureDetector(
                  onTap: player.cycleSpeed,
                  child: SizedBox(
                    width: 44, height: 44,
                    child: Center(
                      child: Text(
                        _fmtSpeed(player.speed),
                        style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                ),

                // Skip back (long press to choose seconds)
                GestureDetector(
                  onLongPress: () =>
                      _showSkipDialog(context, player, isForward: false),
                  onTap: player.skipBackward,
                  child: SizedBox(
                    width: 44, height: 44,
                    child: Icon(_skipRewindIcon(player.rewindSeconds), size: 28, color: cs.primary),
                  ),
                ),

                // Play / pause
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: cs.primary),
                  child: _playSwitch(player.isLoading
                      ? Padding(
                          key: const ValueKey('loading'),
                          padding: const EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                              strokeWidth: 3, strokeCap: StrokeCap.round,
                              color: cs.onPrimary),
                        )
                      : (player.isOffline && ep.localPath == null)
                          ? Icon(Icons.wifi_off_rounded,
                              key: const ValueKey('offline'),
                              color: cs.onPrimary.withValues(alpha: 0.6), size: 30)
                          : IconButton(
                              key: ValueKey(player.isPlaying),
                              onPressed: player.togglePlayPause,
                              icon: Icon(
                                player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: cs.onPrimary, size: 34,
                              ),
                            )),
                ),

                // Skip forward (long press to choose seconds)
                GestureDetector(
                  onLongPress: () =>
                      _showSkipDialog(context, player, isForward: true),
                  onTap: player.skipForward,
                  child: SizedBox(
                    width: 44, height: 44,
                    child: _skipForwardIconDirect(player.forwardSeconds) != null
                        ? Icon(_skipForwardIconDirect(player.forwardSeconds)!, size: 28, color: cs.primary)
                        : Transform.flip(
                            flipX: true,
                            child: Icon(_skipRewindIcon(player.forwardSeconds), size: 28, color: cs.primary),
                          ),
                  ),
                ),

                // Share
                IconButton(
                  onPressed: () => ShareUtils.shareEpisode(ep),
                  icon: Icon(Icons.share_rounded,
                      size: 22, color: cs.primary),
                  tooltip: l10n.shareEpisode,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Text(l10n.shownotes,
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15,
                    color: cs.onSurface)),
            const SizedBox(height: 8),
            ShowNotes(description: ep.description, cs: cs),
            const SizedBox(height: 40),
          ],
    );
  }
}

// ── Chapter navigation row ────────────────────────────────────────────────────

class _ChapterNavRow extends StatelessWidget {
  final PlayerProvider player;
  const _ChapterNavRow({required this.player});

  void _showChapterList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: player,
        child: _ChapterListSheet(cs: cs),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = player.currentChapterIndex;
    final chapter = player.currentChapter;
    final hasPrev = idx > 0;
    final hasNext = idx >= 0 && idx < player.chapters.length - 1;

    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.skip_previous_rounded,
              color: hasPrev ? cs.primary : cs.primary.withValues(alpha: 0.3)),
          onPressed: hasPrev ? player.skipToPreviousChapter : null,
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => _showChapterList(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.list_rounded, size: 14, color: cs.onPrimaryContainer),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      chapter?.title ?? '',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.skip_next_rounded,
              color: hasNext ? cs.primary : cs.primary.withValues(alpha: 0.3)),
          onPressed: hasNext ? player.skipToNextChapter : null,
        ),
      ],
    );
  }
}

// ── Chapter list popup ────────────────────────────────────────────────────────

class _ChapterListSheet extends StatelessWidget {
  final ColorScheme cs;
  const _ChapterListSheet({required this.cs});

  String _fmt(double secs) {
    final total = secs.toInt();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final chapters = player.chapters;
    final currentIdx = player.currentChapterIndex;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2)),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: chapters.length,
              itemBuilder: (ctx, i) {
                final chapter = chapters[i];
                final isActive = i == currentIdx;
                return ListTile(
                  leading: SizedBox(
                    width: 20,
                    child: isActive
                        ? Icon(Icons.play_arrow_rounded, color: cs.primary, size: 18)
                        : null,
                  ),
                  title: Text(
                    chapter.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      color: isActive ? cs.primary : cs.onSurface,
                    ),
                  ),
                  trailing: Text(
                    _fmt(chapter.startTimeSeconds),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  onTap: () {
                    player.seekToChapter(chapter);
                    Navigator.pop(ctx);
                  },
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}

// ── Chapter cover image with crossfade ───────────────────────────────────────

class _ChapterCover extends StatelessWidget {
  final PlayerProvider player;
  final String fallbackUrl;
  final double? size;
  const _ChapterCover({required this.player, required this.fallbackUrl, this.size});

  @override
  Widget build(BuildContext context) {
    final bytes = player.currentChapterImageBytes;
    final url = player.currentCoverImageUrl;
    final idx = player.currentChapterIndex;
    final dim = size ?? 220.0;

    Widget image;
    if (bytes != null) {
      image = Image.memory(
        bytes,
        key: ValueKey('chap_$idx'),
        width: dim, height: dim, fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else {
      final src = url.isNotEmpty ? url : fallbackUrl;
      image = CachedNetworkImage(
        key: ValueKey('cover_$src'),
        imageUrl: src,
        width: dim, height: dim, fit: BoxFit.cover,
        errorWidget: (_, __, ___) => SizedBox(width: dim, height: dim),
      );
    }

    return image;
  }
}
