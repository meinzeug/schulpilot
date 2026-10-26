import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/math_content.dart';
import 'package:schulpilot/ui.dart';

const publicFixture =
    '5/4 darstellen:\nBeispiel: 9/4 → 4/4 + 4/4 + 1/4\n↳ Ein Ganzes und ein Rest bleiben sichtbar.';

Future<void> fonts() async {
  for (final font in ['Nunito', 'SpaceGrotesk', 'Roboto']) {
    await (FontLoader(font)..addFont(
          rootBundle.load(
            'assets/fonts/${font == 'Roboto' ? 'Nunito' : font}.ttf',
          ),
        ))
        .load();
  }
  final sdk = File(Platform.resolvedExecutable).parent.parent.parent.path;
  await (FontLoader('MaterialIcons')..addFont(
        Future.value(
          ByteData.sublistView(
            await File('$sdk/material_fonts/MaterialIcons-Regular.otf')
                .readAsBytes(),
          ),
        ),
      ))
      .load();
}

Future<void> show(
  WidgetTester t,
  String text, {
  double width = 390,
  double scale = 1,
  String family = 'Nunito',
  GlobalKey? captureKey,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width, 844);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 844),
            textScaler: TextScaler.linear(scale),
          ),
          child: SingleChildScrollView(
            child: RepaintBoundary(
              key: captureKey,
              child: ColoredBox(
                color: const Color(0xff101f26),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: MathText(
                    text,
                    style: TextStyle(
                      fontFamily: family,
                      fontSize: 20,
                      color: Colors.white,
                      height: 1.45,
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
  await t.pumpAndSettle();
}

void main() {
  setUpAll(fonts);
  for (final viewport in [(320.0, 2.0), (390.0, 2.0), (1280.0, 1.0)]) {
    testWidgets(
      'Actual bundled-font inline and leading arrows at ${viewport.$1}/${viewport.$2}',
      (t) async {
        final key = GlobalKey();
        await show(
          t,
          publicFixture,
          width: viewport.$1,
          scale: viewport.$2,
          captureKey: key,
        );
        final capture = Platform.environment['ARROW_CAPTURE_PREFIX'];
        if (capture != null) {
          await t.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$capture-${viewport.$1.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
        expect(
          find.byIcon(Icons.subdirectory_arrow_right_rounded),
          findsOneWidget,
        );
        expect(find.byType(FractionNotation), findsNWidgets(5));
        expect(t.widget<MathText>(find.byType(MathText)).data, publicFixture);
        for (final finder in [
          find.byIcon(Icons.arrow_forward_rounded),
          find.byIcon(Icons.subdirectory_arrow_right_rounded),
        ]) {
          final rect = t.getRect(finder);
          expect(rect.width, greaterThan(12));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(viewport.$1));
        }
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Arrow-only prose uses the same literal glyph path without fractions',
    (t) async {
      await show(t, 'Erster Schritt → nächster Schritt\n↳ notiert');
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
      expect(
        find.byIcon(Icons.subdirectory_arrow_right_rounded),
        findsOneWidget,
      );
      expect(find.byType(FractionNotation), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Original narration semantics and explicit override are unchanged',
    (t) async {
      final handle = t.ensureSemantics();
      try {
        await show(t, publicFixture);
        expect(
          find.bySemanticsLabel(MathText.spoken(publicFixture)),
          findsOneWidget,
        );
        expect(MathText.spoken(publicFixture), contains('→'));
        expect(MathText.spoken(publicFixture), contains('↳'));
        await t.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MathText('A → B', semanticsLabel: 'Eigene Beschreibung'),
            ),
          ),
        );
        expect(find.bySemanticsLabel('Eigene Beschreibung'), findsOneWidget);
      } finally {
        handle.dispose();
      }
    },
  );
  testWidgets(
    'Unaffected glyphs and combining graphemes retain original text',
    (t) async {
      const original = 'Äöß e\u0301 👩‍🔬 ⇔ →\u0301 7² ± ×';
      await show(t, original);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
      expect(find.byIcon(Icons.subdirectory_arrow_right_rounded), findsNothing);
      expect(t.widget<MathText>(find.byType(MathText)).data, original);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Repeated arrows preserve order and inherit text color and size',
    (t) async {
      await show(t, 'A → B ↳ C → D', family: 'SpaceGrotesk');
      final icons = t.widgetList<Icon>(find.byType(Icon)).toList();
      expect(icons.map((i) => i.icon), [
        Icons.arrow_forward_rounded,
        Icons.subdirectory_arrow_right_rounded,
        Icons.arrow_forward_rounded,
      ]);
      expect(
        icons.every((i) => i.color == Colors.white && i.size == 20),
        isTrue,
      );
      expect(t.takeException(), isNull);
    },
  );
  test(
    'Spoken math remains exact and plain arrows do not change the answer',
    () {
      expect(
        MathText.spoken('9/4 → 4/4 + 4/4 + 1/4'),
        '9 durch 4 → 4 durch 4 + 4 durch 4 + 1 durch 4',
      );
      expect(MathText.spoken('↳ 5/4'), '↳ 5 durch 4');
    },
  );
}
