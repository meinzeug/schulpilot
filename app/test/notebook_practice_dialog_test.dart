import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:schulpilot/notebook_photo.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/notebook_practice_dialog.dart';
import 'package:schulpilot/ui.dart';

import 'notebook_test.dart' as notebook;

const subject = '11111111111111111111111111111111';
Json page(String id, {int revision = 1}) => {
  'id': id,
  'revision': revision,
  'child_id': 'child',
  'subject_id': subject,
  'title': 'Heft $id',
  'topic': 'Brüche $id',
  'page_number': revision,
  'confirmed': true,
  'purpose': 'notebook',
  'synthetic': false,
};
http.Response reply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

Future<(AppState, List<http.Request>)> openDialog(
  WidgetTester tester, {
  Future<http.Response> Function(http.Request)? respond,
  double width = 390,
  double scale = 1,
  Json? primaryPage,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final requests = <http.Request>[];
  final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((r) async {
        requests.add(r);
        if (respond != null) return respond(r);
        expect(r.method, 'GET');
        return reply({
          'items': [page('base'), page('extra', revision: 2)],
          'total': 2,
        });
      }),
    ),
  )..user = {'id': 'user', 'role': 'child', 'child_id': 'child'};
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      builder: (_, child) => MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<String>(
              context: context,
              builder: (_) => NotebookPracticeDialog(
                state: state,
                childId: 'child',
                subjectId: subject,
                page: primaryPage ?? page('base'),
              ),
            ),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Öffnen'));
  await tester.pumpAndSettle();
  return (state, requests);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '125 notebook practice names the actual page and topic rather than its upload-day ordinal',
    (tester) async {
      final primary = page('base')
        ..['title'] = 'Heftseite 9'
        ..['page_number'] = 9
        ..['topic'] = 'Gemischte Zahlen';
      final extra = page('extra', revision: 2)
        ..['topic'] = 'Brüche bündeln'
        ..['has_image'] = true;
      final (_, requests) = await openDialog(
        tester,
        width: 320,
        scale: 2,
        primaryPage: primary,
        respond: (request) async {
          if (request.url.path.endsWith('/image')) {
            return http.Response.bytes(
              image.encodePng(image.Image(width: 2, height: 2)),
              200,
            );
          }
          return reply({
            'items': [primary, extra],
            'total': 2,
          });
        },
      );
      expect(find.text('Diese Heftseite'), findsOneWidget);
      expect(find.text('Gemischte Zahlen'), findsOneWidget);
      expect(find.text('Heftseite 9'), findsNothing);
      expect(requests, isEmpty);
      await tapText(tester, 'Weitere Heftseiten hinzufügen');
      expect(find.text('Brüche bündeln'), findsOneWidget);
      expect(find.text('Heftseite 9'), findsNothing);
      final preview = tester.widget<NotebookPhoto>(find.byType(NotebookPhoto));
      expect(preview.materialId, 'extra');
      expect(preview.revision, 2);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(
        requests.where((request) => request.url.path.endsWith('/image')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Opening and optional source selection are GET-only; the conscious POST binds exact revisions and count',
    (tester) async {
      final delayed = Completer<http.Response>();
      final (_, requests) = await openDialog(
        tester,
        respond: (r) async {
          if (r.method == 'POST') return delayed.future;
          return reply({
            'items': [page('base'), page('extra', revision: 2)],
            'total': 2,
          });
        },
      );
      expect(requests, isEmpty);
      await tapText(tester, 'Weitere Heftseiten hinzufügen');
      expect(
        requests.single.url.queryParameters,
        containsPair('subject_id', subject),
      );
      expect(
        requests.single.url.queryParameters,
        containsPair('status', 'confirmed'),
      );
      await tapText(tester, 'Brüche extra');
      await tester.enterText(find.byType(TextFormField), '3');
      await tester.ensureVisible(find.text('Runde vorbereiten'));
      await tester.tap(find.text('Runde vorbereiten'));
      await tester.pump();
      final sent = requests.where((r) => r.method == 'POST').single;
      expect(jsonDecode(sent.body), {
        'material_id': 'base',
        'notebook_sources': [
          {'id': 'base', 'revision': 1},
          {'id': 'extra', 'revision': 2},
        ],
        'question_count': 3,
      });
      expect(
        sent.headers['Idempotency-Key'],
        matches(r'^notebook-[a-f0-9]{32}$'),
      );
      expect(sent.headers['X-Schulpilot-Account'], 'user');
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNull,
      );
      delayed.complete(reply({'id': 'job', 'status': 'queued'}, 202));
      await tester.pumpAndSettle();
      expect(find.byType(NotebookPracticeDialog), findsNothing);
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
    },
  );

  testWidgets(
    'Unknown outcome reconciles only after another click with the same payload and key',
    (tester) async {
      var posts = 0;
      final (_, requests) = await openDialog(
        tester,
        respond: (r) async {
          expect(r.method, 'POST');
          posts++;
          return posts == 1
              ? reply({'detail': 'Verbindung unklar'}, 503)
              : reply({'id': 'job', 'status': 'queued'}, 202);
        },
      );
      await tapText(tester, 'Runde vorbereiten');
      expect(posts, 1);
      expect(find.text('Vorbereitung abgleichen'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
        isFalse,
      );
      await tapText(tester, 'Vorbereitung abgleichen');
      expect(posts, 2);
      expect(requests[0].body, requests[1].body);
      expect(
        requests[0].headers['Idempotency-Key'],
        requests[1].headers['Idempotency-Key'],
      );
    },
  );

  for (final value in ['1', '6', '']) {
    testWidgets('Invalid individual task count $value starts no job', (
      tester,
    ) async {
      final (_, requests) = await openDialog(tester);
      await tester.enterText(find.byType(TextFormField), value);
      await tapText(tester, 'Runde vorbereiten');
      expect(
        find.text('Bitte eine Zahl von 2 bis 5 eingeben.'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
    });
  }

  testWidgets(
    'Definitive stale-source rejection is shown without an automatic retry',
    (tester) async {
      final (_, requests) = await openDialog(
        tester,
        respond: (r) async => reply({
          'detail': 'Bitte die geänderte Heftseite erneut auswählen.',
        }, 409),
      );
      await tapText(tester, 'Runde vorbereiten');
      expect(
        find.text('Bitte die geänderte Heftseite erneut auswählen.'),
        findsOneWidget,
      );
      expect(requests, hasLength(1));
      expect(find.text('Runde vorbereiten'), findsOneWidget);
    },
  );

  testWidgets(
    'A token change discards late source results and cannot send a new request',
    (tester) async {
      final delayed = Completer<http.Response>();
      final (state, requests) = await openDialog(
        tester,
        respond: (_) => delayed.future,
      );
      await tester.tap(find.text('Weitere Heftseiten hinzufügen'));
      await tester.pump(const Duration(milliseconds: 300));
      state.api.token = 'new-session';
      state.notifyListeners();
      delayed.complete(
        reply({
          'items': [page('extra')],
          'total': 1,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Brüche extra'), findsNothing);
      expect(find.text('Runde vorbereiten'), findsNothing);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );

  testWidgets(
    'Foreign subject results fail closed instead of becoming selectable sources',
    (tester) async {
      final (_, requests) = await openDialog(
        tester,
        respond: (_) async => reply({
          'items': [
            {...page('other'), 'subject_id': 'other-subject'},
          ],
          'total': 1,
        }),
      );
      await tapText(tester, 'Weitere Heftseiten hinzufügen');
      expect(
        find.text('Die Heftseiten konnten nicht sicher zugeordnet werden.'),
        findsOneWidget,
      );
      expect(find.text('Brüche other'), findsNothing);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );

  testWidgets(
    'The compact dialog remains operable at320px and200percent type',
    (tester) async {
      final (_, requests) = await openDialog(tester, width: 320, scale: 2);
      await tapText(tester, 'Weitere Heftseiten hinzufügen');
      await tapText(tester, 'Brüche extra');
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Zurück'));
      await tester.tap(find.text('Zurück'));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );

  for (final supported in [false, true]) {
    testWidgets(
      'Album entry is a single compact icon only with backend capability $supported',
      (tester) async {
        final (_, _, requests) = await notebook.open(
          tester,
          photos: false,
          respond: (r) async {
            if (r.url.path.endsWith('/subjects')) {
              return notebook.jsonReply(notebook.subjects());
            }
            final response = notebook.pages(r, photos: false);
            response['supports_notebook_practice'] = supported;
            for (final row in response['items']) {
              row['purpose'] = 'notebook';
            }
            return notebook.jsonReply(response);
          },
        );
        expect(
          find.byKey(const ValueKey('notebook-prepare-practice')),
          supported ? findsOneWidget : findsNothing,
        );
        if (supported) {
          await tester.tap(
            find.byKey(const ValueKey('notebook-prepare-practice')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(NotebookPracticeDialog), findsOneWidget);
        }
        expect(requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );
  }
}
