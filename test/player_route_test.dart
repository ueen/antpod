import 'package:antpod/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The player sheet's route with a stand-in sheet: a drag moves it with the
/// finger, the release goes on its way, settled open or closed.
void main() {
  late NavigatorState nav;
  late ScrollController scroll;

  // The 800×600 test screen: open, the sheet's top is at 240; from the
  // bottom edge that's 360 px of travel. All the way up, its top is at 30.
  Future<PlayerSheetRoute> push(WidgetTester tester,
      {required bool tracking, Rect? from}) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        nav = Navigator.of(context);
        return const Scaffold(body: Text('home'));
      }),
    ));
    final route = PlayerSheetRoute(
      tracking: tracking,
      barrierLabel: 'close',
      openSize: 0.6,
      maxSize: 0.95,
      locate: from == null ? null : () => from,
      fromInsets: const EdgeInsets.fromLTRB(12, 7, 12, 8),
      standIn: from == null ? null : (_) => const SizedBox(key: Key('mini')),
      builder: (_, s) {
        scroll = s;
        return ListView(
          controller: s,
          physics: PlayerSheetRoute.scrollPhysics,
          children: const [
            SizedBox(key: Key('sheet'), height: 2000, child: Text('sheet')),
          ],
        );
      },
    );
    nav.push(route);
    await tester.pump();
    return route;
  }

  double top(WidgetTester tester, String key) =>
      tester.getTopLeft(find.byKey(Key(key))).dy;

  testWidgets('a tap opens it on its own; a tap above closes it', (tester) async {
    final route = await push(tester, tracking: false);
    await tester.pumpAndSettle();
    expect(route.animation!.value, 1);
    expect(route.isCurrent, isTrue);
    expect(top(tester, 'sheet'), 240);

    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(route.isActive, isFalse);
    expect(find.text('sheet'), findsNothing);
  });

  testWidgets('it waits for the finger and follows it', (tester) async {
    final route = await push(tester, tracking: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(route.animation!.value, 0, reason: 'no opening on its own');

    route.drag(108);
    await tester.pump();
    expect(route.animation!.value, closeTo(0.3, 1e-9));
    route.drag(-36);
    await tester.pump();
    expect(route.animation!.value, closeTo(0.2, 1e-9));
  });

  testWidgets('let go still on its way up, however little, it opens',
      (tester) async {
    final route = await push(tester, tracking: true);
    route.drag(20);
    route.release(0);
    await tester.pumpAndSettle();
    expect(route.animation!.value, 1);
    expect(route.isCurrent, isTrue);
  });

  testWidgets('from the mini player, any way up opens it, unless sent back',
      (tester) async {
    const mini = Rect.fromLTWH(0, 536, 800, 64);
    Future<PlayerSheetRoute> letGo(double up, double vy) async {
      final route = await push(tester, tracking: true, from: mini);
      route.drag(up);
      route.release(vy);
      await tester.pumpAndSettle();
      return route;
    }

    var route = await letGo(130, 0);
    expect(route.isCurrent, isTrue, reason: 'let go still');
    nav.pop();
    await tester.pumpAndSettle();
    route = await letGo(130, -100);
    expect(route.isCurrent, isTrue, reason: 'the finger lifting is no way back');
    nav.pop();
    await tester.pumpAndSettle();
    route = await letGo(30, 0);
    expect(route.isCurrent, isTrue, reason: 'a little way up is enough');
    nav.pop();
    await tester.pumpAndSettle();
    route = await letGo(130, -300);
    expect(route.isActive, isFalse, reason: 'sent back');
  });

  testWidgets('a slow release goes its way, wherever it lets go', (tester) async {
    var route = await push(tester, tracking: true);
    route.drag(54);
    route.release(60);
    await tester.pumpAndSettle();
    expect(route.isCurrent, isTrue);
    expect(route.animation!.value, 1);

    nav.pop();
    await tester.pumpAndSettle();
    route = await push(tester, tracking: true);
    route.drag(330);
    route.drag(-24); // turned back
    route.release(-60);
    await tester.pumpAndSettle();
    expect(route.isActive, isFalse);
  });

  testWidgets('a release goes on at the finger\'s speed, and slows to a stop',
      (tester) async {
    final route = await push(tester, tracking: true);
    route.drag(180);
    await tester.pump();
    route.release(720); // 2 travels per second
    await tester.pump();
    final v0 = route.animation!.value;
    await tester.pump(const Duration(milliseconds: 100));
    // Just as fast as the finger: no jump ahead, no gap behind.
    expect((route.animation!.value - v0) / 0.1, closeTo(2, 0.05));
    await tester.pump(const Duration(milliseconds: 200));
    final v2 = route.animation!.value;
    expect(v2, lessThan(1), reason: 'not there yet');
    await tester.pump(const Duration(milliseconds: 16));
    expect((route.animation!.value - v2) / 0.016, lessThan(0.5),
        reason: 'slower near the end');
    await tester.pumpAndSettle();
    expect(route.animation!.value, 1);
  });

  testWidgets('let go slowly, it goes on slowly: up to 2 s to open',
      (tester) async {
    final route = await push(tester, tracking: true);
    route.drag(36); // a tenth of the way
    await tester.pump();
    route.release(30); // crawling: it goes on at the slowest glide
    await tester.pump();
    final v0 = route.animation!.value;
    await tester.pump(const Duration(seconds: 1));
    expect(route.animation!.value - v0, closeTo(0.5, 0.02),
        reason: 'half the way a second, steady');
    await tester.pump(const Duration(milliseconds: 600));
    expect(route.animation!.value, lessThan(1), reason: 'still on its way');
    await tester.pumpAndSettle();
    expect(route.animation!.value, 1);
    expect(route.isCurrent, isTrue);
  });

  testWidgets('let go slowly on the way down, it closes as slowly as it opens',
      (tester) async {
    final route = await push(tester, tracking: false);
    await tester.pumpAndSettle();
    route.drag(-36); // a tenth of the way down
    await tester.pump();
    route.release(-30);
    await tester.pump();
    final v0 = route.animation!.value;
    await tester.pump(const Duration(seconds: 1));
    expect(v0 - route.animation!.value, closeTo(0.5, 0.02),
        reason: 'half the way a second, as up');
    await tester.pumpAndSettle();
    expect(route.isActive, isFalse);
  });

  test('a speed the tracker lost, the finger\'s trail still knows', () {
    ({Duration at, double up}) at(int ms, double up) =>
        (at: Duration(milliseconds: ms), up: up);
    // A stalled first frame: 9 px, then 147 px all at once 160 ms on.
    final stalled = [at(0, 9), at(158, 19), at(158, 30), at(160, 166)];
    expect(releaseSpeed(0, stalled), closeTo(981, 1));
    expect(releaseSpeed(900, stalled), 900, reason: 'the tracker had it');
    // Smooth, it's the tracker's: let go still, still it is.
    final smooth = [for (var i = 0; i <= 10; i++) at(i * 16, i * 8.0)];
    expect(releaseSpeed(480, smooth), 480);
    expect(releaseSpeed(0, [at(0, 0), at(5, 40)]), 0,
        reason: 'too short a trail to tell');
  });

  testWidgets('a flick keeps its speed, braking only over the last sixth',
      (tester) async {
    final route = await push(tester, tracking: true);
    route.drag(36);
    await tester.pump();
    route.release(1080); // 3 travels per second, a quick flick
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 230));
    final v1 = route.animation!.value;
    expect(v1, greaterThan(0.75));
    await tester.pump(const Duration(milliseconds: 16));
    expect((route.animation!.value - v1) / 0.016, closeTo(3, 0.05),
        reason: 'still at full speed three quarters of the way');
    await tester.pumpAndSettle();
    expect(route.animation!.value, 1);
  });

  testWidgets('let go on the way down, the content still fades by the place',
      (tester) async {
    const mini = Rect.fromLTWH(0, 536, 800, 64);
    final route = await push(tester, tracking: false, from: mini);
    await tester.pumpAndSettle();
    // 303 px of travel: down to 0.8, the content half faded.
    route.drag(-0.2 * 303);
    await tester.pump();
    final cover = find.descendant(
        of: find.byType(ClipRRect), matching: find.byType(ColoredBox));
    double content(double t) {
      final c = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
      return c * c * (3 - 2 * c);
    }

    route.release(-300);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final want = content(route.animation!.value);
      expect(find.ancestor(
              of: find.byKey(const Key('sheet')), matching: find.byType(Opacity)),
          findsNothing);
      expect(tester.widget<ColoredBox>(cover).color.a, closeTo(1 - want, 1e-6),
          reason: 'at ${route.animation!.value}');
    }
    expect(route.animation!.value, lessThan(0.6), reason: 'faded all the way');
    await tester.pumpAndSettle();
    expect(route.isActive, isFalse);
  });

  testWidgets('open, a drag up grows the sheet before its content scrolls',
      (tester) async {
    await push(tester, tracking: false);
    await tester.pumpAndSettle();
    final g = await tester.startGesture(const Offset(400, 500));
    await g.moveBy(const Offset(0, -30)); // past the touch slop
    await tester.pump();
    final start = top(tester, 'sheet');
    expect(start, lessThan(240));
    await g.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(top(tester, 'sheet'), closeTo(start - 100, 1e-6));
    expect(scroll.offset, 0);

    // At the top (30) it stops; the rest scrolls the content.
    await g.moveBy(const Offset(0, -300));
    await tester.pump();
    expect(scroll.offset, greaterThan(0));
    expect(tester.getTopLeft(find.byType(ListView)).dy, 30);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('open, a drag down follows the finger; back up, it reopens',
      (tester) async {
    final route = await push(tester, tracking: false);
    await tester.pumpAndSettle();
    final g = await tester.startGesture(const Offset(400, 300));
    await g.moveBy(const Offset(0, 30)); // past the touch slop
    await tester.pump();
    final start = top(tester, 'sheet');
    await g.moveBy(const Offset(0, 90));
    await tester.pump();
    expect(top(tester, 'sheet'), closeTo(start + 90, 1e-6));
    await g.moveBy(const Offset(0, -60));
    await tester.pump();
    expect(top(tester, 'sheet'), closeTo(start + 30, 1e-6));
    await g.up();
    await tester.pumpAndSettle();
    expect(route.isCurrent, isTrue);
    expect(route.animation!.value, 1);
  });

  testWidgets('dragged down from open, it closes', (tester) async {
    final route = await push(tester, tracking: false);
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(400, 300), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(route.isActive, isFalse);
  });

  testWidgets('from the mini player, its card rides the frame, 1:1 with the finger',
      (tester) async {
    final route =
        await push(tester, tracking: true, from: const Rect.fromLTWH(0, 520, 800, 80));
    // The card's top is 7 below the mini player's: 287 px to open.
    expect(top(tester, 'sheet'), 527);
    expect(top(tester, 'mini'), 520);

    route.drag(57.4);
    await tester.pump();
    expect(route.animation!.value, closeTo(0.2, 1e-9));
    expect(top(tester, 'sheet'), closeTo(527 - 57.4, 1e-6));
    expect(top(tester, 'mini'), closeTo(520 - 57.4, 1e-6));

    route.release(400); // on its way up
    await tester.pumpAndSettle();
    expect(top(tester, 'sheet'), 240);
    expect(find.byKey(const Key('mini')), findsNothing,
        reason: 'faded into the sheet');
  });
}
