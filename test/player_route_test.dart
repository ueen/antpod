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

  testWidgets('a still release past half way opens, before closes', (tester) async {
    var route = await push(tester, tracking: true);
    route.drag(216);
    route.release(0);
    await tester.pumpAndSettle();
    expect(route.animation!.value, 1);
    expect(route.isCurrent, isTrue);

    nav.pop();
    await tester.pumpAndSettle();
    route = await push(tester, tracking: true);
    route.drag(144);
    route.release(0);
    await tester.pumpAndSettle();
    expect(route.isActive, isFalse);
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
    route.drag(306);
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
    await tester.pump(const Duration(milliseconds: 16));
    final v1 = route.animation!.value;
    // Not slower than the finger at first: no gap behind it.
    expect((v1 - v0) / 0.016, greaterThanOrEqualTo(2 - 0.1));
    await tester.pump(const Duration(milliseconds: 150));
    final v2 = route.animation!.value;
    await tester.pump(const Duration(milliseconds: 16));
    expect((route.animation!.value - v2) / 0.016, lessThan(1),
        reason: 'slower near the end');
    await tester.pumpAndSettle();
    expect(route.animation!.value, 1);
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
