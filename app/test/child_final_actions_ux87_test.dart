import 'page_tools_test_helpers.dart' as page_tools;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_tips.dart';

import 'learning_tips_test.dart' as tips;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/material_screen.dart';
import 'package:schulpilot/lesson_voice.dart';
import 'package:schulpilot/tutor_sheet.dart';

import 'learning_room_test.dart' as rounds;
import 'homework_screen_test.dart' as hw;
import 'child_homework_continuity_test.dart' as hc;
import 'child_sources_input_ux87_test.dart' as src;

Future<void> tap(WidgetTester t, Finder f) async {
  await t.pumpAndSettle();
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'K017 saved homework explanation exposes explicit reading with no automatic speech',
    (t) async {
      final s = hw.account(
        MockClient(
          (_) async =>
              hw.reply(hw.fixture(turns: [hw.analysisTurn(), hw.modelTurn()])),
        ),
      );
      await hw.open(t, s);
      expect(find.byType(ReadAloudButton), findsWidgets);
      expect(find.widgetWithText(TextButton, 'Vorlesen'), findsWidgets);
    },
  );
  testWidgets(
    'K015 unexpected homework transport errors never show their internal marker',
    (t) async {
      final s = hw.account(
        MockClient((r) async {
          if (r.method == 'POST') throw StateError('PRIVATE_TRANSPORT_MARKER');
          return hw.reply(hw.fixture());
        }),
      );
      await hw.open(t, s);
      await t.ensureVisible(find.text('Erkläre es mir'));
      await t.tap(find.text('Erkläre es mir'));
      await hc.flush(t);
      expect(find.textContaining('PRIVATE_TRANSPORT_MARKER'), findsNothing);
      expect(
        find.textContaining('Keine Verbindung zu SCHULPILOT'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'K010 refresh preserves existing homework cards with a labelled status',
    (t) async {
      final pending = Completer<http.Response>();
      var gets = 0;
      final s = hw.account(
        MockClient((_) async {
          gets++;
          return gets == 1
              ? hw.reply({
                  'photos': [
                    {
                      'id': 'p',
                      'topic': 'Gespeichertes Foto',
                      'confirmed': false,
                    },
                  ],
                  'next_cursor': null,
                })
              : pending.future;
        }),
      );
      await hw.open(t, s, overview: true, openTools: false);
      await page_tools.openPageTools(t, 'homework-photo-tools');
      final refresh = find.widgetWithText(
        TextButton,
        'Aufgabenfotos aktualisieren',
      );
      await t.ensureVisible(refresh);
      await t.pumpAndSettle();
      expect(refresh.hitTestable(), findsOneWidget);
      await t.tap(refresh);
      await t.pump();
      expect(find.text('Gespeichertes Foto'), findsOneWidget);
      expect(find.textContaining('aktualisiert'), findsWidgets);
      pending.complete(
        hw.reply({
          'photos': [
            {'id': 'p', 'topic': 'Gespeichertes Foto', 'confirmed': false},
          ],
          'next_cursor': null,
        }),
      );
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'K018 covered homework route pauses status polling and rechecks on return',
    (t) async {
      var reads = 0;
      var pending = false;
      final s = hw.account(
        MockClient((r) async {
          reads++;
          final data = hw.fixture();
          if (pending) {
            (data['turns'] as List).add({
              'id': 'queued',
              'status': 'queued',
              'homework': {'action': 'question'},
            });
          }
          return hw.reply(data);
        }),
      );
      await hw.open(t, s);
      pending = true;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await hc.flush(t);
      final nav = Navigator.of(t.element(find.byType(TextField).first));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Andere Seite')),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      final before = reads;
      await t.pump(const Duration(seconds: 10));
      expect(reads, before);
      pending = false;
      nav.pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await hc.flush(t);
      expect(reads, greaterThan(before));
    },
  );
  testWidgets(
    'K056 synthetic material consent names the configured service without a fabricated price or provider',
    (t) async {
      final requests = <http.Request>[];
      final s = src.account((r) async {
        requests.add(r);
        return src.reply({});
      });
      s.user = {...s.user!, 'synthetic': true};
      await t.pumpWidget(
        src.home(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => importMaterial(context, s, 'child'),
              child: const Text('Importieren'),
            ),
          ),
        ),
      );
      await tap(t, find.text('Importieren'));
      expect(find.textContaining('eingerichteten KI-Dienst'), findsOneWidget);
      expect(find.textContaining('kostenlos'), findsNothing);
      expect(find.textContaining('OpenRouter'), findsNothing);
      s.user = {...s.user!};
      s.refreshState();
      await tap(t, find.text('Bestätigen'));
      expect(requests, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K026 saved explanation can reopen at its own prior step without affecting the answer',
    (t) async {
      final server = rounds.SavedRound();
      server.value['explanation'] =
          'Erster kurzer Absatz.\n\nZweiter kurzer Absatz.';
      final h = await rounds.openRound(t, server);
      await rounds.tapText(t, 'Hilfe');
      await t.ensureVisible(find.text('Mehr Hilfe'));
      await t.tap(find.text('Mehr Hilfe'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Erklärung ansehen'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));
      await t.ensureVisible(find.text('Nächster Schritt'));
      await t.tap(find.text('Nächster Schritt'));
      await t.pump();
      expect(find.text('Schritt 2 von 2'), findsOneWidget);
      await t.tap(find.text('Weiter üben'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Mehr Hilfe'));
      await t.tap(find.text('Mehr Hilfe'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Erklärung ansehen'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Schritt 2 von 2'), findsOneWidget);
      expect(server.answers, 0);
      await h.close();
    },
  );
  testWidgets(
    'K086 a tutor citation has a real private source link only when server metadata supplies it',
    (t) async {
      final s = src.account(
        (_) async => src.reply({
          'questions': [
            {
              'id': 'q',
              'status': 'ready',
              'question': 'Frage',
              'reply': {
                'kind': 'answer',
                'answer': 'Erklärung',
                'sources': [
                  {
                    'label': 'Heftseite',
                    'quote': 'Belegter Satz',
                    'material_id': 'a' * 32,
                  },
                ],
              },
            },
          ],
          'next_cursor': null,
        }),
      );
      await t.pumpWidget(
        src.home(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showTutorSheet(
                context,
                s,
                childId: 'child',
                materialId: 'a' * 32,
              ),
              child: const Text('Fragen'),
            ),
          ),
        ),
      );
      await tap(t, find.text('Fragen'));
      await tap(t, find.text('Wo steht das?'));
      expect(find.text('Heftseite dazu ansehen'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final status in [503, 409]) {
    testWidgets(
      'K087 real unit draft-save status $status blocks the bound media opener',
      (t) async {
        final server = rounds.SavedRound(
          questions: [rounds.question('cat', type: 'short')],
        );
        server.value['learning_session'] = {
          'source_signature': 'test-source',
          'draft_revision': 0,
          'working_memory': {},
          'updated': 0,
        };
        var saves = 0;
        final h = await rounds.openRound(
          t,
          server,
          handle: (r) async {
            if (r.url.path.endsWith('/learning-session/draft')) {
              saves++;
              return rounds.jsonReply({
                'detail': 'Entwurf nicht gespeichert',
              }, status);
            }
            if (r.url.path.contains('/learning-tips/')) {
              return tips.reply(tips.tips());
            }
            return server.handle(r);
          },
        );
        await t.enterText(find.byType(TextField), 'Eigene Antwort');
        await t.pump();
        await rounds.tapText(t, 'Hilfe');
        await t.ensureVisible(find.text('Mehr Hilfe'));
        await t.tap(find.text('Mehr Hilfe'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await t.tap(find.text('Passendes Erklärvideo'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(const Duration(milliseconds: 400));
        final before = t
            .widgetList<LearningTips>(find.byType(LearningTips))
            .last
            .beforeOpen!;
        await expectLater(
          before(),
          throwsA(
            isA<ApiError>().having(
              (e) => e.message,
              'honest draft error',
              contains('noch nicht sicher gespeichert'),
            ),
          ),
        );
        expect(saves, greaterThan(0));
        expect(server.answers, 0);
        await h.close();
      },
    );
  }
}
