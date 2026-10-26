import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_content.dart';
import 'package:schulpilot/material_screen.dart';
import 'package:schulpilot/ui.dart';

// Invented local text only. No source, photo, account or provider access.
const oldDraft =
    'Meine künstliche Korrektur bleibt bis zu meiner Entscheidung erhalten.';
Json page({int revision = 1, String? automatic, bool empty = false}) {
  final checked = const {'checked', 'checked_with_gaps'}.contains(automatic);
  return {
    'id': 'synthetic-page',
    'child_id': 'synthetic-child',
    'subject': 'Mathematik',
    'topic': 'Künstliches Thema',
    'purpose': 'notebook',
    'content': empty ? '' : 'Gespeicherte künstliche Abschrift $revision.',
    'homework': <String>[],
    'uncertainties': <String>[],
    'source_blocks': <Json>[],
    'source_learning': {'factual_status': 'not_assessed'},
    'confirmed': checked,
    'status': checked ? 'confirmed' : 'review',
    'revision': revision,
    'has_image': false,
    'synthetic': false,
    if (automatic != null)
      'material_review': {
        'mode': 'automatic',
        'status': automatic,
        'message': 'Künstliche Statusmeldung: Unleserliche Stellen werden nicht als bewerteter Lernstoff verwendet.',
      },
  };
}

