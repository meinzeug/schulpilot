import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/language_workshop.dart';
import 'package:schulpilot/progress_screen.dart';
import 'package:schulpilot/school_day_history.dart';
import 'package:schulpilot/ui.dart';

import 'child_local_tools_ux88_test.dart' as local;
import 'child_project_tools_ux88_test.dart' as projects;
import 'child_history_ux90_test.dart' as history;
import 'child_source_tools_ux88_test.dart' as source;
import 'notebook_test.dart' as books;
import 'progress_cards_ux88_test.dart' as progress;

Future<void> mountPage(
  WidgetTester tester,
  AppState state,
  Widget page, {
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => ListenableBuilder(
          listenable: state,
          builder: (_, _) =>
              KeyedSubtree(key: ObjectKey(state.user), child: page),
        ),
      ),
      GoRoute(
        path: '/after-school/:id',
        builder: (_, r) => Scaffold(body: Text('Ziel ${r.uri}')),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    state.inbox.dispose();
    state.familyCalls.dispose();
  });
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

Future<void> revealTools(WidgetTester tester) =>
    local.tap(tester, find.byKey(const ValueKey('child-mobile-filter-toggle')));

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUpAll(() async {
    for (final font in ['Nunito', 'SpaceGrotesk', 'Roboto']) {
      await (FontLoader(font)..addFont(
            rootBundle.load(
              'assets/fonts/${font == 'Roboto' ? 'Nunito' : font}.ttf',
            ),
          ))
          .load();
    }
  });

  for (final sample in [
    (320.0, 1.0),
    (390.0, 1.0),
    (320.0, 2.0),
    (1440.0, 1.0),
  ]) {
    testWidgets(
      '103 saved language projects precede optional creation at $sample',
      (tester) async {
        final calls = <http.Request>[];
        final state = projects.account(calls);
        await mountPage(
          tester,
          state,
          LanguageWorkshop(state, childId: 'child'),
          size: Size(sample.$1, 844),
          scale: sample.$2,
        );
        expect(local.input('Dein konkretes Lernziel'), findsNothing);
        expect(find.textContaining('Meine Schulwörter'), findsOneWidget);
        expect(find.textContaining('Tiere beschreiben'), findsOneWidget);
        final row = find.ancestor(
          of: find.textContaining('Meine Schulwörter'),
          matching: find.byType(ListTile),
        );
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        expect(row.hitTestable(), findsOneWidget);
        expect(calls.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    '103 closing the project form retains its exact goal without generation or extra reads',
    (tester) async {
      final calls = <http.Request>[];
      final state = projects.account(calls);
      await mountPage(tester, state, LanguageWorkshop(state, childId: 'child'));
      final before = calls.length;
      await local.tap(tester, find.text('Neue Sprachübung'));
      await tester.enterText(
        local.input('Dein konkretes Lernziel'),
        'Mein eigener unveränderter Entwurf.',
      );
      await local.tap(tester, find.text('Neue Sprachübung'));
      expect(local.input('Dein konkretes Lernziel'), findsNothing);
      await local.tap(tester, find.text('Neue Sprachübung'));
      expect(
        tester
            .widget<TextField>(local.input('Dein konkretes Lernziel'))
            .controller!
            .text,
        'Mein eigener unveränderter Entwurf.',
      );
      expect(calls.length, before);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    '103 selected source-bound words survive closing the deliberate project form',
    (tester) async {
      final calls = <http.Request>[];
      final state = projects.account(calls);
      await mountPage(tester, state, LanguageWorkshop(state, childId: 'child'));
      await local.tap(tester, find.text('Neue Sprachübung'));
      await local.tap(tester, find.widgetWithText(FilterChip, 'word1'));
      await local.tap(tester, find.text('Neue Sprachübung'));
      await local.tap(tester, find.text('Neue Sprachübung'));
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'word1'))
            .selected,
        isTrue,
      );
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    '103 project search is deliberate and leaves its applied local query intact',
    (tester) async {
      final calls = <http.Request>[];
      final state = projects.account(calls);
      await mountPage(tester, state, LanguageWorkshop(state, childId: 'child'));
      final before = calls.length;
      await revealTools(tester);
      await tester.enterText(
        local.input('Geladene Projekte durchsuchen'),
        'Tiere',
      );
      await tester.pumpAndSettle();
      await revealTools(tester);
      expect(local.input('Geladene Projekte durchsuchen'), findsNothing);
      expect(find.textContaining('Meine Schulwörter'), findsNothing);
      expect(find.textContaining('Tiere beschreiben'), findsOneWidget);
      await revealTools(tester);
      expect(
        tester
            .widget<TextField>(local.input('Geladene Projekte durchsuchen'))
            .controller!
            .text,
        'Tiere',
      );
      expect(calls.length, before);
    },
  );

  for (final sample in [
    (320.0, 1.0),
    (390.0, 1.0),
    (320.0, 2.0),
    (1440.0, 1.0),
  ]) {
    testWidgets(
      '103 mailbox shows real messages and help count before optional filters at $sample',
      (tester) async {
        final calls = <http.Request>[];
        final state = local.account((r) async {
          calls.add(r);
          return local.reply({});
        });
        await local.show(
          tester,
          local.mailbox(state, local.mailData()),
          size: Size(sample.$1, 844),
          scale: sample.$2,
        );
        expect(local.input('Nachrichten durchsuchen'), findsNothing);
        expect(find.text('1 offener Hilfewunsch'), findsOneWidget);
        expect(find.text('Bitte Brüche weiter üben.'), findsOneWidget);
        await revealTools(tester);
        await tester.enterText(
          local.input('Nachrichten durchsuchen'),
          'Brüche',
        );
        await tester.pumpAndSettle();
        await revealTools(tester);
        expect(find.text('Bitte Brüche weiter üben.'), findsOneWidget);
        expect(find.text('Ich möchte Tiere entdecken.'), findsNothing);
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final sample in [
    (320.0, 1.0),
    (390.0, 1.0),
    (320.0, 2.0),
    (1440.0, 1.0),
  ]) {
    testWidgets(
      '103 saved school days stay reachable without opening three filters at $sample',
      (tester) async {
        final calls = <http.Request>[];
        final state = local.account((r) async {
          calls.add(r);
          return local.reply({
            'days': [
              history.day('a', '2026-10-20', 'Mathematik'),
              history.day('b', '2026-10-19', 'Biologie'),
            ],
            'next_before': null,
          });
        });
        await mountPage(
          tester,
          state,
          SchoolDayHistory(state, childId: 'child'),
          size: Size(sample.$1, 844),
          scale: sample.$2,
        );
        expect(local.input('Geladene Tagespakete durchsuchen'), findsNothing);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.text('Mathematik'), findsOneWidget);
        final before = calls.length;
        await revealTools(tester);
        await tester.enterText(
          local.input('Geladene Tagespakete durchsuchen'),
          'Biologie',
        );
        await tester.pumpAndSettle();
        await revealTools(tester);
        expect(find.text('Mathematik'), findsNothing);
        expect(find.text('Biologie'), findsOneWidget);
        expect(calls.length, before);
        expect(calls.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets(
      '103 notebook exposes one compact accessible toolbar at $width',
      (tester) async {
        final (_, _, calls) = await books.open(
          tester,
          width: width,
          photos: false,
        );
        final search = find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Im Hefter suchen',
        );
        final filter = find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Filter',
        );
        expect(search, findsOneWidget);
        expect(filter, findsOneWidget);
        expect(tester.getSize(search).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(filter).height, greaterThanOrEqualTo(48));
        await local.tap(tester, search);
        expect(local.input('In diesem Hefter suchen'), findsOneWidget);
        expect(calls.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    '103 source and explicit confirmation precede secondary page maintenance',
    (tester) async {
      final calls = <http.Request>[];
      await source.open(tester, calls);
      final confirm = find.widgetWithText(ActionButton, 'Stimmt, weiter');
      final remove = find.widgetWithText(ActionButton, 'Seite löschen');
      expect(confirm, findsOneWidget);
      expect(remove, findsOneWidget);
      expect(
        tester.getTopLeft(confirm).dy,
        lessThan(tester.getTopLeft(remove).dy),
      );
      expect(calls.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '103 actual progress evidence precedes optional category controls and changing one stays GET-only',
    (tester) async {
      final calls = <http.Request>[];
      final state = local.account((r) async {
        calls.add(r);
        return progress.reply(progress.data(r));
      });
      await mountPage(tester, state, ProgressScreen(state, childId: 'child'));
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Mathematik'), findsOneWidget);
      final before = calls.length;
      await local.tap(tester, find.text('Zeitraum, Suche & Reihenfolge'));
      expect(calls.length, before);
      await local.tap(
        tester,
        find.widgetWithText(ChoiceChip, 'Selbstständig gelöst'),
      );
      expect(calls.last.url.queryParameters['category'], 'independent');
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    '103 an expanded language form disappears on account replacement without any write',
    (tester) async {
      final calls = <http.Request>[];
      final state = projects.account(calls);
      await mountPage(tester, state, LanguageWorkshop(state, childId: 'child'));
      await local.tap(tester, find.text('Neue Sprachübung'));
      await tester.enterText(
        local.input('Dein konkretes Lernziel'),
        'Privater künstlicher Entwurf',
      );
      await local.tap(tester, find.widgetWithText(FilterChip, 'word1'));
      final staleCreate = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Mein Lernprojekt vorbereiten'),
          )
          .onPressed!;
      state.user = {...state.user!, 'id': 'another-synthetic-child'};
      state.notifyListeners();
      await tester.pumpAndSettle();
      staleCreate();
      await tester.pumpAndSettle();
      expect(local.input('Dein konkretes Lernziel'), findsNothing);
      expect(find.text('Privater künstlicher Entwurf'), findsNothing);
      await local.tap(tester, find.text('Neue Sprachübung'));
      expect(
        tester
            .widget<TextField>(local.input('Dein konkretes Lernziel'))
            .controller!
            .text,
        isNot('Privater künstlicher Entwurf'),
      );
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
