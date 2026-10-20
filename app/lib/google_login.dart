import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'ui.dart';

const _proofKey = 'google_login_proof';

String? googleFlowId(Uri uri) {
  try {
    final id = Uri.splitQueryString(uri.fragment)['flow'];
    return id != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ? id : null;
  } on FormatException {
    return null;
  }
}

String nativeInitialLocation(String incoming) {
  final uri = Uri.tryParse(incoming);
  if (uri != null &&
      uri.scheme == 'schulpilot' &&
      uri.host == 'google' &&
      uri.path == '/complete') {
    return Uri(
      path: '/auth/google/complete',
      fragment: Uri(
        queryParameters: {
          if (uri.queryParameters['flow'] != null)
            'flow': uri.queryParameters['flow']!,
          if (uri.queryParameters['ticket'] != null)
            'ticket': uri.queryParameters['ticket']!,
        },
      ).query,
    ).toString();
  }
  if (uri != null &&
      (uri.scheme.isEmpty ||
          (uri.scheme == 'https' && uri.host == 'schulpilot.dorfspy.de')) &&
      uri.path == '/auth/google/complete') {
    return Uri(path: uri.path, fragment: uri.fragment).toString();
  }
  return '/app';
}

Future<String?> beginGoogleLogin(
  AppState state, {
  String intent = 'login',
  String password = '',
}) async {
  String? verifier;
  if (!kIsWeb) {
    final random = Random.secure();
    verifier = base64UrlEncode(
      List<int>.generate(48, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
  }
  final prepared = await state.api.post('/auth/google/prepare', {
    'intent': intent,
    if (password.isNotEmpty) 'password': password,
    if (verifier != null)
      'client_challenge': base64UrlEncode(
        sha256.convert(ascii.encode(verifier)).bytes,
      ).replaceAll('=', ''),
  });
  if (!kIsWeb) {
    await state.storage.write(
      key: _proofKey,
      value: jsonEncode({
        'flow_id': prepared['flow_id'],
        'client_verifier': verifier,
        'expires': DateTime.now().millisecondsSinceEpoch + 600000,
      }),
    );
    final url = Uri.parse(state.api.base).replace(
      path: '/auth/google/start',
      fragment: Uri(queryParameters: {'request': prepared['request']}).query,
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      await state.storage.delete(key: _proofKey);
      throw ApiError('Der Browser konnte nicht geöffnet werden.');
    }
    return prepared['flow_id'];
  }
  await _startBrowser(state, prepared['request']);
  return null;
}

Future<void> _startBrowser(AppState state, String request) async {
  final started = await state.api.post('/auth/google/start', {
    'request': request,
  });
  final uri = Uri.parse(started['authorization_url']);
  if (uri.scheme != 'https' || uri.host != 'accounts.google.com') {
    throw ApiError('Die Google-Anmeldung konnte nicht gestartet werden.');
  }
  if (!await launchUrl(uri, webOnlyWindowName: '_self')) {
    throw ApiError('Google konnte nicht geöffnet werden.');
  }
}

class GoogleLoginButton extends StatelessWidget {
  final AppState state;
  const GoogleLoginButton(this.state, {super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: state.api.get('/auth/google/status'),
    builder: (context, value) {
      if (value.data?['available'] != true) return SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(top: 16),
        child: Column(
          children: [
            Text(
              'Für Eltern',
              style: TextStyle(color: context.palette.muted, fontSize: 12),
            ),
            SizedBox(height: 8),
            _GoogleAction(state),
          ],
        ),
      );
    },
  );
}

class _GoogleAction extends StatefulWidget {
  final AppState state;
  const _GoogleAction(this.state);
  @override
  State<_GoogleAction> createState() => _GoogleActionState();
}

class _GoogleActionState extends State<_GoogleAction> {
  bool busy = false;
  String? error;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (error != null) Notice(error!, warning: true),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1F1F1F),
          side: BorderSide(color: Color(0xFF747775)),
          minimumSize: Size(0, 48),
        ),
        icon: Image.asset(
          'assets/google/signin-icon.png',
          width: 30,
          height: 30,
        ),
        label: Text(busy ? 'Wird geöffnet …' : 'Mit Google anmelden'),
        onPressed: busy
            ? null
            : () async {
                setState(() {
                  busy = true;
                  error = null;
                });
                try {
                  final flow = await beginGoogleLogin(widget.state);
                  if (context.mounted && flow != null) {
                    context.go('/auth/google/complete#flow=$flow');
                  }
                } catch (e) {
                  if (mounted) setState(() => error = e.toString());
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
      ),
    ],
  );
}

class GoogleCompletionScreen extends StatefulWidget {
  final AppState state;
  final Uri uri;
  final bool start;
  const GoogleCompletionScreen(
    this.state, {
    super.key,
    required this.uri,
    this.start = false,
  });
  @override
  State<GoogleCompletionScreen> createState() => _GoogleCompletionScreenState();
}

