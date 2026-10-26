// Synthetic local protocol checks. No real account, provider or network.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/schulbuddy.dart';

import 'schulbuddy_saved_explanation_131_test.dart' as saved;
import 'schulbuddy_test.dart' as buddy;

const starter = 'Erkläre mir diese Grafik';

// The relevant public BuddyScope/BuddyQuestion contract from
// backend/schulpilot/schulbuddy_schemas.py: graphic_index strict int0..5,
// material_revision strict int1..1e9, exam_revision integer>=1; references
// remain strings and a graphic requires its unit/kind/step. This does not
// substitute for backend authority, source or stored-graphic validation.
bool matchesScope(Json body) {
  const integerBounds = <String, (int, int?)>{
    'graphic_index': (0, 5),
    'material_revision': (1, 1000000000),
    'exam_revision': (1, null),
  };
  const stringFields = {
    'page_kind',
    'child_id',
    'learning_asset_instance_id',
    'unit_id',
    'material_id',
    'day_id',
    'question_id',
    'exam_id',
    'exam_session_id',
    'review_task_id',
    'exam_tab',
    'explanation_kind',
    'explanation_step_id',
    'graphic_phase',
    'lab_view',
    'question',
    'reply_to',
  };
  if (!body.keys.every(
    (key) => stringFields.contains(key) || integerBounds.containsKey(key),
  )) {
    return false;
  }
  for (final field in integerBounds.entries) {
    if (!body.containsKey(field.key)) continue;
    final value = body[field.key];
    if (value is! int ||
        value < field.value.$1 ||
        (field.value.$2 != null && value > field.value.$2!)) {
      return false;
    }
  }
  if (stringFields.any(
    (key) => body.containsKey(key) && body[key] is! String,
  )) {
    return false;
  }
  if (body['question'] is! String ||
      (body['question'] as String).trim().isEmpty) {
    return false;
  }
  if (body.containsKey('material_revision') &&
      !body.containsKey('material_id')) {
    return false;
  }
  if (body.containsKey('explanation_step_id')) {
    if (!body.containsKey('unit_id') ||
        !const ['intro', 'question'].contains(body['explanation_kind'])) {
      return false;
    }
    if (body['explanation_kind'] == 'question' &&
        !body.containsKey('question_id')) {
      return false;
    }
  } else if (body.containsKey('graphic_index') ||
      body.containsKey('graphic_phase') ||
      body.containsKey('explanation_kind')) {
    return false;
  }
  if (body.containsKey('graphic_phase') && !body.containsKey('graphic_index')) {
    return false;
  }
  return true;
}

class ScopeCheckingServer {
  final calls = <http.Request>[];
  final bool failFirst;
  Json? accepted;
  int rejected = 0;
  ScopeCheckingServer({this.failFirst = false});

  List<http.Request> get posts =>
      calls.where((r) => r.method == 'POST').toList();
  List<http.Request> get contexts =>
      calls.where((r) => r.url.path.endsWith('/schulbuddy/context')).toList();

  Future<http.Response> handle(http.Request request) async {
    calls.add(request);
    if (request.url.path.endsWith('/image')) {
      expect(request.method, 'GET');
      return http.Response.bytes(
        image.encodePng(image.Image(width: 2, height: 2)),
        200,
      );
    }
    if (request.url.path.endsWith('/visual-position')) {
      expect(request.method, 'GET');
      return buddy.reply({
        'source_signature': 'a' * 64,
        'revision': 1,
        'position': null,
      });
    }
    if (request.url.path.endsWith('/schulbuddy/context')) {
      expect(request.method, 'GET');
      return buddy.reply({
        ...buddy.contextResult(
          request.url.queryParameters['page_kind'] ?? 'learn',
        ),
        'starters': [starter],
        'history': accepted == null
            ? <Json>[]
            : [
                {
                  ...accepted!,
                  'status': 'ready',
                  'answer': 'Künstliche gespeicherte Antwort.',
                },
              ],
      });
    }
    expect(request.url.path, '/api/schulbuddy/questions');
    expect(request.method, 'POST');
    final body = Json.from(jsonDecode(request.body));
    if (!matchesScope(body)) {
      rejected++;
      return buddy.reply({'detail': 'Input should be a valid integer'}, 422);
    }
    expect(request.headers['Idempotency-Key'], isNotEmpty);
    if (failFirst && posts.length == 1) {
      return buddy.reply({
        'detail': 'Künstlicher unklarer Transportausgang.',
      }, 503);
    }
    accepted = {
      ...buddy.turn(status: 'queued', key: request.headers['Idempotency-Key']),
      'question': body['question'],
    };
    return buddy.reply(accepted!);
  }
}

