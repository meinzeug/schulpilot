// Local visual QA using the real task room. Never shipped or connected to an API.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/unit_screen.dart';
import 'package:schulpilot/ui.dart';

final List<dynamic> samples = jsonDecode(
  utf8.decode(base64Decode(const String.fromEnvironment('GRAPHICS'))),
)['cases'];
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(const Gallery());
}

class Gallery extends StatefulWidget {
  const Gallery({super.key});
  @override
  State<Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<Gallery> {
  late final AppState state;
  late final GoRouter router;
  final saved = <String, Json>{};
  final hintCounts = <String, int>{};
  int index = 0;
  bool large = false;
  Json unit(String id) => saved.putIfAbsent(id, () {
    final sample = samples[int.parse(id)];
    return {
      'id': id,
      'child_id': 'synthetic-child',
      'subject': sample['subject'],
      'topic': 'Künstliche Darstellungsprüfung',
      'status': 'active',
      'introduction_seen': true,
      'synthetic': false,
      'active_seconds_approx': 0,
      'explanation':
          'Künstlicher lokaler Test ohne KI und ohne gespeicherte Lernerfolge.',
      'pending_feedback': null,
      'questions': [
        {
          'id': 'q1',
          'type': 'choice',
          'prompt':
              '${sample['subject']}: Betrachte den bestätigten Stoff.\n\n${sample['source']}\n\nÖffne Hilfe, um die Darstellung zu prüfen.',
          'options': [r'\(\frac{1}{2}\)', r'\(x^2\)'],
          'attempts': <Json>[],
          'hints_used': 0,
          'hints': <String>[],
          'presentation': null,
          'explanation': 'Künstliche Prüfung.',
        },
      ],
    };
  });
  http.Response reply(Object data, [int code = 200]) => http.Response(
    jsonEncode(data),
    code,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  Future<http.Response> respond(http.Request request) async {
    final parts = request.url.pathSegments;
    final id = parts.length > 2 ? parts[2] : '0';
    final value = unit(id);
    if (request.method == 'GET') return reply(value);
    if (request.url.path.endsWith('/heartbeat')) {
      return reply({
        'status': 'active',
        'active_seconds_approx': 0,
        'break_recommended': false,
      });
    }
    if (request.url.path.endsWith('/hint')) {
      final sample = samples[int.parse(id)];
      final count = (hintCounts[id] ?? 0) + 1;
      hintCounts[id] = count;
      final p = Map<String, dynamic>.from(sample['question']['presentation']);
      p['blocks'] = [
        for (final b in p['blocks']) {...b as Map, 'disclosure': 'hint1'},
      ];
      value['questions'][0]['presentation'] = p;
      value['questions'][0]['hints_used'] = count;
      return reply({
        'hint': r'Der Bruch \(\frac{s}{t}\) zeigt ein Verhältnis. Prüfe auch die beschriftete Fachzeichnung.',
        'hints_used': count,
        'exhausted': count >= 3,
        'presentation': p,
      });
    }
    if (request.url.path.endsWith('/pause')) {
      value['status'] = 'paused';
      return reply(value);
    }
    if (request.url.path.endsWith('/start')) {
      value['status'] = 'active';
      return reply(value);
    }
    if (request.url.path.endsWith('/explanation')) {
      return reply({
        'explanation':
            r'Die lokale Erklärung setzt auch \[\int_0^1 x^2\,dx=\frac13\] und erhält Tabellen.'
            '\n\nA | B\n--- | ---\n1 | 2\n\n```python\nfor x in range(3):\n    print(x)\n```',
      });
    }
    return reply({
      'detail': 'Diese lokale Sichtprüfung speichert keine Antworten.',
    }, 409);
  }

  @override
  void initState() {
    super.initState();
    state =
        AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient(respond),
            ),
          )
          ..user = {
            'id': 'synthetic-user',
            'role': 'child',
            'child_id': 'synthetic-child',
            'display_name': 'Künstliche Sichtprüfung',
            'families': <Json>[],
          };
    router = GoRouter(
      initialLocation: '/unit/0',
      routes: [
        GoRoute(
          path: '/unit/:id',
          builder: (_, s) => UnitScreen(
            state,
            key: ValueKey(s.pathParameters['id']),
            unitId: s.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: '/app',
          builder: (_, _) => const Scaffold(body: Text('Lokale Prüfung')),
        ),
      ],
    );
  }

  @override
  void dispose() {
    router.dispose();
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    theme: appTheme(),
    routerConfig: router,
    builder: (context, child) => Center(
      child: SizedBox(
        width: 390,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: Size(390, MediaQuery.sizeOf(context).height),
            textScaler: TextScaler.linear(large ? 2 : 1),
          ),
          child: Column(
            children: [
              Material(
                color: surfaceLow,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Lokale Prüfung · künstliche Daten'),
                        Text(
                          '${index + 1}/${samples.length} ${samples[index]['id']}',
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            index = (index + 1) % samples.length;
                            router.go('/unit/$index');
                          }),
                          child: const Text('Nächstes Modell'),
                        ),
                        TextButton(
                          onPressed: () => setState(() => large = !large),
                          child: Text(large ? 'Schrift 100%' : 'Schrift 200%'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(child: child!),
            ],
          ),
        ),
      ),
    ),
  );
}
