import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/math_content.dart';
import 'package:schulpilot/subject_graphic.dart';
import 'package:schulpilot/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Screenshots must use a real font. Flutter's default test font (Ahem)
    // renders every glyph as a black box and hides label/layout problems.
    final artifacts = File(Platform.resolvedExecutable)
        .parent
        .parent
        .parent
        .path;
    final path = '$artifacts/material_fonts/Roboto-Regular.ttf';
    final font = await File(path).readAsBytes();
    final loader = FontLoader('Roboto')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(font)));
    await loader.load();
    final iconFont = await File(
      '$artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(iconFont)));
    await iconLoader.load();
  });
  final cases =
      (jsonDecode(
                File('../testdata/subject_cases_v1.json').readAsStringSync(),
              )['cases']
              as List)
          .cast<Json>();
  for (final width in [320.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final fixture in cases) {
        testWidgets(
          '${fixture['id']}: accessible content at $width / ${scale * 100}%',
          (tester) async {
            tester.view.physicalSize = Size(width, 950);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final question = fixture['question'] as Json;
            final p = Json.from(question['presentation']);
            p['blocks'] = [
              for (final b in p['blocks'])
                {
                  for (final key in (b as Json).keys)
                    if (key != 'source_excerpt') key: b[key],
                },
            ];
            final blocks = (p['blocks'] as List).cast<Json>();
            var visibleStages = <String>{'given'};
            int visibleBlockCount(Set<String> allowed) => blocks
                .where((block) => allowed.contains(block['disclosure']))
                .length;
            final semantics = tester.ensureSemantics();
            Widget page() => MaterialApp(
              theme: appTheme().copyWith(
                textTheme: appTheme().textTheme.apply(fontFamily: 'Roboto'),
              ),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 950),
                  textScaler: TextScaler.linear(scale),
                ),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(fontFamily: 'Roboto'),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            MathText(
                              question['prompt'],
                              style: const TextStyle(fontSize: 22),
                            ),
                            RepaintBoundary(
                              key: const ValueKey('subject-figure'),
                              child: SubjectPresentation(
                                p,
                                stages: visibleStages,
                              ),
                            ),
                            for (final option in question['options'])
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: MathText(option),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpWidget(page());
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            // Before answering, only blocks marked `given` may be projected.
            expect(
              find.byType(SubjectGraphic),
              findsNWidgets(visibleBlockCount({'given'})),
            );
            // The report/review stage may show a solution graphic. Captured
            // screenshots below represent that closed-question stage.
            visibleStages = {'given', 'solution'};
            await tester.pumpWidget(page());
            await tester.pumpAndSettle();
            expect(
              find.byType(SubjectGraphic),
              findsNWidgets(visibleBlockCount(visibleStages)),
            );
            if (fixture['id'] == 'ENG02') {
              expect(find.byType(Table), findsNothing);
              expect(find.text('She is reading.'), findsOneWidget);
              expect(find.text('They are playing.'), findsOneWidget);
            }
            if (fixture['id'] == 'BIO02') {
              expect(
                find.textContaining('Gras ist Nahrung für Kaninchen.'),
                findsOneWidget,
              );
              expect(
                find.textContaining('Kaninchen ist Nahrung für Fuchs.'),
                findsOneWidget,
              );
            }
            if (fixture['id'] == 'LAT01') {
              expect(find.byType(Table), findsOneWidget);
              expect(find.text('aqua'), findsWidgets);
              expect(find.text('Wasser'), findsWidgets);
              expect(find.text('amica'), findsWidgets);
              expect(find.text('Freundin'), findsWidgets);
            }
            if (fixture['id'] == 'GES01') {
              expect(find.text('6. Jahrhundert: 501–600'), findsOneWidget);
              expect(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is Semantics &&
                      widget.properties.image == true &&
                      (widget.properties.label ?? '').contains(
                        '1. Jahrhundert: 1 bis 100',
                      ),
                ),
                findsOneWidget,
              );
            }
            if (width == 320) {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('subject-figure')),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final dir = Directory(
                  '../artifacts/fachtest-2026-10-19/render',
                );
                await dir.create(recursive: true);
                await File('${dir.path}/${fixture['id']}-${scale.toInt()}x.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            semantics.dispose();
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
  testWidgets('Stacked fractions and spoken alternative preserve source text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MathText('Berechne 1/4 + 1/8.'))),
    );
    expect(find.byType(FractionNotation), findsNWidgets(2));
    expect(MathText.spoken('1/4 + 1/8'), '1 durch 4 + 1 durch 8');
    expect(MathText.spoken('19/10/2026'), '19/10/2026');
    expect(tester.takeException(), isNull);
  });
  testWidgets('Numerator/denominator and slash entry retain the same answer', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FractionAnswerInput(controller: controller)),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Zähler'), '6');
    await tester.enterText(find.widgetWithText(TextField, 'Nenner'), '16');
    expect(controller.text, '6/16');
    await tester.tap(find.text('Mit / tippen'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Dein Bruch mit /'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '3/8');
    await tester.tap(find.text('Zähler und Nenner getrennt'));
    await tester.pumpAndSettle();
    expect(controller.text, '3/8');
    expect(find.widgetWithText(TextField, '3'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Nenner'), '0');
    await tester.pump();
    expect(find.text('Der Nenner muss größer als 0 sein.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
