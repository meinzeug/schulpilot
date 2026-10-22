import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart'
    show TextInput, HardwareKeyboard, KeyboardLockMode;
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'auth_information.dart';
import 'app_version.dart';
import 'download_panel.dart';
import 'ui.dart';
import 'store_screens.dart';
import 'google_login.dart';
import 'public_trial.dart';
import 'legal_links.dart';

class LandingScreen extends StatefulWidget {
  final AppState state;
  const LandingScreen(this.state, {super.key});
  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  AppState get state => widget.state;
  late Future<Json> catalog;
  @override
  void initState() {
    super.initState();
    catalog = state.api.get('/store/catalog');
  }

  @override
  void didUpdateWidget(covariant LandingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state.api, state.api)) {
      catalog = state.api.get('/store/catalog');
    }
  }

  void reloadCatalog() {
    setState(() {
      catalog = state.api.get('/store/catalog');
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: catalog,
    builder: (context, snapshot) {
      final offer = PublicTrialOffer.fromCatalog(
        snapshot.connectionState == ConnectionState.done && !snapshot.hasError
            ? snapshot.data ?? {}
            : {},
      );
      return Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              final hero = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tag('GEMEINSAM GUT WEITERLERNEN'),
                  SizedBox(height: 24),
                  Text(
                    'Lernen, das zum\nSchulalltag passt.',
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
                    'Aus euren Heftseiten werden verständliche Lernschritte. Dein Kind übt mit Hilfe, du behältst den Überblick.',
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
                        onPressed: () => context.go(
                          state.user == null ? '/register' : '/app',
                        ),
                        icon: Icon(Icons.arrow_forward_rounded),
                        label: Text(
                          state.user != null
                              ? 'Mein Lernraum'
                              : offer.available
                              ? '30 Tage kostenlos testen'
                              : 'Elternkonto erstellen',
                        ),
                      ),
                      _DemoEntryButton(state),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (snapshot.connectionState != ConnectionState.done)
                    const Text('Der aktuelle Testzugang wird geprüft …')
                  else if (snapshot.hasError) ...[
                    const Text(
                      'Das aktuelle Testangebot konnte nicht geladen werden. Es wurde nichts gebucht.',
                    ),
                    TextButton.icon(
                      onPressed: reloadCatalog,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Testangebot erneut prüfen'),
                    ),
                  ] else
                    TrialTermsSummary(offer, compact: true),
                ],
              );
              final flow = Container(
                padding: EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      context.palette.isDark
                          ? context.palette.panelSurface
                          : const Color(0xFF202C34),
                      context.palette.isDark
                          ? context.palette.surfaceLow
                          : const Color(0xFF1B272E),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
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
                        'fotos',
                      ),
                      (
                        Icons.lightbulb_outline_rounded,
                        '02',
                        'Verstehen & üben',
                        'Mit Hilfe, wenn es hakt.',
                        'lernen',
                      ),
                      (
                        Icons.check_circle_outline_rounded,
                        '03',
                        'Wissen festigen',
                        'Neue Aufgaben. Später wiederholen.',
                        'wiederholen',
                      ),
                    ])
                      ActionPanel(
                        padding: EdgeInsets.all(18),
                        actionLabel: '${item.$3}: Ablauf ansehen',
                        onPressed: () =>
                            context.go('/about?section=${item.$5}'),
                        child: Row(
                          children: [
                            Icon(
                              item.$1,
                              color: context.palette.teal,
                              size: 24,
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.$3,
                                    style: TextStyle(
                                      color: context.palette.ink,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    item.$4,
                                    style: TextStyle(
                                      color: context.palette.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              item.$2,
                              style: TextStyle(
                                color: context.palette.muted,
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
                                  state.user == null
                                      ? 'Anmelden'
                                      : 'Mein Lernraum',
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
                                  'plan',
                                ),
                                (
                                  Icons.support_agent_rounded,
                                  'Hilfe im richtigen Moment',
                                  'Verständliche Erklärungen und passende Hinweise.',
                                  'hilfe',
                                ),
                                (
                                  Icons.family_restroom_rounded,
                                  'Eltern bleiben im Bild',
                                  'Was lief gut? Wo braucht dein Kind Unterstützung?',
                                  'eltern',
                                ),
                              ])
                                SizedBox(
                                  width: wide
                                      ? (constraints.maxWidth.clamp(0, 1240) -
                                                128) /
                                            3
                                      : double.infinity,
                                  child: ActionPanel(
                                    actionLabel: '${item.$2}: Mehr erfahren',
                                    onPressed: () =>
                                        context.go('/about?section=${item.$4}'),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          item.$1,
                                          color: context.palette.teal,
                                        ),
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
                          if (kIsWeb &&
                              snapshot.connectionState ==
                                  ConnectionState.done &&
                              !snapshot.hasError &&
                              snapshot.hasData) ...[
                            StoreSection(
                              state,
                              catalog: snapshot.data,
                              showTrial: false,
                            ),
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
                              PublicLegalLinks(state.api.base),
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
    },
  );
}

class _DemoEntryButton extends StatefulWidget {
  final AppState state;
  const _DemoEntryButton(this.state);
  @override
  State<_DemoEntryButton> createState() => _DemoEntryButtonState();
}

class _DemoEntryButtonState extends State<_DemoEntryButton> {
  int? authenticationRevision;
  AppState? authenticationState;
  @override
  void dispose() {
    final revision = authenticationRevision;
    if (revision != null) authenticationState?.cancelAuthentication(revision);
    super.dispose();
  }

  @override
  Widget build(BuildContext _) => ActionButton(
    label: 'Demo ausprobieren',
    secondary: true,
    onPressed: () async {
      final state = widget.state, account = widget.state.user;
      if (account != null && !state.isDemo) {
        final confirmed = await confirmDialog(
          context,
          'Zum künstlichen Testraum wechseln?',
          'Du verlässt diesen angemeldeten Zugang. Für die Rückkehr brauchst du deine bisherigen Zugangsdaten. Im Testraum nur künstliche Angaben verwenden.',
          confirmLabel: 'Testraum öffnen',
        );
        if (!confirmed) return;
      }
      if (!mounted ||
          !identical(state.user, account) ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final revision = state.beginAuthentication();
      authenticationState = state;
      authenticationRevision = revision;
      final response = await state.api.post('/demo');
      if (!mounted) return;
      await state.accept(response, authenticationRevision: revision);
      if (mounted && ModalRoute.of(context)?.isCurrent != false) {
        context.go('/app');
      }
    },
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

class _AuthScreenState extends State<AuthScreen> with WidgetsBindingObserver {
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
  bool consent = false, passwordVisible = false, tokenVisible = false;
  bool completed = false, leaveAllowed = false, leavePromptOpen = false;
  bool get editable => !submitting && !googleBusy && !completed;
  bool get hasRegistrationDraft =>
      widget.mode == 'register' &&
      !completed &&
      (name.text.isNotEmpty ||
          family.text.isNotEmpty ||
          password.text.isNotEmpty ||
          consent ||
          (_identifierEdited && username.text.isNotEmpty));
  String? _identifierFromPreviousForm;
  bool _identifierEdited = false;
  String? result;
  String? error;
  String? accessNotice;
  Future<Json>? registrationCatalog;
  int? authenticationRevision;
  AppState? authenticationState;

  void cancelOwnAuthentication() {
    final revision = authenticationRevision;
    if (revision != null) authenticationState?.cancelAuthentication(revision);
    authenticationRevision = null;
    authenticationState = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(keyboardChanged);
    passwordFocus.addListener(passwordFocusChanged);
    _restoreIdentifier();
    _readLink();
    if (widget.mode == 'register') {
      registrationCatalog = widget.state.api.get('/store/catalog');
    }
  }

  bool keyboardChanged(KeyEvent event) {
    if (mounted && passwordFocus.hasFocus) setState(() {});
    return false;
  }

  void passwordFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AuthScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.linkUri != widget.linkUri || oldWidget.mode != widget.mode) {
      cancelOwnAuthentication();
      formRevision++;
      submitting = googleBusy = false;
      completed = leaveAllowed = false;
      if (oldWidget.mode != widget.mode) {
        registrationCatalog = widget.mode == 'register'
            ? widget.state.api.get('/store/catalog')
            : null;
        _restoreIdentifier();
        name.clear();
        family.clear();
        consent = false;
      }
      if (oldWidget.mode != widget.mode ||
          oldWidget.linkUri.fragment != widget.linkUri.fragment) {
        password.clear();
        passwordVisible = false;
        tokenVisible = false;
      }
      _readLink();
      result = null;
      error = null;
      accessNotice = null;
      fieldErrors.clear();
    }
  }

  void _restoreIdentifier() {
    final identifier = widget.state.takeAuthIdentifier();
    _identifierFromPreviousForm = identifier;
    _identifierEdited = false;
    username.text =
        widget.mode == 'login' ||
            (['register', 'recovery', 'resend'].contains(widget.mode) &&
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
    cancelOwnAuthentication();
    HardwareKeyboard.instance.removeHandler(keyboardChanged);
    passwordFocus.removeListener(passwordFocusChanged);
    WidgetsBinding.instance.removeObserver(this);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        (passwordVisible || tokenVisible)) {
      setState(() => passwordVisible = tokenVisible = false);
    }
  }

  Future<bool> confirmLeaving() async {
    if (!hasRegistrationDraft) return true;
    if (leavePromptOpen || submitting || googleBusy) return false;
    leavePromptOpen = true;
    final revision = formRevision;
    try {
      final confirmed = await confirmDialog(
        context,
        'Registrierungsentwurf verwerfen?',
        'Deine Angaben sind noch nicht gesendet. Bei Abbrechen kannst du sie hier weiterbearbeiten.',
        confirmLabel: 'Entwurf verwerfen',
        destructive: true,
      );
      return mounted && revision == formRevision && confirmed;
    } finally {
      leavePromptOpen = false;
    }
  }

  Future<void> goToAuth(String location) async {
    if (submitting || googleBusy) return;
    final targetUri = Uri.parse(location), revision = formRevision;
    final target = targetUri.path;
    if (target != '/register' && !await confirmLeaving()) return;
    if (!mounted || revision != formRevision) return;
    final identifier = username.text.isNotEmpty || _identifierEdited
        ? username.text.trim()
        : _identifierFromPreviousForm ?? '';
    widget.state.rememberAuthIdentifier(
      ['/login', '/register', '/recovery', '/resend'].contains(target)
          ? identifier
          : '',
    );
    final next =
        targetUri.queryParameters['next'] ??
        widget.linkUri.queryParameters['next'];
    context.go(
      [
                '/login',
                '/register',
                '/recovery',
                '/resend',
                '/reset',
                '/verify',
              ].contains(target) &&
              next != null &&
              RegExp(r'^/bestellen/[a-z][a-z0-9-]{1,29}$').hasMatch(next)
          ? targetUri.replace(queryParameters: {'next': next}).toString()
          : Uri(
              path: targetUri.path,
              fragment: targetUri.hasFragment ? targetUri.fragment : null,
            ).toString(),
    );
  }

  void fieldEdited(String name) {
    if (name == 'username') _identifierEdited = true;
    setState(() {
      fieldErrors.remove(name);
      error = null;
      result = null;
    });
  }

  String? get pastedLinkCode {
    if (!['reset', 'verify', 'invite'].contains(widget.mode)) return null;
    try {
      final uri = Uri.tryParse(token.text.trim());
      if (uri == null ||
          uri.path != '/${widget.mode}' ||
          uri.userInfo.isNotEmpty) {
        return null;
      }
      final base = Uri.parse(widget.state.api.base);
      if (uri.hasScheme
          ? uri.scheme != 'https' || uri.origin != base.origin
          : uri.hasAuthority) {
        return null;
      }
      final code = Uri.splitQueryString(uri.fragment)['token'];
      return code != null && RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(code)
          ? code
          : null;
    } on FormatException {
      return null;
    }
  }

  void focusError(String key) {
    final node = {
      'username': usernameFocus,
      'name': nameFocus,
      'family': familyFocus,
      'password': passwordFocus,
      'token': tokenFocus,
      'consent': consentFocus,
    }[key];
    node?.requestFocus();
    final target = node?.context;
    if (target != null) Scrollable.ensureVisible(target, alignment: .2);
  }

  bool validateFields() {
    final mode = widget.mode;
    final invalid = <String, String>{};
    if (['login', 'register', 'recovery', 'resend'].contains(mode) &&
        username.text.trim().isEmpty) {
      invalid['username'] = mode == 'login'
          ? 'Gib deine E-Mail oder deinen Benutzernamen ein.'
          : 'Gib deine E-Mail-Adresse ein.';
    } else if (username.text.trim().runes.length > 254) {
      invalid['username'] = 'Nutze höchstens 254 Zeichen.';
    } else if (['register', 'recovery', 'resend'].contains(mode) &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(username.text.trim())) {
      invalid['username'] =
          'Prüfe die E-Mail-Adresse, zum Beispiel name@beispiel.de.';
    }
    if (mode == 'register' && name.text.trim().isEmpty) {
      invalid['name'] = 'Gib deinen Anzeigenamen ein.';
    } else if (name.text.trim().runes.length > 80) {
      invalid['name'] = 'Nutze höchstens 80 Zeichen.';
    }
    if (mode == 'register' && family.text.trim().isEmpty) {
      invalid['family'] = 'Gib einen Namen für deine Familie ein.';
    } else if (family.text.trim().runes.length > 120) {
      invalid['family'] = 'Nutze höchstens 120 Zeichen.';
    }
    if (['login', 'register', 'reset', 'invite'].contains(mode) &&
        password.text.isEmpty) {
      invalid['password'] = 'Gib dein Passwort ein.';
    } else if (['register', 'reset'].contains(mode) &&
        password.text.trim().runes.length < 12) {
      invalid['password'] =
          'Dein neues Passwort braucht mindestens 12 Zeichen.';
    } else if (password.text.runes.length > 128) {
      invalid['password'] = 'Nutze höchstens 128 Zeichen.';
    }
    if (['reset', 'verify', 'invite'].contains(mode) &&
        token.text.trim().isEmpty) {
      invalid['token'] =
          'Öffne den vollständigen E-Mail-Link oder füge seinen Code ein.';
    } else if (['reset', 'verify', 'invite'].contains(mode) &&
        !RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(token.text.trim())) {
      invalid['token'] = 'Der Code ist unvollständig. Öffne den vollständigen E-Mail-Link oder füge den ganzen Code ein.';
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
    if (submitting || googleBusy || completed || !validateFields()) return;
    final mode = widget.mode, uri = widget.linkUri;
    final revision = formRevision;
    setState(() => submitting = true);
    FocusScope.of(context).unfocus();
    try {
      cancelOwnAuthentication();
      authenticationState = widget.state;
      authenticationRevision = widget.state.beginAuthentication();
      if (mode == 'login') {
        await widget.state.login(
          username.text.trim(),
          password.text,
          authenticationRevision: authenticationRevision,
        );
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
          'resend' => '/auth/resend-verification',
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
          'resend' => {'email': username.text.trim()},
          'reset' => {'token': token.text.trim(), 'password': password.text},
          'verify' => {'token': token.text.trim()},
          _ => {
            'token': token.text.trim(),
            'password': password.text,
            'display_name': name.text.trim(),
          },
        },
      );
      if (!mounted || revision != formRevision) return;
      if (['register', 'reset'].contains(mode)) {
        TextInput.finishAutofillContext(shouldSave: true);
      }
      setState(() {
        result = data['message'] is String
            ? data['message']
            : 'Die Änderung wurde bestätigt.';
        accessNotice = mode == 'register' && data['access_notice'] is String
            ? data['access_notice'] as String
            : null;
        completed = [
          'register',
          'reset',
          'verify',
          'invite',
          'recovery',
          'resend',
        ].contains(mode);
        if (mode == 'register') {
          password.clear();
          passwordVisible = false;
        }
        if (['reset', 'verify', 'invite'].contains(mode)) {
          token.clear();
          password.clear();
          passwordVisible = tokenVisible = false;
        }
      });
      showFeedback();
    } catch (failure) {
      if (!mounted || revision != formRevision) return;
      setState(
        () => error = failure is ApiError ? failure.message : 'Die Anfrage konnte nicht abgeschlossen werden. Versuche es bitte erneut.',
      );
      showFeedback();
    } finally {
      if (mounted && revision == formRevision) {
        setState(() => submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final revision = formRevision;
    final title = switch (mode) {
      'register' => 'Euer Start mit Schulpilot',
      'recovery' => 'Passwort vergessen?',
      'resend' => 'Bestätigungslink fehlt?',
      'reset' => 'Neues Elternpasswort',
      'verify' => 'E-Mail bestätigen',
      'invite' => 'Zur Familie dazukommen',
      _ => 'Willkommen zurück',
    };
    return PopScope<Object?>(
      canPop:
          !submitting && !googleBusy && (!hasRegistrationDraft || leaveAllowed),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || submitting || googleBusy || leavePromptOpen) return;
        if (await confirmLeaving() && mounted) {
          setState(() => leaveAllowed = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && context.canPop()) context.pop();
          });
        }
      },
      child: Scaffold(
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
                      if (passwordFocus.hasFocus &&
                          HardwareKeyboard.instance.lockModesEnabled.contains(
                            KeyboardLockMode.capsLock,
                          ))
                        Semantics(
                          liveRegion: true,
                          child: const Notice(
                            'Die Feststelltaste ist aktiv. Prüfe die Groß- und Kleinschreibung deines Passworts.',
                          ),
                        ),
                      Text(switch (mode) {
                        'login' => 'Eltern und Kinder melden sich mit ihrem eigenen Zugang an.',
                        'register' => 'Erstelle dein Elternkonto und bestätige deine E-Mail. Hier löst du keine kostenpflichtige Bestellung aus.',
                        'recovery' => 'Für Eltern: Gib die E-Mail deines Kontos ein. Kinder lassen ihr Passwort von ihren Eltern ändern.',
                        'resend' => 'Für ein noch unbestätigtes Elternkonto: Fordere bewusst einen neuen E-Mail-Link an. Prüfe auch deinen Spamordner. Die Rückmeldung verrät nicht, ob ein Konto existiert.',
                        'reset' => 'Wähle ein neues Elternpasswort. Der sichere Code kommt aus deinem E-Mail-Link.',
                        'invite' => 'Nimm die Einladung zu deiner Familie an. Nutze bei einem vorhandenen Elternkonto dessen Passwort.',
                        _ => 'Bestätige deine E-Mail-Adresse. Der sichere Code wird aus dem vollständigen E-Mail-Link übernommen.',
                      }, style: TextStyle(color: context.palette.muted)),
                      if (mode == 'register' && !completed) ...[
                        const SizedBox(height: 20),
                        FutureBuilder<Json>(
                          future: registrationCatalog,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Text(
                                'Der aktuelle Testzugang wird geprüft …',
                              );
                            }
                            if (snapshot.hasError) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Die aktuelle Testfreigabe konnte nicht geprüft werden. Ein Elternkonto kannst du trotzdem kostenlos anlegen.',
                                  ),
                                  TextButton(
                                    onPressed: () => setState(() {
                                      registrationCatalog = widget.state.api
                                          .get('/store/catalog');
                                    }),
                                    child: const Text(
                                      'Testfreigabe erneut prüfen',
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Panel(
                              color: context.palette.mint,
                              child: TrialTermsSummary(
                                PublicTrialOffer.fromCatalog(
                                  snapshot.data ?? {},
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                      SizedBox(height: 24),
                      SizedBox(
                        key: feedbackKey,
                        child: Semantics(
                          liveRegion: true,
                          child: Column(
                            children: [
                              if (result != null)
                                Notice(
                                  result!,
                                  icon: Icons.check_circle_outline,
                                ),
                              if (result != null && accessNotice != null)
                                Notice(accessNotice!),
                              if (mode == 'register' && completed) ...[
                                const SizedBox(height: 20),
                                const Notice(
                                  'Nächster Schritt: Prüfe dein E-Mail-Postfach und den Spamordner. Wenn du einen Bestätigungslink erhalten hast, öffne ihn vollständig. Danach kannst du dich anmelden.',
                                ),
                                TextButton(
                                  onPressed: () => goToAuth('/verify'),
                                  child: const Text(
                                    'Link-Code aus E-Mail eingeben',
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => setState(() {
                                    completed = false;
                                    result = null;
                                    password.clear();
                                    passwordVisible = false;
                                  }),
                                  child: const Text(
                                    'Registrierungsangaben erneut bearbeiten',
                                  ),
                                ),
                              ],
                              if (error != null) Notice(error!, warning: true),
                              if (fieldErrors.isNotEmpty) ...[
                                Text(
                                  '${fieldErrors.length} ${fieldErrors.length == 1 ? 'Eingabe braucht' : 'Eingaben brauchen'} deine Prüfung.',
                                ),
                                for (final key in fieldErrors.keys)
                                  TextButton(
                                    onPressed: editable
                                        ? () => focusError(key)
                                        : null,
                                    child: Text(
                                      '${const {'username': 'E-Mail oder Benutzername', 'name': 'Anzeigename', 'family': 'Familienname', 'password': 'Passwort', 'token': 'Link-Code', 'consent': 'Berechtigungsbestätigung'}[key]} prüfen',
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if ([
                        'login',
                        'register',
                        'recovery',
                        'resend',
                      ].contains(mode)) ...[
                        TextField(
                          controller: username,
                          onChanged: (_) => fieldEdited('username'),
                          focusNode: usernameFocus,
                          enabled: editable,
                          autocorrect: false,
                          textInputAction: ['recovery', 'resend'].contains(mode)
                              ? TextInputAction.done
                              : TextInputAction.next,
                          onSubmitted: (_) async {
                            if (['recovery', 'resend'].contains(mode)) {
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
                          enabled: editable,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) =>
                              (mode == 'register' ? familyFocus : passwordFocus)
                                  .requestFocus(),
                          decoration: InputDecoration(
                            labelText: 'Dein Anzeigename',
                            helperText: mode == 'invite'
                                ? 'Nur für ein neues Elternkonto erforderlich.'
                                : null,
                            helperMaxLines: 3,
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
                          enabled: editable,
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
                          enabled: editable,
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
                          smartDashesType: SmartDashesType.disabled,
                          smartQuotesType: SmartQuotesType.disabled,
                          enableIMEPersonalizedLearning: false,
                          autofillHints: ['login', 'invite'].contains(mode)
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
                              onPressed: submitting || googleBusy
                                  ? null
                                  : () => setState(
                                      () => passwordVisible = !passwordVisible,
                                    ),
                            ),
                            labelText: mode == 'invite'
                                ? 'Elternpasswort'
                                : mode == 'login'
                                ? 'Passwort'
                                : 'Neues Passwort',
                            helperText: mode == 'invite'
                                ? 'Bestehendes Konto: dein aktuelles Passwort, auch wenn du schon angemeldet bist. Neues Konto: mindestens 12 Zeichen.'
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
                          enabled: editable,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => submit(),
                          obscureText: !tokenVisible,
                          smartDashesType: SmartDashesType.disabled,
                          smartQuotesType: SmartQuotesType.disabled,
                          enableIMEPersonalizedLearning: false,
                          decoration: InputDecoration(
                            suffixIcon: IconButton(
                              tooltip: tokenVisible
                                  ? 'Code verbergen'
                                  : 'Code anzeigen',
                              onPressed: submitting || googleBusy
                                  ? null
                                  : () => setState(
                                      () => tokenVisible = !tokenVisible,
                                    ),
                              icon: Icon(
                                tokenVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                            labelText: 'Sicherer Link-Code',
                            helperText: 'Wird aus dem E-Mail-Link übernommen.',
                            helperMaxLines: 3,
                            errorText: fieldErrors['token'],
                            errorMaxLines: 3,
                          ),
                        ),
                        if (pastedLinkCode != null)
                          TextButton.icon(
                            onPressed: editable
                                ? () {
                                    final code = pastedLinkCode;
                                    if (code == null) return;
                                    token.text = code;
                                    fieldEdited('token');
                                    tokenFocus.requestFocus();
                                  }
                                : null,
                            icon: const Icon(Icons.link_rounded),
                            label: const Text(
                              'Code aus diesem E-Mail-Link übernehmen',
                            ),
                          ),
                        SizedBox(height: 16),
                      ],
                      if (mode == 'register') ...[
                        TextButton.icon(
                          onPressed: submitting || googleBusy
                              ? null
                              : () => context.push('/privacy'),
                          icon: const Icon(Icons.privacy_tip_outlined),
                          label: const Text(
                            'Datenschutz vor dem Anlegen lesen',
                          ),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: consent,
                          focusNode: consentFocus,
                          onChanged: submitting || googleBusy
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
                              style: TextStyle(
                                color: context.palette.warningInk,
                              ),
                            ),
                          ),
                        SizedBox(height: 12),
                      ],
                      if (!completed)
                        ActionButton(
                          key: ValueKey(('auth-submit', revision)),
                          label: submitting
                              ? 'Bitte warten …'
                              : switch (mode) {
                                  'register' => 'Elternkonto anlegen',
                                  'recovery' =>
                                    'Wiederherstellungslink anfordern',
                                  'resend' => 'Bestätigungslink anfordern',
                                  'verify' => 'E-Mail bestätigen',
                                  'reset' => 'Passwort erneuern',
                                  'invite' => 'Einladung annehmen',
                                  _ => 'Anmelden',
                                },
                          onPressed: submit,
                          enabled: editable,
                        ),
                      if (completed &&
                          ['recovery', 'resend'].contains(mode)) ...[
                        TextButton(
                          onPressed: submitting
                              ? null
                              : () async {
                                  setState(() => completed = false);
                                  await submit();
                                },
                          child: const Text('Weiteren Link bewusst anfordern'),
                        ),
                        TextButton(
                          onPressed: submitting
                              ? null
                              : () {
                                  setState(() {
                                    completed = false;
                                    result = null;
                                    error = null;
                                  });
                                  usernameFocus.requestFocus();
                                },
                          child: const Text('Andere E-Mail-Adresse verwenden'),
                        ),
                      ],
                      SizedBox(height: 18),
                      if ((mode == 'login' || mode == 'register') && !completed)
                        GoogleLoginButton(
                          widget.state,
                          key: ValueKey(('google-auth', revision)),
                          enabled: !submitting && !googleBusy,
                          onBusyChanged: (busy) {
                            if (mounted && revision == formRevision) {
                              setState(() => googleBusy = busy);
                            }
                          },
                        ),
                      if (mode == 'login')
                        TextButton.icon(
                          onPressed: submitting || googleBusy
                              ? null
                              : () => showDialog<void>(
                                  context: context,
                                  builder: (dialog) => AlertDialog(
                                    scrollable: true,
                                    title: const Text(
                                      'Deinen Kinderzugang wiederfinden',
                                    ),
                                    content: const Text(
                                      'Frage deine Eltern nach deinem eigenen Benutzernamen. Sie können in ihrem Elternkonto auch ein neues Passwort für dich setzen. Die E-Mail-Wiederherstellung ist für Elternkonten gedacht.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dialog),
                                        child: const Text('Verstanden'),
                                      ),
                                    ],
                                  ),
                                ),
                          icon: const Icon(Icons.child_care_rounded),
                          label: const Text('Kinderzugang vergessen?'),
                        ),
                      if (['login', 'register', 'verify'].contains(mode))
                        TextButton(
                          onPressed: submitting || googleBusy
                              ? null
                              : () => goToAuth('/resend'),
                          child: const Text(
                            'Bestätigungslink erneut anfordern',
                          ),
                        ),
                      if (mode == 'recovery')
                        TextButton(
                          onPressed: submitting
                              ? null
                              : () => goToAuth('/reset'),
                          child: const Text('Link-Code aus E-Mail eingeben'),
                        ),
                      if (mode == 'reset')
                        TextButton(
                          onPressed: submitting
                              ? null
                              : () => goToAuth('/recovery'),
                          child: const Text(
                            'Neuen Wiederherstellungslink anfordern',
                          ),
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
      ),
    );
  }
}

class InformationScreen extends StatelessWidget {
  final String kind;
  final String? section;
  final Api? api;
  const InformationScreen(this.kind, {super.key, this.section, this.api});

  static const features = <String, (String, String)>{
    'fotos': (
      'Heftseiten fotografieren',
      'Fotografiere normale handschriftliche Heftseiten oder Arbeitsblätter. Drehe und beschneide das Bild und gib die Fotos bewusst ab. Prüfe danach den erkannten Text. Erst „Stimmt, weiter“ bestätigt deine Quelle; unlesbare Stellen bleiben offen.',
    ),
    'lernen': (
      'Verstehen und selbst üben',
      'Lies die Erklärung zum bestätigten Unterrichtsstoff und bearbeite eine passende Aufgabe. Deine Antwort und die Rückmeldung bleiben zusammen sichtbar, bis du weitergehst. Hinweise helfen schrittweise; eine unterstützte Lösung wird von einer selbstständigen Lösung unterschieden.',
    ),
    'wiederholen': (
      'Wissen später erneut abrufen',
      'Eine einzelne richtige Antwort beweist noch keine sichere Beherrschung. Neue Aufgaben an späteren Tagen helfen, Wissen erneut abzurufen. Weitere Runden startest du bewusst; verpasste Tage erzeugen keinen Pflicht-Aufgabenberg.',
    ),
    'plan': (
      'Ein überschaubarer Plan für heute',
      'Heute zeigt den nächsten sinnvollen Schritt und deinen gespeicherten Lernstand. Eltern können Themen und Mindestziele setzen. Kleine Runden und Pausen strukturieren den Nachmittag; freiwilliges Weiterlernen bleibt möglich.',
    ),
    'hilfe': (
      'Passende Hilfe, ohne sofort vorzusagen',
      'Fordere einen kleinen Hinweis, ein Beispiel oder eine Erklärung an. Bei Hausaufgaben kannst du Fragen zu deinem Foto stellen. Wenn du festhängst, kannst du berechtigte Eltern um Hilfe bitten. Sprache, Kamera und Bildschirmfreigabe starten nur nach deiner ausdrücklichen Aktion.',
    ),
    'eltern': (
      'Nachvollziehbarer Lernstand für Eltern',
      'Berechtigte Eltern sehen Aufgaben, Antworten und genutzte Hilfe in ihrer Familie. Selbstständig gelöst, mit Unterstützung gelöst, weiter üben und unklar bleiben getrennt. Eine KI-Einschätzung ergänzt diese Belege; sie ersetzt sie nicht und stellt keine pädagogische Diagnose.',
    ),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: brand(),
      leading: IconButton(
        tooltip: GoRouter.maybeOf(context)?.canPop() == true
            ? 'Zurück'
            : 'Zur Startseite',
        icon: Icon(Icons.arrow_back),
        onPressed: () {
          final router = GoRouter.maybeOf(context);
          if (router == null) {
            Navigator.maybePop(context);
          } else if (router.canPop()) {
            router.pop();
          } else {
            router.go('/');
          }
        },
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
                  LoadView<Json>(
                    revision: api,
                    load: () => (api ?? Api()).get('/legal'),
                    builder: (data, _) {
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
                            if (data['complete'] == true &&
                                data['support_email'] is String)
                              PublicSupportContact(data['support_email']),
                          ],
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 24),
                  if (kind != 'privacy' && features.containsKey(section)) ...[
                    SurfaceInset(
                      tone: PanelTone.info,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          heading(features[section]!.$1),
                          Text(features[section]!.$2),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => context.go('/about'),
                      icon: const Icon(Icons.view_list_outlined),
                      label: const Text('Alle Abläufe ansehen'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (kind != 'privacy' && !features.containsKey(section))
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final feature in features.entries)
                          OutlinedButton(
                            onPressed: () =>
                                context.go('/about?section=${feature.key}'),
                            child: Text(feature.value.$1),
                          ),
                      ],
                    ),
                  if (kind == 'privacy')
                    PrivacyReadingPanel(
                      initialSection: section,
                      publicOrigin: (api ?? Api()).base,
                      legalApi: api,
                      text: '''Eltern und Kinder haben eigene Zugänge. Eltern sehen innerhalb ihrer berechtigten Familie Materialien, Lernaufträge, gestellte Aufgaben, Antworten, Hinweise, Erklärungen, Hilfewünsche und eine ungefähre aktive Lernzeit. Andere Apps, Webseiten außerhalb von SCHULPILOT und das übrige Gerät werden nicht überwacht.

Im öffentlichen Testraum werden ausschließlich synthetische Inhalte verarbeitet. Bitte dort keine echten Namen, Fotos oder Kinderantworten eingeben. Jeder Testraum ist getrennt und wird nach 24 Stunden gelöscht. Die feste Demo benötigt keine KI. Der ausdrücklich gekennzeichnete KI-Test sendet ausschließlich ein vom Server erzeugtes künstliches Testblatt bzw. festen Beispielstoff an den dafür freigegebenen Lernanbieter. Freie Kontoeingaben werden dabei nicht übertragen.

Echte Lerninhalte werden nur über ausdrücklich freigegebene und technisch geeignete Anbieter verarbeitet. Ist kein passender geschützter Endpunkt verfügbar, wird die Verarbeitung mit einer verständlichen Meldung angehalten. Nach einer abgeschlossenen Einheit wertet der freigegebene KI-Dienst auch die gespeicherten Aufgaben, Antworten, Fehlversuche und genutzten Hinweise aus und erstellt passende Anschlussübungen. Namen, Zugangsdaten und Familienkennungen werden dafür nicht benötigt. Die Gesamtbewertung und Wiederholungsplanung werden aus den gespeicherten Aktivitäten berechnet.

Fragen zum Heft und ihre Antworten gehören zum privaten Lernverlauf und sind für berechtigte Eltern sichtbar. Die freigegebene Lern-KI erhält dafür die Frage und die bestätigten Hefttexte sowie bei Nachfragen wenige vorherige Antworten. Spracheingabe und Vorlesen sind freiwillig. Der Sprachdienst des Geräts oder Browsers kann Sprache online verarbeiten; vor einer Aufnahme erscheint ein Hinweis. SCHULPILOT speichert keine Audiodateien und lädt selbst keine hoch. Der erkannte Text bleibt vor dem Senden bearbeitbar. Auch Vorlesestimmen können einen Gerätedienst verwenden. Tippen und Lesen bleiben möglich.

Fotos werden vor dem Upload zum Drehen und Zuschneiden angezeigt. Ausstehende zugeschnittene Fotos sind auf diesem Gerät 24 Stunden fortsetzbar (höchstens 8 Seiten / 3 MB). Ältere Einträge werden beim nächsten Appstart oder Öffnen des Assistenten bereinigt; Abmelden oder Entfernen löscht diese lokale Warteschlange. Der Server entfernt Metadaten und gibt private Bilder ausschließlich nach Berechtigungsprüfung aus. Eine Verkleinerung ersetzt nicht das Entfernen persönlicher Angaben im Bild.

Die Google-Anmeldung ist freiwillig und ausschließlich für Eltern. Erst beim bewussten Start wird Google geöffnet. Wir prüfen die von Google bestätigte E-Mail-Adresse und eine eindeutige Kontokennung. Google-Passwörter, Zugriffstokens und Erneuerungstokens werden nicht gespeichert. Bestehende Elternkonten müssen Google nach Anmeldung mit ihrem bisherigen Passwort ausdrücklich verknüpfen. Kinder verwenden weiterhin ihren eigenen Zugang ohne Google. Verknüpfungen lassen sich in den Einstellungen trennen und werden bei Kontolöschung entfernt. Nicht abgeschlossene Anmeldevorgänge gelten zehn Minuten und werden spätestens beim nächsten täglichen Bereinigungslauf gelöscht.

Sitzungen sind widerrufbar. Eltern können Kinderkonten und ihr eigenes Konto löschen sowie einen Familienexport mit Materialien und Lernverlauf herunterladen. Beim Löschen des Familieninhabers wird dessen gesamte Familie gelöscht; eingeladene Eltern verlieren den Zugriff.

Eltern können freiwillig Schulnoten mit Fach, Datum und optionaler Notiz verwalten und deren Gewichtung im Lernplan ausschalten. Noten und Notennotizen werden nicht automatisch an die Lern-KI übermittelt; nur eine abgeleitete Unterstützungsstrategie wird ergänzt. Die Einträge gehören zum Familienexport und werden mit dem Kinderkonto gelöscht.

Freiwillige Lerntipps verweisen auf Sofatutor. Nur dein eigener Klick öffnet den Anbieter; Anmeldung und Abo können nötig sein. Hefttexte, Fotos und SCHULPILOT-Zugänge werden dabei nicht übertragen. Persönliche Zuordnungen, Rückmeldungen und Linkaufrufe sehen nur das eigene Kind und berechtigte Eltern. Ein Linkaufruf beweist kein angesehenes Video und zählt nicht als gelöste Übung oder Lernzeit. Andere Webseiten werden nicht überwacht.

Aufbewahrung: Materialien, Einheiten, Antworten, Heftfragen, Schulnoteneinträge, persönliche Lerntippzuordnungen und Linkaufrufe, Aktivitäten und Nachrichten höchstens 365 Tage; technische Aufträge 30 Tage; abgelaufene Zugangstokens und Sitzungen weitere 7 Tage; tägliche Backups 14 Tage. Backups müssen vor einer Wiederherstellung mit zwischenzeitlichen Löschungen abgeglichen werden. Abrechnung und Betriebsprotokolle enthalten keine Fotos oder vollständigen Kinderantworten.

Benachrichtigungen sind freiwillig. Erst beim Einschalten auf einem angemeldeten Gerät wird Google Firebase Cloud Messaging initialisiert. Für Kinder ist vorher zusätzlich eine Freigabe durch die Eltern erforderlich. Firebase erhält dabei Installations- und Gerätetokens sowie technische Verbindungsdaten; Namen, Lerninhalte, Noten und Familienkennungen werden nicht mitgesendet. Die Verarbeitung ist nicht auf Deutschland oder die EU beschränkt. Analytics, Werbung und Firebase Authentication werden nicht verwendet. Ohne geeignete Google Play Services ist Android-Push nicht zugesichert. Ausschalten, Abmelden und Rechteentzug sperren den weiteren Versand im Backend. Gerätetokens werden verschlüsselt gespeichert, bei Abmeldung oder Entzug entfernt und nach 60 Tagen ohne Aktualisierung bereinigt; Versandstatus nach 14 Tagen. Das Löschen eines Push-Tokens ist keine Zusage einer sofortigen Löschung sämtlicher Firebase-Installationsdaten oder Google-Backups. Die allgemeinen Push-Freigaben und die tatsächlich beobachtete Zustellung werden getrennt geprüft.

Bei einer Bestellung speichern wir Tarif, Gesamtpreis, Vertragsfassung und Zahlungszuordnung. Zahlungsbelege bleiben für die gesetzliche Aufbewahrung acht Jahre nach Ende des Buchungsjahres erhalten; beim Löschen der Familie wird ihre Kontozuordnung entfernt. Diese Belege enthalten keine Kinderantworten oder Lernmaterialien. Die App liest keine Bankkonten aus; ein Administrator prüft Überweisungen im tatsächlichen Bankkonto.

Es gibt keine Werbung, keinen Verkauf von Kinderprofilen und keine gemeinsame Inhaltsbibliothek aus privaten Lernmaterialien. Aktive Lernzeit bleibt eine Näherung. Eine einzelne richtige Antwort begründet keine sichere Beherrschung; fehlende Nutzung keine Aussage über Verständnis.''',
                    )
                  else
                    Text(
                      '''Schulpilot begleitet deinen Lernalltag: vom Foto deiner Heftseiten über Erklärungen und Übungen bis zur passenden Wiederholung.

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
