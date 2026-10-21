import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/learning_explanation.dart';
import 'package:schulpilot/practice_evidence.dart';
import 'package:schulpilot/school_day_screen.dart';
import 'package:schulpilot/subject_graphic.dart';
import 'package:schulpilot/ui.dart';

import 'unit_learning_time_test.dart' as harness;

Widget frame(Widget child, {double scale = 1}) => MaterialApp(
  theme: appTheme().copyWith(
    textTheme: appTheme().textTheme.apply(fontFamily: 'Roboto'),
    textButtonTheme: TextButtonThemeData(
      style: appTheme().textButtonTheme.style!.copyWith(
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: appTheme().filledButtonTheme.style!.copyWith(
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Roboto',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: RepaintBoundary(
        key: const ValueKey('practice-visual'),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  ),
);

void screen(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('practice-visual')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('../artifacts/practice-$name.png')
        .writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final fonts =
        '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts';
    for (final (name, file) in [
      ('Roboto', 'Roboto-Regular.ttf'),
      ('MaterialIcons', 'MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(name)
        ..addFont(
          Future.value(
            ByteData.sublistView(await File('$fonts/$file').readAsBytes()),
          ),
        );
      await loader.load();
    }
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Letter scaffold starts fresh, supports undo and never submits automatically',
    (tester) async {
      final requests = <http.Request>[];
      final unit = harness.unit();
      unit['questions'] = [
        {
          'id': 'first',
          'type': 'short',
          'prompt': 'Schreibe Übung auf Englisch.',
          'attempts': <Json>[],
          'hints_used': 0,
          'language': {'skill': 'spelling', 'answer_locale': 'en-GB'},
        },
      ];
      final h = await harness.openUnit(tester, (r) async {
        requests.add(r);
        if (r.url.path.endsWith('/language-stimulus')) {
          return harness.reply({
            'word_bank': ['e', 'x', 'e', 'r', 'c', 'i', 's', 'e'],
            'joiner': '',
          });
        }
        if (r.url.path.endsWith('/heartbeat')) {
          return harness.reply(harness.heartbeat());
        }
        return harness.reply(unit);
      });
      await tester.enterText(find.byType(TextField).first, 'exercise');
      await harness.tap(tester, 'Mit Bausteinen üben · Hilfe');
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      expect(find.textContaining('Tippe die Buchstaben'), findsOneWidget);
      final chips = find.byType(ActionChip);
      await tester.ensureVisible(chips.at(0));
      await tester.tap(chips.at(0));
      await tester.pumpAndSettle();
      await tester.tap(chips.at(1));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'ex',
      );
      await harness.tap(tester, 'Letzten Baustein zurück');
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'e',
      );
      expect(
        requests.where(
          (r) => r.method == 'POST' && r.url.path.endsWith('/answer'),
        ),
        isEmpty,
      );
      await h.close();
    },
  );

  test('Dates and quantities stay text; 204 and invalid gateway responses are recoverable', () {
    expect(counted(1, 'Minute', 'Minuten'), '1 Minute');
    expect(counted(1, 'Wort', 'Wörter'), '1 Wort');
    expect(schoolDate('2026-10-20'), '20.10.2026');
    expect(schoolDate('1970-01-01'), 'Termin noch offen');
    final api = Api();
    expect(api.decode(http.Response('', 204)), isEmpty);
    expect(
      () => api.decode(http.Response('<html>bad gateway</html>', 503)),
      throwsA(
        isA<ApiError>().having(
          (e) => e.message,
          'safe error',
          contains('bisherigen Antworten bleiben gespeichert'),
        ),
      ),
    );
  });

  for (final (width, scale) in [(320.0, 2.0), (1280.0, 1.0)]) {
    testWidgets(
      'Fraction model has explicit equal-whole, expansion and addition steps at $width/$scale',
      (tester) async {
        screen(tester, width);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          frame(
            const FractionSumDiagram(prompt: 'Berechne 1/3 + 1/6.'),
            scale: scale,
          ),
        );
        expect(find.text('1 · Zwei gleich große Ganze'), findsOneWidget);
        expect(
          find.textContaining('noch unterschiedlich groß'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp('1 von 3 gleich großen Teilen')),
          findsOneWidget,
        );
        expect(find.text('3 · Anteile zusammenführen'), findsNothing);
        await tester.ensureVisible(find.text('Gleich einteilen'));
        await tester.tap(find.text('Gleich einteilen'));
        await tester.pumpAndSettle();
        expect(find.textContaining('noch unterschiedlich groß'), findsNothing);
        expect(
          find.bySemanticsLabel(RegExp('2 von 6 gleich großen Teilen')),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Anteile zusammenlegen'));
        await tester.tap(find.text('Anteile zusammenlegen'));
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel(RegExp('3 von 6 gleich großen Teilen')),
          findsOneWidget,
        );
        expect(find.textContaining('zusätzlich zur Farbe'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, 'fractions-$width-$scale');
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
      },
    );

    testWidgets(
      'Biology diagrams have readable labelled alternatives at $width/$scale',
      (tester) async {
        screen(tester, width);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          frame(
            SubjectPresentation({
              'version': 1,
              'blocks': [
                {
                  'kind': 'plant',
                  'title': 'Erklärschema: Die Wurzel',
                  'variant': 'roots',
                  'disclosure': 'solution',
                  'labels': ['Blüte', 'Blatt', 'Stängel', 'Wurzel'],
                  'numbers': [],
                  'connections': [],
                  'unit': '',
                },
                {
                  'kind': 'forms',
                  'title': 'Bestäubung und Befruchtung',
                  'variant': 'pollination',
                  'disclosure': 'solution',
                  'labels': [
                    'Bestäubung: Pollen gelangt auf die Narbe.',
                    'Befruchtung: Eine männliche Keimzelle verschmilzt mit der Eizelle.',
                  ],
                  'numbers': [],
                  'connections': [],
                  'unit': '',
                },
              ],
            }),
            scale: scale,
          ),
        );
        expect(
          find.bySemanticsLabel(RegExp('Die Wurzel liegt im Boden')),
          findsOneWidget,
        );
        await tester.ensureVisible(find.textContaining('2. Befruchtung:'));
        expect(find.textContaining('männliche Keimzelle'), findsWidgets);
        expect(tester.takeException(), isNull);
        await capture(tester, 'biology-$width-$scale');
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
      },
    );
  }

  testWidgets('Home help offers app support before any parent message', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final state = AppState(
      api: Api(
        client: MockClient((r) async {
          requests.add(r);
          return http.Response('{}', 200);
        }),
      ),
    )..user = {'id': 'kid', 'role': 'child', 'child_id': 'child'};
    var reloads = 0;
    await tester.pumpWidget(
      frame(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showHomeHelp(
              context,
              state,
              childId: 'child',
              refresh: () => reloads++,
            ),
            child: const Text('Hilfe öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Hilfe öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('Etwas erklären lassen'), findsOneWidget);
    expect(find.text('Meine Eltern fragen'), findsOneWidget);
    expect(requests, isEmpty);
    await tester.tap(find.text('Etwas funktioniert nicht'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erneut laden'));
    await tester.pumpAndSettle();
    expect(reloads, 1);
    expect(requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets(
    '21 saved pages and 3 pending photos remain viewable at the daily limit',
    (tester) async {
      screen(tester, 390);
      final requests = <http.Request>[];
      final day = {
        'id': 'day',
        'child_id': 'child',
        'date': '2026-10-19',
        'stage': 'collecting',
        'synthetic': false,
        'max_pages': 24,
        'confirmed_count': 21,
        'units': [],
        'active_job': null,
        'plan': {},
        'pages': [
          for (var i = 1; i <= 21; i++)
            {
              'id': 'p$i',
              'page_number': i,
              'confirmed': true,
              'status': 'confirmed',
              'subject': 'Englisch',
              'synthetic': false,
            },
        ],
      };
      final state =
          AppState(
              api: Api(
                client: MockClient((r) async {
                  requests.add(r);
                  return http.Response(
                    jsonEncode({'day': day}),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }),
              ),
            )
            ..user = {
              'id': 'kid',
              'role': 'child',
              'child_id': 'child',
              'synthetic': false,
            };
      final bytes = img.encodePng(img.Image(width: 100, height: 180));
      for (var i = 0; i < 3; i++) {
        await state.pendingUploads.add('kid', 'child', 'day', bytes);
      }
      final router = GoRouter(
        initialLocation: '/after-school/child',
        routes: [
          GoRoute(
            path: '/after-school/:id',
            builder: (_, _) => SchoolDayScreen(state, childId: 'child'),
          ),
          GoRoute(
            path: '/app',
            builder: (_, _) => const Scaffold(body: Text('Heute')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('21 gespeichert · 3 vorgemerkt · 0 noch möglich'),
        findsOneWidget,
      );
      final preview = find.text('Vorgemerktes Foto 1 ansehen');
      await tester.ensureVisible(preview);
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byTooltip('Zurück zu deinen Fotos'), findsOneWidget);
      await tester.tap(find.byTooltip('Zurück zu deinen Fotos'));
      await tester.pumpAndSettle();
      expect(await state.pendingUploads.read('kid'), hasLength(3));
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  test(
    'Support reasons distinguish retry, hints and unknown legacy support',
    () {
      expect(
        supportReasonLabels({
          'assisted': true,
          'evaluation': {
            'support_reasons': ['another_attempt'],
          },
        }).single,
        contains('noch einmal versucht'),
      );
      expect(
        supportReasonLabels({
          'assisted': true,
          'evaluation': {
            'support_reasons': ['explanation', 'hint'],
          },
        }),
        hasLength(2),
      );
      expect(
        supportReasonLabels({'assisted': true}).single,
        contains('nicht getrennt gespeichert'),
      );
      expect(supportReasonLabels({'assisted': false}), isEmpty);
    },
  );
}
