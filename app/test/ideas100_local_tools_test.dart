import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ideas100_local_views.dart';
import 'package:schulpilot/ideas100_plan_ui.dart';
import 'package:schulpilot/ideas100_source_tools.dart';
import 'package:schulpilot/learning_content.dart';
import 'package:schulpilot/material_screen.dart';
import 'package:schulpilot/ui.dart';

void size(WidgetTester t, double width) {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Widget host(Widget child, {double scale = 1}) => MaterialApp(
  theme: appTheme(brightness: Brightness.dark),
  builder: (c, w) => MediaQuery(
    data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
    child: w!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);
Future<void> tap(WidgetTester t, Finder target) async {
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await t.tap(target);
  await t.pumpAndSettle();
}

AppState actor(List<http.Request> calls) =>
    AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((r) async {
            calls.add(r);
            throw StateError('View must remain local');
          }),
        )..token = 'session',
      )
      ..user = {'id': 'child', 'role': 'child', 'child_id': 'child'}
      ..familyId = 'family';
const source =
    '# Vorhandener Titel\n\nEin gesuchter Begriff steht hier.\n\n## Zweiter Titel\n\nNoch ein gesuchter Begriff.\n\nUnveränderter Abschluss.';
void main() {
  test('page states use reported facts without inferring recognition', () {
    expect(
      ideas100PageStatus({'confirmed': true, 'status': 'unreadable'}),
      'Bestätigt',
    );
    expect(
      ideas100PageStatus({'status': 'uploaded'}),
      contains('Erkennung offen'),
    );
    expect(ideas100PageStatus({'status': 'review'}), contains('Erkannt'));
    expect(ideas100PageStatus({'status': 'unreadable'}), 'Foto unlesbar');
    expect(ideas100PageStatus({}), isNot(contains('Erkannt')));
  });
  for (final view in [(320.0, 2.0), (390.0, 1.0), (1440.0, 1.0)]) {
    testWidgets('source reading, context navigation and typography at $view', (
      t,
    ) async {
      size(t, view.$1);
      await t.pumpWidget(
        host(
          Ideas100SourceReader(
            text: source,
            uncertainties: const ['gesuchter Begriff'],
            onClose: () {},
          ),
          scale: view.$2,
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(LearningHeadingIndex), findsNothing);
      await tap(t, find.byKey(const ValueKey('source-reader-search')));
      await t.enterText(find.byType(TextField), 'gesuchter Begriff');
      await t.pumpAndSettle();
      expect(find.text('Treffer 1 von 2'), findsOneWidget);
      await tap(t, find.byTooltip('Nächster Texttreffer'));
      expect(find.text('Treffer 2 von 2'), findsOneWidget);
      expect(find.text('Unveränderter Abschluss.'), findsOneWidget);
      await tap(t, find.byKey(const ValueKey('source-reader-type')));
      await tap(t, find.text('24 px'));
      await tap(t, find.byTooltip('Zeilenabstand 1.8'));
      expect(
        t
            .widgetList<LearningContent>(find.byType(LearningContent))
            .every((w) => w.style?.fontSize == 24 && w.style?.height == 1.8),
        isTrue,
      );
      await tap(t, find.byKey(const ValueKey('source-reader-contents')));
      expect(find.byType(LearningHeadingIndex), findsOneWidget);
      await tap(t, find.text('Unsichere Angaben nachsehen (1)'));
      await tap(t, find.byType(CheckboxListTile));
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      expect(t.takeException(), isNull);
    });
    testWidgets('comparison responds to $view without hiding either choice', (
      t,
    ) async {
      size(t, view.$1);
      await t.pumpWidget(
        host(
          const Ideas100TextCompare(
            'Gespeicherter Originaltext',
            'Eigene Korrektur',
          ),
          scale: view.$2,
        ),
      );
      await t.pumpAndSettle();
      if (view.$1 < 720) {
        await tap(t, find.text('Dein Entwurf'));
        expect(find.text('Eigene Korrektur'), findsOneWidget);
        await tap(t, find.text('Gespeichert'));
        expect(find.text('Gespeicherter Originaltext'), findsOneWidget);
      } else {
        expect(find.text('Eigene Korrektur'), findsOneWidget);
        expect(find.text('Gespeicherter Originaltext'), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('week date selection includes Today and local search is scoped', (
    t,
  ) async {
    size(t, 320);
    dynamic selected;
    final days = [
      {
        'date': '2026-10-23',
        'items': [
          {'subject': 'Deutsch', 'topic': 'Satz'},
        ],
      },
      {
        'date': '2026-10-24',
        'items': [
          {'subject': 'Mathematik', 'topic': 'Bruch'},
        ],
      },
    ];
    await t.pumpWidget(
      host(
        Ideas100WeekView(
          days: days,
          today: '2026-10-23',
          onSelect: (d) => selected = d,
          builder: (visible) => Column(
            children: [for (final d in visible) Text('Tag ${d['date']}')],
          ),
        ),
      ),
    );
    await tap(t, find.text('Heute'));
    expect(selected['date'], '2026-10-23');
    await t.enterText(find.byType(TextField), 'Bruch');
    await t.pumpAndSettle();
    expect(find.text('Tag 2026-10-23'), findsNothing);
    expect(find.text('Tag 2026-10-24'), findsOneWidget);
    expect(find.text('1 von 2 geladenen Tagen passen.'), findsOneWidget);
  });
  testWidgets('day grouping and provenance preserve the actual input order', (
    t,
  ) async {
    size(t, 390);
    final items = [
      {'subject': 'Deutsch', 'topic': 'A', 'kind': 'material'},
      {
        'subject': 'Mathematik',
        'topic': 'B',
        'kind': 'assignment',
        'mandatory': true,
      },
    ];
    await t.pumpWidget(
      host(
        Ideas100DayItems(
          items: items,
          builder: (i) => Text('Eintrag ${i['topic']}'),
        ),
      ),
    );
    await tap(t, find.byType(DropdownButtonFormField<String>));
    await tap(t, find.text('Nach Verbindlichkeit').last);
    expect(find.text('Verbindliche Elternaufträge'), findsOneWidget);
    expect(find.text('Weitere Vorschläge'), findsOneWidget);
    await tap(t, find.text('Herkunft dieses Planeintrags').first);
    expect(find.text('Bestätigte Heftquelle'), findsOneWidget);
    expect(items.first['topic'], 'A');
  });
  testWidgets('already delivered homework tasks expand without requests', (
    t,
  ) async {
    size(t, 320);
    await t.pumpWidget(
      host(
        Ideas100TaskPreview([
          for (var n = 0; n < 5; n++) {'title': 'Aufgabe $n', 'marked': n == 0},
        ]),
      ),
    );
    expect(find.text('Aufgabe 4'), findsNothing);
    await tap(t, find.text('Alle 5 mitgelieferten Aufgaben ansehen'));
    expect(find.text('Aufgabe 4'), findsOneWidget);
    await tap(t, find.text('Aufgaben einklappen'));
    expect(find.text('Aufgabe 4'), findsNothing);
  });
  testWidgets(
    'highlighting uses original Unicode ranges and never changes the title',
    (t) async {
      size(t, 320);
      const text = 'İstanbul 😀 Mathe MATHE';
      await t.pumpWidget(host(const Ideas100Highlight(text, 'mathe')));
      final rendered = t.widget<Text>(find.byType(Text).last);
      expect(rendered.textSpan!.toPlainText(), text);
      expect(
        (rendered.textSpan! as TextSpan).children!
            .whereType<TextSpan>()
            .where((s) => s.style?.backgroundColor != null)
            .length,
        2,
      );
    },
  );
  testWidgets('stale close callbacks cannot dismiss another local route', (
    t,
  ) async {
    size(t, 390);
    final calls = <http.Request>[];
    final state = actor(calls);
    late BuildContext entry;
    await t.pumpWidget(
      host(
        Builder(
          builder: (c) {
            entry = c;
            return FilledButton(
              onPressed: () => ideas100Dialog<void>(
                c,
                state,
                'Erste Ansicht',
                const Text('Erste Metadaten'),
              ),
              child: const Text('Öffnen'),
            );
          },
        ),
      ),
    );
    await tap(t, find.text('Öffnen'));
    final closeFirst = t
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is IconButton && widget.tooltip == 'Ansicht schließen',
          ),
        )
        .onPressed!;
    ideas100Dialog<void>(
      entry,
      state,
      'Zweite Ansicht',
      const Text('Zweite Metadaten'),
    );
    await t.pumpAndSettle();
    closeFirst();
    await t.pumpAndSettle();
    expect(find.text('Zweite Metadaten'), findsOneWidget);
    await tap(t, find.byTooltip('Ansicht schließen').last);
    expect(find.text('Erste Metadaten'), findsOneWidget);
    closeFirst();
    await t.pumpAndSettle();
    expect(find.text('Erste Metadaten'), findsNothing);
    ideas100Dialog<void>(
      entry,
      state,
      'Dritte Ansicht',
      const Text('Dritte Metadaten'),
    );
    await t.pumpAndSettle();
    closeFirst();
    await t.pumpAndSettle();
    expect(find.text('Dritte Metadaten'), findsOneWidget);
    expect(t.takeException(), isNull);
    expect(calls, isEmpty);
    await t.pumpWidget(const SizedBox());
    state.dispose();
  });
  for (final change in ['account', 'family', 'token']) {
    testWidgets('$change closes the local detail route', (t) async {
      size(t, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      await t.pumpWidget(
        host(
          Builder(
            builder: (c) => FilledButton(
              onPressed: () => ideas100Dialog<void>(
                c,
                state,
                'Private lokale Ansicht',
                const Text('Vorhandene Metadaten'),
              ),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      );
      await tap(t, find.text('Öffnen'));
      expect(find.text('Vorhandene Metadaten'), findsOneWidget);
      switch (change) {
        case 'account':
          state.user = Json.from(state.user!);
        case 'family':
          state.familyId = 'other';
        case 'token':
          state.api.token = 'new';
      }
      state.refreshState();
      await t.pumpAndSettle();
      expect(find.text('Vorhandene Metadaten'), findsNothing);
      expect(calls, isEmpty);
      await t.pumpWidget(const SizedBox());
      state.dispose();
    });
  }
  testWidgets(
    'crop compares Original and output, undo/redo retain original bytes',
    (t) async {
      size(t, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 100, height: 200)),
      );
      final original = bytes.toList();
      Uint8List? result;
      await t.pumpWidget(
        host(
          Builder(
            builder: (c) => FilledButton(
              onPressed: () async {
                result = await cropMaterialPhoto(
                  c,
                  bytes,
                  state: state,
                  initialFrame: const CropFrame(left: .25, right: .75),
                  batchIndex: 2,
                  batchTotal: 3,
                );
              },
              child: const Text('Zuschnitt öffnen'),
            ),
          ),
        ),
      );
      await tap(t, find.text('Zuschnitt öffnen'));
      expect(find.text('Foto 2 von 3 prüfen'), findsOneWidget);
      await tap(t, find.text('Original ansehen'));
      expect(find.byType(CustomPaint), findsWidgets);
      await tap(t, find.text('Ergebnis ansehen'));
      await tap(t, find.text('Zuschnitt bearbeiten'));
      await tap(t, find.text('Um 90° drehen'));
      expect(
        t
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Zuschnitt rückgängig',
              ),
            )
            .onPressed,
        isNotNull,
      );
      await tap(t, find.byTooltip('Zuschnitt rückgängig'));
      await tap(t, find.byTooltip('Zuschnitt wiederholen'));
      await tap(t, find.byTooltip('Zuschnitt rückgängig'));
      final confirm = find.text('Zuschnitt übernehmen');
      await t.ensureVisible(confirm);
      await t.pumpAndSettle();
      await t.tap(confirm);
      await t.pump(const Duration(milliseconds: 32));
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await t.pumpAndSettle();
      expect(result, isNotNull);
      final image = img.decodeImage(result!)!;
      expect(image.width, 50);
      expect(image.height, 200);
      expect(bytes.toList(), original);
      expect(calls, isEmpty);
      await t.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'crop cancellation retains only bounded numeric frame for rechecking',
    (t) async {
      size(t, 320);
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 80, height: 100)),
      );
      CropFrame? frame;
      await t.pumpWidget(
        host(
          Builder(
            builder: (c) => FilledButton(
              onPressed: () => cropMaterialPhoto(
                c,
                bytes,
                initialFrame: frame,
                onFrameChanged: (v) => frame = v,
                batchIndex: 1,
                batchTotal: 2,
              ),
              child: const Text('Prüfen'),
            ),
          ),
        ),
      );
      await tap(t, find.text('Prüfen'));
      await tap(t, find.text('Um 90° drehen'));
      await tap(t, find.text('Abbrechen'));
      expect(frame!.turns, 1);
      await tap(t, find.text('Prüfen'));
      await tap(t, find.text('Abbrechen'));
      expect(frame!.turns, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'account change closes the crop and leaves source bytes untouched',
    (t) async {
      size(t, 320);
      final calls = <http.Request>[];
      final state = actor(calls);
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 20, height: 30)),
      );
      await t.pumpWidget(
        host(
          Builder(
            builder: (c) => FilledButton(
              onPressed: () => cropMaterialPhoto(c, bytes, state: state),
              child: const Text('Prüfen'),
            ),
          ),
        ),
      );
      await tap(t, find.text('Prüfen'));
      state.api.token = 'replacement';
      state.refreshState();
      await t.pumpAndSettle();
      expect(find.byType(CropDialog), findsNothing);
      expect(calls, isEmpty);
      await t.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
