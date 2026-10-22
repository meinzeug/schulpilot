import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show TextInput;
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'app_version.dart';
import 'download_panel.dart';
import 'ui.dart';
import 'store_screens.dart';
import 'google_login.dart';

class LandingScreen extends StatelessWidget {
  final AppState state;
  const LandingScreen(this.state, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          final hero = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tag('LERNEN MIT RÜCKENWIND'),
              SizedBox(height: 24),
              Text(
                'Nach der Schule.\nMit Plan weiter.',
                style: TextStyle(
                  fontSize: wide ? 64 : 42,
                  color: context.palette.ink,
                  height: 1.06,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2.3,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Heftfotos rein. Stoff verstehen. Mit passenden Übungen dranbleiben.',
                style: TextStyle(
                  fontSize: 19,
                  height: 1.5,
                  color: context.palette.muted,
                ),
              ),
              SizedBox(height: 30),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () =>
                        context.go(kIsWeb ? '/angebote' : '/register'),
                    icon: Icon(Icons.arrow_forward_rounded),
                    label: Text(
                      kIsWeb ? 'Tarife ansehen' : 'Elternkonto erstellen',
                    ),
                  ),
                  ActionButton(
                    label: 'Demo ausprobieren',
                    secondary: true,
                    onPressed: () async {
                      await state.accept(await state.api.post('/demo'));
                      if (context.mounted) context.go('/app');
                    },
                  ),
                ],
              ),
            ],
          );
          final flow = Container(
            padding: EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF111C34), teal],
              ),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: context.palette.electric,
                  size: 32,
                ),
                SizedBox(height: 20),
                Text(
                  'Ein klarer nächster Schritt.',
                  style: TextStyle(
                    fontSize: 29,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 24),
                for (final item in [
                  (
                    Icons.document_scanner_rounded,
                    '01',
                    'Stoff sammeln',
                    'Die Heftseiten von heute.',
                  ),
                  (
                    Icons.lightbulb_outline_rounded,
                    '02',
                    'Verstehen & üben',
                    'Mit Hilfe, wenn es hakt.',
                  ),
                  (
                    Icons.check_circle_outline_rounded,
                    '03',
                    'Wissen festigen',
                    'Neue Aufgaben. Später wiederholen.',
                  ),
                ])
                  Container(
                    margin: EdgeInsets.only(bottom: 12),
                    padding: EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .08),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(item.$1, color: Colors.white, size: 24),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.$3,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                item.$4,
                                style: TextStyle(
                                  color: Color(0xFFC7CBED),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          item.$2,
                          style: TextStyle(
                            color: Colors.white38,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 1240),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 44 : 22,
                    vertical: 26,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: brand(),
                            ),
                          ),
                          AppearanceToggle(state),
                          TextButton(
                            onPressed: () => context.go(
                              state.user == null ? '/login' : '/app',
                            ),
                            child: Text(
                              state.user == null ? 'Anmelden' : 'Mein Lernraum',
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: wide ? 80 : 44),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(flex: 6, child: hero),
                            SizedBox(width: 64),
                            Expanded(flex: 5, child: flow),
                          ],
                        )
                      else ...[
                        hero,
                        SizedBox(height: 36),
                        flow,
                      ],
                      SizedBox(height: 42),
                      Wrap(
                        spacing: 20,
                        runSpacing: 20,
                        children: [
                          for (final item in [
                            (
                              Icons.today_rounded,
                              'Ein Plan für heute',
                              'Überschaubare Einheiten statt Aufgabenberge.',
                            ),
                            (
                              Icons.support_agent_rounded,
                              'Hilfe im richtigen Moment',
                              'Verständliche Erklärungen und passende Hinweise.',
                            ),
                            (
                              Icons.family_restroom_rounded,
                              'Eltern bleiben im Bild',
                              'Was lief gut? Wo braucht dein Kind Unterstützung?',
                            ),
                          ])
                            SizedBox(
                              width: wide
                                  ? (constraints.maxWidth.clamp(0, 1240) -
                                            128) /
                                        3
                                  : double.infinity,
                              child: Panel(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(item.$1, color: context.palette.teal),
                                    SizedBox(height: 18),
                                    Text(
                                      item.$2,
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      item.$3,
                                      style: TextStyle(
                                        color: context.palette.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 30),
                      if (kIsWeb) ...[
                        StoreSection(state),
                        SizedBox(height: 32),
                      ],
                      if (kIsWeb) AndroidDownload(state.api),
                      SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton(
                            onPressed: () => openRoute(context, '/privacy'),
                            child: Text('Datenschutz'),
                          ),
                          TextButton(
                            onPressed: () => openRoute(context, '/about'),
                            child: Text('Über SCHULPILOT'),
                          ),
                          if (kIsWeb)
                            TextButton(
                              onPressed: () => context.go('/bedingungen'),
                              child: Text('Vertragsbedingungen & Widerruf'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class AuthScreen extends StatefulWidget {
  final AppState state;
  final String mode;
  final Uri linkUri;
  const AuthScreen(
    this.state, {
    super.key,
    required this.mode,
    required this.linkUri,
  });
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final username = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final family = TextEditingController();
  final token = TextEditingController();
  final usernameFocus = FocusNode();
  final passwordFocus = FocusNode();
  final nameFocus = FocusNode();
  final familyFocus = FocusNode();
  final tokenFocus = FocusNode();
  final consentFocus = FocusNode();
  final feedbackKey = GlobalKey();
  final Map<String, String> fieldErrors = {};
  bool submitting = false, googleBusy = false;
  int formRevision = 0;
  bool consent = false, passwordVisible = false;
  String? _identifierFromPreviousForm;
  bool _identifierEdited = false;
  String? result;
  String? error;
  @override
  void initState() {
    super.initState();
    _restoreIdentifier();
    _readLink();
  }

  @override
  void didUpdateWidget(covariant AuthScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.linkUri != widget.linkUri || oldWidget.mode != widget.mode) {
      formRevision++;
      if (oldWidget.mode != widget.mode) _restoreIdentifier();
      _readLink();
      result = null;
      error = null;
      fieldErrors.clear();
    }
  }

  void _restoreIdentifier() {
    final identifier = widget.state.takeAuthIdentifier();
    _identifierFromPreviousForm = identifier;
    _identifierEdited = false;
    username.text =
        widget.mode == 'login' ||
            (['register', 'recovery'].contains(widget.mode) &&
                identifier?.contains('@') == true)
        ? identifier ?? ''
        : '';
  }

  void _readLink() {
    token.clear();
    if (!['reset', 'verify', 'invite'].contains(widget.mode)) return;
    try {
      final values = Uri.splitQueryString(widget.linkUri.fragment);
      final value = values['token'];
      if (value != null && RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(value)) {
        token.text = value;
      }
    } on FormatException {
      // A damaged email link must still allow manual code entry.
    }
  }

  @override
  void dispose() {
    for (final c in [username, password, name, family, token]) {
      c.dispose();
    }
    for (final focus in [
      usernameFocus,
      passwordFocus,
      nameFocus,
      familyFocus,
      tokenFocus,
      consentFocus,
    ]) {
      focus.dispose();
    }
    super.dispose();
  }

  void showFeedback() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final target = feedbackKey.currentContext;
    if (mounted && target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 200),
        alignment: .1,
      );
    }
  });

  void goToAuth(String location) {
    if (submitting || googleBusy) return;
    final target = Uri.parse(location).path;
    final identifier = username.text.isNotEmpty || _identifierEdited
        ? username.text.trim()
        : _identifierFromPreviousForm ?? '';
    widget.state.rememberAuthIdentifier(
      ['/login', '/register', '/recovery'].contains(target) ? identifier : '',
    );
    context.go(location);
  }

  void fieldEdited(String name) {
    if (name == 'username') _identifierEdited = true;
    if (fieldErrors.containsKey(name) || error != null || result != null) {
      setState(() {
        fieldErrors.remove(name);
        error = null;
        result = null;
      });
    }
  }

  bool validateFields() {
    final mode = widget.mode;
    final invalid = <String, String>{};
    if (['login', 'register', 'recovery'].contains(mode) &&
        username.text.trim().isEmpty) {
      invalid['username'] = mode == 'login'
          ? 'Gib deine E-Mail oder deinen Benutzernamen ein.'
          : 'Gib deine E-Mail-Adresse ein.';
    }
    if (mode == 'register' && name.text.trim().isEmpty) {
      invalid['name'] = 'Gib deinen Anzeigenamen ein.';
    }
    if (mode == 'register' && family.text.trim().isEmpty) {
      invalid['family'] = 'Gib einen Namen für deine Familie ein.';
    }
    if (['login', 'register', 'reset'].contains(mode) &&
        password.text.isEmpty) {
      invalid['password'] = 'Gib dein Passwort ein.';
    } else if (['register', 'reset'].contains(mode) &&
        password.text.runes.length < 12) {
      invalid['password'] =
          'Dein neues Passwort braucht mindestens 12 Zeichen.';
    }
    if (['reset', 'verify', 'invite'].contains(mode) &&
        token.text.trim().isEmpty) {
      invalid['token'] =
          'Öffne den vollständigen E-Mail-Link oder füge seinen Code ein.';
    }
    if (mode == 'register' && !consent) {
      invalid['consent'] = 'Bestätige deine Volljährigkeit und Berechtigung.';
    }
    setState(() {
      fieldErrors
        ..clear()
        ..addAll(invalid);
      error = null;
      result = null;
    });
    if (invalid.isEmpty) return true;
    final focus = {
      'username': usernameFocus,
      'name': nameFocus,
      'family': familyFocus,
      'password': passwordFocus,
      'token': tokenFocus,
      'consent': consentFocus,
    }[invalid.keys.first]!;
    focus.requestFocus();
    return false;
  }

  Future<void> submit() async {
    if (submitting || googleBusy || !validateFields()) return;
    final mode = widget.mode, uri = widget.linkUri;
    final revision = formRevision;
    setState(() => submitting = true);
    FocusScope.of(context).unfocus();
    try {
      if (mode == 'login') {
        await widget.state.login(username.text.trim(), password.text);
        if (!mounted || revision != formRevision) return;
        TextInput.finishAutofillContext(shouldSave: true);
        final next = uri.queryParameters['next'] ?? '';
        context.go(
          widget.state.isParent &&
                  RegExp(r'^/bestellen/[a-z][a-z0-9-]{1,29}$').hasMatch(next)
              ? next
              : '/app',
        );
        return;
      }
      final data = await widget.state.api.post(
        switch (mode) {
          'register' => '/auth/register',
          'recovery' => '/auth/recovery',
          'reset' => '/auth/reset',
          'verify' => '/auth/verify',
          _ => '/invitations/accept',
        },
        switch (mode) {
          'register' => {
            'email': username.text.trim(),
            'password': password.text,
            'display_name': name.text.trim(),
            'family_name': family.text.trim(),
            'adult_consent': consent,
          },
          'recovery' => {'email': username.text.trim()},
          'reset' => {'token': token.text, 'password': password.text},
          'verify' => {'token': token.text},
          _ => {
            'token': token.text,
            'password': password.text,
            'display_name': name.text.trim(),
          },
        },
      );
      if (!mounted || revision != formRevision) return;
      if (['register', 'reset'].contains(mode)) {
        TextInput.finishAutofillContext(shouldSave: true);
      }
      setState(() => result = data['message']);
      showFeedback();
    } catch (failure) {
      if (!mounted || revision != formRevision) return;
      setState(
        () => error = failure is ApiError ? failure.message : 'Die Anfrage konnte nicht abgeschlossen werden. Versuche es bitte erneut.',
      );
      showFeedback();
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final title = switch (mode) {
      'register' => 'Euer Start mit Schulpilot',
      'recovery' => 'Passwort vergessen?',
      'reset' => 'Neues Elternpasswort',
      'verify' => 'E-Mail bestätigen',
      'invite' => 'Zur Familie dazukommen',
      _ => 'Willkommen zurück',
    };
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.palette.cream,
        automaticallyImplyLeading: !submitting && !googleBusy,
        title: InkWell(
          onTap: submitting || googleBusy ? null : () => goToAuth('/'),
          child: brand(),
        ),
        actions: [AppearanceToggle(widget.state), const SizedBox(width: 16)],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 490),
            child: AutofillGroup(
              onDisposeAction: AutofillContextAction.cancel,
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    SizedBox(height: 12),
                    Text(switch (mode) {
                      'login' => 'Eltern und Kinder melden sich mit ihrem eigenen Zugang an.',
                      'register' => 'Erstelle dein Elternkonto. Danach richtest du die Zugänge deiner Kinder ein.',
                      'recovery' => 'Für Eltern: Gib die E-Mail deines Kontos ein. Kinder lassen ihr Passwort von ihren Eltern ändern.',
                      'reset' => 'Wähle ein neues Elternpasswort. Der sichere Code kommt aus deinem E-Mail-Link.',
                      'invite' => 'Nimm die Einladung zu deiner Familie an. Nutze bei einem vorhandenen Elternkonto dessen Passwort.',
                      _ => 'Bestätige deine E-Mail-Adresse. Der sichere Code wird aus dem vollständigen E-Mail-Link übernommen.',
                    }, style: TextStyle(color: context.palette.muted)),
                    SizedBox(height: 24),
                    SizedBox(
                      key: feedbackKey,
                      child: Semantics(
                        liveRegion: true,
                        child: Column(
                          children: [
                            if (result != null)
                              Notice(result!, icon: Icons.check_circle_outline),
                            if (error != null) Notice(error!, warning: true),
                          ],
                        ),
                      ),
                    ),
                    if (['login', 'register', 'recovery'].contains(mode)) ...[
                      TextField(
                        controller: username,
                        onChanged: (_) => fieldEdited('username'),
                        focusNode: usernameFocus,
                        enabled: !submitting,
                        autocorrect: false,
                        textInputAction: mode == 'recovery'
                            ? TextInputAction.done
                            : TextInputAction.next,
                        onSubmitted: (_) async {
                          if (mode == 'recovery') {
                            await submit();
                          } else {
                            (mode == 'register' ? nameFocus : passwordFocus)
                                .requestFocus();
                          }
                        },
                        autofillHints: mode == 'login'
                            ? [AutofillHints.username]
                            : [AutofillHints.email],
                        keyboardType: mode == 'login'
                            ? TextInputType.text
                            : TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: mode == 'login'
                              ? 'E-Mail oder Benutzername'
                              : 'E-Mail-Adresse',
                          helperText: mode == 'login'
                              ? 'Eltern: E-Mail oder Benutzername. Kinder: eigener Benutzername.'
                              : null,
                          helperMaxLines: 3,
                          errorText: fieldErrors['username'],
                          errorMaxLines: 3,
                        ),
                      ),
                      SizedBox(height: 16),
                    ],
                    if (['register', 'invite'].contains(mode)) ...[
                      TextField(
                        controller: name,
                        onChanged: (_) => fieldEdited('name'),
                        focusNode: nameFocus,
                        enabled: !submitting,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) =>
                            (mode == 'register' ? familyFocus : passwordFocus)
                                .requestFocus(),
                        decoration: InputDecoration(
                          labelText: 'Dein Anzeigename',
                          errorText: fieldErrors['name'],
                          errorMaxLines: 3,
                        ),
                      ),
                      SizedBox(height: 16),
                    ],
                    if (mode == 'register') ...[
                      TextField(
                        controller: family,
                        onChanged: (_) => fieldEdited('family'),
                        focusNode: familyFocus,
                        enabled: !submitting,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => passwordFocus.requestFocus(),
                        decoration: InputDecoration(
                          labelText: 'Name deiner Familie',
                          errorText: fieldErrors['family'],
                          errorMaxLines: 3,
                        ),
                      ),
                      SizedBox(height: 16),
                    ],
                    if ([
                      'login',
                      'register',
                      'reset',
                      'invite',
                    ].contains(mode)) ...[
                      TextField(
                        controller: password,
                        onChanged: (_) => fieldEdited('password'),
                        focusNode: passwordFocus,
                        enabled: !submitting,
                        textInputAction:
                            ['login', 'register'].contains(mode) ||
                                token.text.isNotEmpty
                            ? TextInputAction.done
                            : TextInputAction.next,
                        onSubmitted: (_) async {
                          if (['login', 'register'].contains(mode) ||
                              token.text.isNotEmpty) {
                            await submit();
                          } else {
                            tokenFocus.requestFocus();
                          }
                        },
                        obscureText: !passwordVisible,
                        enableSuggestions: false,
                        autocorrect: false,
                        autofillHints: mode == 'login'
                            ? [AutofillHints.password]
                            : [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          suffixIcon: IconButton(
                            tooltip: passwordVisible
                                ? 'Passwort verbergen'
                                : 'Passwort anzeigen',
                            icon: Icon(
                              passwordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () => setState(
                              () => passwordVisible = !passwordVisible,
                            ),
                          ),
                          labelText: mode == 'invite'
                              ? 'Elternpasswort'
                              : mode == 'login'
                              ? 'Passwort'
                              : 'Neues Passwort',
                          helperText: mode == 'invite'
                              ? 'Bestehendes Passwort oder für ein neues Konto mindestens 12 Zeichen. Bereits angemeldet? Dann darf dieses Feld leer bleiben.'
                              : mode == 'login'
                              ? null
                              : 'Mindestens 12 Zeichen.',
                          helperMaxLines: 5,
                          errorText: fieldErrors['password'],
                          errorMaxLines: 3,
                        ),
                      ),
                      SizedBox(height: 16),
                    ],
                    if (['reset', 'verify', 'invite'].contains(mode)) ...[
                      TextField(
                        controller: token,
                        onChanged: (_) => fieldEdited('token'),
                        focusNode: tokenFocus,
                        enabled: !submitting,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => submit(),
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Sicherer Link-Code',
                          helperText: 'Wird aus dem E-Mail-Link übernommen.',
                          helperMaxLines: 3,
                          errorText: fieldErrors['token'],
                          errorMaxLines: 3,
                        ),
                      ),
                      SizedBox(height: 16),
                    ],
                    if (mode == 'register') ...[
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: consent,
                        focusNode: consentFocus,
                        onChanged: submitting
                            ? null
                            : (v) {
                                setState(() => consent = v ?? false);
                                fieldEdited('consent');
                              },
                        title: Text(
                          'Ich bin volljährig und für die Einrichtung dieser Familie berechtigt.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      if (fieldErrors['consent'] != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            fieldErrors['consent']!,
                            style: TextStyle(color: context.palette.warningInk),
                          ),
                        ),
                      SizedBox(height: 12),
                    ],
                    ActionButton(
                      label: submitting
                          ? 'Bitte warten …'
                          : switch (mode) {
                              'register' => 'Elternkonto anlegen',
                              'recovery' => 'Wiederherstellungslink anfordern',
                              'verify' => 'E-Mail bestätigen',
                              'reset' => 'Passwort erneuern',
                              'invite' => 'Einladung annehmen',
                              _ => 'Anmelden',
                            },
                      onPressed: submit,
                      enabled: !submitting && !googleBusy,
                    ),
                    SizedBox(height: 18),
                    if (mode == 'login' || mode == 'register')
                      GoogleLoginButton(
                        widget.state,
                        enabled: !submitting,
                        onBusyChanged: (busy) {
                          if (mounted) setState(() => googleBusy = busy);
                        },
                      ),
                    if (mode == 'login')
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: submitting || googleBusy
                                ? null
                                : () => goToAuth('/recovery'),
                            child: Text('Passwort vergessen'),
                          ),
                          TextButton(
                            onPressed: submitting || googleBusy
                                ? null
                                : () => goToAuth(
                                    Uri(
                                      path: '/register',
                                      queryParameters:
                                          widget.linkUri.queryParameters,
                                    ).toString(),
                                  ),
                            child: Text('Elternkonto erstellen'),
                          ),
                        ],
                      )
                    else
                      TextButton(
                        onPressed: submitting || googleBusy
                            ? null
                            : () => goToAuth(
                                Uri(
                                  path: '/login',
                                  queryParameters:
                                      widget.linkUri.queryParameters,
                                ).toString(),
                              ),
                        child: Text('Zur Anmeldung'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InformationScreen extends StatelessWidget {
  final String kind;
  const InformationScreen(this.kind, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: brand(),
      leading: IconButton(
        icon: Icon(Icons.arrow_back),
        onPressed: () => context.go('/'),
      ),
    ),
    body: SelectionArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 800),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind == 'privacy'
                        ? 'Datenschutz & Transparenz'
                        : 'Über Schulpilot',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  FutureBuilder<Json>(
                    future: Api().get('/legal'),
                    builder: (context, result) {
                      if (!result.hasData) return SizedBox.shrink();
                      final data = result.data!;
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['complete'] == true
                                  ? 'Verantwortlicher Betreiber\n${data['operator']}\n${data['address']}\nSupport: ${data['support_email']}'
                                  : 'Betreiber- und Kontaktangaben werden ergänzt.',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 24),
                  Text(
                    kind == 'privacy'
                        ? '''Eltern und Kinder haben eigene Zugänge. Eltern sehen innerhalb ihrer berechtigten Familie Materialien, Lernaufträge, gestellte Aufgaben, Antworten, Hinweise, Erklärungen, Hilfewünsche und eine ungefähre aktive Lernzeit. Andere Apps, Webseiten außerhalb von SCHULPILOT und das übrige Gerät werden nicht überwacht.

Im öffentlichen Testraum werden ausschließlich synthetische Inhalte verarbeitet. Bitte dort keine echten Namen, Fotos oder Kinderantworten eingeben. Jeder Testraum ist getrennt und wird nach 24 Stunden gelöscht. Die feste Demo benötigt keine KI. Der ausdrücklich gekennzeichnete KI-Test sendet ausschließlich ein vom Server erzeugtes künstliches Testblatt bzw. festen Beispielstoff an die konfigurierten kostenlosen OpenRouter-Modelle. Freie Kontoeingaben werden dabei nicht übertragen.

Echte Lerninhalte werden nur über ausdrücklich freigegebene und technisch geeignete Anbieter verarbeitet. Ist kein passender geschützter Endpunkt verfügbar, wird die Verarbeitung mit einer verständlichen Meldung angehalten. Die aktuelle Betreiberfreigabe steht oben. Nach einer abgeschlossenen Einheit wertet der freigegebene KI-Dienst auch die gespeicherten Aufgaben, Antworten, Fehlversuche und genutzten Hinweise aus und erstellt passende Anschlussübungen. Namen, Zugangsdaten und Familienkennungen werden dafür nicht benötigt. Die Gesamtbewertung und Wiederholungsplanung werden aus den gespeicherten Aktivitäten berechnet.

Fragen zum Heft und ihre Antworten gehören zum privaten Lernverlauf und sind für berechtigte Eltern sichtbar. Die freigegebene Lern-KI erhält dafür die Frage und die bestätigten Hefttexte sowie bei Nachfragen wenige vorherige Antworten. Spracheingabe und Vorlesen sind freiwillig. Der Sprachdienst des Geräts oder Browsers kann Sprache online verarbeiten; vor einer Aufnahme erscheint ein Hinweis. SCHULPILOT speichert keine Audiodateien und lädt selbst keine hoch. Der erkannte Text bleibt vor dem Senden bearbeitbar. Auch Vorlesestimmen können einen Gerätedienst verwenden. Tippen und Lesen bleiben möglich.

Fotos werden vor dem Upload zum Drehen und Zuschneiden angezeigt. Ausstehende zugeschnittene Fotos sind auf diesem Gerät 24 Stunden fortsetzbar (höchstens 8 Seiten / 3 MB). Ältere Einträge werden beim nächsten Appstart oder Öffnen des Assistenten bereinigt; Abmelden oder Entfernen löscht diese lokale Warteschlange. Der Server entfernt Metadaten und gibt private Bilder ausschließlich nach Berechtigungsprüfung aus. Eine Verkleinerung ersetzt nicht das Entfernen persönlicher Angaben im Bild.

Die Google-Anmeldung ist freiwillig und ausschließlich für Eltern. Erst beim bewussten Start wird Google geöffnet. Wir prüfen die von Google bestätigte E-Mail-Adresse und eine eindeutige Kontokennung. Google-Passwörter, Zugriffstokens und Erneuerungstokens werden nicht gespeichert. Bestehende Elternkonten müssen Google nach Anmeldung mit ihrem bisherigen Passwort ausdrücklich verknüpfen. Kinder verwenden weiterhin ihren eigenen Zugang ohne Google. Verknüpfungen lassen sich in den Einstellungen trennen und werden bei Kontolöschung entfernt. Nicht abgeschlossene Anmeldevorgänge gelten zehn Minuten und werden spätestens beim nächsten täglichen Bereinigungslauf gelöscht.

Sitzungen sind widerrufbar. Eltern können Kinderkonten und ihr eigenes Konto löschen sowie einen Familienexport mit Materialien und Lernverlauf herunterladen. Beim Löschen des Familieninhabers wird dessen gesamte Familie gelöscht; eingeladene Eltern verlieren den Zugriff.

Eltern können freiwillig Schulnoten mit Fach, Datum und optionaler Notiz verwalten und deren Gewichtung im Lernplan ausschalten. Noten und Notennotizen werden nicht automatisch an die Lern-KI übermittelt; nur eine abgeleitete Unterstützungsstrategie wird ergänzt. Die Einträge gehören zum Familienexport und werden mit dem Kinderkonto gelöscht.

Freiwillige Lerntipps verweisen auf Sofatutor. Nur dein eigener Klick öffnet den Anbieter; Anmeldung und Abo können nötig sein. Hefttexte, Fotos und SCHULPILOT-Zugänge werden dabei nicht übertragen. Persönliche Zuordnungen, Rückmeldungen und Linkaufrufe sehen nur das eigene Kind und berechtigte Eltern. Ein Linkaufruf beweist kein angesehenes Video und zählt nicht als gelöste Übung oder Lernzeit. Andere Webseiten werden nicht überwacht.

Aufbewahrung: Materialien, Einheiten, Antworten, Heftfragen, Schulnoteneinträge, persönliche Lerntippzuordnungen und Linkaufrufe, Aktivitäten und Nachrichten höchstens 365 Tage; technische Aufträge 30 Tage; abgelaufene Zugangstokens und Sitzungen weitere 7 Tage; tägliche Backups 14 Tage. Backups müssen vor einer Wiederherstellung mit zwischenzeitlichen Löschungen abgeglichen werden. Abrechnung und Betriebsprotokolle enthalten keine Fotos oder vollständigen Kinderantworten.

Benachrichtigungen sind freiwillig. Erst beim Einschalten auf einem angemeldeten Gerät wird Google Firebase Cloud Messaging initialisiert. Für Kinder ist vorher zusätzlich eine Freigabe durch die Eltern erforderlich. Firebase erhält dabei Installations- und Gerätetokens sowie technische Verbindungsdaten; Namen, Lerninhalte, Noten und Familienkennungen werden nicht mitgesendet. Die Verarbeitung ist nicht auf Deutschland oder die EU beschränkt. Analytics, Werbung und Firebase Authentication werden nicht verwendet. Ohne geeignete Google Play Services ist Android-Push nicht zugesichert. Ausschalten, Abmelden und Rechteentzug sperren den weiteren Versand im Backend. Gerätetokens werden verschlüsselt gespeichert, bei Abmeldung oder Entzug entfernt und nach 60 Tagen ohne Aktualisierung bereinigt; Versandstatus nach 14 Tagen. Das Löschen eines Push-Tokens ist keine Zusage einer sofortigen Löschung sämtlicher Firebase-Installationsdaten oder Google-Backups. Die allgemeinen Push-Freigaben und die tatsächlich beobachtete Zustellung werden getrennt geprüft.

Bei einer Bestellung speichern wir Tarif, Gesamtpreis, Vertragsfassung und Zahlungszuordnung. Zahlungsbelege bleiben für die gesetzliche Aufbewahrung acht Jahre nach Ende des Buchungsjahres erhalten; beim Löschen der Familie wird ihre Kontozuordnung entfernt. Diese Belege enthalten keine Kinderantworten oder Lernmaterialien. Die App liest keine Bankkonten aus; ein Administrator prüft Überweisungen im tatsächlichen Bankkonto.

Es gibt keine Werbung, keinen Verkauf von Kinderprofilen und keine gemeinsame Inhaltsbibliothek aus privaten Lernmaterialien. Aktive Lernzeit bleibt eine Näherung. Eine einzelne richtige Antwort begründet keine sichere Beherrschung; fehlende Nutzung keine Aussage über Verständnis.'''
                        : '''Schulpilot begleitet deinen Lernalltag: vom Foto deiner Heftseiten über Erklärungen und Übungen bis zur passenden Wiederholung.

Kinder lernen in ihrem eigenen Lernraum. Eltern sehen, was schon gelingt, und können helfen, wenn es hakt.

Die Demo enthält vorbereitete Beispiele. In deinem eigenen Konto übst du mit deinem Unterrichtsmaterial und KI-Unterstützung.

Version $appVersion''',
                    style: TextStyle(fontSize: 15, height: 1.8),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
