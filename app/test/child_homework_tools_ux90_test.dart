import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/lesson_voice.dart';

import 'homework_screen_test.dart' as h;
import 'child_homework_continuity_test.dart' as c;
import 'child_local_tools_ux88_test.dart' as f;

Uint8List picture() =>
    Uint8List.fromList(image.encodePng(image.Image(width: 3, height: 3)));
void pendingPhoto(AppState state) {
  state.collectionViews['homework_photo:child'] = {
    'account': state.user,
    'family': state.familyId,
    'bytes': picture(),
    'key': 'same-original-upload-key',
    'updated': DateTime.now().millisecondsSinceEpoch,
  };
}

void main() {
  testWidgets(
    'CK007 local unsent homework photo can be inspected without uploading',
    (tester) async {
      final requests = <http.Request>[];
      final state = h.account(
        MockClient((r) async {
          requests.add(r);
          return h.reply({'photos': [], 'next_cursor': null});
        }),
      );
      pendingPhoto(state);
      await h.open(tester, state, overview: true);
      await h.tap(tester, 'Foto in Ruhe ansehen');
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(
        find.text('Nur auf diesem Gerät · noch nicht abgegeben'),
        findsOneWidget,
      );
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'CK008 and CK009 cancelling replacement selection keeps the old photo and upload key',
    (tester) async {
      final requests = <http.Request>[];
      final state = h.account(
        MockClient((r) async {
          requests.add(r);
          return h.reply({'photos': [], 'next_cursor': null});
        }),
      );
      pendingPhoto(state);
      await h.open(tester, state, overview: true);
      await h.tap(tester, 'Anderes Foto nehmen');
      expect(find.text('Abbrechen'), findsOneWidget);
      await h.tap(tester, 'Abbrechen');
      expect(
        find.text('Dieses Foto ist noch nicht abgegeben.'),
        findsOneWidget,
      );
      expect(
        state.collectionViews['homework_photo:child']!['key'],
        'same-original-upload-key',
      );
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'CK010 successful upload is distinguished from pending OCR registration',
    (tester) async {
      final registering = Completer<http.Response>();
      final requests = <http.Request>[];
      final state = h.account(
        MockClient((r) async {
          requests.add(r);
          if (r.url.path.endsWith('/extract')) return registering.future;
          if (r.method == 'POST') return h.reply({'id': 'photo'});
          if (r.url.path.endsWith('/homework') &&
              !r.url.path.contains('/materials/')) {
            return h.reply({'photos': [], 'next_cursor': null});
          }
          return h.reply(h.fixture());
        }),
      );
      pendingPhoto(state);
      await h.open(tester, state, overview: true);
      final send = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Foto erneut senden'),
          )
          .onPressed!;
      send();
      await c.flush(tester);
      expect(
        find.text('Foto gespeichert · Lesen wird angemeldet …'),
        findsOneWidget,
      );
      expect(find.text('Dieses Foto ist noch nicht abgegeben.'), findsNothing);
      expect(requests.where((r) => r.method == 'POST'), hasLength(2));
      registering.complete(h.reply({'id': 'extract'}));
      await c.flush(tester);
    },
  );
  testWidgets(
    'CK050 same-session navigation restores unsent photo without resending it',
    (tester) async {
      var posts = 0;
      final state = h.account(
        MockClient((r) async {
          if (r.method == 'POST') posts++;
          return h.reply(
            r.url.path.contains('/materials/')
                ? h.fixture()
                : {'photos': [], 'next_cursor': null},
          );
        }),
      );
      pendingPhoto(state);
      final router = await c.mount(tester, state, overview: true);
      router.go('/homework/child/photo');
      await tester.pumpAndSettle();
      router.go('/homework/child');
      await tester.pumpAndSettle();
      expect(
        find.text('Dieses Foto ist noch nicht abgegeben.'),
        findsOneWidget,
      );
      expect(posts, 0);
    },
  );
  testWidgets(
    'CK051 current homework citation offers its exact original source and no other source',
    (tester) async {
      final turn = h.modelTurn();
      turn['reply']['sources'] = [
        {'quote': 'Eigener belegter Text', 'material_id': 'photo'},
        {'quote': 'Nicht passende Quelle', 'material_id': 'other'},
      ];
      final state = h.account(
        MockClient(
          (r) async => h.reply(h.fixture(turns: [h.analysisTurn(), turn])),
        ),
      );
      await h.open(tester, state);
      await h.tap(tester, 'Bezug zur Aufgabe');
      expect(find.text('Aufgabenquelle ansehen'), findsOneWidget);
    },
  );
  testWidgets(
    'CK063 photo timeline sorts actual upload dates instead of displaying an open deadline',
    (tester) async {
      final state = h.account(
        MockClient(
          (r) async => h.reply({
            'photos': [
              {
                'id': 'new',
                'title': 'Neueres Foto',
                'topic': 'Neueres Foto',
                'confirmed': true,
                'created': 1792533600,
                'subject': 'Mathematik',
              },
              {
                'id': 'old',
                'title': 'Älteres Foto',
                'topic': 'Älteres Foto',
                'confirmed': true,
                'created': 1792447200,
                'subject': 'Deutsch',
              },
            ],
            'next_cursor': null,
          }),
        ),
      );
      await h.open(tester, state, overview: true);
      await h.tap(tester, 'Fotos zeitlich finden');
      await f.tap(tester, find.byType(DropdownButtonFormField<String>));
      await f.tap(tester, find.text('Älteste zuerst').last);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .toList();
      expect(
        texts.indexOf('Älteres Foto'),
        lessThan(texts.indexOf('Neueres Foto')),
      );
      expect(find.textContaining('Termin noch offen'), findsNothing);
      expect(find.textContaining('20.10.2026'), findsWidgets);
    },
  );
  testWidgets(
    'CK064 reopening homework restores the last photo page by authorized GET',
    (tester) async {
      final requests = <http.Request>[];
      final state = h.account(
        MockClient((r) async {
          requests.add(r);
          if (r.url.path.contains('/materials/')) return h.reply(h.fixture());
          final older = r.url.queryParameters['cursor'] == 'older-page';
          return h.reply({
            'photos': [
              {
                'id': older ? 'photo' : 'first',
                'title': older ? 'Altes Aufgabenfoto' : 'Neues Aufgabenfoto',
                'topic': older ? 'Altes Aufgabenfoto' : 'Neues Aufgabenfoto',
                'confirmed': true,
                'subject': 'Mathematik',
              },
            ],
            'next_cursor': older ? null : 'older-page',
          });
        }),
      );
      final router = await c.mount(tester, state, overview: true);
      await h.tap(tester, 'Weitere Fotos');
      await h.tap(tester, 'Altes Aufgabenfoto');
      router.go('/homework/child');
      await tester.pumpAndSettle();
      expect(requests.last.url.queryParameters['cursor'], 'older-page');
      expect(find.text('Altes Aufgabenfoto'), findsOneWidget);
      expect(find.text('Neues Aufgabenfoto'), findsNothing);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'CK065 saved homework helpers are searchable without a new AI request',
    (tester) async {
      final state = h.account(
        MockClient(
          (r) async =>
              h.reply(h.fixture(turns: [h.analysisTurn(), h.modelTurn()])),
        ),
      );
      await h.open(tester, state);
      await h.tap(tester, 'Lernhilfen zu diesem Foto');
      await tester.enterText(
        f.input('Geladene Lernhilfen durchsuchen'),
        'Rechtecks',
      );
      await tester.pump();
      expect(find.text('1 von 1 geladenen Lernhilfen'), findsOneWidget);
      await tester.enterText(
        f.input('Geladene Lernhilfen durchsuchen'),
        'Nicht vorhanden',
      );
      await tester.pump();
      expect(
        find.text('Hier passt keine geladene Lernhilfe zu deiner Suche.'),
        findsOneWidget,
      );
      await h.tap(tester, 'Zurück zu meinen Hausaufgaben');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'CK066 explicit whole-photo checklist changes only self-reported checkmarks',
    (tester) async {
      final writes = <Json>[];
      final state = h.account(
        MockClient((r) async {
          if (r.method == 'PUT') {
            writes.add(Json.from(jsonDecode(r.body)));
            return h.reply({'revision': 4});
          }
          return h.reply(h.fixture(draft: 'Mein Text'));
        }),
      );
      await h.open(tester, state);
      await h.tap(tester, 'Meine Checkliste abhaken');
      expect(find.textContaining('kein Lernnachweis'), findsOneWidget);
      await h.tap(tester, 'Checkliste abhaken');
      expect(writes.single['done'], ['t1']);
      expect(writes.single['draft'], 'Mein Text');
      expect(writes.single.containsKey('outcome'), isFalse);
    },
  );
  testWidgets(
    'CK067 question dictation is explicit correctable and never auto-submitted',
    (tester) async {
      final requests = <http.Request>[];
      final state = h.account(
        MockClient((r) async {
          requests.add(r);
          return h.reply(h.fixture());
        }),
      );
      await h.open(tester, state);
      final control = tester.widget<VoiceInputButton>(
        find.byType(VoiceInputButton),
      );
      expect(
        control.controller,
        tester.widget<TextField>(f.input('Meine Frage')).controller,
      );
      expect(control.locale, 'de-DE');
      expect(control.maxLength, 1000);
      await f.tap(tester, find.byType(VoiceInputButton));
      expect(find.textContaining('Sprachdienst'), findsWidgets);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'CK068 help understanding check leads to own attempt without overwriting text',
    (tester) async {
      final state = h.account(
        MockClient(
          (r) async => h.reply(
            h.fixture(
              draft: 'Mein Ansatz',
              turns: [h.analysisTurn(), h.modelTurn()],
            ),
          ),
        ),
      );
      await h.open(tester, state);
      await h.tap(tester, 'Nächsten Schritt selbst versuchen');
      final input = tester.widget<TextField>(f.input('Mein eigener Versuch'));
      expect(input.focusNode!.hasFocus, isTrue);
      expect(input.controller!.text, 'Mein Ansatz');
    },
  );
}
