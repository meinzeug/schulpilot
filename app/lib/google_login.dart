import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
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
  bool Function()? isCurrent,
  int? authenticationRevision,
}) async {
  if (authenticationRevision == null) state.beginAuthentication();
  final account = state.user;
  void check() {
    if (!identical(state.user, account) || isCurrent?.call() == false) {
      throw ApiError('Dieser Anmeldeschritt wurde inzwischen verlassen.');
    }
  }

  check();
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
  check();
  if (!kIsWeb) {
    await state.storage.write(
      key: _proofKey,
      value: jsonEncode({
        'flow_id': prepared['flow_id'],
        'client_verifier': verifier,
        'expires': DateTime.now().millisecondsSinceEpoch + 600000,
      }),
    );
    check();
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

class GoogleLoginButton extends StatefulWidget {
  final AppState state;
  final bool enabled;
  final ValueChanged<bool>? onBusyChanged;
  const GoogleLoginButton(
    this.state, {
    super.key,
    this.enabled = true,
    this.onBusyChanged,
  });
  @override
  State<GoogleLoginButton> createState() => _GoogleLoginButtonState();
}

class _GoogleLoginButtonState extends State<GoogleLoginButton> {
  late Future<Json> status;
  Object? owner;
  bool statusLoading = false;
  int statusGeneration = 0;

  Future<Json> loadStatus() async {
    final generation = ++statusGeneration;
    statusLoading = true;
    try {
      return await widget.state.api.get('/auth/google/status');
    } catch (_) {
      // A fast failed refresh may finish before the next build subscribes.
      // Keep an unavailable optional sign-in method from failing the form.
      return {'available': false, 'status_unavailable': true};
    } finally {
      if (generation == statusGeneration) statusLoading = false;
    }
  }

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    status = loadStatus();
    widget.state.addListener(accountChanged);
  }

  void accountChanged() {
    if (!mounted || identical(owner, widget.state.user)) return;
    setState(() {
      owner = widget.state.user;
      status = loadStatus();
    });
  }

  @override
  void didUpdateWidget(covariant GoogleLoginButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state) ||
        !identical(oldWidget.state.api, widget.state.api)) {
      oldWidget.state.removeListener(accountChanged);
      widget.state.addListener(accountChanged);
      owner = widget.state.user;
      status = loadStatus();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: status,
    builder: (context, value) {
      if (value.data?['status_unavailable'] == true) {
        return Column(
          children: [
            const Text(
              'Die optionale Google-Anmeldung konnte gerade nicht geprüft werden. Dein normaler Zugang bleibt verfügbar.',
            ),
            TextButton(
              onPressed: statusLoading || !widget.enabled
                  ? null
                  : () {
                      if (!mounted || statusLoading || !widget.enabled) return;
                      setState(() {
                        status = loadStatus();
                      });
                    },
              child: Text(
                statusLoading
                    ? 'Google-Verfügbarkeit wird geprüft …'
                    : 'Google-Verfügbarkeit erneut prüfen',
              ),
            ),
          ],
        );
      }
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
            _GoogleAction(
              widget.state,
              enabled: widget.enabled,
              onBusyChanged: widget.onBusyChanged,
            ),
          ],
        ),
      );
    },
  );
}

class _GoogleAction extends StatefulWidget {
  final AppState state;
  final bool enabled;
  final ValueChanged<bool>? onBusyChanged;
  const _GoogleAction(this.state, {required this.enabled, this.onBusyChanged});
  @override
  State<_GoogleAction> createState() => _GoogleActionState();
}

