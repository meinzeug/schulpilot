// Isolated synthetic WidgetTester scenarios shared by the native and Chrome runners.
// Every API request is handled by MockClient; no real login, upload, provider or push.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/grades_screen.dart';
import 'package:schulpilot/ui.dart';

const childId = '11111111111111111111111111111111';
Json child() => {
  'id': childId,
  'display_name': 'Künstliches Testkind',
  'subjects': ['Mathematik', 'Englisch'],
  'preferences': {
    'weekdays': [0, 1, 2, 3, 4],
    'daily_minutes': 20,
    'weekly_minutes': 100,
    'session_minutes': 15,
    'break_minutes': 5,
    'focus_subjects': [],
    'subject_days': {},
    'repeat_topics': [],
    'pause_until': '2026-11-15',
    'quiet_start': 20,
    'quiet_end': 8,
    'reminders': false,
    'notify_help': true,
    'push_consent': false,
    'timezone': 'Europe/Berlin',
  },
};
Json grade() => {
  'id': 'synthetic-grade',
  'subject': 'Mathematik',
  'topic': 'Brüche',
  'value': 3.5,
  'scale': 'grade_1_6',
  'kind': 'test',
  'weight': 2,
  'note': '',
  'assessed_on': '2026-10-12',
  'revision': 4,
  'assignment_id': null,
};

class _Fixture {
  final requests = <http.Request>[];
  final Json data;
  _Fixture(this.data);
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              expect(
                r.method,
                anyOf('GET', 'PUT'),
                reason: 'No real login, message, push, provider or upload.',
              );
              return http.Response(
                jsonEncode(r.method == 'GET' ? data : {}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-parent',
          'role': 'parent',
          'display_name': 'Testeltern',
          'families': [
            {
              'id': 'synthetic-family',
              'permission': 'owner',
              'name': 'Künstlicher Haushalt',
            },
          ],
        }
        ..familyId = 'synthetic-family';
  Future<void> mount(
    WidgetTester tester,
    Brightness brightness,
    Widget Function(BuildContext) screen,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(brightness: brightness),
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: widget!,
        ),
        home: Scaffold(body: Builder(builder: screen)),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> press(WidgetTester tester, String label) async {
  final f = find.text(label).last;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, String label, String value) async {
  final f = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.enterText(f, value);
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'WEB parent minimum goals at 320px 200percent $brightness preserve separate values',
      (tester) async {
        final f = _Fixture({});
        await f.mount(
          tester,
          brightness,
          (context) => FilledButton(
            onPressed: () => preferencesDialog(context, f.state, child()),
            child: const Text('Lernvorgaben'),
          ),
        );
        await press(tester, 'Lernvorgaben');
        await fill(tester, 'Mindestziel pro Tag', '25');
        await fill(tester, 'Mindestziel pro Woche', '50');
        final summary = find.textContaining(
          '5 feste Lerntage · 25 Min. pro Lerntag · 50 Min. Wochenminimum.',
        );
        await tester.ensureVisible(summary);
        await tester.pumpAndSettle();
        expect(summary, findsOneWidget);
        expect(tester.takeException(), isNull);
        await press(tester, 'Speichern');
        expect(f.requests, hasLength(1));
        final saved = jsonDecode(f.requests.single.body);
        expect(saved['daily_minutes'], 25);
        expect(saved['weekly_minutes'], 50);
        expect(f.requests.single.method, 'PUT');
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'WEB parent pause calendar at 320px 200percent $brightness remains explicit and readable',
      (tester) async {
        final f = _Fixture({});
        await f.mount(
          tester,
          brightness,
          (context) => FilledButton(
            onPressed: () => preferencesDialog(context, f.state, child()),
            child: const Text('Auszeit'),
          ),
        );
        await press(tester, 'Auszeit');
        final calendar = find.byTooltip('Auszeit im Kalender wählen');
        await tester.ensureVisible(calendar);
        await tester.pumpAndSettle();
        expect(find.text('15.11.2026'), findsOneWidget);
        await tester.tap(calendar);
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        final accept = MaterialLocalizations.of(
          tester.element(find.byType(DatePickerDialog)),
        ).okButtonLabel;
        await press(tester, '16');
        await press(tester, accept);
        expect(find.text('16.11.2026'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('Auszeit aufheben'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Auszeit aufheben'));
        await tester.pumpAndSettle();
        await fill(tester, 'Auszeit bis', '17.11.2026');
        await press(tester, 'Speichern');
        expect(jsonDecode(f.requests.single.body)['pause_until'], '2026-11-17');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'WEB family messages at 320px 200percent $brightness retain context without a send',
      (tester) async {
        final f = _Fixture({
          'child': child(),
          'messages': [
            {
              'id': 'help',
              'kind': 'help',
              'body': 'Künstliche Frage zur Bruchaddition',
              'sender_role': 'child',
              'resolved': false,
              'created': 1792660000,
              'context': {'unit_id': '22222222222222222222222222222222'},
            },
            {
              'id': 'idea',
              'kind': 'interest',
              'body': 'Künstliches Interesse an Planeten',
              'sender_role': 'child',
              'resolved': true,
              'created': 1792650000,
            },
          ],
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final router = GoRouter(
          initialLocation: '/messages/$childId',
          routes: [
            GoRoute(
              path: '/messages/:id',
              builder: (_, s) =>
                  MessagesScreen(f.state, childId: s.pathParameters['id']!),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(
            theme: appTheme(brightness: brightness),
            routerConfig: router,
            builder: (context, widget) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: widget!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await press(tester, 'Offene Hilfe (1)');
        expect(find.text('Künstliches Interesse an Planeten'), findsNothing);
        await press(tester, 'Dazu antworten');
        expect(find.text('Zur ausgewählten Lernrunde'), findsOneWidget);
        await fill(
          tester,
          'Deine Nachricht',
          'Lass uns die gleich großen Teile anschauen.',
        );
        await press(tester, 'Abbrechen');
        expect(find.text('Künstliche Frage zur Bruchaddition'), findsOneWidget);
        expect(f.requests, hasLength(1));
        expect(f.requests.single.method, 'GET');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'WEB grade editor at 320px 200percent $brightness reveals errors and preserves the saved snapshot',
      (tester) async {
        final f = _Fixture({});
        await f.mount(
          tester,
          brightness,
          (context) => FilledButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => GradeEditor(
                f.state,
                childId: childId,
                childName: 'Künstliches Testkind',
                today: '2026-10-22',
                grade: grade(),
              ),
            ),
            child: const Text('Note öffnen'),
          ),
        );
        await press(tester, 'Note öffnen');
        await fill(tester, 'Note', '7');
        await press(tester, 'Speichern');
        expect(find.text('Gib eine Note von 1 bis 6 ein.'), findsOneWidget);
        expect(f.requests, isEmpty);
        expect(tester.takeException(), isNull);
        await fill(tester, 'Note', '3,5');
        await press(tester, 'Weitere Angaben');
        final weight = find.text('Gewichtung');
        await tester.ensureVisible(weight);
        await tester.pumpAndSettle();
        expect(weight, findsOneWidget);
        await press(tester, '2-fach');
        await press(tester, '3-fach');
        expect(tester.takeException(), isNull);
        await press(tester, 'Speichern');
        expect(f.requests, hasLength(1));
        final saved = jsonDecode(f.requests.single.body);
        expect(saved['value'], 3.5);
        expect(saved['revision'], 4);
        expect(saved['weight'], 3);
        expect(saved['assessed_on'], '2026-10-12');
        expect(f.requests.single.method, 'PUT');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
