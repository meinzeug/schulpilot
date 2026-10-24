import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';

import 'schulbuddy_test.dart' as f;

const _intro =
    'Ich helfe dir Schritt für Schritt zu verstehen. Probiere selbst mit; ich verrate nicht gleich die Lösung. KI kann Fehler machen.';
const _notice =
    'Schulbuddy erklärt und fragt nach. Chatantworten sind ungeprüfte Hilfe, keine bewerteten Aufgaben oder Kompetenznachweise.';

Json _context(
  String page, {
  List<Json> history = const [],
  bool available = true,
  String notice = _notice,
}) => {
  ...f.contextResult(page, history: history, available: available),
  'notice': notice,
};

void _expectIntroduction(bool visible) {
  expect(find.text(_intro), visible ? findsOneWidget : findsNothing);
  expect(find.text(_notice), visible ? findsOneWidget : findsNothing);
}

void _disposeChat(WidgetTester tester) {
  // Dispose polling and text controllers before the harness router teardown.
  addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
}

Future<void> _enterQuestion(WidgetTester tester, String value) async {
  await tester.ensureVisible(f.field());
  await tester.enterText(f.field(), value);
  await tester.pump();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final size in [(390.0, 844.0, 1.0), (320.0, 568.0, 2.0)]) {
    testWidgets(
      'an empty chat retains its introduction for a draft and hides it immediately on send at $size',
      (tester) async {
        final sent = Completer<http.Response>();
        final h = await f.open(
          tester,
          width: size.$1,
          height: size.$2,
          scale: size.$3,
          respond: (request) async => request.method == 'POST'
              ? sent.future
              : f.reply(_context('today')),
        );
        _disposeChat(tester);
        await f.tap(tester, find.text('Buddy öffnen'));
        _expectIntroduction(true);
        await _enterQuestion(tester, 'Meine eigene Frage');
        _expectIntroduction(true);
        expect(h.calls.every((request) => request.method == 'GET'), isTrue);

        final send = find.widgetWithText(FilledButton, 'Frage senden');
        await tester.ensureVisible(send);
        await tester.tap(send);
        await tester.pump();
        _expectIntroduction(false);
        expect(find.text('Frage wird gesendet …'), findsOneWidget);
        expect(tester.widget<TextField>(f.field()).readOnly, isTrue);
        final posts = h.calls.where((request) => request.method == 'POST');
        expect(posts, hasLength(1));
        expect(jsonDecode(posts.single.body)['question'], 'Meine eigene Frage');

        sent.complete(f.reply({...f.turn(), 'question': 'Meine eigene Frage'}));
        await tester.pumpAndSettle();
        _expectIntroduction(false);
        expect(find.text('Schulbuddy · KI'), findsOneWidget);
        expect(
          find.textContaining('Betrachte zuerst, was gesucht ist.'),
          findsOneWidget,
        );
        await tester.ensureVisible(f.field());
        expect(f.field().hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final status in ['ready', 'queued', 'failed']) {
    testWidgets(
      'saved $status conversations hide introductions on open, refresh and reopen without sending',
      (tester) async {
        final h = await f.open(
          tester,
          respond: (_) async =>
              f.reply(_context('today', history: [f.turn(status: status)])),
        );
        _disposeChat(tester);
        await f.tap(tester, find.text('Buddy öffnen'));
        _expectIntroduction(false);
        expect(find.text('Wie beginne ich?'), findsOneWidget);
        expect(find.text('Schulbuddy · KI'), findsOneWidget);
        if (status == 'queued') {
          expect(find.textContaining('Schulbuddy denkt nach'), findsOneWidget);
        } else if (status == 'failed') {
          expect(
            find.textContaining('Diese Antwort konnte nicht erstellt werden.'),
            findsOneWidget,
          );
        }
        await f.tap(tester, find.byTooltip('Gespräch aktualisieren'));
        _expectIntroduction(false);
        await f.tap(tester, find.byTooltip('Schulbuddy schließen'));
        await f.tap(tester, find.text('Buddy öffnen'));
        _expectIntroduction(false);
        expect(find.text('Wie beginne ich?'), findsOneWidget);
        expect(h.calls.every((request) => request.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'the accessible info control toggles both hints locally and leaves more visible room for the transcript',
    (tester) async {
      final h = await f.open(
        tester,
        respond: (_) async => f.reply(_context('today', history: [f.turn()])),
      );
      _disposeChat(tester);
      await f.tap(tester, find.text('Buddy öffnen'));
      _expectIntroduction(false);
      final question = find.text('Wie beginne ich?');
      expect(question.hitTestable(), findsOneWidget);
      final compactTop = tester.getTopLeft(question).dy;
      final before = h.calls.length;
      final info = find.byTooltip('Hinweise anzeigen');
      expect(info.hitTestable(), findsOneWidget);
      expect(tester.getSize(info).shortestSide, greaterThanOrEqualTo(48));
      await f.tap(tester, info);
      _expectIntroduction(true);
      final expandedTop = tester.getTopLeft(question).dy;
      expect(expandedTop, greaterThan(compactTop));
      await f.tap(tester, find.byTooltip('Hinweise ausblenden'));
      _expectIntroduction(false);
      expect(tester.getTopLeft(question).dy, lessThan(expandedTop));
      expect(question.hitTestable(), findsOneWidget);
      final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(
        tester.getRect(question).bottom,
        lessThanOrEqualTo(viewport.height),
      );
      expect(h.calls.length, before);
      expect(h.calls.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening a new empty page context restores hints without mixing the previous conversation or sending',
    (tester) async {
      final h = await f.open(
        tester,
        respond: (request) async {
          final page = request.url.queryParameters['page_kind'] ?? 'today';
          return f.reply(
            _context(page, history: page == 'today' ? [f.turn()] : []),
          );
        },
      );
      _disposeChat(tester);
      await f.tap(tester, find.text('Buddy öffnen'));
      await f.tap(tester, find.byTooltip('Hinweise anzeigen'));
      await f.tap(tester, find.byTooltip('Hinweise ausblenden'));
      _expectIntroduction(false);
      await f.tap(tester, find.byTooltip('Schulbuddy schließen'));
      h.router.go('/learn/${f.child}');
      await tester.pumpAndSettle();
      await f.tap(tester, find.text('Buddy öffnen'));
      expect(find.text('Gespräch: Bereich learn'), findsOneWidget);
      expect(find.text('Zur aktuellen Seite wechseln'), findsNothing);
      _expectIntroduction(true);
      expect(find.text('Wie beginne ich?'), findsNothing);
      expect(tester.widget<TextField>(f.field()).controller!.text, isEmpty);
      expect(h.calls.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final status in [422, 503]) {
    testWidgets(
      'a $status send error keeps the explanation and draft while the introduction stays hidden through reload',
      (tester) async {
        const message = 'Die Beispielanfrage ist gerade nicht möglich.';
        final h = await f.open(
          tester,
          respond: (request) async => request.method == 'POST'
              ? f.reply({'detail': message}, status)
              : f.reply(_context('today')),
        );
        _disposeChat(tester);
        await f.tap(tester, find.text('Buddy öffnen'));
        await _enterQuestion(tester, 'Meine noch offene Frage');
        await f.tap(tester, find.text('Frage senden'));
        _expectIntroduction(false);
        expect(find.text(message), findsOneWidget);
        expect(
          tester.widget<TextField>(f.field()).controller!.text,
          'Meine noch offene Frage',
        );
        if (status == 503) {
          expect(
            find.text('Nachsehen, ob die Frage angekommen ist'),
            findsOneWidget,
          );
          expect(find.text('Dieselbe Frage erneut senden'), findsOneWidget);
        } else {
          expect(find.text('Dieselbe Frage erneut senden'), findsNothing);
        }
        await f.tap(tester, find.byTooltip('Gespräch aktualisieren'));
        _expectIntroduction(false);
        expect(
          tester.widget<TextField>(f.field()).controller!.text,
          'Meine noch offene Frage',
        );
        expect(
          h.calls.where((request) => request.method == 'POST'),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a failed refresh preserves the saved transcript and visible error without restoring introductory text',
    (tester) async {
      var fail = false;
      final h = await f.open(
        tester,
        respond: (_) async => fail
            ? f.reply({
                'detail': 'Gespräch konnte nicht aktualisiert werden.',
              }, 503)
            : f.reply(_context('today', history: [f.turn()])),
      );
      _disposeChat(tester);
      await f.tap(tester, find.text('Buddy öffnen'));
      fail = true;
      await f.tap(tester, find.byTooltip('Gespräch aktualisieren'));
      _expectIntroduction(false);
      expect(
        find.text('Gespräch konnte nicht aktualisiert werden.'),
        findsOneWidget,
      );
      expect(find.text('Wie beginne ich?'), findsOneWidget);
      expect(
        find.textContaining('Betrachte zuerst, was gesucht ist.'),
        findsOneWidget,
      );
      expect(h.calls.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a distinct server notice remains visible in an available conversation and when general hints are toggled',
    (tester) async {
      const notice = 'Bitte prüfe die aktuelle Zuordnung deiner Heftseite.';
      final h = await f.open(
        tester,
        respond: (_) async =>
            f.reply(_context('today', history: [f.turn()], notice: notice)),
      );
      _disposeChat(tester);
      await f.tap(tester, find.text('Buddy öffnen'));
      expect(find.text(_intro), findsNothing);
      expect(find.text(notice), findsOneWidget);
      await f.tap(tester, find.byTooltip('Hinweise anzeigen'));
      expect(find.text(_intro), findsOneWidget);
      expect(find.text(notice), findsOneWidget);
      await f.tap(tester, find.byTooltip('Hinweise ausblenden'));
      expect(find.text(_intro), findsNothing);
      expect(find.text(notice), findsOneWidget);
      expect(h.calls.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final notice in [
    'Neue Fragen sind in diesem Bereich gesperrt.',
    _notice,
  ]) {
    testWidgets('a read-only conversation retains its server notice: $notice', (
      tester,
    ) async {
      final h = await f.open(
        tester,
        width: 320,
        height: 568,
        scale: 2,
        respond: (_) async => f.reply(
          _context(
            'today',
            available: false,
            history: [f.turn()],
            notice: notice,
          ),
        ),
      );
      _disposeChat(tester);
      await f.tap(tester, find.text('Buddy öffnen'));
      expect(find.text(_intro), findsNothing);
      expect(find.text(notice), findsOneWidget);
      expect(find.byTooltip('Hinweise anzeigen'), findsNothing);
      expect(find.byTooltip('Hinweise ausblenden'), findsNothing);
      expect(
        find.textContaining('Betrachte zuerst, was gesucht ist.'),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(f.field());
      expect(field.enabled, isFalse);
      expect(field.readOnly, isTrue);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Frage senden'),
            )
            .onPressed,
        isNull,
      );
      expect(h.calls.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
