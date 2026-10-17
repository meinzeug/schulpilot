import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/codex_model_picker.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/ui.dart';

// Invented names describe local mocked catalog entries, never live model IDs.
Json config({
  String provider = 'codex',
  String model = 'fixture-alpha',
  String reasoning = 'medium',
  String photo = '',
}) => {
  'provider': provider,
  'model': model,
  'extraction_model': photo,
  'reasoning_effort': reasoning,
  'has_key': false,
  'status': 'Künstliche Testkonfiguration',
  'emergency_stop': false,
  'image_capable': true,
  'structured_capable': true,
  'privacy_approved': false,
  'capability_evidence': '',
  'extraction_capability_evidence': '',
  'privacy_evidence': '',
  'reserve_micros': 1000,
  'input_per_million_micros': null,
  'output_per_million_micros': null,
  'pricing_evidence': '',
  'max_output_tokens': 4000,
  'global_limit_micros': 10000000,
};

Json catalogModel(
  String id,
  String name,
  List<String> efforts,
  String defaultEffort, {
  List<String> inputs = const ['text', 'image'],
  bool hidden = false,
}) => {
  'id': id,
  'name': name,
  'reasoning_efforts': efforts,
  'default_reasoning_effort': defaultEffort,
  'input_modalities': inputs,
  'hidden': hidden,
};

Json catalog({List<Json>? models}) => {
  'models':
      models ??
      [
        catalogModel('fixture-alpha', 'Alpha', [
          'low',
          'medium',
          'high',
        ], 'medium'),
        catalogModel('fixture-beta', 'Beta', ['low', 'high'], 'high'),
        catalogModel('fixture-photo', 'Foto', ['low'], 'low'),
        catalogModel(
          'fixture-text',
          'Nur Text',
          ['low', 'medium'],
          'medium',
          inputs: ['text'],
        ),
        catalogModel('fixture-other', 'Andere Denkstufe', [
          'minimal',
        ], 'minimal'),
      ],
  'source': 'codex_cli',
  'cli_version': '0.162.1',
};

http.Response response(Json body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Finder pickerDropdown(String kind) => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButtonFormField<String> &&
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('codex-$kind-'),
);

