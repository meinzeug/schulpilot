import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/material_screen.dart';
import 'package:schulpilot/api.dart';

import 'child_local_tools_ux88_test.dart' as f;
import 'child_sources_input_ux87_test.dart' as source;

Future<AppState> open(
  WidgetTester tester,
  List<http.Request> calls, {
  bool saved = false,
  double scale = 1,
}) async {
  final state = f.account((r) async {
    calls.add(r);
    return f.reply({});
  });
  final page = source.page('page', saved: saved)
    ..['synthetic'] = false
    ..['has_image'] = false
    ..['subject_id'] = 'b' * 32
    ..['content'] =
        'Eine künstliche Mitschrift.\nFläche = Länge mal Breite\nVolumen = Länge mal Breite mal Höhe';
  await f.show(
    tester,
    MaterialReview(
      state,
      page,
      onRefresh: () {},
      simpleChild: true,
      showUnitAction: false,
    ),
    scale: scale,
    size: const Size(320, 568),
  );
  return state;
}

void main() {
  testWidgets(
    'KK086 page offers the existing subject notebook by its real subject ID',
    (tester) async {
      final calls = <http.Request>[];
      await open(tester, calls);
      await f.tap(tester, find.text('Zugehörigen Fachhefter öffnen'));
      expect(
        find.text('Ziel /library/child/subject/${'b' * 32}'),
        findsOneWidget,
      );
      expect(calls.where((r) => r.method != 'GET'), isEmpty);
    },
  );
  testWidgets(
    'KK087 own source correction can be cancelled or reverted without changing stored content',
    (tester) async {
      final calls = <http.Request>[];
      await open(tester, calls);
      await f.tap(tester, find.text('Etwas verbessern'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Text auf der Seite'),
        'Meine falsche Korrektur',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await f.tap(tester, find.text('Eigene Korrektur zurücknehmen'));
      await f.tap(tester, find.text('Weiter verbessern'));
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Text auf der Seite'),
            )
            .controller!
            .text,
        'Meine falsche Korrektur',
      );
      await f.tap(tester, find.text('Eigene Korrektur zurücknehmen'));
      await f.tap(tester, find.text('Gespeicherten Text wiederherstellen'));
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Text auf der Seite'),
            )
            .controller!
            .text,
        contains('Fläche = Länge mal Breite'),
      );
      expect(calls.where((r) => r.method != 'GET'), isEmpty);
    },
  );
  testWidgets(
    'KK088 source lookup finds whole verified lines and has a clear zero result at 200 percent',
    (tester) async {
      final calls = <http.Request>[];
      await open(tester, calls, scale: 2, saved: true);
      await f.tap(tester, find.text('Im Seitentext nachsehen'));
      await tester.enterText(f.input('Wort oder Textstelle finden'), 'Volumen');
      await tester.pumpAndSettle();
      expect(find.textContaining('1 passende Textzeilen'), findsOneWidget);
      await tester.enterText(f.input('Wort oder Textstelle finden'), 'nichts');
      await tester.pumpAndSettle();
      expect(find.text('Keine passende Textzeile gefunden.'), findsOneWidget);
      await f.tap(tester, find.text('Zurück zur Heftseite'));
      expect(tester.takeException(), isNull);
      expect(calls.where((r) => r.method != 'GET'), isEmpty);
    },
  );
  testWidgets(
    'KK089 copying source text is explicit and includes only the current displayed text',
    (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(call.arguments['text']);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await open(tester, []);
      expect(copied, isEmpty);
      await f.tap(tester, find.text('Aktuellen Seitentext kopieren'));
      expect(copied.single, contains('Volumen = Länge mal Breite mal Höhe'));
    },
  );
  testWidgets(
    'KK093 a page explicitly without an original image remains readable without requesting a broken photo',
    (tester) async {
      final calls = <http.Request>[];
      await open(tester, calls, saved: true);
      expect(calls.any((r) => r.url.path.endsWith('/image')), isFalse);
      expect(find.text('Heftfoto vergrößern'), findsNothing);
      expect(find.text('Im Seitentext nachsehen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final familyChange in [false, true]) {
    testWidgets(
      'KK012 private source reader closes after ${familyChange ? 'family switch' : 'same-ID fresh session'} and old close is harmless',
      (tester) async {
        final state = await open(tester, []);
        await f.tap(tester, find.text('Im Seitentext nachsehen'));
        final close = tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Zurück zur Heftseite'),
            )
            .onPressed!;
        if (familyChange) {
          state.familyId = 'other-family';
        } else {
          state.user = {...state.user!};
        }
        state.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.text('In deinem Seitentext nachsehen'), findsNothing);
        close();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
