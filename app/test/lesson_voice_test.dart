import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/lesson_voice.dart';

class FakeLessonVoice implements LessonVoiceAdapter {
  int reads = 0, listens = 0, cancellations = 0;
  String? readText;
  String? readLocale, listenLocale;
  bool? readSlow;
  bool recording = false;
  LessonVoiceFailure? readFailure, listenFailure;
  Completer<void>? reading, permission;
  ValueChanged<String>? result;
  VoidCallback? finished;
  ValueChanged<LessonVoiceFailure>? failed;

  @override
  Future<void> read(
    String text, {
    required bool Function() isActive,
    String locale = 'de-DE',
    bool slow = false,
  }) async {
    reads++;
    readText = text;
    readLocale = locale;
    readSlow = slow;
    if (readFailure != null) throw readFailure!;
    reading = Completer<void>();
    await reading!.future;
  }

  @override
  Future<void> listen({
    String locale = 'de-DE',
    required bool Function() isActive,
    required VoidCallback onStarted,
    required ValueChanged<String> onText,
    required VoidCallback onDone,
    required ValueChanged<LessonVoiceFailure> onError,
  }) async {
    listens++;
    listenLocale = locale;
    if (listenFailure != null) throw listenFailure!;
    if (permission != null) await permission!.future;
    if (!isActive()) return;
    recording = true;
    result = onText;
    finished = onDone;
    failed = onError;
    onStarted();
  }

  @override
  Future<void> cancel() async {
    cancellations++;
    recording = false;
    if (reading?.isCompleted == false) reading!.complete();
  }
}

Future<void> confirmSpeech(WidgetTester tester) async {
  await tester.tap(find.text('Sprechen'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Sprechen'),
    ),
  );
  await tester.pumpAndSettle();
}

Widget inputHome(
  LessonVoiceSession voice,
  TextEditingController controller, {
  VoidCallback? submit,
  int maxLength = 500,
}) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        TextField(controller: controller),
        VoiceInputButton(
          controller: controller,
          voice: voice,
          maxLength: maxLength,
        ),
        FilledButton(onPressed: submit ?? () {}, child: const Text('Senden')),
      ],
    ),
  ),
);

