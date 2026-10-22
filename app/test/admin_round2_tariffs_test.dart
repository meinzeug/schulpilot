import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/ui.dart';

http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json family() => {
  'id': 'synthetic-family',
  'plan': 'Künstlicher Tarif',
  'child_limit': 2,
  'call_limit': 100,
  'budget_micros': 2000000,
  'synthetic': true,
};
AppState account(Future<http.Response> Function(http.Request) handler) =>
    AppState(
      api: Api(
        base: 'https://example.invalid/api',
        client: MockClient(handler),
      ),
    )..user = {'id': 'synthetic-admin', 'role': 'admin'};
Finder field(String label) => find.widgetWithText(TextFormField, label);
TextField editor(WidgetTester t, String label) => t.widget<TextField>(
  find.descendant(of: field(label), matching: find.byType(TextField)),
);
Future<void> tap(WidgetTester t, Finder target) async {
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pumpAndSettle();
}

Future<void> open(WidgetTester t, AppState s) async {
  await t.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => entitlementDialog(context, s, family()),
            child: const Text('Tarif öffnen'),
          ),
        ),
      ),
    ),
  );
  await tap(t, find.text('Tarif öffnen'));
}

void main() {
  testWidgets(
    'AA001 family card body opens its own tariff without a mutation',
    (t) async {
      final calls = <http.Request>[];
      Json? edited;
      final s = account((r) async {
        calls.add(r);
        return response({
          'items': [family()],
          'pagination': {'page': 1, 'pages': 1, 'total': 1},
        });
      });
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminFamilyList(
                s,
                revision: 1,
                onEdit: (value) async => edited = value,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(ActionPanel), findsOneWidget);
      await tap(t, find.text('synthetic-family'));
      expect(edited?['id'], 'synthetic-family');
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    'AA002 tariff editor identifies the exact family and saved plan',
    (t) async {
      final s = account((_) async => response({}));
      await open(t, s);
      expect(find.text('Familie: synthetic-family'), findsOneWidget);
      expect(find.text('Bisheriger Tarif: Künstlicher Tarif'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA003 blank and overlong tariff names stay local with the draft',
    (t) async {
      final calls = <http.Request>[];
      final s = account((r) async {
        calls.add(r);
        return response({});
      });
      await open(t, s);
      for (final invalid in ['   ', 'x' * 41]) {
        await t.enterText(field('Tarifname'), invalid);
        await tap(t, find.text('Speichern'));
        expect(
          find.text('Einen Tarifnamen mit 1 bis 40 Zeichen eintragen.'),
          findsOneWidget,
        );
        expect(
          t.widget<TextFormField>(field('Tarifname')).controller!.text,
          invalid,
        );
        expect(calls, isEmpty);
      }
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA004 numeric tariff fields enforce the actual backend ranges before PUT',
    (t) async {
      final calls = <http.Request>[];
      final s = account((r) async {
        calls.add(r);
        return response({});
      });
      await open(t, s);
      for (final item in [
        ('Kinderanzahl', '21', '2'),
        ('KI-Aufrufe / Monat', '-1', '100'),
        ('Kostenlimit / Monat (Mikro-USD)', '100000001', '2000000'),
      ]) {
        await t.enterText(field(item.$1), item.$2);
        await tap(t, find.text('Speichern'));
        expect(calls, isEmpty);
        expect(find.textContaining('Ganze Zahl von'), findsOneWidget);
        await t.enterText(field(item.$1), item.$3);
      }
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('AA005 tariff Next follows field order and Done never submits', (
    t,
  ) async {
    final calls = <http.Request>[];
    final s = account((r) async {
      calls.add(r);
      return response({});
    });
    await open(t, s);
    await t.showKeyboard(field('Tarifname'));
    await t.testTextInput.receiveAction(TextInputAction.next);
    await t.pump();
    expect(editor(t, 'Kinderanzahl').focusNode!.hasFocus, isTrue);
    await t.showKeyboard(field('Kostenlimit / Monat (Mikro-USD)'));
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(calls, isEmpty);
    expect(
      editor(t, 'Kostenlimit / Monat (Mikro-USD)').focusNode!.hasFocus,
      isFalse,
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'AA006 AA007 pending tariff commit freezes its snapshot and keeps its result route',
    (t) async {
      final pending = Completer<http.Response>();
      final calls = <http.Request>[];
      final s = account((r) {
        calls.add(r);
        return pending.future;
      });
      await open(t, s);
      await t.enterText(field('Tarifname'), 'Neuer künstlicher Tarif');
      await t.ensureVisible(find.text('Speichern'));
      await t.tap(find.text('Speichern'));
      await t.pump();
      expect(calls, hasLength(1));
      expect(jsonDecode(calls.single.body)['plan'], 'Neuer künstlicher Tarif');
      expect(
        t
            .widgetList<TextFormField>(find.byType(TextFormField))
            .every((w) => w.enabled == false),
        isTrue,
      );
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.text('Tarifberechtigungen'), findsOneWidget);
      expect(find.text('Tarif wird gespeichert …'), findsOneWidget);
      pending.complete(response({}));
      await t.pumpAndSettle();
      expect(find.text('Tarifberechtigungen'), findsNothing);
    },
  );

  testWidgets(
    'AA008 a rejected tariff save keeps a persistent error and the exact draft',
    (t) async {
      final s = account(
        (_) async => response({'detail': 'Künstlicher Tarifkonflikt'}, 409),
      );
      await open(t, s);
      await t.enterText(field('Tarifname'), 'Korrigierbarer Entwurf');
      await tap(t, find.text('Speichern'));
      expect(find.text('Künstlicher Tarifkonflikt'), findsOneWidget);
      expect(
        t.widget<TextFormField>(field('Tarifname')).controller!.text,
        'Korrigierbarer Entwurf',
      );
      expect(find.text('Tarifberechtigungen'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA009 a replacement admin session removes only its old private tariff route',
    (t) async {
      final calls = <http.Request>[];
      final s = account((r) async {
        calls.add(r);
        return response({});
      });
      await open(t, s);
      final stale = t
          .widget<ActionButton>(find.widgetWithText(ActionButton, 'Speichern'))
          .onPressed;
      final context = t.element(find.text('Tarifberechtigungen'));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(title: Text('Neuer Dialog')),
        ),
      );
      await t.pumpAndSettle();
      s.user = {...s.user!};
      s.refreshState();
      await t.pumpAndSettle();
      await stale();
      await t.pumpAndSettle();
      expect(find.text('Neuer Dialog'), findsOneWidget);
      expect(find.text('Tarifberechtigungen'), findsNothing);
      expect(calls, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA010 tariff micro-USD has an exact live readable amount without changing transport',
    (t) async {
      final calls = <http.Request>[];
      final s = account((r) async {
        calls.add(r);
        return response({});
      });
      await open(t, s);
      await t.enterText(field('Kostenlimit / Monat (Mikro-USD)'), '7');
      await t.pump();
      expect(
        find.text('Monatliches Kostenlimit: 0.000007 USD'),
        findsOneWidget,
      );
      await tap(t, find.text('Speichern'));
      expect(jsonDecode(calls.single.body)['budget_micros'], 7);
    },
  );

  testWidgets(
    'AA011 repeated family edit callbacks open one editor while the first is pending',
    (t) async {
      final pending = Completer<void>();
      var edits = 0;
      final s = account(
        (_) async => response({
          'items': [family()],
          'pagination': {'page': 1, 'pages': 1, 'total': 1},
        }),
      );
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminFamilyList(
                s,
                revision: 1,
                onEdit: (_) {
                  edits++;
                  return pending.future;
                },
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final old = t.widget<ActionPanel>(find.byType(ActionPanel)).onPressed!;
      old();
      old();
      await t.pump();
      expect(edits, 1);
      pending.complete();
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
    },
  );
}
