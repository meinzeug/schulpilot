import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/schulbuddy_dock_hint.dart';

final _paint = find.byKey(const ValueKey('schulbuddy-dock-hint-paint'));

class _Controls extends ChangeNotifier {
  bool active = true;
  bool ticker = true;
  bool reduced = false;
  bool accessible = false;

  void change(VoidCallback update) {
    update();
    notifyListeners();
  }
}

Future<_Controls> _mount(
  WidgetTester tester, {
  bool active = true,
  bool reduced = false,
  bool accessible = false,
  GlobalKey<NavigatorState>? navigator,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final controls = _Controls()
    ..active = active
    ..reduced = reduced
    ..accessible = accessible;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    controls.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Center(
          child: AnimatedBuilder(
            animation: controls,
            builder: (context, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: controls.reduced,
                accessibleNavigation: controls.accessible,
              ),
              child: TickerMode(
                enabled: controls.ticker,
                child: SchulbuddyDockHint(active: controls.active),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controls;
}

Future<List<int>> _pixels(WidgetTester tester) async {
  final painter = tester.widget<CustomPaint>(_paint).painter!;
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(10, 24));
  final picture = recorder.endRecording();
  final result = await tester.runAsync(() async {
    final image = await picture.toImage(10, 24);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer
        .asUint8List(data.offsetInBytes, data.lengthInBytes)
        .toList();
  });
  picture.dispose();
  return result!;
}

int _brightest(List<int> pixels) {
  var brightest = 0;
  for (var index = 0; index < pixels.length; index += 4) {
    if (pixels[index + 3] > 32) {
      final light = pixels[index] + pixels[index + 1] + pixels[index + 2];
      if (light > brightest) {
        brightest = light;
      }
    }
  }
  return brightest;
}

Future<void> _midSweep(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 8800));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('Hint is decorative, 10 by 24, with a crisp one-pixel shaft', (
    tester,
  ) async {
    await _mount(tester, active: false);
    expect(tester.getSize(_paint), const Size(10, 24));
    expect(
      find.ancestor(of: _paint, matching: find.byType(ExcludeSemantics)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(of: _paint, matching: find.byType(IgnorePointer))
                .first,
          )
          .ignoring,
      isTrue,
    );
    final pixels = await _pixels(tester);
    int alpha(int x, int y) => pixels[(y * 10 + x) * 4 + 3];
    expect(alpha(5, 8), greaterThan(240));
    expect(alpha(4, 8), 0);
    expect(alpha(6, 8), 0);
    final painter = tester.widget<CustomPaint>(_paint).painter!;
    for (final size in [
      Size.zero,
      const Size(double.infinity, 24),
      const Size(10, double.nan),
      const Size(-1, 24),
      const Size(1, 1),
    ]) {
      final recorder = ui.PictureRecorder();
      expect(() => painter.paint(Canvas(recorder), size), returnsNormally);
      recorder.endRecording().dispose();
    }
  });

  testWidgets('A finite light sweep repeats after ticker-free dim intervals', (
    tester,
  ) async {
    await _mount(tester);
    final dim = await _pixels(tester);
    expect(tester.binding.transientCallbackCount, 0);
    await _midSweep(tester);
    expect(
      _brightest(await _pixels(tester)),
      greaterThan(_brightest(dim) + 50),
    );
    await tester.pump(const Duration(milliseconds: 650));
    expect(await _pixels(tester), dim);
    expect(tester.binding.transientCallbackCount, 0);
    // Existing header tests can settle during the long quiet interval.
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await _midSweep(tester);
    expect(
      _brightest(await _pixels(tester)),
      greaterThan(_brightest(dim) + 50),
    );
  });

  for (final accessibility in [false, true]) {
    testWidgets(
      '${accessibility ? 'Accessible navigation' : 'Reduced motion'} stays static',
      (tester) async {
        await _mount(
          tester,
          reduced: !accessibility,
          accessible: accessibility,
        );
        final dim = await _pixels(tester);
        await tester.pump(const Duration(seconds: 30));
        expect(await _pixels(tester), dim);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  testWidgets(
    'Disabling during a sweep cancels both animation and future sweeps',
    (tester) async {
      final controls = await _mount(tester);
      await _midSweep(tester);
      controls.change(() => controls.active = false);
      await tester.pump();
      final dim = await _pixels(tester);
      await tester.pump(const Duration(seconds: 30));
      expect(await _pixels(tester), dim);
      expect(tester.binding.transientCallbackCount, 0);
      controls.change(() => controls.active = true);
      await tester.pump();
      expect(await _pixels(tester), dim);
      await _midSweep(tester);
      expect(
        _brightest(await _pixels(tester)),
        greaterThan(_brightest(dim) + 50),
      );
    },
  );

  testWidgets('A hidden TickerMode cancels the quiet timer and active sweep', (
    tester,
  ) async {
    final controls = await _mount(tester);
    await _midSweep(tester);
    controls.change(() => controls.ticker = false);
    await tester.pump();
    final dim = await _pixels(tester);
    await tester.pump(const Duration(seconds: 30));
    expect(await _pixels(tester), dim);
    expect(tester.binding.transientCallbackCount, 0);
    controls.change(() => controls.ticker = true);
    await tester.pump();
    expect(await _pixels(tester), dim);
    await _midSweep(tester);
    expect(
      _brightest(await _pixels(tester)),
      greaterThan(_brightest(dim) + 50),
    );
  });

  testWidgets(
    'Background lifecycle pauses immediately and resumes with quiet time',
    (tester) async {
      await _mount(tester);
      await _midSweep(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      final dim = await _pixels(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(await _pixels(tester), dim);
      expect(tester.binding.transientCallbackCount, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(await _pixels(tester), dim);
      await _midSweep(tester);
      expect(
        _brightest(await _pixels(tester)),
        greaterThan(_brightest(dim) + 50),
      );
    },
  );

  testWidgets(
    'A covering modal pauses even when the underlying route stays painted',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await _mount(tester, navigator: navigator);
      await _midSweep(tester);
      final closed = navigator.currentState!.push<void>(
        PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) =>
              const Center(child: Text('Eigener Testdialog')),
        ),
      );
      await tester.pumpAndSettle();
      final dim = await _pixels(tester);
      await tester.pump(const Duration(seconds: 30));
      expect(await _pixels(tester), dim);
      expect(tester.binding.transientCallbackCount, 0);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await closed;
      expect(await _pixels(tester), dim);
      await _midSweep(tester);
      expect(
        _brightest(await _pixels(tester)),
        greaterThan(_brightest(dim) + 50),
      );
    },
  );
}
