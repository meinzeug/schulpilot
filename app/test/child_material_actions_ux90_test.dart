import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'material_actions_test.dart' as f;
import 'child_local_tools_ux88_test.dart' as local;

void main() {
  testWidgets(
    'CK027 rereading has an explicit AI action and cancel never starts it',
    (tester) async {
      final harness = await f.mount(tester, (r) async => f.reply({}));
      await local.tap(tester, find.text('Aktion öffnen'));
      expect(find.text('Mit KI neu einlesen'), findsOneWidget);
      expect(find.text('Bestätigen'), findsNothing);
      await local.tap(tester, find.text('Abbrechen'));
      expect(harness.requests, isEmpty);
    },
  );
  testWidgets(
    'CK028 status refresh has a real pending GET state and ignores duplicate taps',
    (tester) async {
      final pending = Completer<http.Response>();
      var jobReads = 0;
      await f.mount(tester, (r) async {
        if (r.url.path.contains('/materials/')) {
          return f.reply({
            'id': 'new-photo',
            'child_id': 'child',
            'topic': 'Geometrie',
          });
        }
        jobReads++;
        return jobReads == 1
            ? f.reply({'detail': 'Vorübergehend offline'}, status: 503)
            : pending.future;
      }, processing: true);
      final callback = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Status neu laden'),
          )
          .onPressed!;
      callback();
      await tester.pump();
      callback();
      await tester.pump();
      expect(find.text('Status wird geladen …'), findsOneWidget);
      expect(jobReads, 2);
      pending.complete(
        f.reply({
          'kind': 'extract',
          'material_id': 'new-photo',
          'status': 'completed',
          'result': {'material_id': 'new-photo'},
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Seite prüfen'), findsOneWidget);
    },
  );
  testWidgets(
    'CK029 queued OCR is shown as waiting rather than already reading',
    (tester) async {
      await f.mount(
        tester,
        (r) async => r.url.path.contains('/materials/')
            ? f.reply({
                'id': 'new-photo',
                'child_id': 'child',
                'topic': 'Geometrie',
                'created': 1792600000,
              })
            : f.reply({
                'kind': 'extract',
                'material_id': 'new-photo',
                'status': 'queued',
              }),
        processing: true,
      );
      expect(find.text('Deine Seite wartet auf das Einlesen.'), findsOneWidget);
      expect(find.textContaining('Foto gespeichert:'), findsOneWidget);
      expect(find.text('Die KI liest dein Foto …'), findsNothing);
    },
  );
  testWidgets(
    'CK030 processing displays the real source and a purely reading source destination',
    (tester) async {
      final harness = await f.mount(
        tester,
        (r) async => r.url.path.contains('/materials/')
            ? f.reply({
                'id': 'new-photo',
                'child_id': 'child',
                'topic': 'Geometrie',
              })
            : f.reply({
                'kind': 'extract',
                'material_id': 'new-photo',
                'status': 'queued',
              }),
        processing: true,
      );
      expect(find.text('Deine Seite: Geometrie'), findsOneWidget);
      await f.tap(tester, 'Gespeicherte Seite ansehen');
      expect(find.text('Prüfen new-photo'), findsOneWidget);
      expect(harness.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'CK031 failed OCR shows the saved understandable reason with no automatic retry',
    (tester) async {
      final harness = await f.mount(
        tester,
        (r) async => r.url.path.contains('/materials/')
            ? f.reply({
                'id': 'new-photo',
                'child_id': 'child',
                'topic': 'Geometrie',
              })
            : f.reply({
                'kind': 'extract',
                'material_id': 'new-photo',
                'status': 'failed',
                'error': 'Das Foto war zu unscharf.',
              }),
        processing: true,
      );
      expect(find.text('Das Foto war zu unscharf.'), findsOneWidget);
      expect(
        find.textContaining('nichts automatisch erneut gestartet'),
        findsOneWidget,
      );
      expect(harness.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
