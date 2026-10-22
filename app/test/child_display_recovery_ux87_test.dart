import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:schulpilot/adaptive_learning_step.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/daily_plan_panel.dart';
import 'package:schulpilot/notebook_photo.dart';
import 'package:schulpilot/lesson_voice.dart';
import 'package:schulpilot/ui.dart';

import 'lesson_voice_test.dart' as vf;

Widget home(Widget c) => MaterialApp(
  theme: appTheme(),
  home: Scaffold(body: c),
);
Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'K091 biology step without a title never invents fraction subject matter',
    (t) async {
      await t.pumpWidget(
        home(
          const AdaptiveLearningStep(
            plan: {
              'phase': 'explanation',
              'message': 'Lies den gespeicherten Absatz.',
            },
          ),
        ),
      );
      expect(find.textContaining('Brüche'), findsNothing);
      expect(find.text('Ein anderer Blick auf deine Aufgabe'), findsOneWidget);
    },
  );
  for (final explanation in <Object>[
    <String, dynamic>{},
    {'text': 42},
    'legacy',
  ]) {
    testWidgets(
      'K092 incomplete legacy explanation $explanation stays readable without a crash',
      (t) async {
        await t.pumpWidget(
          home(
            AdaptiveLearningStep(
              plan: {'phase': 'explanation', 'explanation': explanation},
            ),
          ),
        );
        expect(t.takeException(), isNull);
        expect(find.textContaining('gleich großen Mengen'), findsNothing);
      },
    );
  }
  testWidgets(
    'K093 child day preview labels its bound and explicitly reveals remaining saved days',
    (t) async {
      final plan = {
        'date': '2026-10-20',
        'week': List.generate(
          6,
          (i) => {
            'date': '2026-10-${21 + i}',
            'items': <Json>[],
            'planned_minutes': 10,
          },
        ),
      };
      await t.pumpWidget(
        home(
          SingleChildScrollView(
            child: DailyPlanPanel(plan: plan, childView: true),
          ),
        ),
      );
      expect(find.text('Die nächsten drei Lerntage'), findsOneWidget);
      expect(find.text('Sa, 24.10.'), findsNothing);
      await tap(t, find.text('Weitere 3 Lerntage ansehen'));
      expect(find.text('Sa, 24.10.'), findsOneWidget);
    },
  );
  testWidgets(
    'K094 invalid photo bytes have one explicit successful reload and no automatic loop',
    (t) async {
      var gets = 0;
      final s = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((_) async {
            gets++;
            return http.Response.bytes(
              gets == 1
                  ? [1, 2, 3]
                  : image.encodePng(image.Image(width: 2, height: 2)),
              200,
            );
          }),
        ),
      )..user = {'id': 'own', 'role': 'child'};
      await t.pumpWidget(home(NotebookPhoto(s, materialId: 'page')));
      await t.pumpAndSettle();
      expect(find.text('Foto erneut laden'), findsOneWidget);
      expect(gets, 1);
      expect(t.takeException(), isNull);
      await tap(t, find.text('Foto erneut laden'));
      expect(gets, 2);
      expect(find.text('Foto erneut laden'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('K095 failed thumbnail retains a meaningful accessible label', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    final s = AppState(
      api: Api(
        base: 'https://example.invalid/api',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'detail': 'Foto nicht erreichbar'}),
            404,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    )..user = {'id': 'own', 'role': 'child'};
    await t.pumpWidget(
      home(NotebookPhoto(s, materialId: 'page', thumbnail: true)),
    );
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('Heftfoto nicht verfügbar'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    handle.dispose();
  });
  testWidgets('K094 photo bytes and zoom disappear on a same-ID new login', (
    t,
  ) async {
    final fresh = Completer<http.Response>();
    var reads = 0;
    final s = AppState(
      api: Api(
        base: 'https://example.invalid/api',
        client: MockClient(
          (_) async => ++reads == 1
              ? http.Response.bytes(
                  image.encodePng(image.Image(width: 2, height: 2)),
                  200,
                )
              : fresh.future,
        ),
      ),
    )..user = {'id': 'own', 'role': 'child'};
    await t.pumpWidget(
      home(NotebookPhoto(s, materialId: 'page', zoomable: true)),
    );
    await t.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    s.user = {...s.user!};
    s.refreshState();
    await t.pump();
    expect(find.byType(Image), findsNothing);
    expect(reads, 2);
    fresh.complete(
      http.Response.bytes(
        image.encodePng(image.Image(width: 3, height: 3)),
        200,
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'K031 removing a microphone owner closes only its consent and old callbacks never start capture',
    (t) async {
      final adapter = vf.FakeLessonVoice();
      final voice = LessonVoiceSession(adapter: adapter);
      final text = TextEditingController();
      addTearDown(voice.dispose);
      addTearDown(text.dispose);
      final nav = GlobalKey<NavigatorState>();
      Widget page(bool visible) => MaterialApp(
        navigatorKey: nav,
        theme: appTheme(),
        home: Scaffold(
          body: visible
              ? VoiceInputButton(controller: text, voice: voice)
              : const Text('Neue Aufgabe'),
        ),
      );
      await t.pumpWidget(page(true));
      await tap(t, find.text('Sprechen'));
      final old = t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Sprechen'))
          .onPressed!;
      nav.currentState!.push(
        DialogRoute<void>(
          context: nav.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Neuer Dialog')),
        ),
      );
      await t.pumpAndSettle();
      await t.pumpWidget(page(false));
      await t.pumpAndSettle();
      old();
      await t.pumpAndSettle();
      expect(find.text('Mit dem Mikrofon schreiben?'), findsNothing);
      expect(find.text('Neuer Dialog'), findsOneWidget);
      expect(adapter.listens, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
}
