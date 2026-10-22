import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';

import 'progress_cards_ux88_test.dart' as f;

Json data(http.Request r, {int page = 1, int pages = 1}) => {
  ...f.data(r, page: page, pages: pages),
  'pagination': {'page': page, 'pages': pages, 'page_size': 1, 'total': pages},
  'view_filters': {
    'period': r.url.queryParameters['period'] ?? 'all',
    'sort': r.url.queryParameters['sort'] ?? 'default',
    'search': r.url.queryParameters['search'] ?? '',
    'status': r.url.queryParameters['status'] ?? 'all',
    'round_kind': r.url.queryParameters['round_kind'] ?? 'all',
  },
};
Future<void> tools(WidgetTester t) async {
  await t.ensureVisible(find.text('Zeitraum, Suche & Reihenfolge'));
  await t.tap(find.text('Zeitraum, Suche & Reihenfolge'));
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder target) async {
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pumpAndSettle();
}

void main() {
  for (final choice in [
    ('RQ032', 'Zeitraum', 'Letzte 7 Tage', 'period', '7', 'zeitraum'),
    (
      'RQ033',
      'Reihenfolge',
      'Weiter üben zuerst',
      'sort',
      'practice',
      'sortierung',
    ),
    ('RQ035', 'Rundenstatus', 'Pausiert', 'status', 'paused', 'status'),
    (
      'RQ036',
      'Rundenart',
      'Wörterrunden',
      'round_kind',
      'vocabulary',
      'rundenart',
    ),
  ]) {
    f.scenario(
      '${choice.$1} progress ${choice.$4} is server-filtered and addressable',
      (t) async {
        final calls = <http.Request>[];
        final fixture = await f.display(t, (r) async {
          calls.add(r);
          return f.reply(data(r));
        });
        await tools(t);
        final field = find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == choice.$2,
        );
        await tap(t, field);
        await tap(t, find.text(choice.$3).last);
        final query = calls
            .lastWhere((r) => r.url.path.endsWith('/learning-progress'))
            .url
            .queryParameters;
        expect(query[choice.$4], choice.$5);
        expect(
          fixture
              .router
              .routeInformationProvider
              .value
              .uri
              .queryParameters[choice.$6],
          choice.$5,
        );
        expect(calls.every((r) => r.method == 'GET'), isTrue);
      },
    );
  }
  f.scenario(
    'RQ034 progress subject search needs explicit submission and preserves evidence',
    (t) async {
      final calls = <http.Request>[];
      await f.display(t, (r) async {
        calls.add(r);
        return f.reply(data(r));
      });
      await tools(t);
      final field = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Fach oder Thema suchen',
      );
      final before = calls.length;
      await t.enterText(field, 'Brüche');
      await t.pump();
      expect(calls.length, before);
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      expect(
        calls
            .lastWhere((r) => r.url.path.endsWith('/learning-progress'))
            .url
            .queryParameters['search'],
        'Brüche',
      );
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  f.scenario('RQ037 a long progress ledger has a bounded direct page chooser', (
    t,
  ) async {
    final calls = <http.Request>[];
    await f.display(t, (r) async {
      calls.add(r);
      return f.reply(
        data(
          r,
          page: int.parse(r.url.queryParameters['page'] ?? '1'),
          pages: 4,
        ),
      );
    });
    await tap(t, find.text('Seite 1 von 4'));
    await t.enterText(find.byType(TextField).last, '99');
    await tap(t, find.text('Seite öffnen'));
    expect(
      find.text('Bitte eine vorhandene Seitennummer eingeben.'),
      findsOneWidget,
    );
    await t.enterText(find.byType(TextField).last, '3');
    await tap(t, find.text('Seite öffnen'));
    expect(
      calls
          .lastWhere((r) => r.url.path.endsWith('/learning-progress'))
          .url
          .queryParameters['page'],
      '3',
    );
    expect(find.text('Seite 3 von 4'), findsOneWidget);
  });
  f.scenario(
    'RQ038 progress deep links restore explicit view filters without local guessing',
    (t) async {
      final calls = <http.Request>[];
      await f.display(
        t,
        (r) async {
          calls.add(r);
          return f.reply(data(r));
        },
        location: '/progress/kid?zeitraum=30&sortierung=recent&suche=Zellen&status=completed&rundenart=learning',
      );
      final q = calls
          .firstWhere((r) => r.url.path.endsWith('/learning-progress'))
          .url
          .queryParameters;
      expect(q['period'], '30');
      expect(q['sort'], 'recent');
      expect(q['search'], 'Zellen');
      expect(q['status'], 'completed');
      expect(q['round_kind'], 'learning');
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  f.scenario('RQ039 older servers show an honest filter error and safe reset', (
    t,
  ) async {
    final calls = <http.Request>[];
    await f.display(t, (r) async {
      calls.add(r);
      return f.reply(f.data(r));
    }, location: '/progress/kid?zeitraum=7');
    expect(find.textContaining('noch nicht verfügbar'), findsOneWidget);
    expect(find.text('Mathematik'), findsNothing);
    await tools(t);
    await tap(t, find.text('Ansichtsfilter zurücksetzen'));
    expect(find.text('Mathematik'), findsOneWidget);
    expect(calls.every((r) => r.method == 'GET'), isTrue);
  });
}
