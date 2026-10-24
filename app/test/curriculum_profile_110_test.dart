import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/curriculum_profile_dialog.dart';
import 'package:schulpilot/ui.dart';

import 'parent_settings_ux88_test.dart' as settings;

const actorId = '11111111111111111111111111111111';
const childId = '22222222222222222222222222222222';
const otherChildId = '33333333333333333333333333333333';
const path = '/api/children/$childId/curriculum-profile';
http.Response response(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json profile({bool configured = false}) => {
  'child_id': childId,
  'revision': 0,
  'profile_revision': 'a' * 64,
  'grade': 7,
  'state_code': configured ? 'DE-BW' : null,
  'school_form_id': configured ? 'bw_example' : null,
  'configured': configured,
  'needs_review': false,
  'state_binding_stale': false,
  'legacy_region': 'Nordrhein-Westfalen',
  'legacy_school_type': 'Gymnasium',
  'can_manage': true,
  'updated': null,
};
Json catalog() => {
  'states': [
    {
      'code': 'DE-BW',
      'name': 'Baden-Württemberg',
      'coverage': 'partial',
      'school_forms': [
        {'id': 'bw_example', 'label': 'Künstlicher Schulweg A'},
      ],
    },
    {
      'code': 'DE-NW',
      'name': 'Nordrhein-Westfalen',
      'coverage': 'partial',
      'school_forms': [
        {'id': 'nw_example', 'label': 'Künstlicher Schulweg B'},
      ],
    },
  ],
  'coverage': {'complete': false},
};

Finder field(String prefix, {bool skipOffstage = true}) =>
    find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey &&
          (widget.key! as ValueKey).value.toString().startsWith(prefix),
      skipOffstage: skipOffstage,
    );
Finder stateField() => field('curriculum-state:');
Finder schoolField() => field('curriculum-school:');
Finder gradeField() => field('curriculum-grade:');
String? stateValue(WidgetTester tester) =>
    tester.widget<DropdownButtonFormField<String>>(stateField()).initialValue;
String? schoolValue(WidgetTester tester) =>
    tester.widget<DropdownButtonFormField<String>>(schoolField()).initialValue;
int? gradeValue(WidgetTester tester) =>
    tester.widget<DropdownButtonFormField<int>>(gradeField()).initialValue;

DropdownButton<T> innerDropdown<T>(WidgetTester tester, Finder form) =>
    tester.widget<DropdownButton<T>>(
      find
          .descendant(
            of: form,
            matching: find.byWidgetPredicate(
              (widget) => widget is DropdownButton<T>,
            ),
          )
          .first,
    );

