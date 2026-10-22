import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
// Pinned plugin host codec, solely to inspect a synthetic save request without writing a file.
// ignore: implementation_imports
import 'package:file_saver/src/messages.g.dart'
    show FileSaverHostApi, SaveRequest;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/parent_assignment_dialog.dart';
import 'package:schulpilot/parent_export_dialog.dart';
import 'package:schulpilot/parent_operator_audit.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/parent_overview.dart';

import 'parent_cards_ux88_test.dart' as cards;

import 'admin_round2_tariffs_test.dart' as tariffs;
import 'parent_workflows_ux90_test.dart' as workflows;
import 'parent_saved_tools_ux90_test.dart' as saved;
import 'parent_messages_ux88_test.dart' show tap;
import 'parent_insights_test.dart' show response;

Finder textField(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> scroll(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      160,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'PK008 copied completed assignment is a separate new goal without old dates or revision',
    (tester) async {
      final f = saved.Fixture();
      f.state.user!['families'] = [
        {'id': 'family', 'permission': 'owner'},
      ];
      final original = {
        'id': 'old-goal',
        'subject': 'Mathematik',
        'topic': 'Brüche',
        'kind': 'parent',
        'note': 'Künstliche Notiz',
        'mandatory': true,
        'done': true,
        'due': '2026-10-20',
        'scheduled_for': '2026-10-19',
        'revision': 8,
      };
      await f.mount(
        tester,
        (c) => TextButton(
          onPressed: () => showParentAssignmentDialog(
            c,
            f.state,
            {
              'id': 'child',
              'display_name': 'Künstliches Kind',
              'subjects': ['Mathematik'],
              'planning_today': '2026-10-22',
            },
            [],
            parseDate: DateTime.tryParse,
            copyFrom: original,
          ),
          child: const Text('Kopie öffnen'),
        ),
      );
      await tap(tester, find.text('Kopie öffnen'));
      expect(
        tester
            .widget<TextField>(textField('Termin (optional)'))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(textField('Frühester Lernbeginn (optional)'))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        find.textContaining('Neue Kopie: Antworten und Runden'),
        findsOneWidget,
      );
      await tap(tester, find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(f.requests.single.method, 'POST');
      expect(f.requests.single.url.path, '/api/children/child/assignments');
      final body = jsonDecode(f.requests.single.body) as Json;
      expect(body['topic'], 'Brüche');
      expect(body.containsKey('revision'), isFalse);
      expect(body['due'], isNull);
      expect(body['scheduled_for'], isNull);
      expect(original['done'], isTrue);
      expect(original['revision'], 8);
    },
  );
  testWidgets(
    'PK010 assignment calendar anchors empty deadline to saved child planning day',
    (tester) async {
      final f = saved.Fixture();
      f.state.user!['families'] = [
        {'id': 'family', 'permission': 'owner'},
      ];
      await f.mount(
        tester,
        (c) => TextButton(
          onPressed: () => showParentAssignmentDialog(
            c,
            f.state,
            {
              'id': 'child',
              'display_name': 'Künstliches Kind',
              'subjects': ['Mathematik'],
              'planning_today': '2025-05-06',
            },
            [],
            parseDate: DateTime.tryParse,
          ),
          child: const Text('Öffnen'),
        ),
      );
      await tap(tester, find.text('Öffnen'));
      final icon = find.descendant(
        of: textField('Termin (optional)'),
        matching: find.byType(IconButton),
      );
      await tap(tester, icon);
      expect(
        tester
            .widget<DatePickerDialog>(find.byType(DatePickerDialog))
            .initialDate,
        DateTime(2025, 5, 6),
      );
      expect(f.requests, isEmpty);
      f.replaceAccount();
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
    },
  );
  for (final item in [
    (
      'PK055',
      'Gespeicherte Notenherkunft',
      'Mit bestätigtem PDF-Beleg',
      'source',
      'pdf',
    ),
    (
      'PK056',
      'Verknüpftes Lernziel',
      'Mit zugeordnetem Lernziel',
      'goal',
      'linked',
    ),
  ]) {
    testWidgets(
      '${item.$1} actual source and linked goal filters are read-only',
      (tester) async {
        final f = workflows.collection();
        await f.mount(tester, '/grades/child');
        await scroll(tester, find.text(item.$2));
        await workflows.choose(tester, item.$2, item.$3);
        expect(f.requests.last.url.queryParameters[item.$4], item.$5);
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      },
    );
  }
  testWidgets(
    'PK057 excluding photos is reviewed before exact child export and error retains that scope',
    (tester) async {
      final f = saved.Fixture();
      f.respond = (r) async =>
          response({'detail': 'Synthetischer Exportfehler'}, 503);
      await f.mount(
        tester,
        (c) => TextButton(
          onPressed: () => showParentChildExport(c, f.state, {
            'id': 'child',
            'display_name': 'Künstliches Kind',
          }),
          child: const Text('Öffnen'),
        ),
      );
      await tap(tester, find.text('Öffnen'));
      expect(f.requests, isEmpty);
      await tap(tester, find.text('Persönliche Bilddateien mitnehmen'));
      await tap(tester, find.text('Kinderexport ausdrücklich speichern'));
      expect(f.requests.single.url.path, '/api/children/child/export');
      expect(f.requests.single.url.queryParameters['include_photos'], 'false');
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(find.text('Synthetischer Exportfehler'), findsOneWidget);
    },
  );
  testWidgets(
    'PK058 tariff conflict keeps draft and compares actual saved values before explicit adoption',
    (tester) async {
      final f = saved.Fixture();
      f.state.user = {'id': 'operator', 'role': 'admin'};
      final initial = {...tariffs.family(), 'entitlement_revision': 'a' * 64};
      final fresh = {
        ...initial,
        'child_limit': 4,
        'entitlement_revision': 'b' * 64,
      };
      var puts = 0;
      f.respond = (r) async => r.method == 'GET'
          ? response({
              'items': [fresh],
            })
          : ++puts == 1
          ? response({'detail': 'Zwischenänderung'}, 409)
          : response({});
      await f.mount(
        tester,
        (c) => TextButton(
          onPressed: () => entitlementDialog(c, f.state, initial),
          child: const Text('Öffnen'),
        ),
      );
      await tap(tester, find.text('Öffnen'));
      await tester.enterText(tariffs.field('Kinderanzahl'), '3');
      await tap(tester, find.text('Speichern'));
      expect(f.requests.first.headers['If-Match'], 'a' * 64);
      expect(tariffs.editor(tester, 'Kinderanzahl').controller!.text, '3');
      await tap(tester, find.text('Gespeicherten Tarif vergleichen'));
      expect(puts, 1);
      expect(f.requests.last.method, 'GET');
      expect(
        find.text('Kinderanzahl · gespeichert: 4 · dein Entwurf: 3'),
        findsOneWidget,
      );
      await tap(
        tester,
        find.text('Gespeicherten Tarif in den Entwurf übernehmen'),
      );
      expect(puts, 1);
      expect(tariffs.editor(tester, 'Kinderanzahl').controller!.text, '4');
      await tap(tester, find.text('Speichern'));
      expect(f.requests.last.headers['If-Match'], 'b' * 64);
      expect(puts, 2);
    },
  );
  testWidgets(
    'PK058 pending tariff comparison never crosses a new authenticated account map',
    (tester) async {
      final f = saved.Fixture();
      f.state.user = {'id': 'operator', 'role': 'admin'};
      final pending = Completer<http.Response>();
      f.respond = (r) async => r.method == 'GET'
          ? pending.future
          : response({'detail': 'Zwischenänderung'}, 409);
      await f.mount(
        tester,
        (c) => TextButton(
          onPressed: () => entitlementDialog(c, f.state, {
            ...tariffs.family(),
            'entitlement_revision': 'a' * 64,
          }),
          child: const Text('Öffnen'),
        ),
      );
      await tap(tester, find.text('Öffnen'));
      await tap(tester, find.text('Speichern'));
      await tester.ensureVisible(find.text('Gespeicherten Tarif vergleichen'));
      await tester.tap(find.text('Gespeicherten Tarif vergleichen'));
      await tester.pump();
      f.replaceAccount();
      await tester.pump();
      pending.complete(
        response({
          'items': [
            {
              ...tariffs.family(),
              'child_limit': 8,
              'entitlement_revision': 'b' * 64,
            },
          ],
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(f.requests.where((r) => r.method == 'PUT'), hasLength(1));
    },
  );
  testWidgets(
    'PK054 loaded operational CSV is a local neutral subset and escapes spreadsheet formulas',
    (tester) async {
      final f = saved.Fixture();
      f.state.user = {'id': 'operator', 'role': 'admin'};
      final data = saved.auditData()..['total'] = 400;
      data['items'][0]['target'] = ' =SYNTHETIC()';
      f.respond = (r) async => response(data);
      SaveRequest? output;
      final channel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.file_saver.FileSaverHostApi.saveAs',
        FileSaverHostApi.pigeonChannelCodec,
      );
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(channel, (message) async {
            output = (message as List).single as SaveRequest;
            return ['synthetic-memory-only'];
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(channel, null),
      );
      await f.mount(
        tester,
        (c) => TextButton(
          onPressed: () => showAdminAuditExplorer(c, f.state),
          child: const Text('Öffnen'),
        ),
      );
      await tap(tester, find.text('Öffnen'));
      await scroll(
        tester,
        find.text('1 von 400 passenden Ereignissen geladen'),
      );
      expect(
        find.text('1 von 400 passenden Ereignissen geladen'),
        findsOneWidget,
      );
      await tap(tester, find.text('Nur geladene Auswahl als CSV'));
      expect(output, isNotNull);
      final csv = utf8.decode(output!.bytes!);
      expect(csv.split('\r\n').where((s) => s.isNotEmpty), hasLength(2));
      expect(csv, contains("' =SYNTHETIC()"));
      expect(f.requests, hasLength(1));
      expect(f.requests.single.method, 'GET');
    },
    skip: kIsWeb,
  );
  testWidgets(
    'PK059 homework photo date retains child timezone at UTC day boundary',
    (tester) async {
      final f = workflows.collection();
      f.homework['timezone'] = 'Europe/Berlin';
      f.homework['photos'][0].addAll({
        'created': 1792872900,
        'created_local': '2026-10-25T00:15:00+02:00',
      });
      await f.mount(tester, '/parent-homework/child');
      await scroll(tester, find.text('25.10.2026 · 00:15 · Europe/Berlin'));
      expect(find.text('25.10.2026 · 00:15 · Europe/Berlin'), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );

  for (final available in [false, true]) {
    testWidgets(
      'PK061 absent evidence is unknown while actual zero remains an observation $available',
      (tester) async {
        final f = saved.Fixture();
        final value = cards.summary();
        if (!available) {
          value.remove('practice_summary');
        }
        if (available) {
          value['practice_summary'] = {
            'practiced_tasks': 0,
            'independent_tasks': 0,
            'assisted_tasks': 0,
            'needs_practice_tasks': 0,
            'uncertain_tasks': 0,
          };
        }
        await f.mount(
          tester,
          (_) => SingleChildScrollView(child: ParentOverview(data: value)),
        );
        expect(
          find.text('0 beantwortete Aufgaben'),
          available ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Übungsstand nicht vollständig gemeldet'),
          available ? findsNothing : findsOneWidget,
        );
        expect(f.requests, isEmpty);
      },
    );
  }
}
