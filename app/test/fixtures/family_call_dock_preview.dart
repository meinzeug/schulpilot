/// LOCAL PREVIEW ENTRY ONLY. Never a production/release target.
///
/// Uses the production FamilyCallHost/FamilyCallScreen and service, but every
/// request is caught by MockClient and every media surface is a drawing.
/// No login, provider, WebRTC peer, microphone, camera or display capture runs.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/family_call_media.dart';
import 'package:schulpilot/family_call_screen.dart';
import 'package:schulpilot/family_call_service.dart';
import 'package:schulpilot/ui.dart';

const _callId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _childId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _unitOne = '11111111111111111111111111111111';
const _unitTwo = '22222222222222222222222222222222';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setUrlStrategy(PathUrlStrategy(BrowserPlatformLocation(), true));
  runApp(const _DockPreview());
}

class _PreviewTransport {
  String? status;
  int sequence = 0;
  final List<Json> answers = [];

  Json metadata() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return {
      'id': _callId,
      'child_id': _childId,
      'child_name': 'Künstliches Testkind',
      'status': status ?? 'ended',
      'role': 'child',
      'is_participant': true,
      'created': now - 20,
      'accepted_at': status == 'accepted' ? now - 10 : null,
      'ring_expires': now + 45,
      'expires': now + 3600,
      'valid_until': now + 90,
      'server_now': now,
      'context_kind': 'learning',
      'context_id': _unitOne,
    };
  }

  http.Response _json(Object value) => http.Response(
    jsonEncode(value),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<http.Response> respond(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/family-calls/config')) {
      return _json({'available': true, 'notice': 'Nur synthetische Vorschau.'});
    }
    if (path.endsWith('/family-calls/active')) {
      return _json({
        'calls': ['ringing', 'accepted'].contains(status) ? [metadata()] : [],
      });
    }
    if (path.endsWith('/family-calls') && request.method == 'POST') {
      return _json(metadata());
    }
    if (path.endsWith('/end') || path.endsWith('/decline')) {
      status = 'ended';
      return _json(metadata());
    }
    if (path.endsWith('/ice')) return _json({'ice_servers': []});
    if (path.endsWith('/signals')) {
      if (request.method == 'POST') {
        final sent = Json.from(jsonDecode(request.body));
        final sentSequence = ++sequence;
        if (sent['kind'] == 'offer') {
          answers.add({
            'sequence': ++sequence,
            'kind': 'answer',
            'payload': {'sdp': 'synthetic-answer'},
          });
        }
        return _json({'sequence': sentSequence, 'status': 'accepted'});
      }
      final after =
          int.tryParse(request.url.queryParameters['after'] ?? '') ?? 0;
      return _json({
        'status': status,
        'signals': answers
            .where((answer) => answer['sequence'] > after)
            .toList(),
        'cursor': sequence,
      });
    }
    if (path.contains('/family-calls/')) return _json(metadata());
    // Never fall back to a real client, including links on the real call page.
    return _json({'synthetic': true, 'items': [], 'unread_count': 0});
  }

  void begin(String stage) {
    status = stage;
    sequence = 0;
    answers.clear();
  }
}

class _PreviewMedia extends FamilyCallMedia {
  bool _camera = true, _microphone = true, _sharing = false;
  bool _connected = false, _closed = false;

  @override
  bool get microphoneEnabled => !_closed && _microphone;
  @override
  bool get cameraEnabled => !_closed && _camera;
  @override
  bool get sharingScreen => !_closed && _sharing;
  @override
  bool get hasRemoteCamera => !_closed && _connected;
  @override
  bool get hasRemoteScreen => false;
  @override
  bool get remoteCameraFrameSeen => hasRemoteCamera;
  @override
  String get connectionState => _closed
      ? 'closed'
      : _connected
      ? 'connected'
      : 'new';

  @override
  Future<void> prepare({required bool camera}) async => _camera = camera;
  @override
  Future<void> connect(List<dynamic> iceServers) async {
    _connected = true;
    notifyListeners();
  }