String? selected(WidgetTester tester, String kind) => tester
    .widget<DropdownButtonFormField<String>>(pickerDropdown(kind))
    .initialValue;

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> select(WidgetTester tester, String kind, String label) async {
  await tap(tester, pickerDropdown(kind));
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> mount(
  WidgetTester tester, {
  required Future<http.Response> Function(http.Request) handler,
  Json? saved,
  String endpoint = '/admin/provider',
  double width = 390,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState(
    api: Api(base: 'https://example.invalid/api', client: MockClient(handler)),
  )..user = {'id': 'test-operator', 'role': 'admin'};
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ProviderForm(
              state,
              saved ?? config(),
              endpoint: endpoint,
              onRefresh: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'catalog loading preserves model and reasoning without a text ID field',
    (tester) async {
      final pending = Completer<http.Response>();
      final requests = <String>[];
      await mount(
        tester,
        handler: (request) async {
          requests.add(request.url.path);
          return pending.future;
        },
      );
      expect(find.text('Codex-Modelle werden geladen …'), findsOneWidget);
      expect(selected(tester, 'lesson'), 'fixture-alpha');
      expect(selected(tester, 'reasoning'), 'medium');
      expect(
        find.text('Modell-ID für Lerneinheiten (laut Anbieter)'),
        findsNothing,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(pickerDropdown('lesson'))
            .onChanged,
        isNull,
      );
      pending.complete(response(catalog()));
      await tester.pumpAndSettle();
      expect(requests, ['/api/admin/provider/codex/models']);
      expect(selected(tester, 'lesson'), 'fixture-alpha');
      expect(selected(tester, 'reasoning'), 'medium');
      expect(selected(tester, 'photo'), '');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit model switch visibly adapts reasoning and saves both fields',
    (tester) async {
      Json? written;
      await mount(
        tester,
        handler: (request) async {
          if (request.method == 'GET') return response(catalog());
          expect(request.method, 'PUT');
          expect(request.url.path, '/api/admin/provider');
          written = jsonDecode(request.body) as Json;
          return response({'status': 'Gespeichert'});
        },
      );
      await tester.pumpAndSettle();
      await select(tester, 'lesson', 'Beta (fixture-beta)');
      expect(selected(tester, 'lesson'), 'fixture-beta');
      expect(selected(tester, 'reasoning'), 'high');
      expect(
        find.textContaining('Denkstufe auf high angepasst'),
        findsOneWidget,
      );
      await tap(tester, find.text('Konfiguration sicher speichern'));
      expect(written?['provider'], 'codex');
      expect(written?['model'], 'fixture-beta');
      expect(written?['reasoning_effort'], 'high');
      expect(written?['extraction_model'], '');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'supported reasoning survives a model switch and explicit reasoning can be saved',
    (tester) async {
      Json? written;
      await mount(
        tester,
        saved: config(reasoning: 'low'),
        handler: (request) async {
          if (request.method == 'GET') return response(catalog());
          written = jsonDecode(request.body) as Json;
          return response({});
        },
      );
      await tester.pumpAndSettle();
      await select(tester, 'lesson', 'Beta (fixture-beta)');
      expect(selected(tester, 'reasoning'), 'low');
      expect(find.textContaining('Denkstufe auf'), findsNothing);
      await select(tester, 'reasoning', 'high');
      await tap(tester, find.text('Konfiguration sicher speichern'));
      expect(written?['reasoning_effort'], 'high');
    },
  );

  testWidgets(
    'photo choices are image capable and reasoning is shared by both models',
    (tester) async {
      Json? written;
      await mount(
        tester,
        saved: config(reasoning: 'high'),
        handler: (request) async {
          if (request.method == 'GET') return response(catalog());
          written = jsonDecode(request.body) as Json;
          return response({});
        },
      );
      await tester.pumpAndSettle();
      await tap(tester, pickerDropdown('photo'));
      expect(find.text('Nur Text (fixture-text)'), findsNothing);
      await tester.tap(find.text('Foto (fixture-photo)').last);
      await tester.pumpAndSettle();
      expect(selected(tester, 'reasoning'), 'low');
      final reasoning = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: pickerDropdown('reasoning'),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(
        reasoning.items!
            .where((item) => item.enabled)
            .map((item) => item.value),
        ['low'],
      );
      await tap(tester, find.text('Konfiguration sicher speichern'));
      expect(written?['extraction_model'], 'fixture-photo');
      expect(written?['reasoning_effort'], 'low');
    },
  );

  testWidgets(
    'a photo model default is used when the lesson default is unsupported',
    (tester) async {
      await mount(
        tester,
        saved: config(reasoning: 'high'),
        handler: (_) async => response(
          catalog(
            models: [
              catalogModel('fixture-alpha', 'Alpha', [
                'low',
                'medium',
                'high',
              ], 'high'),
              catalogModel('fixture-photo', 'Foto', [
                'low',
                'medium',
              ], 'medium'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await select(tester, 'photo', 'Foto (fixture-photo)');
      expect(selected(tester, 'reasoning'), 'medium');
      expect(
        find.textContaining('Denkstufe auf medium angepasst'),
        findsOneWidget,
      );
    },
  );

  testWidgets('incompatible model pair remains visible and cannot be saved', (
    tester,
  ) async {
    var writes = 0;
    await mount(
      tester,
      handler: (request) async {
        if (request.method == 'GET') return response(catalog());
        writes++;
        return response({});
      },
    );
    await tester.pumpAndSettle();
    await select(tester, 'photo', 'Andere Denkstufe (fixture-other)');
    expect(selected(tester, 'photo'), 'fixture-other');
    expect(selected(tester, 'reasoning'), 'medium');
    expect(find.textContaining('keine gemeinsame Denkstufe'), findsOneWidget);
    await tap(tester, find.text('Konfiguration sicher speichern'));
    expect(writes, 0);
    expect(find.textContaining('keine gemeinsame Denkstufe'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'catalog outage preserves a saved route and retries only explicitly',
    (tester) async {
      var loads = 0;
      Json? written;
      await mount(
        tester,
        saved: config(model: 'fixture-old', reasoning: 'xhigh'),
        handler: (request) async {
          if (request.method == 'GET') {
            loads++;
            return loads == 1
                ? response({
                    'detail':
                        'Der isolierte Modelldienst ist nicht erreichbar.',
                  }, 503)
                : response(catalog());
          }
          written = jsonDecode(request.body) as Json;
          return response({});
        },
      );
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(
        find.text('Der isolierte Modelldienst ist nicht erreichbar.'),
        findsOneWidget,
      );
      expect(selected(tester, 'lesson'), 'fixture-old');
      expect(selected(tester, 'reasoning'), 'xhigh');
      await tap(tester, find.text('Konfiguration sicher speichern'));
      expect(written?['model'], 'fixture-old');
      expect(written?['reasoning_effort'], 'xhigh');
      await tap(tester, find.text('Modelle neu laden'));
      expect(loads, 2);
      expect(selected(tester, 'lesson'), 'fixture-old');
      expect(selected(tester, 'reasoning'), 'xhigh');
      expect(
        find.textContaining('Gespeicherte Auswahl bleibt erhalten.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching provider ignores a pending catalog and retains ordinary model input',
    (tester) async {
      final pending = Completer<http.Response>();
      Json? written;
      await mount(
        tester,
        handler: (request) async {
          if (request.method == 'GET') return pending.future;
          written = jsonDecode(request.body) as Json;
          return response({});
        },
      );
      final provider = find.byType(DropdownButtonFormField<String>).first;
      await tester.ensureVisible(provider);
      await tester.pump();
      await tester.tap(provider);
      // The pending load still animates, so avoid pumpAndSettle until switching.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('OpenAI API').last);
      await tester.pumpAndSettle();
      expect(find.byType(CodexModelPicker), findsNothing);
      pending.complete(response(catalog()));
      await tester.pumpAndSettle();
      expect(
        find.text('Modell-ID für Lerneinheiten (laut Anbieter)'),
        findsOneWidget,
      );
      expect(find.text('Codex-Modelle werden geladen …'), findsNothing);
      await tap(tester, find.text('Konfiguration sicher speichern'));
      expect(written?['provider'], 'openai');
      expect(written?['model'], 'fixture-alpha');
      expect(written!.containsKey('reasoning_effort'), false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('initial setup loads its protected model endpoint', (
    tester,
  ) async {
    final requests = <String>[];
    await mount(
      tester,
      endpoint: '/setup/provider',
      handler: (request) async {
        requests.add(request.url.path);
        return response(catalog());
      },
    );
    await tester.pumpAndSettle();
    expect(requests, ['/api/setup/provider/codex/models']);
    expect(selected(tester, 'lesson'), 'fixture-alpha');
  });

  testWidgets(
    'a model without reasoning does not invalidate the other catalog entries',
    (tester) async {
      await mount(
        tester,
        handler: (_) async => response(
          catalog(
            models: [
              ...(catalog()['models'] as List<Json>),
              catalogModel('fixture-no-effort', 'Ohne Denkstufe', [], 'medium'),
              catalogModel(
                'fixture-hidden',
                'Weitere Option',
                ['medium'],
                'medium',
                hidden: true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Die Modellliste ist unvollständig. Bitte neu laden.'),
        findsNothing,
      );
      expect(selected(tester, 'lesson'), 'fixture-alpha');
      final lesson = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: pickerDropdown('lesson'),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(
        lesson.items!
            .singleWhere((item) => item.value == 'fixture-no-effort')
            .enabled,
        false,
      );
      expect(
        lesson.items!
            .singleWhere((item) => item.value == 'fixture-hidden')
            .enabled,
        true,
      );
      expect(
        find.text('Modellzugriff wird mit dem Prüflauf bestätigt.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a text-only main model requires an explicit compatible photo model',
    (tester) async {
      final writes = <Json>[];
      await mount(
        tester,
        handler: (request) async {
          if (request.method == 'GET') return response(catalog());
          writes.add(jsonDecode(request.body) as Json);
          return response({});
        },
      );
      await tester.pumpAndSettle();
      await select(tester, 'lesson', 'Nur Text (fixture-text)');
      expect(selected(tester, 'photo'), '');
      expect(find.textContaining('kann keine Fotos lesen'), findsOneWidget);
      await tap(tester, find.text('Konfiguration sicher speichern'));
      expect(writes, isEmpty);
      await select(tester, 'photo', 'Foto (fixture-photo)');
      expect(selected(tester, 'reasoning'), 'low');
      await tap(tester, find.text('Konfiguration sicher speichern'));
      expect(writes.single['model'], 'fixture-text');
      expect(writes.single['extraction_model'], 'fixture-photo');
      expect(writes.single['reasoning_effort'], 'low');
    },
  );

  testWidgets(
    'new Codex routing cannot be saved while its catalog is unavailable',
    (tester) async {
      var reads = 0, writes = 0;
      await mount(
        tester,
        saved: config(provider: 'openai'),
        handler: (request) async {
          if (request.method == 'GET') {
            reads++;
            return response({'detail': 'Modellkatalog nicht erreichbar.'}, 503);
          }
          writes++;
          return response({});
        },
      );
      await tester.pumpAndSettle();
      expect(reads, 0);
      await tap(tester, find.byType(DropdownButtonFormField<String>).first);
      await tester.tap(find.text('Codex CLI · experimentell').last);
      await tester.pumpAndSettle();
      expect(reads, 1);
      await tap(tester, find.text('Konfiguration sicher speichern'));
      expect(writes, 0);
      expect(find.byType(CodexModelPicker), findsOneWidget);
      expect(
        find.textContaining('bevor du eine andere Auswahl speicherst'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'OpenRouter retains ordinary editable model fields without catalog requests',
    (tester) async {
      final writes = <Json>[];
      await mount(
        tester,
        saved: config(provider: 'openrouter'),
        handler: (request) async {
          expect(request.method, 'PUT');
          writes.add(jsonDecode(request.body) as Json);
          return response({});
        },
      );
      await tester.pumpAndSettle();
      expect(find.byType(CodexModelPicker), findsNothing);
      expect(
        find.text('Modell-ID für Lerneinheiten (laut Anbieter)'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Abweichendes Bildmodell (optional, sonst Modell für Lerneinheiten)',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Konfiguration sicher speichern'));
      expect(writes.single['provider'], 'openrouter');
      expect(writes.single.containsKey('reasoning_effort'), false);
    },
  );

  testWidgets('malformed catalog is rejected without replacing saved choices', (
    tester,
  ) async {
    await mount(
      tester,
      handler: (_) async => response(
        catalog(
          models: [
            catalogModel('fixture-alpha', 'Alpha', ['low'], 'medium'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Die Modellliste ist unvollständig. Bitte neu laden.'),
      findsOneWidget,
    );
    expect(selected(tester, 'lesson'), 'fixture-alpha');
    expect(selected(tester, 'reasoning'), 'medium');
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('provider choices fit a $width pixel viewport', (tester) async {
      await mount(
        tester,
        width: width,
        handler: (_) async => response(catalog()),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(pickerDropdown('lesson'));
      await tester.pumpAndSettle();
      final lesson = tester.getRect(pickerDropdown('lesson'));
      final reasoning = tester.getRect(pickerDropdown('reasoning'));
      expect(lesson.left, greaterThanOrEqualTo(0));
      expect(lesson.right, lessThanOrEqualTo(width));
      expect(reasoning.top, greaterThan(lesson.bottom));
      await tap(tester, pickerDropdown('lesson'));
      expect(find.text('Beta (fixture-beta)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