class _GoogleCompletionScreenState extends State<GoogleCompletionScreen>
    with WidgetsBindingObserver {
  final name = TextEditingController();
  final family = TextEditingController();
  final password = TextEditingController();
  Timer? timer;
  String? flow, verifier, ticket, email, error;
  bool busy = false, consent = false, returnToApp = false;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initialize();
  }

  @override
  void didUpdateWidget(covariant GoogleCompletionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) initialize();
  }

  Future<void> initialize() async {
    final current = ++generation;
    timer?.cancel();
    busy = false;
    email = null;
    verifier = null;
    ticket = null;
    returnToApp = false;
    error = null;
    try {
      if (widget.start) {
        if (!kIsWeb) throw ApiError('Bitte starte die Anmeldung in der App.');
        final request = Uri.splitQueryString(widget.uri.fragment)['request'];
        if (request == null ||
            !RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(request)) {
          throw ApiError('Bitte starte die Google-Anmeldung erneut.');
        }
        await _startBrowser(widget.state, request);
        return;
      }
      flow = googleFlowId(widget.uri);
      final fragment = Uri.splitQueryString(widget.uri.fragment);
      if (fragment.containsKey('error')) {
        throw ApiError(
          'Die Google-Anmeldung konnte nicht bestätigt werden. Bitte starte erneut.',
        );
      }
      ticket = fragment['ticket'];
      if (!kIsWeb) {
        final raw = await widget.state.storage.read(key: _proofKey);
        final proof = raw == null ? null : jsonDecode(raw) as Map;
        if (proof == null ||
            proof['expires'] < DateTime.now().millisecondsSinceEpoch ||
            (flow != null && flow != proof['flow_id'])) {
          throw ApiError(
            'Bitte starte die Google-Anmeldung auf diesem Gerät erneut.',
          );
        }
        flow = proof['flow_id'];
        verifier = proof['client_verifier'];
      }
      if (flow == null) {
        throw ApiError('Die Anmeldung wurde abgebrochen. Bitte starte erneut.');
      }
      if (!mounted || generation != current) return;
      await check();
      if (!kIsWeb && mounted && generation == current) {
        timer = Timer.periodic(Duration(seconds: 5), (_) {
          if (email == null &&
              error == null &&
              !returnToApp &&
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed) {
            check();
          }
        });
      }
    } catch (e) {
      if (mounted && generation == current) {
        setState(() => error = e.toString());
      }
    }
  }

  Future<void> check({bool register = false}) async {
    if (busy || flow == null) return;
    final current = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.state.api.post('/auth/google/result', {
        'flow_id': flow,
        if (verifier != null) 'client_verifier': verifier,
        if (ticket != null) 'ticket': ticket,
        if (register)
          'registration': {
            'email': email,
            'display_name': name.text.trim(),
            'family_name': family.text.trim(),
            'password': password.text,
            'adult_consent': consent,
          },
      });
      if (!mounted || current != generation) return;
      if (result['status'] == 'verification_required') {
        timer?.cancel();
        if (!kIsWeb) await widget.state.storage.delete(key: _proofKey);
        if (mounted) context.go('/verify');
        return;
      }
      if (result['status'] == 'authenticated' || result['status'] == 'linked') {
        timer?.cancel();
        if (!kIsWeb) await widget.state.storage.delete(key: _proofKey);
        if (result['status'] == 'authenticated') {
          await widget.state.accept(result);
        }
        if (mounted) {
          context.go(result['status'] == 'linked' ? '/settings' : '/app');
        }
      } else {
        setState(() {
          email = result['email'];
          returnToApp = result['status'] == 'return_to_app';
        });
      }
    } catch (e) {
      if (mounted && current == generation) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && current == generation) setState(() => busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !widget.start &&
        email == null &&
        !returnToApp) {
      check();
    }
  }

  @override
  void dispose() {
    ++generation;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    name.dispose();
    family.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: brand()),
    body: Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 490),
          child: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading(
                  email != null ? 'Dein Elternkonto' : 'Mit Google anmelden',
                ),
                if (error != null) Notice(error!, warning: true),
                if (busy) LinearProgressIndicator(),
                if (email != null) ...[
                  Text(email!, style: TextStyle(color: context.palette.muted)),
                  SizedBox(height: 18),
                  TextField(
                    controller: name,
                    decoration: InputDecoration(labelText: 'Dein Anzeigename'),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: family,
                    decoration: InputDecoration(
                      labelText: 'Name deiner Familie',
                    ),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: password,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Elternpasswort (mindestens 12 Zeichen)',
                      helperText: 'Für Wiederherstellung und geschützte Kontoeinstellungen.',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: consent,
                    onChanged: (v) => setState(() => consent = v ?? false),
                    title: Text(
                      'Ich bin volljährig und zur Einrichtung dieser Familie berechtigt.',
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/privacy'),
                    child: Text('Datenschutz lesen'),
                  ),
                  FilledButton(
                    onPressed: busy || !consent
                        ? null
                        : () => check(register: true),
                    child: Text('Elternkonto erstellen'),
                  ),
                ] else if (returnToApp) ...[
                  Text(
                    'Google ist bestätigt. Öffne SCHULPILOT, um fortzufahren.',
                  ),
                  SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => launchUrl(
                      Uri(
                        scheme: 'schulpilot',
                        host: 'google',
                        path: '/complete',
                        queryParameters: {'flow': flow!, 'ticket': ?ticket},
                      ),
                      webOnlyWindowName: '_self',
                    ),
                    child: Text('SCHULPILOT öffnen'),
                  ),
                ] else if (error == null) ...[
                  Text(
                    'Bestätige deine Anmeldung bei Google. Danach geht es hier weiter.',
                  ),
                  SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: busy ? null : check,
                    child: Text('Weiter'),
                  ),
                ],
                TextButton(
                  onPressed: () async {
                    timer?.cancel();
                    if (!kIsWeb) {
                      await widget.state.storage.delete(key: _proofKey);
                    }
                    if (context.mounted) {
                      context.go(
                        widget.state.user == null ? '/login' : '/settings',
                      );
                    }
                  },
                  child: Text('Zurück'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