  @override
  Future<Json> offer() async => {
    'sdp': 'synthetic-offer',
    'camera_stream_id': 'synthetic-local-camera',
    'screen_stream_id': _sharing ? 'synthetic-screen' : null,
  };
  @override
  Future<Json> answer(Json offer) async => {'sdp': 'synthetic-answer'};
  @override
  Future<void> receiveAnswer(Json answer) async {}
  @override
  Future<void> receiveIce(Json candidate) async {}
  @override
  Future<void> toggleMicrophone() async {
    _microphone = !_microphone;
    notifyListeners();
  }

  @override
  Future<bool> toggleCamera() async {
    _camera = !_camera;
    notifyListeners();
    return false;
  }

  @override
  Future<void> startScreen() async {
    _sharing = true;
    notifyListeners();
  }

  @override
  Future<void> stopScreen() async {
    _sharing = false;
    notifyListeners();
  }

  @override
  Widget video({required bool remote, bool screen = false}) =>
      _DrawnVideo(remote: remote, screen: screen);
  @override
  Future<void> close() async {
    _closed = true;
    _sharing = false;
    _connected = false;
  }
}

class _DrawnVideo extends StatelessWidget {
  final bool remote, screen;
  const _DrawnVideo({required this.remote, required this.screen});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: remote
            ? [const Color(0xff223b65), const Color(0xff322153)]
            : [const Color(0xff123c48), const Color(0xff152b4c)],
      ),
    ),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: const Color(0xff416787),
                child: Icon(
                  screen ? Icons.desktop_windows_rounded : Icons.person_rounded,
                  size: 43,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                screen
                    ? 'Beispielbildschirm'
                    : remote
                    ? 'Eltern · Platzhalter'
                    : 'Kind · Platzhalter',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'Synthetisches Bild',
                style: TextStyle(color: Color(0xffd0deed), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DockPreview extends StatefulWidget {
  const _DockPreview();
  @override
  State<_DockPreview> createState() => _DockPreviewState();
}

class _DockPreviewState extends State<_DockPreview> {
  final navigator = GlobalKey<NavigatorState>();
  final transport = _PreviewTransport();
  late final AppState state;
  late final GoRouter router;
  bool settingStage = false;

  void _appearanceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    state =
        AppState(
            api: Api(
              base: 'https://synthetic.invalid/api',
              client: MockClient(transport.respond),
            ),
            familyCallFactory: (state) => FamilyCallService(
              state,
              nativeEnabled: false,
              webPlatform: true,
              mediaFactory: _PreviewMedia.new,
              pollInterval: const Duration(milliseconds: 750),
              requestScreenPermission: () async => false,
            ),
          )
          ..user = {
            'id': 'synthetic-preview-child',
            'role': 'child',
            'child_id': _childId,
            'display_name': 'Testkind',
            'synthetic': true,
          };
    state.addListener(_appearanceChanged);
    router = GoRouter(
      navigatorKey: navigator,
      initialLocation: '/unit/$_unitOne',
      routes: [
        GoRoute(path: '/app', redirect: (_, _) => '/unit/$_unitOne'),
        GoRoute(path: '/learn/:child', redirect: (_, _) => '/unit/$_unitOne'),
        GoRoute(
          path: '/unit/:id',
          builder: (_, route) => _SyntheticTask(
            key: ValueKey(route.pathParameters['id']),
            state: state,
            second: route.pathParameters['id'] == _unitTwo,
          ),
        ),
        GoRoute(
          path: '/family-call/:id',
          builder: (_, route) =>
              FamilyCallScreen(state, callId: route.pathParameters['id']!),
        ),
      ],
      errorBuilder: (context, _) => PageFrame(
        state: state,
        title: 'Synthetische Vorschau',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Diese Seite gehört nicht zur lokalen Gesprächsvorschau.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => router.go('/unit/$_unitOne'),
              child: const Text('Zur Beispielaufgabe'),
            ),
          ],
        ),
      ),
    );
    state.familyCalls.activate(state.user);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_stage('accepted')),
    );
  }

  Future<void> _stage(String status) async {
    if (settingStage) return;
    setState(() => settingStage = true);
    try {
      if (state.familyCalls.live) await state.familyCalls.end();
      if (status != 'ended') {
        transport.begin(status);
        await state.familyCalls.start(
          contextKind: 'learning',
          contextId: _unitOne,
        );
        await state.familyCalls.refresh(force: true);
      }
    } finally {
      if (mounted) setState(() => settingStage = false);
    }
  }

  @override
  void dispose() {
    state.removeListener(_appearanceChanged);
    router.dispose();
    state.familyCalls.dispose();
    state.api.client.close();
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Synthetische Gesprächsdock-Vorschau',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    darkTheme: appTheme(brightness: Brightness.dark),
    themeMode: state.darkAppearance ? ThemeMode.dark : ThemeMode.light,
    routerConfig: router,
    builder: (context, child) => Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(Icons.science_outlined, size: 18),
                  const Text('Synthetische Vorschau · keine Kamera, keine KI'),
                  OutlinedButton(
                    onPressed: settingStage ? null : () => _stage('ringing'),
                    child: const Text('Klingeln'),
                  ),
                  OutlinedButton(
                    onPressed: settingStage ? null : () => _stage('accepted'),
                    child: const Text('Verbunden'),
                  ),
                  OutlinedButton(
                    onPressed: settingStage ? null : () => _stage('ended'),
                    child: const Text('Beenden'),
                  ),
                  IconButton(
                    tooltip: state.darkAppearance
                        ? 'Helles Design'
                        : 'Dunkles Design',
                    onPressed: () => state.setAppearance(!state.darkAppearance),
                    icon: Icon(
                      state.darkAppearance
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: router.routeInformationProvider,
            builder: (context, _) => FamilyCallHost(
              state,
              navigatorKey: navigator,
              currentPath: router.routeInformationProvider.value.uri.path,
              openCall: (id) => router.push('/family-call/$id'),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SyntheticTask extends StatefulWidget {
  final AppState state;
  final bool second;
  const _SyntheticTask({super.key, required this.state, required this.second});
  @override
  State<_SyntheticTask> createState() => _SyntheticTaskState();
}

class _SyntheticTaskState extends State<_SyntheticTask> {
  final answer = TextEditingController();
  bool? correct;

  @override
  void dispose() {
    answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Brüche addieren',
    subtitle:
        'Fiktive Aufgabe · Tippen, Feedback und Gespräch gemeinsam prüfen.',
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    context.go('/unit/${widget.second ? _unitOne : _unitTwo}'),
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text(
                  widget.second
                      ? 'Zur ersten Beispielaufgabe'
                      : 'Andere Beispielaufgabe öffnen',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Aufgabe ${widget.second ? 2 : 1} · synthetisch',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Addiere die Brüche.',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Fraction(
                        widget.second ? '2' : '1',
                        widget.second ? '5' : '4',
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 22),
                        child: Text('+', style: TextStyle(fontSize: 30)),
                      ),
                      _Fraction('1', widget.second ? '10' : '8'),
                      const Padding(
                        padding: EdgeInsets.only(left: 22),
                        child: Text('= ?', style: TextStyle(fontSize: 30)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  TextField(
                    key: const ValueKey('preview-answer-input'),
                    controller: answer,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Deine Antwort',
                      hintText: 'Bruch oder Rechenweg eingeben',
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    key: const ValueKey('preview-check-answer'),
                    onPressed: () => setState(() {
                      correct =
                          answer.text.replaceAll(' ', '').trim() ==
                          (widget.second ? '1/2' : '3/8');
                    }),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Beispielantwort prüfen'),
                  ),
                ],
              ),
            ),
            if (correct != null) ...[
              const SizedBox(height: 16),
              Panel(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      correct!
                          ? Icons.check_circle_outline_rounded
                          : Icons.lightbulb_outline_rounded,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        correct!
                            ? 'Das geplante Beispielergebnis stimmt. Diese Rückmeldung bleibt beim Öffnen oder Verkleinern des Gesprächs sichtbar.'
                            : 'Überlege, wie du beide Brüche mit demselben Nenner schreiben kannst. Dies ist eine feste synthetische Rückmeldung, keine KI-Bewertung.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Nur lokale Sichtprüfung. Alle Personen, Bilder, Aufgaben und Antworten sind künstlich.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _Fraction extends StatelessWidget {
  final String numerator, denominator;
  const _Fraction(this.numerator, this.denominator);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(numerator, style: Theme.of(context).textTheme.headlineMedium),
        Container(
          height: 2,
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: Theme.of(context).colorScheme.onSurface,
        ),
        Text(denominator, style: Theme.of(context).textTheme.headlineMedium),
      ],
    ),
  );
}
