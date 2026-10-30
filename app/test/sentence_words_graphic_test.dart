import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/sentence_words_graphic.dart';
import 'package:schulpilot/subject_graphic.dart';
import 'package:schulpilot/ui.dart';

void main() {
  setUpAll(() async {
    for (final font in ['Nunito', 'SpaceGrotesk']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
    }
  });
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'literal sentence fits $width at scale $scale without a numbered word list',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            MaterialApp(
              theme: appTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: SubjectGraphic({
                      'kind': 'sentence',
                      'title': 'Satz zum Anschauen',
                      'disclosure': 'given',
                      'labels': ['Der', 'Hund', 'rennt', 'im', 'Park'],
                      'marks': [],
                    }),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final word in ['Der', 'Hund', 'rennt', 'im', 'Park']) {
            expect(find.text(word), findsOneWidget);
          }
          expect(find.text('1. Der'), findsNothing);
          expect(find.text('Der · Hund · rennt · im · Park'), findsNothing);
          expect(find.textContaining('Subjekt'), findsNothing);
          expect(
            find.bySemanticsLabel('Satz: Der Hund rennt im Park. '),
            findsOneWidget,
          );
          if (scale == 1) {
            expect(
              tester.getSize(find.byType(SentenceWordsGraphic)).height,
              lessThan(180),
            );
          }
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }
  testWidgets(
    'only disclosed server markings appear, including complete word groups',
    (tester) async {
      final data = {
        'version': 1,
        'blocks': [
          {
            'kind': 'sentence',
            'title': 'Gespeicherter Satz',
            'disclosure': 'hint2',
            'labels': ['Der Hund', 'rennt', 'im Park'],
            'marks': [
              {'index': 0, 'role': 'subject'},
              {'index': 1, 'role': 'predicate'},
            ],
          },
        ],
      };
      Widget app(Set<String> stages) => MaterialApp(
        theme: appTheme(),
        home: Scaffold(body: SubjectPresentation(data, stages: stages)),
      );
      await tester.pumpWidget(app({'given'}));
      expect(find.byType(SentenceWordsGraphic), findsNothing);
      await tester.pumpWidget(app({'hint2'}));
      expect(find.text('Der Hund'), findsOneWidget);
      expect(find.text('Subjekt – wer oder was?'), findsOneWidget);
      expect(find.text('Prädikat – was geschieht?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
