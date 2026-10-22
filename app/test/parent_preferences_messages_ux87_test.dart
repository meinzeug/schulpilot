import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/subject_level.dart';
import 'package:schulpilot/ui.dart';

import 'parent_learning_overview_test.dart' as fixture;

class _Fixture {
  final data = fixture.parentOverview(), requests = <http.Request>[];
  Future<http.Response?> Function(http.Request)? respond;
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              return await respond?.call(r) ??
                  fixture.jsonResponse(r.method == 'GET' ? data : {});
            }),
          ),
        )
        ..user = fixture.parentUser()
        ..familyId = 'own-family';
  Future<BuildContext> mount(
    WidgetTester tester, {
    String dialog = 'preferences',
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    late BuildContext screen;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              screen = context;
              return FilledButton(
                onPressed: () async {
                  if (dialog == 'level') {
                    await editSubjectLevel(
                      context,
                      state,
                      data['child']['id'],
                      'math',
                    );
                  } else {
                    await preferencesDialog(context, state, data['child']);
                  }
                },
                child: const Text('Öffnen'),
              );
            },
          ),
        ),
      ),
    );
    await tap(tester, 'Öffnen');
    return screen;
  }
}

Future<void> tap(WidgetTester tester, String label) async {
  final f = find.text(label).last;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, String label, String value) async {
  final f = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.enterText(f, value);
  await tester.pump();
}

Json subject({int revision = 1}) => {
  'id': 'math',
  'title': 'Mathematik',
  'selected': true,
  'setting_revision': revision,
  'level_type': 'klasse',
  'level_number': 5,
};
Json levels() => {
  'items': [
    {
      'id': 'class-5',
      'title': 'Klasse 5',
      'level_type': 'klasse',
      'level_number': 5,
    },
    {
      'id': 'class-6',
      'title': 'Klasse 6',
      'level_type': 'klasse',
      'level_number': 6,
    },
  ],
};
void _setupLevels(_Fixture f) {
  f.respond = (r) async => fixture.jsonResponse(
    r.url.path.endsWith('/levels')
        ? levels()
        : {
            'can_manage': true,
            'items': [subject()],
          },
  );
}