class Fixture {
  final calls = <http.Request>[];
  late final state =
      AppState(
          api: Api(
            base: 'https://synthetic.invalid/api',
            client: MockClient((request) async {
              calls.add(request);
              return http.Response(
                '{}',
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          )..token = 'invented-session',
        )
        ..user = {
          'id': 'synthetic-child-user',
          'role': 'child',
          'child_id': 'synthetic-child',
        }
        ..familyId = 'synthetic-family';
  final data = ValueNotifier<Json>(page());
  late GoRouter router;
  final String role;
  Fixture({this.role = 'child'}) {
    if (role == 'parent') {
      state.user = {'id': 'synthetic-parent-user', 'role': 'parent'};
    }
  }
  Future<void> open(
    WidgetTester tester, {
    double width = 390,
    double scale = 2,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<Json>(
                valueListenable: data,
                builder: (_, value, _) => MaterialReview(
                  state,
                  value,
                  onRefresh: () {},
                  showUnitAction: false,
                  simpleChild: role == 'child',
                ),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    router.dispose();
  }

  void dispose() {
    data.dispose();
    state.dispose();
  }
}

Finder textField(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Finder literal(String text) =>
    find.byWidgetPredicate((w) => w is LearningContent && w.text == text);
Future<void> tap(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
  });
  for (final role in ['child', 'parent']) {
    for (final status in [
      'checking',
      'checked',
      'checked_with_gaps',
      'failed',
    ]) {
      testWidgets(
        '142 $role shows real automatic $status provenance at390px and200percent without a request',
        (tester) async {
          final f = Fixture(role: role);
          addTearDown(f.dispose);
          f.data.value = page(
            automatic: status,
            empty: status == 'checked_with_gaps',
          );
          final before = jsonEncode(f.data.value);
          await f.open(tester);
          expect(
            find.textContaining('Künstliche Statusmeldung:'),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is Tooltip &&
                  (w.message?.startsWith('Du hast die Abschrift') ?? false),
            ),
            findsNothing,
          );
          if (status.startsWith('checked')) {
            expect(find.text('Automatisch abgeglichen'), findsOneWidget);
            expect(find.text('Stimmt, weiter'), findsNothing);
            if (role == 'child') {
              final tip = tester.widget<Tooltip>(
                find.byWidgetPredicate(
                  (w) =>
                      w is Tooltip &&
                      (w.message?.contains('zweiter KI-Durchgang') ?? false),
                ),
              );
              expect(
                tip.message,
                contains('keine fachliche Richtigkeitsgarantie'),
              );
            }
          }
          if (status == 'checked_with_gaps') {
            expect(
              find.textContaining('Lesestellen bleiben offen'),
              findsOneWidget,
            );
          }
          for (final element in find.byType(Notice).evaluate()) {
            final box = tester.getRect(find.byWidget(element.widget));
            expect(box.left, greaterThanOrEqualTo(0));
            expect(box.right, lessThanOrEqualTo(390));
          }
          expect(jsonEncode(f.data.value), before);
          expect(f.calls, isEmpty);
          expect(tester.takeException(), isNull);
          await f.close(tester);
        },
      );
    }
  }
  testWidgets(
    '142 manual confirmed provenance remains explicitly human and no automatic claim is invented',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      f.data.value = page()..addAll({'confirmed': true, 'status': 'confirmed'});
      await f.open(tester);
      expect(find.text('Text übernommen'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Tooltip &&
              (w.message?.startsWith('Du hast die Abschrift') ?? false),
        ),
        findsOneWidget,
      );
      expect(find.text('Automatisch abgeglichen'), findsNothing);
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );
  testWidgets(
    '142 a confirmed automatic revision preserves the older correction through close and reopen',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      await f.open(tester);
      await tap(tester, find.text('Etwas verbessern'));
      await tester.enterText(textField('Text auf der Seite'), oldDraft);
      f.data.value = page(revision: 2, automatic: 'checked');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Deine Korrektur bleibt hier erhalten'),
        findsOneWidget,
      );
      expect(literal(oldDraft), findsOneWidget);
      expect(find.text('Stimmt, weiter'), findsNothing);
      expect(f.calls, isEmpty);
      await f.close(tester);
      final stored = f
          .state
          .collectionViews['source_correction:synthetic-child:synthetic-page']!;
      expect(stored['revision'], 1);
      expect(stored['content'], oldDraft);
      await f.open(tester);
      expect(literal(oldDraft), findsOneWidget);
      expect(
        find.textContaining('Deine Korrektur bleibt hier erhalten'),
        findsOneWidget,
      );
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );
  testWidgets(
    '142 replacing an old automatic-conflict draft needs the existing explicit discard confirmation',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      await f.open(tester);
      await tap(tester, find.text('Etwas verbessern'));
      await tester.enterText(textField('Text auf der Seite'), oldDraft);
      f.data.value = page(revision: 2, automatic: 'checked_with_gaps');
      await tester.pumpAndSettle();
      await tap(tester, find.text('Gespeicherte Seite laden'));
      expect(find.text('Eigene Korrektur zurücknehmen?'), findsOneWidget);
      await tap(tester, find.text('Weiter verbessern'));
      expect(literal(oldDraft), findsOneWidget);
      expect(f.calls, isEmpty);
      await tap(tester, find.text('Gespeicherte Seite laden'));
      await tap(tester, find.text('Gespeicherten Text wiederherstellen'));
      expect(literal(oldDraft), findsNothing);
      expect(literal('Gespeicherte künstliche Abschrift 2.'), findsWidgets);
      expect(find.text('Automatisch abgeglichen'), findsOneWidget);
      expect(f.calls, isEmpty);
      await f.close(tester);
      expect(
        f.state.collectionViews.containsKey(
          'source_correction:synthetic-child:synthetic-page',
        ),
        false,
      );
    },
  );
  testWidgets(
    '142 automatic-conflict drafts are not rebound to a replacement account',
    (tester) async {
      final f = Fixture();
      addTearDown(f.dispose);
      await f.open(tester);
      await tap(tester, find.text('Etwas verbessern'));
      await tester.enterText(textField('Text auf der Seite'), oldDraft);
      f.data.value = page(revision: 2, automatic: 'checked');
      await tester.pumpAndSettle();
      await f.close(tester);
      expect(f.state.collectionViews, isNotEmpty);
      f.state.user = {...f.state.user!};
      f.state.refreshState();
      await f.open(tester);
      expect(literal(oldDraft), findsNothing);
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );
}