class Fixture {
  final calls = <http.Request>[];
  Json stored = profile();
  Future<http.Response>? pendingGet, pendingPut;
  int failures = 0, failureStatus = 409;
  final child = ValueNotifier(childId);
  final replacement = ValueNotifier<AppState?>(null);
  int saves = 0;
  final navigator = GlobalKey<NavigatorState>();
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              calls.add(request);
              expectSync(request.headers['X-Schulpilot-Account'], actorId);
              if (request.url.path == '/api/curriculum/catalog' &&
                  request.method == 'GET') {
                return response(catalog());
              }
              expectSync(request.url.path, path);
              if (request.method == 'GET') {
                return pendingGet ?? response(stored);
              }
              expectSync(request.method, 'PUT');
              expectSync(
                request.headers['Idempotency-Key'],
                matches(r'^[A-Za-z0-9_-]{16,80}$'),
              );
              if (pendingPut != null) {
                return pendingPut!;
              }
              if (failures > 0) {
                failures--;
                return response({
                  'detail': 'Künstlicher Speicherkonflikt. Dein Entwurf bleibt erhalten.',
                }, failureStatus);
              }
              final body = Json.from(jsonDecode(request.body));
              expectSync(body.keys.toSet(), {
                'revision',
                'profile_revision',
                'state_code',
                'school_form_id',
                'grade',
              });
              stored = {
                ...stored,
                ...body,
                'revision': body['revision'] + 1,
                'profile_revision': 'b' * 64,
                'configured': true,
              };
              return response(stored);
            }),
          ),
        )
        ..user = {
          'id': actorId,
          'role': 'parent',
          'families': [
            {'id': 'family-a', 'permission': 'manage'},
          ],
        }
        ..familyId = 'family-a'
        ..api.token = 'synthetic-session';
  Iterable<http.Request> get puts => calls.where((r) => r.method == 'PUT');

  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    bool settle = true,
    bool dynamicChild = false,
    bool dynamicState = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      state.inbox.dispose();
      state.dispose();
      child.dispose();
      replacement.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: appTheme(),
        builder: (context, content) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: content!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => dynamicChild || dynamicState
                ? TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => ValueListenableBuilder<AppState?>(
                        valueListenable: replacement,
                        builder: (_, replaced, _) =>
                            ValueListenableBuilder<String>(
                              valueListenable: child,
                              builder: (_, id, _) => CurriculumProfileEditor(
                                replaced ?? state,
                                childId: id,
                                childName: 'Künstliches Kind',
                              ),
                            ),
                      ),
                    ),
                    child: const Text('Profil öffnen'),
                  )
                : CurriculumProfileButton(
                    state,
                    childId: childId,
                    childName: 'Künstliches Kind',
                    onSaved: () => saves++,
                  ),
          ),
        ),
      ),
    );
    expect(
      calls,
      isEmpty,
      reason: 'The button does not load or configure a child profile on mount.',
    );
    await tester.tap(
      dynamicChild || dynamicState
          ? find.text('Profil öffnen')
          : find.byKey(const ValueKey('curriculum-profile:$childId')),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  Future<void> cover(WidgetTester tester) async {
    showDialog<void>(
      context: navigator.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text('Fremder Dialog'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zurück zum Profil'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder.hitTestable());
  await tester.pumpAndSettle();
}

Future<void> pick(WidgetTester tester, Finder finder, String label) async {
  await tap(tester, finder);
  await tap(tester, find.text(label).last);
}

Future<void> background(WidgetTester tester, bool resumed) async {
  for (final value
      in resumed
          ? [
              AppLifecycleState.hidden,
              AppLifecycleState.inactive,
              AppLifecycleState.resumed,
            ]
          : [
              AppLifecycleState.inactive,
              AppLifecycleState.hidden,
              AppLifecycleState.paused,
            ]) {
    tester.binding.handleAppLifecycleStateChanged(value);
    await tester.pump();
  }
}

void main() {
  testWidgets(
    '110 opening the actual curriculum button performs two reads and never guesses legacy school fields',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      expect(f.calls.map((r) => r.url.path).toSet(), {
        '/api/curriculum/catalog',
        path,
      });
      expect(f.puts, isEmpty);
      expect(stateValue(tester), isNull);
      expect(schoolValue(tester), isNull);
      expect(gradeValue(tester), 7);
      expect(
        find.textContaining('Bisher eingetragen: Nordrhein-Westfalen'),
        findsOneWidget,
      );
      expect(
        find.textContaining('nicht als vollständiger Lehrplan'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Zuordnung speichern'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    '110 grade selection offers exactly 1 through 13 without writes',
    (tester) async {
      final f = Fixture()..stored = profile(configured: true);
      await f.mount(tester);
      final grade = tester.widget<DropdownButtonFormField<int>>(gradeField());
      expect(
        innerDropdown<int>(
          tester,
          gradeField(),
        ).items!.map((item) => item.value),
        List.generate(13, (i) => i + 1),
      );
      grade.onChanged!(13);
      await tester.pumpAndSettle();
      expect(gradeValue(tester), 13);
      tester.widget<DropdownButtonFormField<int>>(gradeField()).onChanged!(1);
      await tester.pumpAndSettle();
      expect(gradeValue(tester), 1);
      tester.widget<DropdownButtonFormField<int>>(gradeField()).onChanged!(0);
      tester.widget<DropdownButtonFormField<int>>(gradeField()).onChanged!(14);
      await tester.pumpAndSettle();
      expect(gradeValue(tester), 1);
      expect(f.puts, isEmpty);
    },
  );

  testWidgets(
    '110 changing the federal state clears its school form and rejects an old form callback',
    (tester) async {
      final f = Fixture()..stored = profile(configured: true);
      await f.mount(tester);
      final old = tester
          .widget<DropdownButtonFormField<String>>(schoolField())
          .onChanged!;
      await pick(tester, stateField(), 'Nordrhein-Westfalen');
      expect(stateValue(tester), 'DE-NW');
      expect(schoolValue(tester), isNull);
      expect(
        innerDropdown<String>(
          tester,
          schoolField(),
        ).items!.map((item) => item.value),
        [null, 'nw_example'],
      );
      old('bw_example');
      await tester.pumpAndSettle();
      expect(
        schoolValue(tester),
        isNull,
        reason:
            'An old school form belongs to a different federal-state snapshot.',
      );
      expect(tester.takeException(), isNull);
      expect(f.puts, isEmpty);
    },
  );

  testWidgets(
    '110 conscious save sends dual CAS actor and idempotency and confirms the saved profile',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await pick(tester, stateField(), 'Baden-Württemberg');
      await pick(tester, schoolField(), 'Künstlicher Schulweg A');
      tester.widget<DropdownButtonFormField<int>>(gradeField()).onChanged!(13);
      await tester.pumpAndSettle();
      expect(f.puts, isEmpty);
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Zuordnung speichern'),
      );
      expect(jsonDecode(f.puts.single.body), {
        'revision': 0,
        'profile_revision': 'a' * 64,
        'state_code': 'DE-BW',
        'school_form_id': 'bw_example',
        'grade': 13,
      });
      expect(
        find.textContaining('Gespeichert. Die Lehrplanauswahl'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Zuordnung speichern'),
            )
            .onPressed,
        isNull,
      );
      expect(f.state.user!['id'], actorId);
    },
  );

  testWidgets(
    '110 a conflict retains the selected draft without automatic resave',
    (tester) async {
      final f = Fixture()
        ..stored = profile(configured: true)
        ..failures = 1;
      await f.mount(tester);
      tester.widget<DropdownButtonFormField<int>>(gradeField()).onChanged!(8);
      await tester.pumpAndSettle();
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Zuordnung speichern'),
      );
      expect(
        find.textContaining('Künstlicher Speicherkonflikt'),
        findsOneWidget,
      );
      expect(gradeValue(tester), 8);
      expect(stateValue(tester), 'DE-BW');
      expect(schoolValue(tester), 'bw_example');
      expect(f.puts, hasLength(1));
      expect(f.calls.where((r) => r.method == 'GET').length, 2);
    },
  );

  testWidgets(
    '110 a conscious unchanged retry keeps its original idempotency key',
    (tester) async {
      final f = Fixture()
        ..stored = profile(configured: true)
        ..failures = 1
        ..failureStatus = 503;
      await f.mount(tester);
      tester.widget<DropdownButtonFormField<int>>(gradeField()).onChanged!(8);
      await tester.pumpAndSettle();
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Zuordnung speichern'),
      );
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Zuordnung speichern'),
      );
      expect(f.puts, hasLength(2));
      expect(
        f.puts.first.headers['Idempotency-Key'],
        f.puts.last.headers['Idempotency-Key'],
      );
    },
  );

  testWidgets(
    '110 closing a dirty form lets the parent consciously retain its draft',
    (tester) async {
      final f = Fixture()..stored = profile(configured: true);
      await f.mount(tester);
      tester.widget<DropdownButtonFormField<int>>(gradeField()).onChanged!(8);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Schließen'));
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      await tap(tester, find.text('Weiterbearbeiten'));
      expect(gradeValue(tester), 8);
      expect(f.puts, isEmpty);
    },
  );

  for (final change in [
    'user',
    'family',
    'token',
    'child',
    'route',
    'lifecycle',
    'state',
  ]) {
    testWidgets(
      '110 pending profile response does not cross a $change boundary',
      (tester) async {
        final pending = Completer<http.Response>();
        final f = Fixture()..pendingGet = pending.future;
        await f.mount(
          tester,
          settle: false,
          dynamicChild: change == 'child',
          dynamicState: change == 'state',
        );
        if (change == 'user') {
          f.state.user = {...f.state.user!, 'id': otherChildId};
          f.state.notifyListeners();
        }
        if (change == 'family') {
          f.state.familyId = 'family-b';
          f.state.notifyListeners();
        }
        if (change == 'token') {
          f.state.api.token = 'replacement';
          f.state.notifyListeners();
        }
        if (change == 'child') {
          f.child.value = otherChildId;
        }
        if (change == 'state') {
          final other =
              AppState(
                  api: Api(
                    base: 'https://example.invalid/api',
                    client: MockClient(
                      (_) async => throw StateError(
                        'A replacement state must not receive old profile requests.',
                      ),
                    ),
                  ),
                )
                ..user = f.state.user
                ..familyId = f.state.familyId
                ..api.token = f.state.api.token;
          addTearDown(() {
            other.inbox.dispose();
            other.dispose();
          });
          f.replacement.value = other;
        }
        if (change == 'route') {
          showDialog<void>(
            context: f.navigator.currentContext!,
            builder: (_) => const AlertDialog(title: Text('Fremder Dialog')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
        }
        if (change == 'lifecycle') {
          await background(tester, false);
        }
        await tester.pump();
        pending.complete(response(profile(configured: true)));
        await tester.pumpAndSettle();
        expect(
          stateField(),
          findsNothing,
          reason:
              'An obsolete response must not populate the old profile form.',
        );
        expect(f.puts, isEmpty);
        if (change == 'lifecycle') {
          await background(tester, true);
          await tester.pumpAndSettle();
        }
      },
    );
  }

  for (final change in [
    'user',
    'family',
    'token',
    'child',
    'route',
    'lifecycle',
    'state',
  ]) {
    testWidgets('110 saved form callbacks are inert after a $change boundary', (
      tester,
    ) async {
      final f = Fixture()..stored = profile(configured: true);
      await f.mount(
        tester,
        dynamicChild: change == 'child',
        dynamicState: change == 'state',
      );
      tester.widget<DropdownButtonFormField<int>>(gradeField()).onChanged!(8);
      await tester.pumpAndSettle();
      final old = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Zuordnung speichern'),
          )
          .onPressed!;
      final oldSchool = tester
          .widget<DropdownButtonFormField<String>>(schoolField())
          .onChanged!;
      if (change == 'user') {
        f.state.user = {...f.state.user!, 'id': otherChildId};
        f.state.notifyListeners();
      }
      if (change == 'family') {
        f.state.familyId = 'family-b';
        f.state.notifyListeners();
      }
      if (change == 'token') {
        f.state.api.token = 'replacement';
        f.state.notifyListeners();
      }
      if (change == 'child') {
        f.child.value = otherChildId;
      }
      if (change == 'state') {
        final other =
            AppState(
                api: Api(
                  base: 'https://example.invalid/api',
                  client: MockClient(
                    (_) async => throw StateError(
                      'A replacement state must not receive old profile requests.',
                    ),
                  ),
                ),
              )
              ..user = f.state.user
              ..familyId = f.state.familyId
              ..api.token = f.state.api.token;
        addTearDown(() {
          other.inbox.dispose();
          other.dispose();
        });
        f.replacement.value = other;
      }
      if (change == 'route') {
        await f.cover(tester);
      }
      if (change == 'lifecycle') {
        await background(tester, false);
      }
      await tester.pumpAndSettle();
      old();
      oldSchool('bw_example');
      await tester.pumpAndSettle();
      expect(f.puts, isEmpty);
      if (change == 'route') {
        expect(find.text('Fremder Dialog'), findsOneWidget);
      }
      if (change == 'lifecycle') {
        await background(tester, true);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('aktuellen Stand neu laden'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Zuordnung speichern'),
              )
              .onPressed,
          isNull,
        );
      }
    });
  }

  testWidgets(
    '110 a stale binding is visible even when both legacy labels are empty',
    (tester) async {
      final f = Fixture()
        ..stored = {
          ...profile(),
          'needs_review': true,
          'state_binding_stale': true,
          'legacy_region': '',
          'legacy_school_type': '',
        };
      await f.mount(tester);
      expect(
        find.textContaining('außerhalb des Lehrplanprofils geändert'),
        findsOneWidget,
      );
      expect(stateValue(tester), isNull);
      expect(f.puts, isEmpty);
    },
  );

  testWidgets(
    '110 only an actual saved profile signals a refresh after its authorized close',
    (tester) async {
      final f = Fixture()..stored = profile(configured: true);
      await f.mount(tester);
      expect(f.saves, 0);
      tester.widget<DropdownButtonFormField<int>>(gradeField()).onChanged!(8);
      await tester.pumpAndSettle();
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Zuordnung speichern'),
      );
      expect(
        f.saves,
        0,
        reason:
            'The parent view waits until the owned dialog has fully returned.',
      );
      await tap(tester, find.text('Schließen'));
      expect(f.saves, 1);
      expect(f.puts, hasLength(1));
    },
  );

  testWidgets(
    '110 reading and closing a profile never signals a saved change',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await tap(tester, find.text('Schließen'));
      expect(f.saves, 0);
      expect(f.puts, isEmpty);
    },
  );

  testWidgets(
    '110 a save response behind a foreign dialog does not apply or signal success',
    (tester) async {
      final delayed = Completer<http.Response>();
      final f = Fixture()
        ..stored = profile(configured: true)
        ..pendingPut = delayed.future;
      await f.mount(tester);
      tester.widget<DropdownButtonFormField<int>>(gradeField()).onChanged!(8);
      await tester.pumpAndSettle();
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Zuordnung speichern'),
      );
      await f.cover(tester);
      delayed.complete(
        response({
          ...profile(configured: true),
          'grade': 8,
          'revision': 1,
          'profile_revision': 'b' * 64,
        }),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Gespeichert. Die Lehrplanauswahl'),
        findsNothing,
      );
      expect(find.text('Fremder Dialog'), findsOneWidget);
      expect(f.saves, 0);
      await tap(tester, find.text('Zurück zum Profil'));
      expect(find.textContaining('Der Dialog war verdeckt'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Zuordnung speichern'),
            )
            .onPressed,
        isNull,
      );
      expect(f.puts, hasLength(1));
    },
  );

  testWidgets(
    '110 an in-flight read waits for its own discard confirmation without restarting requests',
    (tester) async {
      final f = Fixture()..stored = profile(configured: true);
      await f.mount(tester);
      tester.widget<DropdownButtonFormField<int>>(gradeField()).onChanged!(8);
      await tester.pumpAndSettle();
      final delayed = Completer<http.Response>();
      f.pendingGet = delayed.future;
      await tap(tester, find.text('Neu laden'));
      await tester.tap(
        find.widgetWithText(FilledButton, 'Änderungen verwerfen'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.widgetWithText(TextButton, 'Schließen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      delayed.complete(response({...profile(configured: true), 'grade': 9}));
      await tester.pump();
      expect(
        field('curriculum-grade:', skipOffstage: false),
        findsNothing,
        reason: 'The pending read must remain loading underneath its owned confirmation.',
      );
      expect(
        find.byType(LinearProgressIndicator, skipOffstage: false),
        findsOneWidget,
      );
      await tester.tap(find.text('Weiterbearbeiten'));
      await tester.pumpAndSettle();
      expect(gradeValue(tester), 9);
      expect(find.textContaining('Der Dialog war verdeckt'), findsNothing);
      expect(f.calls.where((r) => r.method == 'GET').length, 4);
      expect(f.puts, isEmpty);
    },
  );

  testWidgets(
    '110 actual Settings children LoadView refreshes the displayed class after a saved close',
    (tester) async {
      final f = settings.Fixture();
      f.state.user = {...f.state.user!, 'id': actorId};
      f.children.first['id'] = childId;
      var stored = profile(configured: true);
      f.respond = (request) async {
        if (request.url.path == '/api/curriculum/catalog') {
          return response(catalog());
        }
        if (request.url.path == '/api/children/$childId/sessions') {
          return response([]);
        }
        if (request.url.path != path) {
          return null;
        }
        expectSync(request.headers['X-Schulpilot-Account'], actorId);
        if (request.method == 'PUT') {
          final body = Json.from(jsonDecode(request.body));
          stored = {
            ...stored,
            ...body,
            'revision': 1,
            'profile_revision': 'b' * 64,
          };
          f.children.first['grade'] = body['grade'];
        }
        return response(stored);
      };
      await f.mount(tester, section: 'family');
      final reads = f.requests
          .where((r) => r.url.path == '/api/families/family-a')
          .length;
      await tap(
        tester,
        find.byKey(const ValueKey('curriculum-profile:$childId')),
      );
      tester.widget<DropdownButtonFormField<int>>(gradeField()).onChanged!(8);
      await tester.pumpAndSettle();
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Zuordnung speichern'),
      );
      expect(
        f.requests.where((r) => r.url.path == '/api/families/family-a').length,
        reads,
      );
      await tap(tester, find.text('Schließen'));
      expect(
        f.requests.where((r) => r.url.path == '/api/families/family-a').length,
        reads + 1,
      );
      expect(find.text('Klasse 8'), findsOneWidget);
      expect(
        f.requests.where((r) => r.method == 'PUT' && r.url.path == path),
        hasLength(1),
      );
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '110 curriculum selection remains legible and explicitly saveable at $width/$scale',
        (tester) async {
          final f = Fixture();
          await f.mount(tester, width: width, scale: scale);
          await pick(tester, stateField(), 'Nordrhein-Westfalen');
          await pick(tester, schoolField(), 'Künstlicher Schulweg B');
          await tap(
            tester,
            find.widgetWithText(FilledButton, 'Zuordnung speichern'),
          );
          expect(f.puts, hasLength(1));
          expect(
            find.textContaining('Gespeichert. Die Lehrplanauswahl'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
