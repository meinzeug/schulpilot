import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/admin_material_review.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/installation_screen.dart';
import 'package:schulpilot/ui.dart';

import 'codex_provider_form_test.dart' as provider;

const endpoint = '/api/admin/installation/material-review';
http.Response reply(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class Fixture {
  final calls = <http.Request>[];
  Json value = {'mode': 'manual', 'revision': 9};
  Future<http.Response> Function(http.Request)? response;
  late final state = AppState(
    api: Api(
      base: 'https://synthetic.invalid/api',
      client: MockClient((request) async {
        calls.add(request);
        if (request.url.path == '/api/admin/installation') {
          return reply({
            'site': <String, dynamic>{'smtp_mode': 'tls'},
            'provider': provider.config(provider: 'openai'),
            'checks': <String, dynamic>{},
          });
        }
        if (response != null) return await response!(request);
        if (request.url.path == endpoint) {
          if (request.method == 'PUT') {
            final body = Json.from(jsonDecode(request.body));
            expect(body.keys.toSet(), {'mode', 'expected_revision'});
            expect(body['expected_revision'], value['revision']);
            value = {
              'mode': body['mode'],
              'revision': (value['revision'] as int) + 1,
            };
          }
          return reply(value);
        }
        throw StateError(
          'Unexpected synthetic request: ${request.method} ${request.url.path}',
        );
      }),
    )..token = 'synthetic-admin-session',
  )..user = {'id': 'synthetic-admin', 'role': 'admin'};
  List<http.Request> get writes =>
      calls.where((r) => r.method != 'GET').toList();
  late GoRouter router;
  Future<void> open(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    bool installation = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(state.dispose);
    router = GoRouter(
      initialLocation: '/admin/settings',
      routes: [
        GoRoute(
          path: '/admin/settings',
          builder: (_, _) => installation
              ? InstallationScreen(state, initial: false, initialSection: 'ai')
              : Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: AdminMaterialReviewSettings(state),
                  ),
                ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(),
        routerConfig: router,
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: widget!,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async =>
      tester.pumpWidget(const SizedBox.shrink());
}

Future<void> tap(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> expand(WidgetTester tester) =>
    tap(tester, find.text('Prüfung neuer Heftseiten'));
Finder save() => find.byWidgetPredicate(
  (w) => w is ActionButton && w.label == 'Prüfmodus speichern',
);
String? selected(WidgetTester tester) => tester
    .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
    .groupValue;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
  });
  for (final view in [
    (320.0, 2.0),
    (390.0, 1.0),
    (390.0, 2.0),
    (1280.0, 1.0),
  ]) {
    testWidgets(
      '141 review policy reads lazily and saves one explicit CAS choice at $view',
      (tester) async {
        final f = Fixture();
        await f.open(tester, width: view.$1, scale: view.$2);
        expect(f.calls, isEmpty);
        await expand(tester);
        expect(f.calls.map((r) => r.method), ['GET']);
        expect(selected(tester), 'manual');
        expect(tester.widget<ActionButton>(save()).enabled, false);
        await tap(tester, find.text('Automatisch prüfen'));
        expect(selected(tester), 'automatic');
        expect(f.writes, isEmpty);
        expect(
          find.textContaining('Unleserliche Stellen bleiben markiert'),
          findsOneWidget,
        );
        for (final title in ['Manuell prüfen', 'Automatisch prüfen']) {
          final tile = find.widgetWithText(RadioListTile<String>, title);
          expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
          expect(tester.getRect(tile).right, lessThanOrEqualTo(view.$1));
        }
        await tap(tester, save());
        expect(f.writes, hasLength(1));
        expect(f.writes.single.method, 'PUT');
        expect(f.writes.single.url.path, endpoint);
        expect(jsonDecode(f.writes.single.body), {
          'mode': 'automatic',
          'expected_revision': 9,
        });
        expect(find.text('Prüfmodus gespeichert.'), findsOneWidget);
        expect(tester.widget<ActionButton>(save()).enabled, false);
        expect(
          f.calls.any(
            (r) => r.method == 'POST' || r.url.path.contains('/materials/'),
          ),
          false,
        );
        expect(tester.takeException(), isNull);
        await f.close(tester);
      },
    );
  }
  testWidgets(
    '141 CAS conflict keeps the draft and an explicit GET rebinds its revision without saving',
    (tester) async {
      final f = Fixture();
      await f.open(tester);
      await expand(tester);
      await tap(tester, find.text('Automatisch prüfen'));
      f.response = (request) async => request.method == 'PUT'
          ? reply({'detail': 'Künstlicher Revisionskonflikt'}, 409)
          : reply({'mode': 'manual', 'revision': 12});
      await tap(tester, save());
      expect(selected(tester), 'automatic');
      expect(
        find.textContaining('Dein Entwurf bleibt erhalten'),
        findsOneWidget,
      );
      expect(tester.widget<ActionButton>(save()).enabled, false);
      expect(f.writes, hasLength(1));
      await tap(tester, find.text('Aktuellen Stand abgleichen'));
      expect(selected(tester), 'automatic');
      expect(find.text('Gespeichert: Manuell prüfen'), findsOneWidget);
      expect(f.writes, hasLength(1));
      f.response = (request) async {
        expect(jsonDecode(request.body), {
          'mode': 'automatic',
          'expected_revision': 12,
        });
        return reply({'mode': 'automatic', 'revision': 13});
      };
      await tap(tester, save());
      expect(f.writes, hasLength(2));
      expect(find.text('Prüfmodus gespeichert.'), findsOneWidget);
      await f.close(tester);
    },
  );
  testWidgets('141 failed or malformed GET never invents a manual default', (
    tester,
  ) async {
    final f = Fixture();
    f.response = (_) async => reply({'mode': 'unknown', 'revision': 9});
    await f.open(tester);
    await expand(tester);
    expect(find.byType(RadioListTile<String>), findsNothing);
    expect(tester.widget<ActionButton>(save()).enabled, false);
    expect(f.writes, isEmpty);
    f.response = (_) async => reply({'mode': 'automatic', 'revision': 11});
    await tap(tester, find.text('Gespeicherten Stand laden'));
    expect(selected(tester), 'automatic');
    expect(f.writes, isEmpty);
    await f.close(tester);
  });
  for (final phase in ['GET', 'PUT']) {
    for (final identity in ['account', 'session']) {
      testWidgets('141 late $phase cannot update a replacement $identity', (
        tester,
      ) async {
        final f = Fixture();
        final pending = Completer<http.Response>();
        await f.open(tester);
        if (phase == 'GET') {
          f.response = (_) => pending.future;
          final target = find.text('Prüfung neuer Heftseiten');
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pump();
        } else {
          await expand(tester);
          await tap(tester, find.text('Automatisch prüfen'));
          f.response = (_) => pending.future;
          await tester.ensureVisible(save());
          await tester.tap(save());
          await tester.pump();
        }
        if (identity == 'account') {
          f.state.user = Json.from(f.state.user!);
        } else {
          f.state.api.token = 'replacement-admin-session';
        }
        f.state.refreshState();
        await tester.pumpAndSettle();
        pending.complete(reply({'mode': 'automatic', 'revision': 10}));
        await tester.pumpAndSettle();
        expect(find.text('Prüfung neuer Heftseiten'), findsNothing);
        expect(find.text('Prüfmodus gespeichert.'), findsNothing);
        expect(f.writes, hasLength(phase == 'PUT' ? 1 : 0));
        expect(tester.takeException(), isNull);
        await f.close(tester);
      });
    }
  }
  testWidgets('141 non-admin has no policy control or requests', (
    tester,
  ) async {
    final f = Fixture();
    f.state.user = {'id': 'synthetic-parent', 'role': 'parent'};
    await f.open(tester);
    expect(find.text('Prüfung neuer Heftseiten'), findsNothing);
    expect(f.calls, isEmpty);
    await f.close(tester);
  });
  testWidgets(
    '141 installed AI section keeps policy and provider drafts apart across tab changes',
    (tester) async {
      final f = Fixture();
      await f.open(tester, installation: true);
      expect(f.calls.where((r) => r.url.path == endpoint), isEmpty);
      await expand(tester);
      await tap(tester, find.text('Automatisch prüfen'));
      final model = find.widgetWithText(
        TextField,
        'Modell-ID für Lerneinheiten (laut Anbieter)',
      );
      await tester.ensureVisible(model);
      await tester.enterText(model, 'synthetic-unsaved-provider-model');
      await tap(tester, find.widgetWithText(ChoiceChip, 'E-Mail'));
      await tap(tester, find.widgetWithText(ChoiceChip, 'KI'));
      expect(selected(tester), 'automatic');
      expect(
        tester.widget<TextField>(model).controller!.text,
        'synthetic-unsaved-provider-model',
      );
      expect(f.writes, isEmpty);
      await tap(tester, save());
      expect(f.writes.map((r) => r.url.path), [endpoint]);
      expect(
        tester.widget<TextField>(model).controller!.text,
        'synthetic-unsaved-provider-model',
      );
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );
}