void main() {
  testWidgets(
    'P76 unmatched subject days show a conflict without changing the saved choice',
    (tester) async {
      final f = _Fixture();
      f.data['child']['preferences']['weekdays'] = [0, 1];
      f.data['child']['preferences']['subject_days'] = {
        'Mathematik': [5],
      };
      await f.mount(tester);
      await tap(tester, 'Fächer auf Tage verteilen');
      expect(
        find.textContaining('Mathematik hat keinen Fach-Lerntag gemeinsam'),
        findsOneWidget,
      );
      await tap(tester, 'Speichern');
      final body = jsonDecode(f.requests.single.body);
      expect(body['weekdays'], [0, 1]);
      expect(body['subject_days'], {
        'Mathematik': [5],
      });
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P77 live schedule summary keeps day and week minima independent at large text',
    (tester) async {
      final f = _Fixture();
      f.data['child']['preferences']['weekdays'] = [0, 1, 2, 3, 4];
      await f.mount(tester, width: 320, scale: 2);
      await fill(tester, 'Mindestziel pro Tag', '25');
      await fill(tester, 'Mindestziel pro Woche', '50');
      expect(
        find.textContaining(
          '5 feste Lerntage · 25 Min. pro Lerntag · 50 Min. Wochenminimum.',
        ),
        findsOneWidget,
      );
      await tap(tester, 'Speichern');
      expect(jsonDecode(f.requests.single.body)['weekly_minutes'], 50);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P78 equal quiet hours and a midnight interval have distinct explanations',
    (tester) async {
      final f = _Fixture();
      await f.mount(tester);
      expect(
        find.text('Ruhezeit von 20 bis 8 Uhr am nächsten Tag.'),
        findsOneWidget,
      );
      await fill(tester, 'Ruhezeit ab', '8');
      expect(find.text('Gleiche Uhrzeiten: keine Ruhezeit.'), findsOneWidget);
      await tap(tester, 'Speichern');
      final body = jsonDecode(f.requests.single.body);
      expect(body['quiet_start'], 8);
      expect(body['quiet_end'], 8);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P79 German pause dates have a calendar and clear path but keep ISO transport',
    (tester) async {
      final f = _Fixture();
      f.data['child']['preferences']['pause_until'] = '2026-11-15';
      await f.mount(tester);
      final date = find.widgetWithText(TextFormField, 'Auszeit bis');
      await tester.ensureVisible(date);
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(date).controller!.text, '15.11.2026');
      await tester.tap(find.byTooltip('Auszeit im Kalender wählen'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(DatePickerDialog))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Auszeit aufheben'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(date).controller!.text, '');
      await fill(tester, 'Auszeit bis', '16.11.2026');
      await tap(tester, 'Speichern');
      expect(jsonDecode(f.requests.single.body)['pause_until'], '2026-11-16');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('P79 an impossible pause date stays local and keeps the draft', (
    tester,
  ) async {
    final f = _Fixture();
    await f.mount(tester);
    await fill(tester, 'Auszeit bis', '31.02.2026');
    await tap(tester, 'Speichern');
    expect(
      find.text('Bitte ein gültiges Datum als TT.MM.JJJJ eingeben.'),
      findsOneWidget,
    );
    expect(f.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('P80 focus subject selection preserves existing private text', (
    tester,
  ) async {
    final f = _Fixture();
    f.data['child']['preferences']['focus_subjects'] = ['Privates Fach'];
    f.data['child']['subjects'] = ['Mathematik', 'Englisch'];
    await f.mount(tester);
    final choice = find.widgetWithText(FilterChip, 'Englisch');
    await tester.ensureVisible(choice);
    await tester.pumpAndSettle();
    await tester.tap(choice);
    await tester.pumpAndSettle();
    await tap(tester, 'Speichern');
    expect(jsonDecode(f.requests.single.body)['focus_subjects'], [
      'Privates Fach',
      'Englisch',
    ]);
    expect(f.requests.single.method, 'PUT');
    await tester.pumpWidget(const SizedBox());
  });
  for (final label in ['Fächer', 'Themen zum Wiederholen']) {
    testWidgets(
      'P81 $label rejects 21 entries locally and permits the existing twenty limit',
      (tester) async {
        final f = _Fixture();
        await f.mount(tester);
        await fill(
          tester,
          label,
          List.generate(21, (i) => 'Eintrag $i').join(', '),
        );
        await tap(tester, 'Speichern');
        expect(
          find.text('Bitte höchstens 20 Einträge angeben.'),
          findsOneWidget,
        );
        expect(f.requests, isEmpty);
        await fill(
          tester,
          label,
          List.generate(20, (i) => 'Eintrag $i').join(', '),
        );
        await tap(tester, 'Speichern');
        expect(f.requests, hasLength(1));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'P82 revoking child consent explains registration removal and stays explicit',
    (tester) async {
      final f = _Fixture();
      f.data['child']['preferences']['push_consent'] = true;
      await f.mount(tester);
      expect(
        find.textContaining(
          'Ausschalten entfernt seine vorhandenen Push-Registrierungen.',
        ),
        findsOneWidget,
      );
      final control = find.widgetWithText(
        SwitchListTile,
        'Push am Kindergerät erlauben',
      );
      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      await tester.tap(control);
      await tester.pumpAndSettle();
      await tap(tester, 'Speichern');
      expect(jsonDecode(f.requests.single.body)['push_consent'], false);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P83 the help preference states its existing notification conditions',
    (tester) async {
      final f = _Fixture();
      await f.mount(tester);
      expect(
        find.textContaining('Push bleibt zusätzlich vom Geräte-Opt-in'),
        findsOneWidget,
      );
      final control = find.widgetWithText(
        SwitchListTile,
        'Hilfewünsche hervorheben & melden',
      );
      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      await tester.tap(control);
      await tester.pumpAndSettle();
      await tap(tester, 'Speichern');
      expect(jsonDecode(f.requests.single.body)['notify_help'], false);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P01 P02 preferences bind the exact parent and a pending save removes only its old route',
    (tester) async {
      final pending = Completer<http.Response>();
      final f = _Fixture();
      f.respond = (r) async => pending.future;
      final screen = await f.mount(tester);
      final save = find.text('Speichern');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      expect(f.requests, hasLength(1));
      expect(tester.widget<PopScope>(find.byType(PopScope).last).canPop, false);
      final account = {...f.state.user!};
      f.state.user = account;
      f.state.refreshState();
      unawaited(
        showDialog<void>(
          context: screen,
          builder: (_) => const AlertDialog(title: Text('Neue Sitzung')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lernziele & Plan'), findsNothing);
      pending.complete(fixture.jsonResponse({}));
      await tester.pumpAndSettle();
      expect(find.text('Neue Sitzung'), findsOneWidget);
      expect(identical(f.state.user, account), true);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P01 an account change removes the private pause calendar together with its own draft',
    (tester) async {
      final f = _Fixture();
      f.data['child']['preferences']['pause_until'] = '2026-11-15';
      final screen = await f.mount(tester);
      await tester.ensureVisible(find.byTooltip('Auszeit im Kalender wählen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Auszeit im Kalender wählen'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      f.state.familyId = 'another-family';
      f.state.refreshState();
      unawaited(
        showDialog<void>(
          context: screen,
          builder: (_) => const AlertDialog(title: Text('Neue Familie')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.text('Lernziele & Plan'), findsNothing);
      expect(find.text('Neue Familie'), findsOneWidget);
      expect(f.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P93 a failed level write keeps the choice and explicitly reloads the new revision',
    (tester) async {
      final f = _Fixture();
      var revision = 1, writes = 0;
      f.respond = (r) async {
        if (r.method == 'PUT') {
          writes++;
          expect(jsonDecode(r.body)['level_number'], 6);
          expect(jsonDecode(r.body)['revision'], writes == 1 ? 1 : 2);
          return fixture.jsonResponse(
            writes == 1
                ? {'detail': 'Die Stufe wurde inzwischen geändert.'}
                : {},
            writes == 1 ? 409 : 200,
          );
        }
        return fixture.jsonResponse(
          r.url.path.endsWith('/levels')
              ? levels()
              : {
                  'can_manage': true,
                  'items': [subject(revision: revision)],
                },
        );
      };
      await f.mount(tester, dialog: 'level');
      await tap(tester, 'Klasse 5');
      await tap(tester, 'Klasse 6');
      await tap(tester, 'Stufe übernehmen');
      expect(find.text('Die Stufe wurde inzwischen geändert.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Klasse 6'), findsOneWidget);
      expect(writes, 1);
      revision = 2;
      await tap(tester, 'Gespeicherte Stufe neu laden');
      expect(find.text('Klasse 6'), findsOneWidget);
      expect(writes, 1);
      await tap(tester, 'Stufe übernehmen');
      expect(writes, 2);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P93 a pending level save is single and cannot be dismissed or edited',
    (tester) async {
      final pending = Completer<http.Response>();
      final f = _Fixture();
      _setupLevels(f);
      final get = f.respond!;
      f.respond = (r) => r.method == 'PUT' ? pending.future : get(r);
      await f.mount(tester, dialog: 'level');
      await tester.tap(find.text('Stufe übernehmen'));
      await tester.pump();
      expect(f.requests.where((r) => r.method == 'PUT'), hasLength(1));
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .onChanged,
        isNull,
      );
      expect(tester.widget<PopScope>(find.byType(PopScope).last).canPop, false);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Abbrechen'))
            .onPressed,
        isNull,
      );
      pending.complete(fixture.jsonResponse({}));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P93 old level reads do not open in a new login map with the same id',
    (tester) async {
      final pending = Completer<http.Response>();
      final f = _Fixture();
      _setupLevels(f);
      final get = f.respond!;
      f.respond = (r) =>
          r.url.path.endsWith('/levels') ? pending.future : get(r);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => editSubjectLevel(
                  context,
                  f.state,
                  f.data['child']['id'],
                  'math',
                ),
                child: const Text('Öffnen'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Öffnen'));
      await tester.pump();
      f.state.user = {...f.state.user!};
      f.state.refreshState();
      pending.complete(fixture.jsonResponse(levels()));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(f.requests.every((r) => r.method == 'GET'), true);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('P93 a new account removes only its own old level dialog', (
    tester,
  ) async {
    final f = _Fixture();
    _setupLevels(f);
    final screen = await f.mount(tester, dialog: 'level');
    f.state.user = {...f.state.user!};
    f.state.refreshState();
    unawaited(
      showDialog<void>(
        context: screen,
        builder: (_) => const AlertDialog(title: Text('Neue Sitzung')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stufe festlegen'), findsNothing);
    expect(find.text('Neue Sitzung'), findsOneWidget);
    expect(f.requests.every((r) => r.method == 'GET'), true);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'P93 clearing a known level keeps nullable API semantics at 320px large text',
    (tester) async {
      final f = _Fixture();
      _setupLevels(f);
      final get = f.respond!;
      f.respond = (r) async =>
          r.method == 'PUT' ? fixture.jsonResponse({}) : get(r);
      await f.mount(tester, dialog: 'level', width: 320, scale: 1.8);
      await tap(tester, 'Klasse 5');
      await tap(tester, 'Noch nicht festlegen');
      await tap(tester, 'Stufe übernehmen');
      expect(
        jsonDecode(f.requests.singleWhere((r) => r.method == 'PUT').body),
        {
          'active': true,
          'revision': 1,
          'level_type': null,
          'level_number': null,
          'level_confirmed': true,
        },
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P94 P95 messages show local stored timestamps and actual request kinds',
    (tester) async {
      final f = _Fixture();
      f.data['messages'] = [
        for (final kind in [
          'help',
          'interest',
          'plan_change',
          'reply',
          'reminder',
          'preparation',
        ])
          {
            'id': kind,
            'kind': kind,
            'body': 'Künstliche Nachricht $kind',
            'resolved': kind == 'interest',
            'sender_role': kind == 'reply' ? 'parent' : 'child',
            'created':
                DateTime(2026, 10, 22, 13, 5).millisecondsSinceEpoch / 1000,
          },
      ];
      await _mountMessages(tester, f);
      for (final label in [
        'Hilfewunsch',
        'Interesse',
        'Planvorschlag',
        'Antwort',
        'Lernerinnerung',
        'Heftvorbereitung',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('22.10.2026 · 13:05'), findsNWidgets(6));
      expect(find.text('Besprochen'), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), true);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P96 P97 open-help filtering describes the bounded loaded preview and never resolves work',
    (tester) async {
      final f = _Fixture();
      f.data['messages'] = [
        for (var i = 0; i < 100; i++)
          {
            'id': 'message-$i',
            'kind': i == 99 ? 'help' : 'reply',
            'body': i == 99 ? 'Älterer offener Hilfewunsch' : 'Antwort $i',
            'resolved': false,
            'sender_role': i == 99 ? 'child' : 'parent',
            'created': 1792660000 + i,
          },
      ];
      await _mountMessages(tester, f);
      expect(
        find.text('Bis zu 100 neueste Nachrichten · 100 geladen'),
        findsOneWidget,
      );
      await tap(tester, 'Offene Hilfe (1)');
      expect(find.text('Älterer offener Hilfewunsch'), findsOneWidget);
      expect(find.text('Antwort 0'), findsNothing);
      expect(
        find.textContaining('Ältere Nachrichten können außerhalb'),
        findsOneWidget,
      );
      expect(f.requests, hasLength(1));
      expect(f.requests.single.method, 'GET');
      await tap(tester, 'Alle geladenen');
      expect(find.text('Antwort 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P98 a reply uses only the explicitly selected saved task context',
    (tester) async {
      final f = _Fixture();
      f.data['messages'] = [
        for (final id in [
          '11111111111111111111111111111111',
          '22222222222222222222222222222222',
        ])
          {
            'id': id,
            'kind': 'help',
            'body': 'Künstliche Frage $id',
            'resolved': false,
            'sender_role': 'child',
            'created': 1792660000,
            'context': {'unit_id': id},
          },
      ];
      await _mountMessages(tester, f);
      final answer = find.text('Dazu antworten').last;
      await tester.ensureVisible(answer);
      await tester.pumpAndSettle();
      await tester.tap(answer);
      await tester.pumpAndSettle();
      expect(find.text('Zur ausgewählten Lernrunde'), findsOneWidget);
      expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.enterText(
        find.byType(TextField),
        'Schau auf die gleich großen Teile.',
      );
      await tap(tester, 'Senden');
      final sent = f.requests.singleWhere((r) => r.method == 'POST');
      expect(jsonDecode(sent.body), {
        'kind': 'reply',
        'body': 'Schau auf die gleich großen Teile.',
        'unit_id': '22222222222222222222222222222222',
      });
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P98 removed source contexts have no invalid read or reply route',
    (tester) async {
      final f = _Fixture();
      f.data['messages'] = [
        {
          'id': 'old',
          'kind': 'help',
          'body': 'Künstliche alte Frage',
          'resolved': false,
          'sender_role': 'child',
          'context': null,
          'context_unavailable': true,
        },
      ];
      await _mountMessages(tester, f);
      expect(
        find.text('Der zugehörige Lernstoff ist nicht mehr verfügbar.'),
        findsOneWidget,
      );
      expect(find.text('Dazu antworten'), findsNothing);
      expect(find.text('Lernrunde ansehen'), findsNothing);
      expect(f.requests.every((r) => r.method == 'GET'), true);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P01 message preview disappears on a family change without reusing its old callback',
    (tester) async {
      final f = _Fixture();
      f.data['messages'] = [
        {
          'id': 'private',
          'kind': 'help',
          'body': 'Private künstliche Frage',
          'resolved': false,
          'sender_role': 'child',
        },
      ];
      await _mountMessages(tester, f);
      expect(find.text('Private künstliche Frage'), findsOneWidget);
      f.state.familyId = 'another-family';
      f.state.refreshState();
      await tester.pumpAndSettle();
      expect(find.text('Private künstliche Frage'), findsNothing);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final technicalOnly in [false, true]) {
    testWidgets(
      'P99 no academic activity is honestly empty technicalOnly=$technicalOnly',
      (tester) async {
        final f = _Fixture();
        f.respond = (r) async {
          expect(r.method, 'GET');
          if (r.url.path.endsWith('/activity')) {
            return fixture.jsonResponse(
              technicalOnly
                  ? [
                      {
                        'kind': 'provider_migration',
                        'created': 1792660000,
                        'detail': {},
                      },
                    ]
                  : [],
            );
          }
          if (r.url.path.endsWith('/learning')) {
            return fixture.jsonResponse({
              'items': [],
              'units': [],
              'subjects': [],
              'pagination': {'page': 1, 'pages': 1, 'total': 0},
              'section': 'completed',
            });
          }
          return fixture.jsonResponse(f.data);
        };
        await _mountMessages(tester, f, history: true);
        expect(
          find.textContaining(
            'Hier sind noch keine fachlichen Lernaktivitäten gespeichert.',
          ),
          findsOneWidget,
        );
        if (technicalOnly) {
          expect(find.text('Technische Ereignisse'), findsOneWidget);
        }
        expect(f.requests.every((r) => r.method == 'GET'), true);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'P100 refreshing the saved overview re-reads the existing timeline without a write',
    (tester) async {
      final f = _Fixture();
      var activity = 0;
      f.respond = (r) async {
        expect(r.method, 'GET');
        if (r.url.path.endsWith('/activity')) {
          return fixture.jsonResponse([
            {
              'kind': 'answer',
              'created': 1792660000,
              'detail': {'text': 'Gespeicherter Stand ${++activity}'},
            },
          ]);
        }
        if (r.url.path.endsWith('/learning')) {
          return fixture.jsonResponse({
            'items': [],
            'units': [],
            'subjects': [],
            'pagination': {'page': 1, 'pages': 1, 'total': 0},
            'section': 'completed',
          });
        }
        return fixture.jsonResponse(f.data);
      };
      await _mountMessages(tester, f, history: true);
      expect(find.text('Gespeicherter Stand 1'), findsOneWidget);
      f.state.refreshState();
      await tester.pumpAndSettle();
      expect(find.text('Gespeicherter Stand 2'), findsOneWidget);
      expect(activity, 2);
      expect(f.requests.every((r) => r.method == 'GET'), true);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Future<GoRouter> _mountMessages(
  WidgetTester tester,
  _Fixture f, {
  bool history = false,
}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final child = f.data['child']['id'];
  final router = GoRouter(
    initialLocation: history ? '/child/$child' : '/messages/$child',
    routes: [
      GoRoute(
        path: '/messages/:id',
        builder: (_, s) =>
            MessagesScreen(f.state, childId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/child/:id',
        builder: (_, s) => ChildDetailScreen(
          f.state,
          childId: s.pathParameters['id']!,
          section: 'verlauf',
        ),
      ),
      GoRoute(
        path: '/unit/:id',
        builder: (_, s) =>
            Scaffold(body: Text("Runde ${s.pathParameters['id']!}")),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return router;
}