class _GoogleActionState extends State<_GoogleAction> {
  bool busy = false;
  String? error;
  int? authenticationRevision;
  AppState? authenticationState;
  @override
  void dispose() {
    final revision = authenticationRevision;
    if (revision != null) authenticationState?.cancelAuthentication(revision);
    super.dispose();
  }

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
        onPressed: busy || !widget.enabled
            ? null
            : () async {
                if (busy || !widget.enabled) return;
                setState(() {
                  busy = true;
                  error = null;
                });
                widget.onBusyChanged?.call(true);
                try {
                  final state = widget.state;
                  final account = state.user;
                  authenticationState = state;
                  authenticationRevision = state.beginAuthentication();
                  final flow = await beginGoogleLogin(
                    state,
                    authenticationRevision: authenticationRevision,
                    isCurrent: () =>
                        mounted &&
                        identical(widget.state, state) &&
                        identical(state.user, account) &&
                        ModalRoute.of(context)?.isCurrent != false,
                  );
                  if (context.mounted && flow != null) {
                    context.go('/auth/google/complete#flow=$flow');
                  }
                } catch (e) {
                  if (mounted) {
                    setState(
                      () => error = e is ApiError ? e.message : 'Google konnte gerade nicht geöffnet werden. Versuche es bitte erneut.',
                    );
                  }
                } finally {
                  if (mounted) {
                    setState(() => busy = false);
                    widget.onBusyChanged?.call(false);
                  }
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
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final family = TextEditingController();
  final password = TextEditingController();
  final nameFocus = FocusNode(),
      familyFocus = FocusNode(),
      passwordFocus = FocusNode();
  Timer? timer;
  String? flow, verifier, ticket, email, error;
  bool busy = false,
      consent = false,
      returnToApp = false,
      cancelling = false,
      passwordVisible = false;
  int generation = 0;
  int? authenticationRevision;
  AppState? authenticationState;
  Object? owner;
  bool expired = false, committing = false;
  int? proofExpires;
  bool existingLogin = false, awaitingReturn = false;

  void cancelOwnAuthentication() {
    final revision = authenticationRevision;
    if (revision != null) authenticationState?.cancelAuthentication(revision);
    authenticationRevision = null;
  }

  void accountChanged() {
    if (!mounted || committing || identical(owner, widget.state.user)) return;
    cancelOwnAuthentication();
    ++generation;
    timer?.cancel();
    setState(() {
      email = null;
      flow = verifier = ticket = null;
      name.clear();
      family.clear();
      password.clear();
      passwordVisible = consent = busy = false;
      error = 'Der Kontozugang hat sich geändert. Starte diesen Google-Schritt bei Bedarf neu.';
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    owner = widget.state.user;
    widget.state.addListener(accountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) initialize();
    });
  }

  @override
  void didUpdateWidget(covariant GoogleCompletionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        oldWidget.start != widget.start ||
        !identical(oldWidget.state, widget.state)) {
      if (!identical(oldWidget.state, widget.state)) {
        oldWidget.state.removeListener(accountChanged);
        widget.state.addListener(accountChanged);
      }
      name.clear();
      family.clear();
      password.clear();
      consent = false;
      passwordVisible = false;
      initialize();
    }
  }

  Future<void> initialize() async {
    cancelOwnAuthentication();
    authenticationState = widget.state;
    authenticationRevision = widget.state.beginAuthentication();
    owner = widget.state.user;
    final current = ++generation;
    timer?.cancel();
    busy = false;
    cancelling = false;
    flow = null;
    email = null;
    verifier = null;
    ticket = null;
    returnToApp = false;
    error = null;
    expired = false;
    proofExpires = null;
    existingLogin = awaitingReturn = false;
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
      if (fragment.containsKey('flow') && flow == null) {
        throw ApiError(
          'Der Anmeldelink ist ungültig. Bitte starte die Google-Anmeldung erneut.',
        );
      }
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
            proof['flow_id'] is! String ||
            !RegExp(r'^[a-f0-9]{32}$').hasMatch(proof['flow_id']) ||
            proof['client_verifier'] is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{43,128}$')
                .hasMatch(proof['client_verifier']) ||
            proof['expires'] is! int ||
            proof['expires'] < DateTime.now().millisecondsSinceEpoch ||
            (flow != null && flow != proof['flow_id'])) {
          throw ApiError(
            'Bitte starte die Google-Anmeldung auf diesem Gerät erneut.',
          );
        }
        flow = proof['flow_id'];
        verifier = proof['client_verifier'];
        proofExpires = proof['expires'];
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
              ModalRoute.of(context)?.isCurrent != false &&
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed) {
            check();
          }
        });
      }
    } catch (e) {
      if (mounted && generation == current) {
        flow = verifier = ticket = null;
        setState(
          () => error = e is ApiError ? e.message : 'Die Anmeldung konnte gerade nicht geprüft werden. Bitte versuche es erneut.',
        );
      }
    }
  }

  Future<void> check({bool register = false}) async {
    if (!mounted ||
        busy ||
        cancelling ||
        flow == null ||
        expired ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    if (proofExpires != null &&
        proofExpires! <= DateTime.now().millisecondsSinceEpoch) {
      timer?.cancel();
      setState(() {
        expired = true;
        password.clear();
        passwordVisible = false;
        error = 'Dieser Anmeldeschritt auf dem Gerät ist abgelaufen. Starte die Google-Anmeldung bewusst neu.';
      });
      return;
    }
    if (register) {
      final invalid = form.currentState?.validateGranularly();
      if (invalid == null || invalid.isNotEmpty) {
        if (invalid != null && invalid.isNotEmpty) {
          final first = invalid.first;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !cancelling && first.mounted) {
              final nodes = {
                ValueKey(('google-name', generation)): nameFocus,
                ValueKey(('google-family', generation)): familyFocus,
                ValueKey(('google-password', generation)): passwordFocus,
              };
              nodes[first.widget.key]?.requestFocus();
              Scrollable.ensureVisible(first.context, alignment: .2);
            }
          });
        }
        return;
      }
    }
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
        if (mounted && current == generation) context.go('/verify');
        return;
      }
      if (result['status'] == 'authenticated' || result['status'] == 'linked') {
        timer?.cancel();
        if (!kIsWeb) await widget.state.storage.delete(key: _proofKey);
        if (!mounted || current != generation) return;
        if (result['status'] == 'authenticated') {
          committing = true;
          try {
            await widget.state.accept(
              result,
              authenticationRevision: authenticationRevision,
            );
          } finally {
            committing = false;
          }
          if (register) TextInput.finishAutofillContext(shouldSave: true);
        }
        if (mounted && current == generation) {
          context.go(result['status'] == 'linked' ? '/settings' : '/app');
        }
      } else {
        if (![
          'pending',
          'awaiting_return',
          'registration_required',
          'return_to_app',
        ].contains(result['status'])) {
          throw ApiError(
            'Dieser Google-Anmeldestand wird nicht unterstützt. Starte die Anmeldung erneut; dein vorhandenes Konto bleibt bestehen.',
          );
        }
        if (result['status'] == 'registration_required' &&
            (result['email'] is! String ||
                (result['email'] as String).isEmpty)) {
          throw ApiError(
            'Die bestätigte Google-E-Mail fehlt. Starte die Anmeldung erneut.',
          );
        }
        if (result['status'] == 'return_to_app' &&
            (ticket == null ||
                !RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(ticket!))) {
          throw ApiError(
            'Der sichere App-Rückkehrlink ist unvollständig. Starte Google erneut in der App.',
          );
        }
        setState(() {
          email = result['email'];
          returnToApp = result['status'] == 'return_to_app';
          awaitingReturn = result['status'] == 'awaiting_return';
        });
      }
    } catch (e) {
      if (!identical(owner, widget.state.user)) {
        accountChanged();
        return;
      }
      if (mounted && current == generation) {
        setState(() {
          error = e is ApiError ? e.message : 'Die Anmeldung konnte gerade nicht geprüft werden. Bitte versuche es erneut.';
          existingLogin =
              register && e is ApiError && e.status == 409 && email != null;
        });
      }
    } finally {
      if (mounted && current == generation) setState(() => busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && passwordVisible) {
      setState(() => passwordVisible = false);
    }
    if (state == AppLifecycleState.resumed &&
        !widget.start &&
        email == null &&
        error == null &&
        !cancelling &&
        !returnToApp) {
      check();
    }
  }

  @override
  void dispose() {
    cancelOwnAuthentication();
    widget.state.removeListener(accountChanged);
    ++generation;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    name.dispose();
    family.dispose();
    password.dispose();
    nameFocus.dispose();
    familyFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  Future<void> cancel({bool passwordLogin = false}) async {
    if (!mounted || cancelling) return;
    ++generation;
    cancelOwnAuthentication();
    timer?.cancel();
    setState(() => cancelling = true);
    try {
      if (!kIsWeb) await widget.state.storage.delete(key: _proofKey);
      if (!mounted) return;
      context.go(
        passwordLogin || widget.state.user == null ? '/login' : '/settings',
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          cancelling = false;
          error = 'Der Anmeldeschritt konnte nicht beendet werden. Bitte versuche es erneut.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: brand()),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 490),
          child: AutofillGroup(
            onDisposeAction: AutofillContextAction.cancel,
            child: Panel(
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading(
                      email != null
                          ? 'Dein Elternkonto'
                          : 'Mit Google anmelden',
                    ),
                    if (error != null)
                      Semantics(
                        liveRegion: true,
                        child: Notice(error!, warning: true),
                      ),
                    if (existingLogin)
                      TextButton(
                        onPressed: busy || cancelling
                            ? null
                            : () {
                                widget.state.rememberAuthIdentifier(email!);
                                password.clear();
                                cancel(passwordLogin: true);
                              },
                        child: const Text(
                          'Mit vorhandenem Elternkonto anmelden',
                        ),
                      ),
                    if (busy || cancelling)
                      Semantics(
                        liveRegion: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              cancelling
                                  ? 'Anmeldung wird beendet …'
                                  : 'Google-Anmeldung wird geprüft …',
                            ),
                            const SizedBox(height: 8),
                            const LinearProgressIndicator(),
                          ],
                        ),
                      ),
                    if (email != null) ...[
                      SelectableText(
                        email!,
                        style: TextStyle(color: context.palette.muted),
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        key: ValueKey(('google-name', generation)),
                        controller: name,
                        focusNode: nameFocus,
                        enabled: !busy && !cancelling && !expired,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => familyFocus.requestFocus(),
                        autofillHints: const [AutofillHints.name],
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Gib deinen Anzeigenamen ein.'
                            : (value ?? '').trim().runes.length > 80
                            ? 'Nutze höchstens 80 Zeichen.'
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Dein Anzeigename',
                          errorMaxLines: 3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: ValueKey(('google-family', generation)),
                        controller: family,
                        focusNode: familyFocus,
                        enabled: !busy && !cancelling && !expired,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => passwordFocus.requestFocus(),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Gib einen Namen für deine Familie ein.'
                            : (value ?? '').trim().runes.length > 120
                            ? 'Nutze höchstens 120 Zeichen.'
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Name deiner Familie',
                          errorMaxLines: 3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: ValueKey(('google-password', generation)),
                        controller: password,
                        focusNode: passwordFocus,
                        enabled: !busy && !cancelling && !expired,
                        obscureText: !passwordVisible,
                        enableSuggestions: false,
                        autocorrect: false,
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        enableIMEPersonalizedLearning: false,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => check(register: true),
                        autofillHints: const [AutofillHints.newPassword],
                        validator: (value) =>
                            (value ?? '').trim().runes.length < 12
                            ? 'Nutze mindestens 12 Zeichen.'
                            : (value ?? '').runes.length > 128
                            ? 'Nutze höchstens 128 Zeichen.'
                            : null,
                        decoration: InputDecoration(
                          labelText: 'Elternpasswort',
                          helperText: 'Mindestens 12 Zeichen. Für Wiederherstellung und geschützte Kontoeinstellungen.',
                          helperMaxLines: 5,
                          errorMaxLines: 3,
                          suffixIcon: IconButton(
                            tooltip: passwordVisible
                                ? 'Passwort verbergen'
                                : 'Passwort anzeigen',
                            onPressed: busy || cancelling || expired
                                ? null
                                : () => setState(
                                    () => passwordVisible = !passwordVisible,
                                  ),
                            icon: Icon(
                              passwordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      FormField<bool>(
                        key: ValueKey(('google-consent', generation)),
                        initialValue: consent,
                        validator: (value) => value == true ? null : 'Bestätige deine Volljährigkeit und Berechtigung.',
                        builder: (field) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: field.value,
                              onChanged: busy || cancelling || expired
                                  ? null
                                  : (value) {
                                      field.didChange(value ?? false);
                                      setState(() => consent = value ?? false);
                                    },
                              title: const Text(
                                'Ich bin volljährig und zur Einrichtung dieser Familie berechtigt.',
                              ),
                            ),
                            if (field.hasError)
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  field.errorText!,
                                  style: TextStyle(
                                    color: context.palette.dangerInk,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: busy || cancelling
                            ? null
                            : () => context.push('/privacy'),
                        child: const Text('Datenschutz lesen'),
                      ),
                      FilledButton(
                        onPressed: busy || cancelling || expired
                            ? null
                            : () => check(register: true),
                        child: const Text('Elternkonto erstellen'),
                      ),
                    ] else if (returnToApp) ...[
                      const Text(
                        'Google ist bestätigt. Öffne SCHULPILOT, um fortzufahren.',
                      ),
                      const SizedBox(height: 16),
                      ActionButton(
                        label: 'SCHULPILOT öffnen',
                        enabled: !cancelling,
                        onPressed: () async {
                          final opened = await launchUrl(
                            Uri(
                              scheme: 'schulpilot',
                              host: 'google',
                              path: '/complete',
                              queryParameters: {
                                'flow': flow!,
                                'ticket': ?ticket,
                              },
                            ),
                            webOnlyWindowName: '_self',
                          );
                          if (!opened) {
                            throw ApiError(
                              'Die App konnte nicht geöffnet werden. Öffne SCHULPILOT auf diesem Gerät und kehre zur Anmeldung zurück.',
                            );
                          }
                        },
                      ),
                    ] else ...[
                      if (awaitingReturn) ...[
                        const Notice(
                          'Google hat bereits geantwortet. Für die sichere Anmeldung fehlt noch der Rückkehrlink aus dem Browser auf diesem Gerät. Eine neue Google-Bestätigung ist dafür nicht nötig.',
                        ),
                        TextButton(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (dialog) => AlertDialog(
                              title: const Text('Sicher zur App zurückkehren'),
                              scrollable: true,
                              content: const Text(
                                '1. Zum Browser wechseln, in dem du Google bestätigt hast.\n2. Dort „SCHULPILOT öffnen“ wählen.\n3. Den Wechsel in diese App erlauben.\nWenn der Browser geschlossen wurde oder der Link abgelaufen ist, diesen Anmeldeschritt beenden und bewusst neu starten. Es werden weder Codes noch Zugangsdaten kopiert oder versendet.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    if (ModalRoute.of(dialog)?.isCurrent ==
                                        true) {
                                      Navigator.of(dialog).pop();
                                    }
                                  },
                                  child: const Text('Verstanden'),
                                ),
                              ],
                            ),
                          ),
                          child: const Text('Rückkehrschritte ansehen'),
                        ),
                      ],
                      if (error == null && !awaitingReturn)
                        const Text(
                          'Bestätige deine Anmeldung bei Google. Danach geht es hier weiter.',
                        ),
                      if (flow != null && !widget.start) ...[
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: busy || cancelling ? null : check,
                          child: Text(
                            error == null ? 'Weiter' : 'Erneut prüfen',
                          ),
                        ),
                      ],
                    ],
                    TextButton(
                      onPressed: cancelling ? null : cancel,
                      child: const Text('Zurück'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
