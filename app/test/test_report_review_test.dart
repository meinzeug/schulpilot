import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/learning_explanation.dart';
import 'package:schulpilot/material_screen.dart';
import 'package:schulpilot/tutor_sheet.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/unit_screen.dart';

void small(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

http.Response jsonReply(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets('E07 task preview needs an explicit binding decision at 320px', (
    tester,
  ) async {
    small(tester);
    List? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              child: const Text('Seite bestätigen'),
              onPressed: () async {
                result = await showDialog<List>(
                  context: context,
                  builder: (_) => const MaterialTaskDialog(
                    hasDuplicate: true,
                    items: [
                      {
                        'key': 'synthetic-key',
                        'text': 'Probeaufgabe: 1/3 + 1/6 = ?',
                        'classification': 'example',
                      },
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Seite bestätigen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ähnliches Blatt'), findsOneWidget);
    expect(find.text('Probeaufgabe: 1/3 + 1/6 = ?'), findsOneWidget);
    expect(result, isNull);
    final action = find.text('Auswahl übernehmen');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(result, [
      {'key': 'synthetic-key', 'classification': 'example'},
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'K42 saved explanation has readable steps and an accessible fraction model',
    (tester) async {
      small(tester);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: LearningExplanation(
                  text: 'Zuerst gleich große Teile finden.\n\nDann die Zähler addieren.',
                  prompt: 'Berechne 1/4 + 1/8.',
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Schritt 1 von 2'), findsOneWidget);
      expect(find.text('Dann die Zähler addieren.'), findsNothing);
      await tester.ensureVisible(find.text('Gleich einteilen'));
      await tester.tap(find.text('Gleich einteilen'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Anteile zusammenlegen'));
      await tester.tap(find.text('Anteile zusammenlegen'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('3 von 8 gleich großen Teilen')),
        findsOneWidget,
      );
      final next = find.text('Nächster Schritt');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('Schritt 2 von 2'), findsOneWidget);
      expect(find.text('Dann die Zähler addieren.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  test('K33 crop changes the selected region, retains orientation and removes metadata', () {
    final source = img.Image(width: 200, height: 100);
    img.fill(source, color: img.ColorRgb8(50, 100, 150));
    final bytes = Uint8List.fromList(img.encodeJpg(source));
    final crop = img.decodeJpg(
      encodeMaterialCrop({
        'bytes': bytes,
        'turns': 0,
        'left': .25,
        'top': 0.0,
        'right': .75,
        'bottom': 1.0,
      }),
    )!;
    expect(crop.width, 100);
    expect(crop.height, 100);
    expect(crop.exif.isEmpty, isTrue);
    final rotated = img.decodeJpg(
      encodeMaterialCrop({
        'bytes': bytes,
        'turns': 1,
        'left': 0.0,
        'top': 0.0,
        'right': 1.0,
        'bottom': 1.0,
      }),
    )!;
    expect([rotated.width, rotated.height], [100, 200]);
  });

  test('E12 calendar parsing rejects invalid and rolled-over dates', () {
    expect(planningDate('31.02.2026'), isNull);
    expect(planningDate('2026-02-29'), isNull);
    expect(planningDate('2028-02-29'), DateTime(2028, 2, 29));
    expect(planningDate('24.10.2026'), DateTime(2026, 10, 24));
    expect(friendlyDate(0), 'noch offen');
    expect(friendlyDate('1970-01-01'), 'noch offen');
    expect(statusLabel('ready'), 'Bereit');
    expect(statusLabel('planned'), 'Geplant');
  });

  testWidgets(
    'E12 invalid fields stay inline and valid dates are saved unambiguously',
    (tester) async {
      small(tester);
      final posts = <http.Request>[];
      final state =
          AppState(
              api: Api(
                base: 'https://example.invalid/api',
                client: MockClient((r) async {
                  posts.add(r);
                  return jsonReply({});
                }),
              ),
            )
            ..user = {
              'id': 'parent',
              'role': 'parent',
              'families': [
                {'id': 'synthetic-family', 'permission': 'owner'},
              ],
            }
            ..familyId = 'synthetic-family';
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                child: const Text('Auftrag'),
                onPressed: () => assignmentDialog(context, state, {
                  'id': 'child',
                  'display_name': 'Künstliches Kind',
                  'subjects': ['Mathematik'],
                }, []),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Auftrag'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Speichern'));
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(posts, isEmpty);
      final theme = find.widgetWithText(TextFormField, 'Thema / Lernziel');
      await tester.ensureVisible(theme);
      await tester.enterText(theme, 'Brüche addieren');
      final date = find.widgetWithText(TextFormField, 'Termin (optional)');
      await tester.ensureVisible(date);
      await tester.enterText(date, '31.02.2026');
      await tester.ensureVisible(find.text('Speichern'));
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(posts, isEmpty);
      expect(find.textContaining('gültiges Datum'), findsOneWidget);
      await tester.ensureVisible(date);
      await tester.enterText(date, '24.10.2026');
      tester.testTextInput.hide();
      await tester.ensureVisible(find.text('Speichern'));
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(posts, hasLength(1));
      expect(jsonDecode(posts.single.body)['due'], '2026-10-24');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'K47 a teacher question accepts a direct answer and keeps its conversation link',
    (tester) async {
      small(tester);
      final requests = <http.Request>[];
      final turn = <String, dynamic>{
        'id': 'question',
        'created': 1,
        'question': 'Hilf mir mit Walen.',
        'status': 'ready',
        'reply': {
          'kind': 'foundation',
          'answer': 'Wale atmen Luft mit Lungen.',
          'next_question': 'Warum muss ein Wal auftauchen?',
          'sources': [],
        },
      };
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((r) async {
            requests.add(r);
            if (r.method == 'POST') {
              return jsonReply({
                ...turn,
                'id': 'answer',
                'created': 2,
                'reply_to': 'question',
                'question': 'Zum Atmen.',
                'reply': {
                  'kind': 'answer',
                  'answer': 'Genau, er holt Luft.',
                  'next_question': null,
                  'sources': [],
                },
              });
            }
            return jsonReply({
              'questions': [turn],
              'next_cursor': null,
            });
          }),
        ),
      )..user = {'id': 'child', 'role': 'child', 'child_id': 'child'};
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                child: const Text('Fragen'),
                onPressed: () => showTutorSheet(
                  context,
                  state,
                  childId: 'child',
                  materialId: 'page',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Fragen'));
      await tester.pumpAndSettle();
      expect(find.text('Warum muss ein Wal auftauchen?'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.enterText(find.byType(TextField), 'Zum Atmen.');
      await tester.pump();
      final action = find.text('Antwort senden');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      final body = jsonDecode(
        requests.where((r) => r.method == 'POST').single.body,
      );
      expect(body, {
        'material_id': 'page',
        'question': 'Zum Atmen.',
        'reply_to': 'question',
      });
      expect(find.text('Genau, er holt Luft.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final matching in [false, true]) {
    testWidgets(
      matching
          ? 'K07 partial match feedback identifies only the saved wrong pair'
          : 'K45 explicit recheck updates the same saved answer without a new attempt',
      (tester) async {
        small(tester);
        final semantics = tester.ensureSemantics();
        final requests = <http.Request>[];
        var outcome = matching ? 'incorrect' : 'uncertain';
        Json task() => {
          'id': 'q',
          'type': matching ? 'match' : 'short',
          'prompt': matching
              ? 'Ordne die Tiere ihren Klassen zu.'
              : 'Berechne 1/4 + 1/8.',
          'options': matching ? ['Hund', 'Frosch', 'Karpfen', 'Amsel'] : [],
          'choices': ['Säugetiere', 'Amphibien', 'Fische', 'Vögel'],
          'hints_used': 0,
          'attempts': [
            {
              'id': 'saved',
              'answer': matching ? 'Reptilien;Amphibien;Fische;Vögel' : '6/16',
              'outcome': outcome,
              if (outcome == 'correct')
                'assessment_history': [
                  {'previous_outcome': 'uncertain', 'outcome': 'correct'},
                ],
              'assisted': false,
              'evaluation': {
                'reason': 'Gespeicherte fachliche Prüfung.',
                if (matching)
                  'parts': [
                    {'label': 'Hund', 'outcome': 'incorrect'},
                    {'label': 'Frosch', 'outcome': 'correct'},
                    {'label': 'Karpfen', 'outcome': 'correct'},
                    {'label': 'Amsel', 'outcome': 'correct'},
                  ],
              },
            },
          ],
        };
        Json unit() => {
          'id': 'u',
          'child_id': 'child',
          'subject': matching ? 'Biologie' : 'Mathematik',
          'topic': matching ? 'Tierklassen' : 'Brüche',
          'status': 'paused',
          'explanation': 'Gespeicherte Erklärung.',
          'introduction_seen': true,
          'supports_recheck': true,
          'questions': [task()],
          'coaching': null,
          'pending_feedback': {
            'attempt_id': 'saved',
            'question_id': 'q',
            'answer': task()['attempts'][0]['answer'],
            'outcome': outcome,
            'assisted': false,
            'explanation': null,
          },
        };
        final state = AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              if (r.url.path.endsWith('/recheck')) {
                outcome = 'correct';
                return jsonReply({
                  'unit': unit(),
                  'outcome': 'correct',
                  'assisted': false,
                  'explanation': 'Gleich viel.',
                });
              }
              return jsonReply(unit());
            }),
          ),
        )..user = {'id': 'child', 'role': 'child', 'child_id': 'child'};
        final router = GoRouter(
          initialLocation: '/unit/u',
          routes: [
            GoRoute(
              path: '/unit/:id',
              builder: (_, _) => UnitScreen(state, unitId: 'u'),
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp.router(theme: appTheme(), routerConfig: router),
        );
        await tester.pumpAndSettle();
        if (matching) {
          expect(find.bySemanticsLabel('Richtig zugeordnet'), findsNWidgets(3));
          expect(
            find.bySemanticsLabel('Dieses Paar noch einmal versuchen'),
            findsOneWidget,
          );
          expect(requests.where((r) => r.method == 'POST'), isEmpty);
        } else {
          final check = find.text('Antwort erneut prüfen');
          await tester.ensureVisible(check);
          await tester.tap(check);
          await tester.pumpAndSettle();
          expect(find.text('Richtig!'), findsOneWidget);
          expect(find.text('6/16'), findsOneWidget);
          expect(find.text('Bewertung nachgeprüft'), findsOneWidget);
          await tester.ensureVisible(find.text('Bewertung nachgeprüft'));
          await tester.tap(find.text('Bewertung nachgeprüft'));
          await tester.pumpAndSettle();
          expect(find.text('Nicht sicher bewertbar → Richtig'), findsOneWidget);
          expect(
            requests
                .where((r) => r.method == 'POST')
                .map((r) => r.url.path)
                .toList(),
            ['/api/units/u/questions/q/recheck'],
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        semantics.dispose();
      },
    );
  }
}