void main() {
  test(
    'Explicit English reading and German instructions keep their own locale',
    () async {
      final adapter = FakeLessonVoice();
      final voice = LessonVoiceSession(adapter: adapter);
      final owner = Object();
      final english = voice.read(
        owner,
        'Where is the school?',
        locale: 'en-GB',
        slow: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(adapter.readLocale, 'en-GB');
      expect(adapter.readSlow, isTrue);
      adapter.reading!.complete();
      expect(await english, isTrue);
      final german = voice.read(owner, 'Höre erst zu.', locale: 'de-DE');
      await Future<void>.delayed(Duration.zero);
      expect(adapter.readLocale, 'de-DE');
      adapter.reading!.complete();
      expect(await german, isTrue);
      voice.dispose();
    },
  );

  test(
    'Language change cancels preceding playback and STT uses answer locale',
    () async {
      final adapter = FakeLessonVoice();
      final voice = LessonVoiceSession(adapter: adapter);
      final owner = Object();
      final first = voice.read(owner, 'Apfel', locale: 'de-DE');
      await Future<void>.delayed(Duration.zero);
      final second = voice.read(owner, 'apple', locale: 'en-US');
      await Future<void>.delayed(Duration.zero);
      expect(await first, isFalse);
      expect(adapter.readLocale, 'en-US');
      adapter.reading!.complete();
      expect(await second, isTrue);
      String? transcript;
      await voice.listen(owner, (text) => transcript = text, locale: 'en-GB');
      expect(adapter.listenLocale, 'en-GB');
      adapter.result!('I go to school');
      expect(transcript, 'I go to school');
      await voice.stop(owner: owner);
      expect(adapter.recording, isFalse);
      voice.dispose();
    },
  );

  test(
    'Missing English voice is a failure and never a completed hearing stimulus',
    () async {
      final adapter = FakeLessonVoice()
        ..readFailure = const LessonVoiceFailure('Englische Stimme fehlt.');
      final voice = LessonVoiceSession(adapter: adapter);
      expect(await voice.read(Object(), 'apple', locale: 'en-GB'), isFalse);
      expect(voice.message, contains('Stimme fehlt'));
      voice.dispose();
    },
  );
  testWidgets('Reading starts only on tap and has an immediate stop control', (
    tester,
  ) async {
    final adapter = FakeLessonVoice();
    final voice = LessonVoiceSession(adapter: adapter);
    addTearDown(voice.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadAloudButton(text: 'Künstlicher Lerntext.', voice: voice),
        ),
      ),
    );
    expect(adapter.reads, 0);
    expect(adapter.listens, 0);
    expect(adapter.cancellations, 0);
    await tester.tap(find.text('Vorlesen'));
    await tester.pumpAndSettle();
    expect(adapter.reads, 1);
    expect(adapter.readText, 'Künstlicher Lerntext.');
    expect(find.text('Vorlesen stoppen'), findsOneWidget);
    await tester.tap(find.text('Vorlesen stoppen'));
    await tester.pumpAndSettle();
    expect(voice.mode, LessonVoiceMode.idle);
    expect(find.text('Vorlesen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Missing voice is reported without inventing successful playback',
    (tester) async {
      final adapter = FakeLessonVoice()
        ..readFailure = const LessonVoiceFailure(
          'Keine deutsche Stimme verfügbar.',
        );
      final voice = LessonVoiceSession(adapter: adapter);
      addTearDown(voice.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReadAloudButton(text: 'Beispielstoff.', voice: voice),
          ),
        ),
      );
      await tester.tap(find.text('Vorlesen'));
      await tester.pumpAndSettle();
      expect(find.text('Keine deutsche Stimme verfügbar.'), findsOneWidget);
      expect(find.text('Vorlesen stoppen'), findsNothing);
      expect(voice.mode, LessonVoiceMode.idle);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Microphone notice can be declined before any initialization', (
    tester,
  ) async {
    final adapter = FakeLessonVoice();
    final voice = LessonVoiceSession(adapter: adapter);
    final text = TextEditingController(text: 'Mein eigener Text');
    addTearDown(voice.dispose);
    addTearDown(text.dispose);
    await tester.pumpWidget(inputHome(voice, text));
    expect(adapter.listens, 0);
    await tester.tap(find.text('Sprechen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('an seinen Sprachdienst'), findsOneWidget);
    expect(adapter.listens, 0);
    await tester.tap(find.text('Lieber tippen'));
    await tester.pumpAndSettle();
    expect(adapter.listens, 0);
    expect(text.text, 'Mein eigener Text');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Dictated words remain editable and never submit themselves', (
    tester,
  ) async {
    final adapter = FakeLessonVoice();
    final voice = LessonVoiceSession(adapter: adapter);
    final text = TextEditingController(text: 'Ich weiß:');
    var submissions = 0;
    addTearDown(voice.dispose);
    addTearDown(text.dispose);
    await tester.pumpWidget(
      inputHome(voice, text, submit: () => submissions++),
    );
    await confirmSpeech(tester);
    expect(adapter.recording, isTrue);
    adapter.result!('Der Nenner');
    await tester.pump();
    expect(text.text, 'Ich weiß: Der Nenner');
    adapter.result!('Der Nenner steht unten.');
    await tester.pump();
    expect(text.text, 'Ich weiß: Der Nenner steht unten.');
    expect(submissions, 0);
    await tester.enterText(find.byType(TextField), 'Meine geprüfte Antwort');
    await tester.pump();
    expect(adapter.recording, isFalse);
    adapter.result!('Spätes Ergebnis');
    expect(text.text, 'Meine geprüfte Antwort');
    expect(submissions, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Permission refusal keeps typing available', (tester) async {
    final adapter = FakeLessonVoice()
      ..listenFailure = const LessonVoiceFailure('Mikrofon nicht freigegeben.');
    final voice = LessonVoiceSession(adapter: adapter);
    final text = TextEditingController();
    addTearDown(voice.dispose);
    addTearDown(text.dispose);
    await tester.pumpWidget(inputHome(voice, text));
    await confirmSpeech(tester);
    expect(find.text('Mikrofon nicht freigegeben.'), findsOneWidget);
    expect(voice.mode, LessonVoiceMode.idle);
    await tester.enterText(find.byType(TextField), 'Ich tippe weiter.');
    expect(text.text, 'Ich tippe weiter.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Stopping recording rejects later callbacks', (tester) async {
    final adapter = FakeLessonVoice();
    final voice = LessonVoiceSession(adapter: adapter);
    final text = TextEditingController();
    addTearDown(voice.dispose);
    addTearDown(text.dispose);
    await tester.pumpWidget(inputHome(voice, text));
    await confirmSpeech(tester);
    adapter.result!('Ein Bruch');
    await tester.pump();
    await tester.tap(find.text('Aufnahme stoppen'));
    await tester.pumpAndSettle();
    adapter.result!('Darf nicht mehr ergänzt werden');
    expect(text.text, 'Ein Bruch');
    expect(adapter.recording, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Backgrounding cancels capture and prevents delayed permission starts',
    (tester) async {
      final adapter = FakeLessonVoice()..permission = Completer<void>();
      final voice = LessonVoiceSession(adapter: adapter);
      final text = TextEditingController();
      addTearDown(voice.dispose);
      addTearDown(text.dispose);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await tester.pumpWidget(inputHome(voice, text));
      await confirmSpeech(tester);
      expect(voice.mode, LessonVoiceMode.preparing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      adapter.permission!.complete();
      await tester.pumpAndSettle();
      expect(adapter.recording, isFalse);
      expect(voice.mode, LessonVoiceMode.idle);
      expect(text.text, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Covering the learning route stops the microphone', (
    tester,
  ) async {
    final adapter = FakeLessonVoice();
    final voice = LessonVoiceSession(adapter: adapter);
    final text = TextEditingController();
    addTearDown(voice.dispose);
    addTearDown(text.dispose);
    await tester.pumpWidget(inputHome(voice, text));
    await confirmSpeech(tester);
    final context = tester.element(find.byType(VoiceInputButton));
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Andere Seite')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(adapter.recording, isFalse);
    expect(voice.mode, LessonVoiceMode.idle);
    adapter.result!('Veraltetes Ergebnis');
    expect(text.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'The app-side deadline ends recording without discarding recognized text',
    (tester) async {
      final adapter = FakeLessonVoice();
      final voice = LessonVoiceSession(adapter: adapter);
      final text = TextEditingController();
      addTearDown(voice.dispose);
      addTearDown(text.dispose);
      await tester.pumpWidget(inputHome(voice, text));
      await confirmSpeech(tester);
      adapter.result!('Gespeicherter Textentwurf');
      await tester.pump(const Duration(seconds: 36));
      expect(adapter.recording, isFalse);
      expect(voice.mode, LessonVoiceMode.idle);
      expect(text.text, 'Gespeicherter Textentwurf');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Disposing the input cancels its session and respects field length',
    (tester) async {
      final adapter = FakeLessonVoice();
      final voice = LessonVoiceSession(adapter: adapter);
      final text = TextEditingController(text: 'Bruch:');
      addTearDown(voice.dispose);
      addTearDown(text.dispose);
      await tester.pumpWidget(inputHome(voice, text, maxLength: 12));
      await confirmSpeech(tester);
      adapter.result!('ein Halbes und mehr');
      await tester.pump();
      expect(text.text.startsWith('Bruch:'), isTrue);
      expect(text.text.length, lessThanOrEqualTo(12));
      final before = text.text;
      await tester.pumpWidget(const SizedBox());
      expect(adapter.recording, isFalse);
      adapter.result!('Kein neuer Text nach Dispose');
      expect(text.text, before);
      expect(tester.takeException(), isNull);
    },
  );

  test('A pending start cannot outlive its owner', () async {
    final adapter = FakeLessonVoice();
    final voice = LessonVoiceSession(adapter: adapter);
    final owner = Object();
    final pending = voice.read(owner, 'Künstlicher Testtext');
    await voice.stop(owner: owner);
    await pending;
    expect(adapter.reads, 0);
    expect(voice.mode, LessonVoiceMode.idle);
    voice.dispose();
  });
}
