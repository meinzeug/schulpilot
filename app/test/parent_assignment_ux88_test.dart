import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/collection_screen.dart';
import 'package:schulpilot/dashboard.dart' show assignmentDialog;
import 'package:schulpilot/ui.dart';

http.Response response(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class Fixture {
  final requests = <http.Request>[];
  Future<http.Response?> Function(http.Request)? respond;
  final Json child = {
    'id': 'child-a',
    'display_name': 'Künstliches Kind A',
    'subjects': ['Englisch', 'Biologie'],
  };
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              return await respond?.call(r) ??
                  response(
                    r.method == 'GET'
                        ? {
                            'items': [],
                            'subjects': [],
                            'page': 1,
                            'pages': 1,
                            'total': 0,
                          }
                        : {},
                  );
            }),
          ),
        )
        ..user = {
          'id': 'parent-a',
          'role': 'parent',
          'families': [
            {'id': 'family-a', 'permission': 'owner'},
            {'id': 'family-b', 'permission': 'owner'},
          ],
        }
        ..familyId = 'family-a';
  Future<BuildContext> open(
    WidgetTester tester, {
    Json? existing,
    Json? sourceUnit,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext screen;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (c) {
              screen = c;
              return FilledButton(
                onPressed: () => assignmentDialog(
                  c,
                  state,
                  child,
                  [],
                  existing: existing,
                  sourceUnit: sourceUnit,
                ),
                child: const Text('Öffnen'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    addTearDown(() {
      state.inbox.dispose();
      state.dispose();
    });
    return screen;
  }
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> ready(WidgetTester tester) async {
  await tester.enterText(field('Fach'), 'Englisch');
  await tester.enterText(field('Thema / Lernziel'), 'Simple Past');
}

void main() {
  for (final change in ['family', 'same-id login']) {
    testWidgets('PP031 assignment draft closes on exact $change replacement', (
      tester,
    ) async {
      final f = Fixture();
      await f.open(tester);
      await ready(tester);
      final saved = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Speichern'))
          .onPressed!;
      if (change == 'family') {
        f.state.familyId = 'family-b';
      } else {
        f.state.user = {...f.state.user!};
      }
      f.state.refreshState();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      saved();
      await tester.pump();
      expect(f.requests, isEmpty);
      expect(find.text('Öffnen'), findsOneWidget);
    });
  }
  testWidgets(
    'PP040 one pending save freezes all fields and retains its exact snapshot',
    (tester) async {
      final f = Fixture();
      final pending = Completer<http.Response>();
      f.respond = (_) => pending.future;
      await f.open(tester);
      await ready(tester);
      await tester.enterText(
        field('Was soll geübt werden?'),
        'Künstlicher unveränderlicher Auftrag.',
      );
      await tester.ensureVisible(find.text('Speichern'));
      await tester.tap(find.text('Speichern'));
      await tester.pump();
      expect(f.requests, hasLength(1));
      for (final widget in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(widget.enabled, isFalse);
      }
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      expect(
        find.widgetWithText(FilledButton, 'Lernziel speichern …'),
        findsOneWidget,
      );
      pending.complete(response({}));
      await tester.pumpAndSettle();
      final body = jsonDecode(f.requests.single.body);
      expect(body['subject'], 'Englisch');
      expect(body['topic'], 'Simple Past');
      expect(body['note'], 'Künstlicher unveränderlicher Auftrag.');
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'PP041 pending save cannot be dismissed and completes into the saved plan',
    (tester) async {
      final f = Fixture();
      final pending = Completer<http.Response>();
      f.respond = (_) => pending.future;
      await f.open(tester);
      await ready(tester);
      await tester.ensureVisible(find.text('Speichern'));
      await tester.tap(find.text('Speichern'));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Abbrechen'))
            .onPressed,
        isNull,
      );
      await tester.tapAt(const Offset(2, 2));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      pending.complete(response({}));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Lernziel gespeichert. Neue Übungen werden erst bewusst vorbereitet.',
        ),
        findsOneWidget,
      );
      expect(f.requests, hasLength(1));
    },
  );
  testWidgets(
    'PP042 a start date after its deadline is caught locally without a POST',
    (tester) async {
      final f = Fixture();
      await f.open(tester);
      await ready(tester);
      await tester.enterText(field('Termin (optional)'), '24.10.2026');
      await tester.enterText(
        field('Frühester Lernbeginn (optional)'),
        '25.10.2026',
      );
      await tap(tester, find.text('Speichern'));
      expect(
        find.text('Der Lernbeginn darf nicht nach dem Termin liegen.'),
        findsOneWidget,
      );
      expect(f.requests, isEmpty);
      await tester.enterText(
        field('Frühester Lernbeginn (optional)'),
        '23.10.2026',
      );
      await tap(tester, find.text('Speichern'));
      final body = jsonDecode(f.requests.single.body);
      expect(body['scheduled_for'], '2026-10-23');
      expect(body['due'], '2026-10-24');
    },
  );
  testWidgets(
    'PP043 server refusal remains inline and preserves the private draft',
    (tester) async {
      final f = Fixture();
      f.respond = (_) async =>
          response({'detail': 'Die Heftquelle wurde geändert.'}, 409);
      await f.open(tester, width: 320, scale: 2);
      await ready(tester);
      await tap(tester, find.text('Speichern'));
      expect(find.text('Die Heftquelle wurde geändert.'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Die Heftquelle wurde geändert.')).dy,
        lessThan(900),
      );
      expect(
        tester.widget<TextField>(field('Thema / Lernziel')).controller!.text,
        'Simple Past',
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'PP044 intended child is named before creating a learning assignment',
    (tester) async {
      final f = Fixture();
      await f.open(tester);
      expect(find.text('Für Künstliches Kind A'), findsOneWidget);
      expect(f.requests, isEmpty);
    },
  );
  testWidgets(
    'PP045 multi-subject child is not silently assigned mathematics',
    (tester) async {
      final f = Fixture();
      await f.open(tester);
      expect(tester.widget<TextField>(field('Fach')).controller!.text, isEmpty);
      await tap(tester, find.widgetWithText(ChoiceChip, 'Biologie'));
      expect(
        tester.widget<TextField>(field('Fach')).controller!.text,
        'Biologie',
      );
      expect(f.requests, isEmpty);
    },
  );
  testWidgets(
    'PP046 selected source mismatch is explicit; adopting source metadata is a separate action',
    (tester) async {
      final f = Fixture();
      await f.open(tester);
      await ready(tester);
      await tap(tester, find.text('Heftseite auswählen (optional)'));
      final picker = tester.widget<PagedCollection>(
        find.byType(PagedCollection),
      );
      picker.onSelect!({
        'id': 'material-a',
        'subject': 'Biologie',
        'topic': 'Zellen',
        'title': 'Künstliche Zellseite',
      });
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Die ausgewählte Heftseite gehört zu Biologie.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(field('Fach')).controller!.text,
        'Englisch',
      );
      await tap(tester, find.text('Fach und Thema der Heftseite übernehmen'));
      expect(
        tester.widget<TextField>(field('Fach')).controller!.text,
        'Biologie',
      );
      expect(
        tester.widget<TextField>(field('Thema / Lernziel')).controller!.text,
        'Zellen',
      );
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
    },
  );
  testWidgets('PP047 source round without a photo can be explicitly unlinked', (
    tester,
  ) async {
    final f = Fixture();
    await f.open(
      tester,
      sourceUnit: {
        'id': 'manual-unit',
        'subject': 'Englisch',
        'topic': 'Simple Past',
      },
    );
    await tap(tester, find.text('Verknüpfung mit Lernrunde aufheben'));
    await tap(tester, find.text('Speichern'));
    final body = jsonDecode(f.requests.single.body);
    expect(body['source_unit_id'], isNull);
    expect(body['material_id'], isNull);
  });
  testWidgets(
    'PP048 missing network acknowledgement retries exactly the same request and body',
    (tester) async {
      final f = Fixture();
      var attempt = 0;
      f.respond = (_) async => ++attempt == 1
          ? response({'detail': 'Speicherung nicht bestätigt.'}, 503)
          : response({});
      await f.open(tester);
      await ready(tester);
      await tap(tester, find.text('Speichern'));
      expect(find.text('Anfrage abgleichen'), findsOneWidget);
      expect(
        tester.widget<TextField>(field('Thema / Lernziel')).enabled,
        isFalse,
      );
      await tap(tester, find.text('Anfrage abgleichen'));
      expect(f.requests, hasLength(2));
      expect(
        f.requests[1].headers['Idempotency-Key'],
        f.requests[0].headers['Idempotency-Key'],
      );
      expect(f.requests[1].body, f.requests[0].body);
    },
  );
  testWidgets(
    'PP049 save clearly distinguishes stored goals from generated learning work',
    (tester) async {
      final f = Fixture();
      await f.open(tester);
      expect(
        find.textContaining(
          'Es erzeugt noch keine KI-Übungen und startet keine Lernrunde.',
        ),
        findsOneWidget,
      );
      expect(f.requests, isEmpty);
    },
  );
  testWidgets(
    'PP050 editing a completed assignment explicitly reopens it without generation',
    (tester) async {
      final f = Fixture();
      await f.open(
        tester,
        existing: {
          'id': 'done-topic',
          'subject': 'Englisch',
          'topic': 'Simple Past',
          'done': true,
          'revision': 3,
        },
      );
      expect(
        find.textContaining('Erneutes Speichern öffnet ihn wieder'),
        findsOneWidget,
      );
      await tap(tester, find.text('Auftrag wieder öffnen'));
      expect(f.requests.single.method, 'PUT');
      expect(
        f.requests.single.url.path,
        '/api/children/child-a/assignments/done-topic',
      );
      expect(jsonDecode(f.requests.single.body)['revision'], 3);
      expect(f.requests.any((r) => r.url.path.contains('/prepare')), isFalse);
    },
  );
  testWidgets('PP031 family switch removes only its own calendar and editor', (
    tester,
  ) async {
    final f = Fixture();
    final screen = await f.open(tester);
    await tap(tester, find.byTooltip('Termin im Kalender auswählen'));
    expect(find.byType(DatePickerDialog), findsOneWidget);
    unawaited(
      showDialog<void>(
        context: screen,
        builder: (_) =>
            const AlertDialog(content: Text('Neue unabhängige Ansicht')),
      ),
    );
    await tester.pumpAndSettle();
    f.state.familyId = 'family-b';
    f.state.refreshState();
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('Ein Lernziel vorgeben'), findsNothing);
    expect(find.text('Neue unabhängige Ansicht'), findsOneWidget);
    expect(f.requests, isEmpty);
  });
  testWidgets(
    'PP040 successful save underneath a newer dialog preserves the newer route',
    (tester) async {
      final f = Fixture();
      final pending = Completer<http.Response>();
      f.respond = (_) => pending.future;
      final screen = await f.open(tester);
      await ready(tester);
      await tester.ensureVisible(find.text('Speichern'));
      await tester.tap(find.text('Speichern'));
      await tester.pump();
      unawaited(
        showDialog<void>(
          context: screen,
          builder: (_) =>
              const AlertDialog(content: Text('Neue unabhängige Ansicht')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      pending.complete(response({}));
      await tester.pumpAndSettle();
      expect(find.text('Neue unabhängige Ansicht'), findsOneWidget);
      expect(find.text('Ein Lernziel vorgeben'), findsNothing);
    },
  );
}
