import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_tips.dart';
import 'package:schulpilot/ui.dart';

import 'learning_tips_test.dart' as f;

Future<void> tap(WidgetTester t, Finder node) async {
  await t.ensureVisible(node.first);
  await t.pumpAndSettle();
  await t.tap(node.first);
  await t.pumpAndSettle();
}

Finder search() => find.byWidgetPredicate(
  (w) =>
      w is TextField &&
      w.decoration?.labelText == 'Geladene Lerntipps durchsuchen',
);
void main() {
  testWidgets(
    'RQ103 failed deliberate topic selection remains available for review',
    (t) async {
      final calls = <http.Request>[];
      await f.mount(t, (q) async {
        calls.add(q);
        if (q.method == 'PUT') {
          return http.Response(
            '{"detail":"Bitte Auswahl erneut prüfen"}',
            409,
            headers: {'content-type': 'application/json'},
          );
        }
        if (q.url.path.contains('/topics')) {
          return f.reply({
            'items': [],
            'total': 0,
            'subject': {'title': 'Mathematik'},
          });
        }
        return f.reply(f.tips());
      });
      await tap(t, find.text('Lerntipps'));
      await tap(t, find.text('Thema auswählen'));
      await tap(t, find.text('Themenauswahl leeren'));
      await tap(t, find.text('Keine Themen übernehmen'));
      expect(
        find.textContaining('Deine Themenauswahl ist noch nicht bestätigt'),
        findsOneWidget,
      );
      await tap(
        t,
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(IconButton),
        ),
      );
      await tap(t, find.text('Thema auswählen'));
      expect(find.text('Keine Themen übernehmen'), findsOneWidget);
      expect(find.text('Brüche addieren'), findsNothing);
      expect(calls.where((q) => q.method == 'PUT'), hasLength(1));
      expect(calls.where((q) => q.method == 'POST'), isEmpty);
    },
  );
  testWidgets(
    'RQ109 delayed old media writes and stale card callbacks cannot change a new source',
    (t) async {
      final calls = <http.Request>[];
      final delayed = Completer<http.Response>();
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((q) async {
            calls.add(q);
            if (q.method == 'POST') return delayed.future;
            return f.reply({
              ...f.tips(),
              'media_return': {
                'content_id': 'content-1',
                'topic_id': 'topic-1',
                'status': 'opened',
              },
              if (q.url.path.contains('/new'))
                'recommended': [
                  {...f.content(1), 'title': 'Aktueller neuer Lerntipp'},
                ],
            });
          }),
        ),
      )..user = {'id': 'own', 'role': 'child', 'child_id': 'child'};
      var resource = 'old';
      late StateSetter change;
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (ctx, set) {
                change = set;
                return SingleChildScrollView(
                  child: LearningTips(
                    state,
                    childId: 'child',
                    kind: 'material',
                    resourceId: resource,
                    initiallyExpanded: true,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final oldCallback = t
          .widget<TipContentCard>(find.byType(TipContentCard).first)
          .onReject!;
      await t.ensureVisible(find.text('Ich habe ihn angesehen'));
      await t.tap(find.text('Ich habe ihn angesehen'));
      await t.pump();
      expect(calls.where((q) => q.method == 'POST'), hasLength(1));
      change(() => resource = 'new');
      await t.pumpAndSettle();
      await tap(t, find.text('Lerntipps'));
      final reads = calls.where((q) => q.method == 'GET').length;
      oldCallback();
      await t.pump();
      delayed.complete(
        http.Response(
          '{"detail":"Alter Fehler darf hier nicht erscheinen"}',
          503,
          headers: {'content-type': 'application/json'},
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Aktueller neuer Lerntipp'), findsOneWidget);
      expect(
        find.text('Alter Fehler darf hier nicht erscheinen'),
        findsNothing,
      );
      expect(calls.where((q) => q.method == 'POST'), hasLength(1));
      expect(calls.where((q) => q.method == 'GET').length, reads);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'RQ077 loaded learning tips can be searched without model or interaction writes',
    (t) async {
      final calls = <http.Request>[];
      await f.mount(t, (q) async {
        calls.add(q);
        return f.reply(f.tips());
      });
      await tap(t, find.text('Lerntipps'));
      await tap(t, find.text('Lerntipps eingrenzen'));
      await t.enterText(search(), 'Lerntipp 2');
      await t.pumpAndSettle();
      expect(find.text('Künstlicher Lerntipp 2'), findsOneWidget);
      expect(find.text('Künstlicher Lerntipp 1'), findsNothing);
      expect(
        find.text('Suche nur in den 3 hier geladenen Tipps.'),
        findsOneWidget,
      );
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ078 a child can deliberately choose readable text rather than video among loaded tips',
    (t) async {
      final calls = <http.Request>[];
      await f.mount(t, (q) async {
        calls.add(q);
        return f.reply(f.tips());
      });
      await tap(t, find.text('Lerntipps'));
      await tap(t, find.text('Lerntipps eingrenzen'));
      await tap(
        t,
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Darstellung des Lerntipps',
        ),
      );
      await tap(t, find.text('Lerntexte').last);
      expect(find.text('Künstlicher Lerntipp 2'), findsOneWidget);
      expect(find.text('Künstlicher Lerntipp 1'), findsNothing);
      await tap(t, find.text('Lerntippfilter zurücksetzen'));
      expect(find.text('Künstlicher Lerntipp 1'), findsOneWidget);
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ079 expanded recommendations can return to a smaller saved view',
    (t) async {
      final calls = <http.Request>[];
      await f.mount(t, (q) async {
        calls.add(q);
        return f.reply(f.tips());
      });
      await tap(t, find.text('Lerntipps'));
      await tap(t, find.text('Weitere anzeigen'));
      expect(find.text('Künstlicher Lerntipp 4'), findsOneWidget);
      await tap(t, find.text('Weniger Lerntipps anzeigen'));
      expect(find.text('Künstlicher Lerntipp 4'), findsNothing);
      expect(calls.last.url.queryParameters['limit'], '3');
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ080 refresh of ready tips is an explicit GET and preserves local narrowed reading',
    (t) async {
      final calls = <http.Request>[];
      await f.mount(t, (q) async {
        calls.add(q);
        return f.reply(f.tips());
      });
      await tap(t, find.text('Lerntipps'));
      await tap(t, find.text('Lerntipps eingrenzen'));
      await t.enterText(search(), '2');
      await t.pumpAndSettle();
      await tap(t, find.text('Lerntipps aktualisieren'));
      expect(t.widget<TextField>(search()).controller!.text, '2');
      expect(find.text('Künstlicher Lerntipp 1'), findsNothing);
      expect(calls.where((q) => q.method == 'GET').length, 2);
    },
  );
  testWidgets(
    'RQ081 learning tips are hidden immediately after same-account family change',
    (t) async {
      final state = await f.mount(t, (q) async => f.reply(f.tips()));
      await tap(t, find.text('Lerntipps'));
      expect(find.text('Künstlicher Lerntipp 1'), findsOneWidget);
      state.familyId = 'another-family';
      state.notifyListeners();
      await t.pumpAndSettle();
      expect(find.text('Künstlicher Lerntipp 1'), findsNothing);
    },
  );
  testWidgets(
    'RQ082 the whole selected topic set can be emptied and restored before deliberate confirmation',
    (t) async {
      final api = Api(
        base: 'https://example.invalid/api',
        client: MockClient(
          (_) async => f.reply({
            'items': [],
            'total': 0,
            'subject': {'title': 'Mathematik'},
          }),
        ),
      );
      final own = AppState(api: api)..user = {'id': 'own', 'role': 'child'};
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: TopicBrowser(
              own,
              childId: 'child',
              subjectId: 'math',
              selected: {'one'},
              selectedLabels: {'one': 'Brüche'},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, find.text('Themenauswahl leeren'));
      expect(find.text('Keine Themen übernehmen'), findsOneWidget);
      await tap(t, find.text('Themenauswahl wiederherstellen'));
      expect(find.text('Auswahl übernehmen'), findsOneWidget);
      expect(find.text('Brüche'), findsOneWidget);
    },
  );
  testWidgets(
    'RQ083 a covered async action pauses its busy animation until its own dialog closes',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ActionButton(
                label: 'Eigener Dialog',
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) =>
                      const AlertDialog(title: Text('Bewusst prüfen')),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Eigener Dialog'));
      await t.pumpAndSettle();
      expect(find.text('Bewusst prüfen'), findsOneWidget);
      expect(t.binding.hasScheduledFrame, isFalse);
    },
  );
}
