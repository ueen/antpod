import 'package:antpod/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The player sheet's route with a stand-in sheet: a drag moves it with the
/// finger, the release settles it open or closes it.
void main() {
  late NavigatorState nav;

  // The 800×600 test screen: open, the sheet's top is at 240; from the
  // bottom edge that's 360 px of travel.
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
      locate: from == null ? null : () => from,
      standIn: from == null ? null : (_) => const SizedBox(key: Key('mini')),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.3, maxChildSize: 0.95,
        expand: false,
        builder: (_, ctrl) => ColoredBox(
          key: const Key('sheet'),
          color: Colors.white,
          child: ListView(controller: ctrl, children: const [
            SizedBox(height: 2000, child: Text('sheet')),
          ]),
        ),
      ),
    );
    nav.push(route);
    await tester.pump();
    return route;
  }

  testWidgets('a tap opens it on its own; a tap above closes it', (tester) async {
    final route = await push(tester, tracking: false);
    await tester.pumpAndSettle();
    expect(route.animation!.value, 1);
    expect(route.isCurrent, isTrue);

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

  testWidgets('a slow release past half way opens, before closes', (tester) async {
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

  testWidgets('a flick goes its way, wherever it lets go', (tester) async {
    var route = await push(tester, tracking: true);
    route.drag(54);
    route.release(1080);
    await tester.pumpAndSettle();
    expect(route.isCurrent, isTrue);
    expect(route.animation!.value, 1);

    nav.pop();
    await tester.pumpAndSettle();
    route = await push(tester, tracking: true);
    route.drag(306);
    route.release(-1080);
    await tester.pumpAndSettle();
    expect(route.isActive, isFalse);
  });

  testWidgets('dragged down to its smallest size, it closes', (tester) async {
    final route = await push(tester, tracking: false);
    await tester.pumpAndSettle();
    // The sheet takes the lower 60 % of the 600 px test screen.
    await tester.dragFrom(const Offset(400, 300), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(route.isActive, isFalse);
  });

  testWidgets('from the mini player, its card rides the edge, 1:1 with the finger',
      (tester) async {
    final route =
        await push(tester, tracking: true, from: const Rect.fromLTWH(0, 520, 800, 80));
    double top(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
    expect(top('sheet'), 520);
    expect(top('mini'), 520);

    route.drag(140); // of 520 − 240
    await tester.pump();
    expect(route.animation!.value, closeTo(0.5, 1e-9));
    expect(top('sheet'), closeTo(380, 1e-6));
    expect(top('mini'), closeTo(380, 1e-6));

    route.release(400); // a flick up
    await tester.pumpAndSettle();
    expect(top('sheet'), 240);
  });
}
