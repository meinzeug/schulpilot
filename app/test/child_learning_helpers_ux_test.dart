import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_explanation.dart';
import 'package:schulpilot/lesson_voice.dart';
import 'package:schulpilot/material_screen.dart';
import 'package:schulpilot/subject_picker.dart';
import 'package:schulpilot/ui.dart';

import 'lesson_voice_test.dart' as vf;

Widget home(Widget child) => MaterialApp(
  theme: appTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
http.Response reply(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
AppState account(MockClient client) => AppState(
  api: Api(base: 'https://example.invalid/api', client: client),
)..user = {'id': 'child-user', 'role': 'child', 'child_id': 'child'};
Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final prompt in [
    '-1/3 + 1/6',
    '− 1/3 + 1/6',
    '101/3 + 1/6',
    '0.1/3 + 1/6',
    '1/3 + 1/6 + 1/4',
    '1/3 + 1/6 * 2',
    '1/3 + 1/6.5',
  ]) {
    testWidgets('K021 unsupported fraction expression: $prompt', (
      tester,
    ) async {
      await tester.pumpWidget(home(FractionSumDiagram(prompt: prompt)));
      expect(find.text('1 · Zwei gleich große Ganze'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'K022 K023 new question resets explanation and announces its step',
    (tester) async {
      final semantics = tester.ensureSemantics();

      const text = 'Erster kurzer Absatz.\n\nZweiter kurzer Absatz.';
      await tester.pumpWidget(
        home(const LearningExplanation(text: text, prompt: '1/3 + 1/6')),
      );
      await tap(tester, find.text('Nächster Schritt'));
      expect(find.text('Schritt 2 von 2'), findsOneWidget);
      await tester.pumpWidget(
        home(const LearningExplanation(text: text, prompt: '1/4 + 1/8')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Schritt 1 von 2'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.text('Schritt 1 von 2'))
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      semantics.dispose();
    },
  );
  testWidgets('K024 fraction cells stay readable at 320px and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 900),
            textScaler: TextScaler.linear(2),
          ),
          child: const Scaffold(
            body: SingleChildScrollView(
              child: FractionSumDiagram(prompt: '1/8 + 1/24'),
            ),
          ),
        ),
      ),
    );
    await tap(tester, find.text('Gleich einteilen'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('K025 lowercase sentence starts do not prevent readable chunks', (
    tester,
  ) async {
    final text = List.filled(
      10,
      'dies ist ein längerer erklärender Satz mit einem kleinen Beispiel.',
    ).join(' ');
    await tester.pumpWidget(home(LearningExplanation(text: text)));
    expect(find.textContaining('Schritt 1 von'), findsOneWidget);
  });
  testWidgets('K027 reading preparation is single flight and explicit', (
    tester,
  ) async {
    final adapter = vf.FakeLessonVoice();
    final voice = LessonVoiceSession(adapter: adapter);
    addTearDown(voice.dispose);
    final preparation = Completer<void>();
    var saves = 0;
    await tester.pumpWidget(
      home(
        ReadAloudButton(
          text: 'Künstlicher Text',
          voice: voice,
          beforeRead: () {
            saves++;
            return preparation.future;
          },
        ),
      ),
    );
    expect(adapter.reads, 0);
    final callback = tester
        .widget<TextButton>(find.byType(TextButton))
        .onPressed!;
    callback();
    callback();
    await tester.pump();
    expect(saves, 1);
    expect(find.text('Vorlesen wird vorbereitet …'), findsOneWidget);
    preparation.complete();
    await tester.pump();
    await tester.pump();
    expect(adapter.reads, 1);
    await voice.stop();
    await tester.pumpAndSettle();
  });
  testWidgets('K027 old reading preparation cannot speak a newer question', (
    tester,
  ) async {
    final adapter = vf.FakeLessonVoice();
    final voice = LessonVoiceSession(adapter: adapter);
    addTearDown(voice.dispose);
    final preparation = Completer<void>();
    await tester.pumpWidget(
      home(
        ReadAloudButton(
          text: 'Alter Text',
          voice: voice,
          beforeRead: () => preparation.future,
        ),
      ),
    );
    tester.widget<TextButton>(find.byType(TextButton)).onPressed!();
    await tester.pump();
    await tester.pumpWidget(
      home(ReadAloudButton(text: 'Neuer Text', voice: voice)),
    );
    preparation.complete();
    await tester.pumpAndSettle();
    expect(adapter.reads, 0);
  });
  testWidgets('K028 speech input retains complete graphemes at its limit', (
    tester,
  ) async {
    final adapter = vf.FakeLessonVoice();
    final voice = LessonVoiceSession(adapter: adapter);
    final controller = TextEditingController();
    addTearDown(voice.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(vf.inputHome(voice, controller, maxLength: 3));
    await vf.confirmSpeech(tester);
    adapter.result!('a😀éz');
    await tester.pump();
    expect(controller.text, 'a😀é');
    expect(controller.selection.extentOffset, controller.text.length);
    await voice.stop();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'K029 K030 permission waiting and recording deadline are explained',
    (tester) async {
      final adapter = vf.FakeLessonVoice()..permission = Completer<void>();
      final voice = LessonVoiceSession(adapter: adapter);
      final controller = TextEditingController(text: 'Eigener Anfang');
      addTearDown(voice.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(vf.inputHome(voice, controller));
      await vf.confirmSpeech(tester);
      expect(find.text('Mikrofon wird vorbereitet · Stoppen'), findsOneWidget);
      adapter.permission!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Aufnahme stoppen'), findsOneWidget);
      await tester.pump(const Duration(seconds: 36));
      await tester.pumpAndSettle();
      expect(find.textContaining('nach 35 Sekunden beendet'), findsOneWidget);
      expect(controller.text, 'Eigener Anfang');
      expect(adapter.listens, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K067 K068 K070 subjects support keyboard search and selected semantics',
    (tester) async {
      var gets = 0;
      final controller = TextEditingController(text: 'Mathematik');
      addTearDown(controller.dispose);
      final state = account(
        MockClient((_) async {
          gets++;
          return reply({
            'items': [
              {'id': 'math', 'title': 'Mathematik'},
              {'id': 'chem', 'title': 'Chemie'},
            ],
          });
        }),
      );
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        home(
          SubjectField(
            state,
            childId: 'child',
            controller: controller,
            enabled: true,
            changed: () {},
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Fach suchen'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.widgetWithText(ListTile, 'Mathematik'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      await tester.enterText(find.byType(TextField), 'Chem');
      await tester.pump();
      expect(find.widgetWithText(ListTile, 'Mathematik'), findsNothing);
      await tap(tester, find.text('Chemie'));
      expect(controller.text, 'Chemie');
      expect(gets, 1);
      semantics.dispose();
    },
  );
  testWidgets('K068 empty subject search offers an explicit reset', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final state = account(
      MockClient(
        (_) async => reply({
          'items': [
            {'id': 'math', 'title': 'Mathematik'},
          ],
        }),
      ),
    );
    await tester.pumpWidget(
      home(
        SubjectField(
          state,
          childId: 'child',
          controller: controller,
          enabled: true,
          changed: () {},
        ),
      ),
    );
    await tap(tester, find.text('Fach auswählen'));
    await tester.enterText(find.byType(TextField), 'xxxx');
    await tester.pump();
    expect(find.text('Kein Fach passt zu deiner Suche.'), findsOneWidget);
    await tap(tester, find.text('Suche leeren'));
    expect(find.text('Mathematik'), findsOneWidget);
  });
  testWidgets('K069 an empty subject catalog is explained', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final state = account(MockClient((_) async => reply({'items': []})));
    await tester.pumpWidget(
      home(
        SubjectField(
          state,
          childId: 'child',
          controller: controller,
          enabled: true,
          changed: () {},
        ),
      ),
    );
    await tap(tester, find.text('Fach auswählen'));
    expect(find.textContaining('keine Fächer verfügbar'), findsOneWidget);
  });
  testWidgets(
    'subject dialog closes on a same-ID new login without popping newer UI',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final state = account(
        MockClient(
          (_) async => reply({
            'items': [
              {'id': 'math', 'title': 'Privates Fach'},
            ],
          }),
        ),
      );
      await tester.pumpWidget(
        home(
          SubjectField(
            state,
            childId: 'child',
            controller: controller,
            enabled: true,
            changed: () {},
          ),
        ),
      );
      await tap(tester, find.text('Fach auswählen'));
      final stale = tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Privates Fach'))
          .onTap!;
      state.user = {...state.user!};
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Privates Fach'), findsNothing);
      final ctx = tester.element(find.byType(SubjectField));
      unawaited(
        showDialog<void>(
          context: ctx,
          builder: (_) => const AlertDialog(title: Text('Neuer Dialog')),
        ),
      );
      await tester.pumpAndSettle();
      stale();
      await tester.pumpAndSettle();
      expect(find.text('Neuer Dialog'), findsOneWidget);
      expect(controller.text, isEmpty);
    },
  );
  testWidgets('K057 an unreadable crop is explained before submission', (
    tester,
  ) async {
    await tester.pumpWidget(home(CropDialog(Uint8List.fromList([1, 2, 3]))));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Dieses Bild kann nicht gelesen werden.'),
      findsOneWidget,
    );
    expect(
      tester.widget<ActionButton>(find.byType(ActionButton)).enabled,
      isFalse,
    );
    expect(find.text('Anderes Foto wählen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'K058 K059 crop bounds survive rotation and have a full-photo reset',
    (tester) async {
      final bytes = Uint8List.fromList(
        image.encodeJpg(image.Image(width: 40, height: 30)),
      );
      await tester.pumpWidget(home(CropDialog(bytes)));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Bild zuschneiden'));
      tester.widget<Slider>(find.byType(Slider).first).onChanged!(.2);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tap(tester, find.text('Um 90° drehen'));
      }
      expect(
        tester.widget<Slider>(find.byType(Slider).first).value,
        closeTo(.2, .00001),
      );
      await tap(tester, find.text('Ganzes Foto verwenden'));
      expect(tester.widget<Slider>(find.byType(Slider).first).value, 0);
      expect(tester.widget<Slider>(find.byType(Slider).at(2)).value, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
