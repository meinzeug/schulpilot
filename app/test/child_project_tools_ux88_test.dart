import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/language_workshop.dart';
import 'package:schulpilot/language_options.dart';

import 'child_local_tools_ux88_test.dart' as f;
import 'language_retry_test.dart' as old;

AppState account(List<http.Request> calls, {bool detail = false}) =>
    f.account((r) async {
      calls.add(r);
      if (detail) {
        return f.reply({
          ...old.project(true),
          'target_locale': 'fr-FR',
          'source_revisions': [
            {'id': 'a' * 32, 'revision': 1},
          ],
          'result': {
            'response': 'Une explication conservée.',
            'response_locale': 'fr-FR',
            'criteria': [],
            'source_excerpt': 'Mon texte confirmé.',
          },
        });
      }
      if (r.url.path.endsWith('/vocabulary')) {
        return f.reply({
          'items': [
            for (var n = 1; n <= 7; n++)
              {'id': 'w$n', 'word': 'word$n', 'meaning': 'Bedeutung $n'},
          ],
          'pagination': {'total': 7},
        });
      }
      if (r.url.path.endsWith('/materials')) {
        return f.reply({
          'items': [],
          'pagination': {'total': 0},
        });
      }
      return f.reply({
        'projects': [
          for (final option in [
            ('ready', 'school', 'en-GB'),
            ('failed', 'animals', 'fr-FR'),
          ])
            {
              'id': option.$2,
              'mode': 'exam',
              'target_locale': option.$3,
              'status': option.$1,
              'goal': option.$2 == 'school'
                  ? 'Meine Schulwörter'
                  : 'Tiere beschreiben',
            },
        ],
        'has_more': false,
      });
    });
void main() {
  testWidgets('KK041 saved project displays its actual confirmed locale', (
    tester,
  ) async {
    final calls = <http.Request>[];
    await f.show(
      tester,
      LanguageWorkshop(
        account(calls, detail: true),
        childId: 'child',
        projectId: 'project',
      ),
    );
    expect(find.text(learningLocales['fr-FR']!), findsOneWidget);
    expect(calls.every((r) => r.method == 'GET'), isTrue);
  });
  testWidgets(
    'KK042 stored project excerpt opens only its real source without another generation',
    (tester) async {
      final calls = <http.Request>[];
      await f.show(
        tester,
        LanguageWorkshop(
          account(calls, detail: true),
          childId: 'child',
          projectId: 'project',
        ),
      );
      await f.tap(tester, find.text('Beleg im bestätigten Stoff'));
      await f.tap(tester, find.text('Bestätigte Heftseite ansehen'));
      expect(find.text('Ziel /material/${'a' * 32}'), findsOneWidget);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'KK043 prepared project summary opens exactly its existing practice round',
    (tester) async {
      final calls = <http.Request>[];
      await f.show(
        tester,
        LanguageWorkshop(
          account(calls, detail: true),
          childId: 'child',
          projectId: 'project',
        ),
      );
      await f.tap(
        tester,
        find.text('Deine gespeicherten Aufgaben zu diesem Lernprojekt'),
      );
      expect(find.text('Ziel /unit/round'), findsOneWidget);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'KK074 saved project search finds loaded goals and languages without server traffic',
    (tester) async {
      final calls = <http.Request>[];
      await f.show(tester, LanguageWorkshop(account(calls), childId: 'child'));
      await f.tap(
        tester,
        find.byKey(const ValueKey('child-mobile-filter-toggle')),
      );
      final before = calls.length;
      await tester.enterText(f.input('Geladene Projekte durchsuchen'), 'Tiere');
      await tester.pumpAndSettle();
      expect(find.textContaining('Tiere beschreiben'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.textContaining('Meine Schulwörter'),
          matching: find.byType(ListTile),
        ),
        findsNothing,
      );
      expect(calls.length, before);
    },
  );
  testWidgets(
    'KK075 actual project state filter separates failed preparation without retrying it',
    (tester) async {
      final calls = <http.Request>[];
      await f.show(tester, LanguageWorkshop(account(calls), childId: 'child'));
      await f.tap(
        tester,
        find.byKey(const ValueKey('child-mobile-filter-toggle')),
      );
      await f.tap(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Projektstand',
        ),
      );
      await f.tap(tester, find.text('Vorbereitung fehlgeschlagen').last);
      expect(find.textContaining('Tiere beschreiben'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.textContaining('Meine Schulwörter'),
          matching: find.byType(ListTile),
        ),
        findsNothing,
      );
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'KK076 selecting loaded workshop words supports local search without losing already selected pairs',
    (tester) async {
      final calls = <http.Request>[];
      await f.show(tester, LanguageWorkshop(account(calls), childId: 'child'));
      await f.tap(tester, find.text('Neue Sprachübung'));
      await f.tap(tester, find.widgetWithText(FilterChip, 'word1'));
      await tester.enterText(
        f.input('Geladene Schulwörter finden'),
        'Bedeutung 7',
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'word7'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'word2'), findsNothing);
      expect(find.widgetWithText(InputChip, 'word1'), findsOneWidget);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