class TypedSavedFixture extends saved.SavedExplanationFixture {
  final server = ScopeCheckingServer();
  late final AppState _typedState =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient(server.handle),
          ),
        )
        ..user = {
          'id': 'synthetic-reader',
          'role': 'child',
          'child_id': saved.childId,
        }
        ..familyId = 'synthetic-family'
        ..api.token = 'synthetic-token';
  @override
  AppState get state => _typedState;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('132 only the three known JSON integer references change type; query and strings remain exact', () {
    const references = {
      'unit_id': saved.unitId,
      'question_id': 'q2',
      'explanation_kind': 'question',
      'explanation_step_id': 'e1',
      'graphic_index': '0',
      'graphic_phase': 'initial',
      'material_revision': '7',
      'exam_revision': '4',
      'lab_view': '{"version":1,"recipe_id":"physics.force_motion"}',
    };
    const context = SchulbuddyContext('learn', references);
    final body = context.fields;
    expect(body['graphic_index'], allOf(isA<int>(), 0));
    expect(body['material_revision'], allOf(isA<int>(), 7));
    expect(body['exam_revision'], allOf(isA<int>(), 4));
    for (final key in references.keys.where(
      (key) => !const [
        'graphic_index',
        'material_revision',
        'exam_revision',
      ].contains(key),
    )) {
      expect(body[key], references[key]);
      expect(body[key], isA<String>());
    }
    expect(context.references, references);
    expect(Uri.parse(context.path).queryParameters, {
      'page_kind': 'learn',
      ...references,
    });
  });

  test('132 invalid numeric values are not zeroed, omitted or accepted by the strict scope oracle', () {
    for (final sample in [
      ('graphic_index', '-1'),
      ('graphic_index', '6'),
      ('graphic_index', '1.5'),
      ('graphic_index', 'true'),
      ('graphic_index', '0x00'),
      ('graphic_index', '00'),
      ('graphic_index', ''),
      ('material_revision', '0'),
      ('material_revision', '1000000001'),
      ('material_revision', '1.5'),
      ('exam_revision', '0'),
      ('exam_revision', 'unknown'),
    ]) {
      final context = SchulbuddyContext('learn', {
        'unit_id': saved.unitId,
        'question_id': 'q2',
        'explanation_kind': 'question',
        'explanation_step_id': 'e1',
        if (sample.$1 == 'material_revision') 'material_id': buddy.unit,
        sample.$1: sample.$2,
      });
      final body = {...context.fields, 'question': starter};
      expect(body.containsKey(sample.$1), isTrue);
      expect(matchesScope(body), isFalse, reason: '${sample.$1}=${sample.$2}');
      expect(Uri.parse(context.path).queryParameters[sample.$1], sample.$2);
      if (sample.$2 != '0') expect(body[sample.$1], isNot(0));
    }
    const validScope = SchulbuddyContext('learn', {
      'unit_id': saved.unitId,
      'question_id': 'q2',
      'explanation_kind': 'question',
      'explanation_step_id': 'e1',
      'graphic_index': '0',
      'graphic_phase': 'initial',
    });
    expect(
      matchesScope({
        'page_kind': 'learn',
        ...validScope.references,
        'question': starter,
      }),
      isFalse,
      reason: 'The oracle must reject the exact legacy string-index body.',
    );
    expect(matchesScope({...validScope.fields, 'question': starter}), isTrue);
    final oversized = SchulbuddyContext('learn', {
      'graphic_index': '9007199254740993',
    });
    expect(oversized.fields['graphic_index'], '9007199254740993');
  });

  testWidgets(
    '132 actual nested saved explanation starter sends typed index once, polls and returns unchanged',
    (tester) async {
      final fixture = TypedSavedFixture();
      await fixture.mount(tester);
      await fixture.openSaved(tester);
      await fixture.openBuddy(tester);
      final server = fixture.server;
      expect(server.posts, isEmpty);
      expect(server.contexts.last.url.queryParameters['graphic_index'], '0');
      expect(
        server.contexts.last.url.queryParameters['explanation_kind'],
        'question',
      );
      expect(
        server.contexts.last.url.queryParameters['explanation_step_id'],
        'e1',
      );
      await buddy.tap(tester, find.text(starter));
      expect(server.posts, hasLength(1));
      expect(server.rejected, 0);
      final body = Json.from(jsonDecode(server.posts.single.body));
      expect(matchesScope(body), isTrue);
      expect(body['graphic_index'], allOf(isA<int>(), 0));
      expect(body['unit_id'], saved.unitId);
      expect(body['question_id'], 'q2');
      expect(body['explanation_step_id'], 'e1');
      expect(body['graphic_phase'], 'initial');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Künstliche gespeicherte Antwort.'), findsOneWidget);
      expect(server.posts, hasLength(1));
      expect(server.contexts, hasLength(greaterThanOrEqualTo(2)));
      await buddy.tap(tester, find.byTooltip('Schulbuddy schließen'));
      expect(find.text('Kurz erklärt'), findsOneWidget);
      expect(find.text('1 von 2 gleich großen Teilen.'), findsWidgets);
      expect(server.calls.where((r) => r.method == 'PUT'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '132 actual original-photo context keeps revision query text but starter POST has integer revision',
    (tester) async {
      final server = ScopeCheckingServer();
      await buddy.open(tester, photoEntry: true, respond: server.handle);
      await buddy.tap(tester, find.text('Foto groß öffnen'));
      await buddy.tap(tester, find.byTooltip('Schulbuddy öffnen'));
      expect(
        server.contexts.last.url.queryParameters['material_revision'],
        '7',
      );
      expect(server.posts, isEmpty);
      await buddy.tap(tester, find.text(starter));
      expect(server.posts, hasLength(1));
      expect(server.rejected, 0);
      final body = Json.from(jsonDecode(server.posts.single.body));
      expect(matchesScope(body), isTrue);
      expect(body['material_revision'], allOf(isA<int>(), 7));
      expect(body['material_id'], buddy.unit);
      expect(body.containsKey('graphic_index'), isFalse);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await buddy.tap(tester, find.byTooltip('Schulbuddy schließen'));
      expect(find.text('Heftfoto'), findsOneWidget);
      expect(server.posts, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '132 uncertain typed send retries the same body and key only after explicit action',
    (tester) async {
      final server = ScopeCheckingServer(failFirst: true);
      await buddy.open(tester, photoEntry: true, respond: server.handle);
      await buddy.tap(tester, find.text('Foto groß öffnen'));
      await buddy.tap(tester, find.byTooltip('Schulbuddy öffnen'));
      await buddy.tap(tester, find.text(starter));
      expect(server.posts, hasLength(1));
      expect(server.accepted, isNull);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(server.posts, hasLength(1));
      await buddy.tap(tester, find.byTooltip('Schulbuddy schließen'));
      await buddy.tap(tester, find.byTooltip('Schulbuddy öffnen'));
      expect(server.posts, hasLength(1));
      await buddy.tap(tester, find.text('Dieselbe Frage erneut senden'));
      expect(server.posts, hasLength(2));
      expect(server.rejected, 0);
      expect(server.posts[0].body, server.posts[1].body);
      expect(server.posts[0].headers['Idempotency-Key'], isNotEmpty);
      expect(
        server.posts[0].headers['Idempotency-Key'],
        server.posts[1].headers['Idempotency-Key'],
      );
      expect(
        jsonDecode(server.posts[1].body)['material_revision'],
        allOf(isA<int>(), 7),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(server.posts, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
}
