import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'admin_workspace_ui.dart';
import 'admin_material_review.dart';
import 'settings_screen.dart';
import 'ui.dart';

class InstallationScreen extends StatefulWidget {
  final AppState state;
  final bool initial;
  final String? initialSection;
  const InstallationScreen(
    this.state, {
    super.key,
    this.initial = true,
    this.initialSection,
  });
  @override
  State<InstallationScreen> createState() => _InstallationScreenState();
}

class _InstallationScreenState extends State<InstallationScreen>
    with WidgetsBindingObserver {
  static const sections = {
    'operation': 0,
    'email': 1,
    'ai': 2,
    'tariff': 3,
    'push': 4,
    'status': 5,
  };
  Json? config;
  Object? error;
  bool unlocked = false, loading = true, providerVisited = false;
  int step = 0;
  final code = TextEditingController();
  final username = TextEditingController(text: 'admin');
  final password = TextEditingController();
  final confirm = TextEditingController();
  final recipient = TextEditingController();
  final fields = <String, TextEditingController>{};
  final flags = <String, bool>{};
  bool busy = false, adminPasswordVisible = false;
  final visibleSecrets = <String>{};
  final fieldErrors = <String, String>{};
  final focuses = <String, FocusNode>{};
  late final owner = widget.state.user;
  bool get own => mounted && identical(widget.state.user, owner);
  int loadGeneration = 0;
  String? mailResult;
  String? unlockError;
  final savedFields = <String, String>{};
  final savedFlags = <String, bool>{};
  final dirtyFields = <String>{}, dirtyFlags = <String>{};
  bool get siteDirty => dirtyFields.isNotEmpty || dirtyFlags.isNotEmpty;
  bool completionUncertain = false;
  String? secretResult;
  bool hasStoredSecret(String key) =>
      config?['site'][switch (key) {
        'smtp_password' => 'has_smtp_password',
        'fcm_service_account_json' => 'has_fcm_service_account',
        'google_oauth_client_json' => 'has_google_oauth_client',
        _ => '',
      }] ==
      true;

  Future<void> removeStoredSecret(
    String key,
    String label,
  ) => runAction(() async {
    if (!hasStoredSecret(key)) return;
    final confirmed = await confirmDialog(
      context,
      'Gespeicherten Konfigurationseintrag entfernen?',
      '$label wird gezielt aus den gespeicherten Betriebseinstellungen entfernt. Ein lokaler Ersatzentwurf und andere Änderungen werden nicht mitgespeichert. Außerhalb der App hinterlegte Dateien werden nicht gelöscht; prüfe die tatsächliche Verfügbarkeit danach gesondert.',
      confirmLabel: 'Gespeicherten Eintrag entfernen',
      destructive: true,
    );
    if (!confirmed || !own) return;
    final saved = await widget.state.api.put('$base/site', {
      'clear_$key': true,
    });
    if (!own) return;
    setState(() {
      config = saved;
      visibleSecrets.remove(key);
      secretResult =
          '$label: gespeicherten Eintrag entfernt. Andere Entwürfe wurden nicht übertragen. Eine externe Konfiguration kann weiter gelten; Verfügbarkeit separat prüfen.';
    });
    await load();
  });

  void edited(String key) => setState(() {
    if (fields.containsKey(key)) {
      if (fields[key]!.text == savedFields[key]) {
        dirtyFields.remove(key);
      } else {
        dirtyFields.add(key);
      }
    }
    fieldErrors.remove(key);
    secretResult = null;
    error = null;
  });

  void relock() {
    unlocked = false;
    config = null;
    step = 0;
    code.clear();
    password.clear();
    confirm.clear();
    adminPasswordVisible = false;
    visibleSecrets.clear();
    for (final entry in fields.entries) {
      if (secretInput(entry.key)) entry.value.clear();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        (adminPasswordVisible || visibleSecrets.isNotEmpty)) {
      setState(() {
        adminPasswordVisible = false;
        visibleSecrets.clear();
      });
    }
  }

  Future<void> unlock() => runAction(() async {
    final value = code.text.trim();
    if (value.length < 32 || value.length > 128) {
      setState(
        () => unlockError = 'Den vollständigen Installationscode mit 32 bis 128 Zeichen eingeben.',
      );
      inputFocus('unlock_code').requestFocus();
      return;
    }
    await widget.state.api.post('/setup/unlock', {'code': value});
    if (!own) return;
    code.clear();
    await load();
  });

  Future<void> resetSiteDraft() async {
    if (busy || !own || !siteDirty) return;
    final discard = await confirmDialog(
      context,
      'Betriebsentwurf verwerfen?',
      'Die noch nicht gespeicherten Betriebs-, E-Mail-, Tarif- und Push-Eingaben werden auf den zuletzt geladenen Stand zurückgesetzt. Ein KI-Anbieterentwurf bleibt erhalten.',
      confirmLabel: 'Betriebsentwurf verwerfen',
      destructive: true,
    );
    if (!discard || !own || busy) return;
    setState(() {
      for (final entry in fields.entries) {
        entry.value.text = savedFields[entry.key] ?? '';
      }
      flags.addAll(savedFlags);
      dirtyFields.clear();
      dirtyFlags.clear();
      fieldErrors.clear();
      error = null;
      visibleSecrets.clear();
      mailResult = null;
    });
  }

  Future<void> reviewSiteDraft() async {
    if (!own || busy || !siteDirty) return;
    final labels = {
      for (final field in groups.expand((g) => g)) field.$1: field.$2,
      'privacy_evidence': 'Datenschutzfreigabe',
      'synthetic_ai_daily_limit': 'Künstliche KI-Tests pro Tag',
      'smtp_mode': 'SMTP-Verschlüsselung',
      'real_data_approved': 'Verarbeitung echter Lerninhalte',
      'synthetic_demo': 'Beispiel-Lernraum',
      'synthetic_ai_enabled': 'Künstliche KI-Tests',
      'push_approved': 'Push-Freigabe',
      'google_login_enabled': 'Google-Anmeldung',
    };
    final rows = <String>[
      for (final key in dirtyFields)
        secretInput(key) || key == 'fcm_public_config'
            ? '${labels[key] ?? key}: neuer Konfigurations-/Geheimnisentwurf; Inhalt wird hier nicht angezeigt.'
            : '${labels[key] ?? key}\nGespeichert: ${savedFields[key] ?? ''}\nEntwurf: ${fields[key]!.text}',
      for (final key in dirtyFlags)
        '${labels[key] ?? key}: ${savedFlags[key] == true ? 'an' : 'aus'} → ${flags[key] == true ? 'an' : 'aus'}',
    ];
    await confirmDialog(
      context,
      'Betriebsänderungen vor dem Speichern prüfen',
      '${rows.join('\n\n')}\n\nDies prüft nur deinen lokalen Entwurf. Es wird nichts gespeichert und kein Anbieter-, Mail- oder Pushauftrag ausgelöst.',
      confirmLabel: 'Zum Entwurf zurück',
    );
  }

  FocusNode inputFocus(String key) =>
      focuses.putIfAbsent(key, () => FocusNode());
  List<String> get inputOrder {
    if (widget.initial && step == 0) return ['username', 'password', 'confirm'];
    return switch (step - (widget.initial ? 1 : 0)) {
      0 => [
        ...groups[0].map((f) => f.$1),
        if (flags['real_data_approved'] == true) 'privacy_evidence',
        if (flags['synthetic_ai_enabled'] == true) 'synthetic_ai_daily_limit',
      ],
      1 => [...groups[1].map((f) => f.$1), 'test_recipient'],
      3 => groups[2].map((f) => f.$1).toList(),
      4 => groups[3].map((f) => f.$1).toList(),
      _ => [],
    };
  }

  void nextInput(String key) {
    final order = inputOrder, index = inputOrder.indexOf(key);
    if (index >= 0 && index + 1 < order.length) {
      inputFocus(order[index + 1]).requestFocus();
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  static const textLimits = {
    'operator_name': 160,
    'operator_address': 1000,
    'operator_support_email': 254,
    'operator_phone': 80,
    'operator_complaints_address': 1000,
    'operator_legal_info': 2000,
    'smtp_host': 253,
    'smtp_user': 254,
    'smtp_password': 1024,
    'smtp_from': 254,
    'default_plan': 40,
    'privacy_evidence': 500,
    'fcm_public_config': 10000,
    'fcm_service_account_json': 16000,
    'google_oauth_client_json': 16000,
    'push_privacy_evidence': 500,
    'fcm_config_verification': 1000,
  };
  static const ranges = <String, (int, int)>{
    'smtp_port': (1, 65535),
    'default_child_limit': (1, 20),
    'default_call_limit': (0, 10000),
    'default_budget_micros': (0, 100000000),
    'synthetic_ai_daily_limit': (1, 100),
  };
  Future<void> runAction(Future<void> Function() action) async {
    if (busy || !own) return;
    final owner = widget.state.user;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted && identical(widget.state.user, owner)) {
        setState(() {
          if (widget.initial && failure is ApiError && failure.status == 401) {
            relock();
          }
          error = failure is ApiError
              ? failure
              : ApiError(
                  'Die Änderung konnte nicht abgeschlossen werden. Dein Entwurf bleibt erhalten.',
                );
        });
      }
    } finally {
      if (mounted && identical(widget.state.user, owner)) {
        setState(() => busy = false);
      }
    }
  }

  String get base => widget.initial ? '/setup' : '/admin/installation';
  static const groups = <List<(String, String)>>[
    [
      ('operator_name', 'Betreiber'),
      ('operator_address', 'Anschrift'),
      ('operator_support_email', 'Support-E-Mail'),
      ('operator_phone', 'Telefonnummer für Kunden'),
      (
        'operator_complaints_address',
        'Beschwerdeanschrift (nur falls abweichend)',
      ),
      (
        'operator_legal_info',
        'Register, Vertretung und USt-IdNr. (falls erforderlich)',
      ),
    ],
    [
      ('smtp_host', 'SMTP-Server'),
      ('smtp_port', 'Port'),
      ('smtp_user', 'Benutzername'),
      ('smtp_password', 'SMTP-Passwort'),
      ('smtp_from', 'Absender-E-Mail'),
    ],
    [
      ('default_plan', 'Tarifname'),
      ('default_child_limit', 'Kinder je Familie'),
      ('default_call_limit', 'KI-Aufrufe pro Monat'),
      ('default_budget_micros', 'Familienbudget in Mikro-US-Dollar'),
    ],
    [
      ('fcm_public_config', 'Firebase-App-Konfiguration (JSON)'),
      ('fcm_service_account_json', 'Firebase-Dienstkonto (JSON)'),
      ('google_oauth_client_json', 'Google-Anmeldung · Webclient (JSON)'),
      ('push_privacy_evidence', 'Nachweis der Push-Freigabe'),
      (
        'fcm_config_verification',
        'Prüfung von Firebase-Apps, APIs und Schlüsselrestriktionen',
      ),
    ],
  ];
  static const numbers = {
    'smtp_port',
    'default_child_limit',
    'default_call_limit',
    'default_budget_micros',
    'synthetic_ai_daily_limit',
  };
  final extras = ['privacy_evidence', 'synthetic_ai_daily_limit', 'smtp_mode'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(accountChanged);
    if (!widget.initial) {
      step = sections[widget.initialSection] ?? 0;
      providerVisited = step == 2;
    }
    load();
  }

  void accountChanged() {
    if (own || !mounted) return;
    loadGeneration++;
    code.clear();
    password.clear();
    confirm.clear();
    for (final field in fields.values) {
      field.clear();
    }
    setState(() {
      config = null;
      visibleSecrets.clear();
    });
  }

  @override
  void didUpdateWidget(covariant InstallationScreen old) {
    super.didUpdateWidget(old);
    if (!widget.initial &&
        old.initialSection != widget.initialSection &&
        !busy) {
      selectStep(sections[widget.initialSection] ?? 0);
    }
  }

  Future<void> load() async {
    if (!own) return;
    final generation = ++loadGeneration;
    try {
      final value = await widget.state.api.get(
        widget.initial ? '/setup/config' : '/admin/installation',
      );
      if (!own || generation != loadGeneration) return;
      final site = value['site'] as Map;
      for (final key in [
        ...groups.expand((g) => g.map((f) => f.$1)),
        ...extras,
      ]) {
        fields.putIfAbsent(
          key,
          () => TextEditingController(text: '${site[key] ?? ''}'),
        );
        savedFields[key] = '${site[key] ?? ''}';
        if (!dirtyFields.contains(key)) fields[key]!.text = savedFields[key]!;
        if (fields[key]!.text == savedFields[key]) dirtyFields.remove(key);
      }
      for (final key in [
        'real_data_approved',
        'synthetic_demo',
        'synthetic_ai_enabled',
        'push_approved',
        'google_login_enabled',
      ]) {
        flags.putIfAbsent(key, () => site[key] == true);
        savedFlags[key] = site[key] == true;
        if (!dirtyFlags.contains(key)) flags[key] = savedFlags[key]!;
        if (flags[key] == savedFlags[key]) dirtyFlags.remove(key);
      }
      setState(() {
        config = value;
        unlocked = true;
        error = null;
      });
    } catch (e) {
      if (own && generation == loadGeneration) {
        setState(() {
          if (e is ApiError && e.status == 401 && widget.initial) relock();
          error = e is ApiError && e.status == 401 && widget.initial ? null : e;
        });
      }
    } finally {
      if (own && generation == loadGeneration) setState(() => loading = false);
    }
  }

  Future<bool> save() async {
    if (!own) {
      throw ApiError(
        'Die Sitzung hat sich geändert. Öffne die Einstellungen neu.',
      );
    }
    fieldErrors.clear();
    for (final entry in ranges.entries) {
      final number = int.tryParse(fields[entry.key]?.text.trim() ?? '');
      if (number == null ||
          number < entry.value.$1 ||
          number > entry.value.$2) {
        fieldErrors[entry.key] =
            'Ganze Zahl von ${entry.value.$1} bis ${entry.value.$2} eingeben.';
      }
    }
    for (final entry in textLimits.entries) {
      final raw = fields[entry.key]?.text ?? '';
      if ((secretInput(entry.key) ? raw : raw.trim()).runes.length >
          entry.value) {
        fieldErrors[entry.key] = 'Nutze höchstens ${entry.value} Zeichen.';
      }
    }
    if ((fields['default_plan']?.text.trim() ?? '').isEmpty) {
      fieldErrors['default_plan'] = 'Einen Tarifnamen eingeben.';
    }
    if (!RegExp(r'^[A-Za-z0-9.-]*$')
        .hasMatch(fields['smtp_host']?.text.trim() ?? '')) {
      fieldErrors['smtp_host'] = 'Nur den SMTP-Hostnamen eingeben, ohne https://, Leerzeichen oder Port.';
    }
    for (final key in ['operator_support_email', 'smtp_from']) {
      final value = fields[key]?.text.trim() ?? '';
      if (value.isNotEmpty &&
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
        fieldErrors[key] = 'Eine vollständige E-Mail-Adresse mit @ und gültiger Domain eingeben.';
      }
    }
    for (final key in [
      'fcm_public_config',
      'fcm_service_account_json',
      'google_oauth_client_json',
    ]) {
      final text = fields[key]?.text ?? '';
      if (text.trim().isEmpty) continue;
      try {
        final raw = jsonDecode(text);
        if (raw is! Map) {
          fieldErrors[key] =
              'Eine JSON-Objektstruktur mit geschweiften Klammern eingeben.';
        } else if (key == 'fcm_public_config') {
          const allowed = {
            'apiKey',
            'appId',
            'messagingSenderId',
            'projectId',
            'authDomain',
            'vapidKey',
            'androidAppId',
            'androidApiKey',
          };
          if (raw.keys.any((k) => !allowed.contains(k)) ||
              raw.values.any((v) => v is! String) ||
              (raw['projectId'] != null &&
                  raw['projectId'] != '' &&
                  !RegExp(r'^[a-z][a-z0-9-]{4,62}$')
                      .hasMatch(raw['projectId']))) {
            fieldErrors[key] = 'Die öffentliche Firebase-Konfiguration benötigt bekannte Textfelder und eine gültige Projektkennung. Keine Dienstkontodaten hier eintragen.';
          }
        } else if (key == 'fcm_service_account_json') {
          if (raw['type'] != 'service_account' ||
              raw['token_uri'] != 'https://oauth2.googleapis.com/token' ||
              [
                'project_id',
                'client_email',
                'private_key',
              ].any((k) => raw[k] is! String || (raw[k] as String).isEmpty)) {
            fieldErrors[key] = 'Ein vollständiges Firebase-Dienstkonto mit Projekt, Konto-E-Mail, privatem Schlüssel und Google-Tokenadresse verwenden.';
          }
        } else if (key == 'google_oauth_client_json') {
          final web = raw['web'];
          final callback =
              '${widget.state.api.base.replaceFirst(RegExp(r'/$'), '')}/auth/google/callback';
          if (web is! Map ||
              web['client_id'] is! String ||
              !RegExp(r'^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$')
                  .hasMatch(web['client_id']) ||
              web['client_secret'] is! String ||
              (web['client_secret'] as String).length < 12 ||
              (web['client_secret'] as String).length > 1024 ||
              web['auth_uri'] != 'https://accounts.google.com/o/oauth2/auth' ||
              web['token_uri'] != 'https://oauth2.googleapis.com/token' ||
              web['redirect_uris'] is! List ||
              !(web['redirect_uris'] as List).contains(callback)) {
            fieldErrors[key] = 'Den Google-Webclient für diese Installation verwenden. Client-ID, Geheimnis, Google-Adressen und die genaue API-Rücksprungadresse müssen enthalten sein.';
          }
        }
      } catch (_) {
        fieldErrors[key] = 'Ungültiges JSON. Die Eingabe bleibt erhalten; zuerst die Klammern und Anführungszeichen prüfen.';
      }
    }
    final publicRaw = fields['fcm_public_config']?.text ?? '';
    final accountRaw = fields['fcm_service_account_json']?.text ?? '';
    if (publicRaw.trim().isNotEmpty &&
        accountRaw.trim().isNotEmpty &&
        !fieldErrors.containsKey('fcm_public_config') &&
        !fieldErrors.containsKey('fcm_service_account_json')) {
      final public = jsonDecode(publicRaw) as Map,
          account = jsonDecode(accountRaw) as Map;
      if (public['projectId'] != account['project_id']) {
        fieldErrors['fcm_public_config'] = 'App-Konfiguration und Dienstkonto gehören zu unterschiedlichen Firebase-Projekten. Vor dem Speichern das bestehende richtige Projekt abgleichen.';
        fieldErrors['fcm_service_account_json'] =
            'Das Projekt des Dienstkontos muss zur App-Konfiguration passen.';
      }
    }
    if (flags['real_data_approved'] == true &&
        (fields['privacy_evidence']?.text.trim().runes.length ?? 0) < 20) {
      fieldErrors['privacy_evidence'] = 'Die Freigabe mit mindestens 20 Zeichen nachvollziehbar dokumentieren.';
    }
    if (flags['push_approved'] == true) {
      for (final key in ['push_privacy_evidence', 'fcm_config_verification']) {
        if ((fields[key]?.text.trim().runes.length ?? 0) < 20) {
          fieldErrors[key] =
              'Vor der Push-Freigabe mindestens 20 Zeichen Nachweis eintragen.';
        }
      }
    }
    if (fieldErrors.isNotEmpty) {
      setState(() {});
      final key = fieldErrors.keys.first;
      final label = [
        ...groups.expand((g) => g),
        ('synthetic_ai_daily_limit', 'Beispiel-KI-Aufrufe'),
        ('privacy_evidence', 'Datenschutzfreigabe'),
      ].firstWhere((e) => e.$1 == key).$2;
      throw ApiError('$label: ${fieldErrors[key]}');
    }
    final data = <String, dynamic>{
      for (final key in dirtyFlags) key: flags[key],
    };
    for (final entry in fields.entries) {
      if (!dirtyFields.contains(entry.key)) continue;
      if (secretInput(entry.key) && entry.value.text.isEmpty) continue;
      data[entry.key] = numbers.contains(entry.key)
          ? int.tryParse(entry.value.text)
          : entry.value.text;
    }
    if (data['real_data_approved'] == true) {
      data['privacy_evidence'] = fields['privacy_evidence']!.text;
    }
    if (data['push_approved'] == true) {
      data['push_privacy_evidence'] = fields['push_privacy_evidence']!.text;
      data['fcm_config_verification'] = fields['fcm_config_verification']!.text;
    }
    if (data.isEmpty) return false;
    final saved = await widget.state.api.put('$base/site', data);
    if (!own) throw ApiError('Die Sitzung hat sich geändert.');
    loadGeneration++;
    config = saved;
    final savedSite = saved['site'] as Map;
    for (final entry in fields.entries) {
      if (secretInput(entry.key)) {
        entry.value.clear();
      } else {
        entry.value.text = '${savedSite[entry.key] ?? ''}';
      }
      savedFields[entry.key] = entry.value.text;
    }
    for (final key in flags.keys.toList()) {
      flags[key] = savedSite[key] == true;
    }
    savedFlags.addAll(flags);
    visibleSecrets.clear();
    secretResult = null;
    dirtyFields.clear();
    dirtyFlags.clear();
    setState(() {});
    return true;
  }

  Future<void> reconcileCompletion() async {
    await widget.state.checkInstallation();
    if (!mounted || !own) return;
    if (!widget.state.needsSetup) {
      password.clear();
      confirm.clear();
      code.clear();
      context.go('/login');
    } else {
      setState(() {
        completionUncertain = false;
        error = ApiError(
          'Der Server benötigt die Einrichtung weiterhin. Prüfe die Eingaben und schließe erst danach bewusst ab.',
        );
      });
    }
  }

  Future<void> completeInstallation() => runAction(() async {
    if (completionUncertain) return;
    if (password.text != confirm.text) {
      throw ApiError('Die Passwörter stimmen nicht überein.');
    }
    await save();
    if (!own) return;
    setState(() => completionUncertain = true);
    try {
      await widget.state.api.post('/setup/complete', {
        'username': username.text.trim(),
        'password': password.text,
      });
      if (!own) return;
      password.clear();
      confirm.clear();
    } on ApiError catch (failure) {
      if (failure.status >= 400 &&
          failure.status < 500 &&
          failure.status != 409) {
        if (own) setState(() => completionUncertain = false);
        rethrow;
      }
      throw ApiError(
        'Der Abschluss konnte noch nicht bestätigt werden. Prüfe zuerst den Einrichtungsstatus; es wird kein zweites Administratorkonto angefordert.',
      );
    }
    await reconcileCompletion();
  });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(accountChanged);
    for (final focus in focuses.values) {
      focus.dispose();
    }
    for (final c in [
      code,
      username,
      password,
      confirm,
      recipient,
      ...fields.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool secretInput(String key) => const {
    'smtp_password',
    'fcm_service_account_json',
    'google_oauth_client_json',
  }.contains(key);
  Widget input(String key, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          focusNode: inputFocus(key),
          textInputAction: inputOrder.isNotEmpty && key == inputOrder.last
              ? TextInputAction.done
              : TextInputAction.next,
          onSubmitted: (_) => nextInput(key),
          controller: fields[key],
          onChanged: (_) => edited(key),
          enabled: !busy,
          autocorrect: false,
          enableSuggestions: false,
          smartDashesType: secretInput(key) ? SmartDashesType.disabled : null,
          smartQuotesType: secretInput(key) ? SmartQuotesType.disabled : null,
          enableIMEPersonalizedLearning: !secretInput(key),
          obscureText:
              [
                'smtp_password',
                'fcm_service_account_json',
                'google_oauth_client_json',
              ].contains(key) &&
              !visibleSecrets.contains(key),
          maxLines:
              [
                'operator_address',
                'operator_complaints_address',
                'operator_legal_info',
                'fcm_public_config',
                'privacy_evidence',
                'push_privacy_evidence',
                'fcm_config_verification',
              ].contains(key)
              ? 3
              : 1,
          keyboardType: numbers.contains(key)
              ? TextInputType.number
              : key == 'operator_phone'
              ? TextInputType.phone
              : ['operator_support_email', 'smtp_from'].contains(key)
              ? TextInputType.emailAddress
              : TextInputType.text,
          decoration: InputDecoration(
            labelText: label,
            errorText: fieldErrors[key],
            errorMaxLines: 3,
            suffixIcon:
                [
                  'smtp_password',
                  'fcm_service_account_json',
                  'google_oauth_client_json',
                ].contains(key)
                ? IconButton(
                    tooltip: visibleSecrets.contains(key)
                        ? 'Eingabe verbergen'
                        : 'Eingabe anzeigen',
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            if (!visibleSecrets.add(key)) {
                              visibleSecrets.remove(key);
                            }
                          }),
                    icon: Icon(
                      visibleSecrets.contains(key)
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  )
                : null,
            hintText:
                (key == 'smtp_password' &&
                        config?['site']['has_smtp_password'] == true) ||
                    (key == 'fcm_service_account_json' &&
                        config?['site']['has_fcm_service_account'] == true) ||
                    (key == 'google_oauth_client_json' &&
                        config?['site']['has_google_oauth_client'] == true)
                ? 'Gespeichert · leer lassen zum Beibehalten'
                : null,
          ),
        ),
        if (secretInput(key) && hasStoredSecret(key))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy ? null : () => removeStoredSecret(key, label),
              icon: const Icon(Icons.delete_outline),
              label: Text('Gespeicherten Eintrag entfernen: $label'),
            ),
          ),
      ],
    ),
  );

  Widget toggle(String key, String label) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: flags[key] ?? false,
    onChanged: busy
        ? null
        : (v) => setState(() {
            flags[key] = v;
            if (v == savedFlags[key]) {
              dirtyFlags.remove(key);
            } else {
              dirtyFlags.add(key);
            }
            error = null;
          }),
  );

  Widget group(int index) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (final field in groups[index]) input(field.$1, field.$2)],
  );

  void selectStep(int next, {bool afterSave = false}) {
    if (busy && !afterSave) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      step = next;
      if (next == (widget.initial ? 3 : 2)) providerVisited = true;
    });
  }

  Widget providerSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!widget.initial) ...[
        AdminMaterialReviewSettings(widget.state, enabled: step == 2),
        const SizedBox(height: 12),
      ],
      ProviderForm(
        widget.state,
        Map<String, dynamic>.from(config!['provider']),
        key: ValueKey(config!['provider']['revision']),
        endpoint: widget.initial ? '/setup/provider' : '/admin/provider',
        onRefresh: load,
      ),
      const SizedBox(height: 12),
      OperatorProbePanel(
        widget.state,
        endpoint: widget.initial ? '/setup/provider' : '/admin/provider',
        savedRevision: config!['provider']['revision'],
        onFinished: load,
      ),
    ],
  );

  int? _checkSection(String key) => switch (key) {
    'mail_configured' => 1,
    'operator_complete' || 'data_approved' => 0,
    'push_available' => 4,
    _ => null,
  };
  int _fieldSection(String key) => key.startsWith('smtp_')
      ? 1
      : key.startsWith('default_')
      ? 3
      : key.startsWith('fcm_') ||
            key.startsWith('google_') ||
            key.startsWith('push_')
      ? 4
      : 0;

  void showFieldError(int section) {
    selectStep(section + (widget.initial ? 1 : 0));
    final key = fieldErrors.keys.firstWhere(
      (key) => _fieldSection(key) == section,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!own) return;
      inputFocus(key).requestFocus();
      final field = inputFocus(key).context;
      if (field != null) Scrollable.ensureVisible(field, alignment: .2);
    });
  }

  Widget content() {
    if (widget.initial && !kIsWeb) {
      return Panel(
        child: Column(
          children: [
            heading('SchuleSchlau wird eingerichtet'),
            const Text('Bitte die Ersteinrichtung im Browser abschließen.'),
            const SizedBox(height: 12),
            ActionButton(
              label: 'Im Browser öffnen',
              onPressed: () async {
                await runAction(() async {
                  final opened = await launchUrl(
                    Uri.parse(
                      widget.state.api.base.replaceFirst(
                        RegExp(r'/api/?$'),
                        '/setup',
                      ),
                    ),
                    mode: LaunchMode.externalApplication,
                  );
                  if (!opened) {
                    throw ApiError(
                      'Der Browser konnte nicht geöffnet werden. Öffne die Webadresse deiner Installation manuell und wähle /setup.',
                    );
                  }
                });
              },
            ),
          ],
        ),
      );
    }
    if (loading) return const Center(child: CircularProgressIndicator());
    if (!unlocked && !widget.initial) {
      return OutlinedButton.icon(
        onPressed: load,
        icon: const Icon(Icons.refresh),
        label: const Text('Erneut laden'),
      );
    }
    if (!unlocked) {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading('Willkommen bei SchuleSchlau'),
            const Text(
              'Öffne die Ersteinrichtung mit dem Installationscode deines Servers.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: code,
              focusNode: inputFocus('unlock_code'),
              enabled: !busy,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => unlock(),
              onChanged: (_) => setState(() => unlockError = null),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              enableIMEPersonalizedLearning: false,
              decoration: InputDecoration(
                labelText: 'Installationscode',
                errorText: unlockError,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            ActionButton(
              label: 'Einrichtung öffnen',
              icon: Icons.lock_open_rounded,
              enabled: !busy,
              onPressed: unlock,
            ),
          ],
        ),
      );
    }
    final labels = [
      if (widget.initial) 'Admin',
      'Betrieb',
      'E-Mail',
      'KI',
      'Tarif',
      'Push',
      widget.initial ? 'Abschluss' : 'Status',
    ];
    final current = step - (widget.initial ? 1 : 0);
    Widget? body;
    if (widget.initial && step == 0) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('Dein Administratorkonto'),
          TextField(
            controller: username,
            enabled: !busy,
            onChanged: (_) => edited('username'),
            focusNode: inputFocus('username'),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => nextInput('username'),
            decoration: InputDecoration(
              labelText: 'Admin-Benutzername',
              errorText: fieldErrors['username'],
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: password,
            onChanged: (_) => edited('password'),
            focusNode: inputFocus('password'),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => nextInput('password'),
            enabled: !busy,
            autocorrect: false,
            enableSuggestions: false,
            obscureText: !adminPasswordVisible,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            enableIMEPersonalizedLearning: false,
            decoration: InputDecoration(
              suffixIcon: IconButton(
                tooltip: adminPasswordVisible
                    ? 'Passwort verbergen'
                    : 'Passwort anzeigen',
                onPressed: busy
                    ? null
                    : () => setState(
                        () => adminPasswordVisible = !adminPasswordVisible,
                      ),
                icon: Icon(
                  adminPasswordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
              labelText: 'Admin-Passwort',
              errorText: fieldErrors['password'],
              errorMaxLines: 3,
              helperText: 'Mindestens 12 Zeichen.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: confirm,
            onChanged: (_) => edited('confirm'),
            focusNode: inputFocus('confirm'),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => nextInput('confirm'),
            enabled: !busy,
            autocorrect: false,
            enableSuggestions: false,
            obscureText: !adminPasswordVisible,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            enableIMEPersonalizedLearning: false,
            decoration: InputDecoration(
              labelText: 'Admin-Passwort wiederholen',
              errorText: fieldErrors['confirm'],
              errorMaxLines: 3,
            ),
          ),
        ],
      );
    } else if (current == 0) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('Betreiber & Datenschutz'),
          group(0),
          toggle(
            'real_data_approved',
            'Verarbeitung echter Lerninhalte freigeben',
          ),
          if (flags['real_data_approved'] == true)
            input(
              'privacy_evidence',
              'Dokumentierte Anbieter- und Datenschutzfreigabe',
            ),
          toggle('synthetic_demo', 'Beispiel-Lernraum anbieten'),
          toggle(
            'synthetic_ai_enabled',
            'KI-Tests mit künstlichen Daten erlauben',
          ),
          if (flags['synthetic_ai_enabled'] == true)
            input(
              'synthetic_ai_daily_limit',
              'Maximale Beispiel-KI-Aufrufe pro Tag',
            ),
        ],
      );
    } else if (current == 1) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('E-Mail-Versand'),
          group(1),
          DropdownButtonFormField<String>(
            initialValue: fields['smtp_mode']!.text,
            decoration: const InputDecoration(labelText: 'Verschlüsselung'),
            items: const [
              DropdownMenuItem(value: 'starttls', child: Text('STARTTLS')),
              DropdownMenuItem(value: 'tls', child: Text('TLS')),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() {
                    fields['smtp_mode']!.text = v ?? 'starttls';
                    if (fields['smtp_mode']!.text == savedFields['smtp_mode']) {
                      dirtyFields.remove('smtp_mode');
                    } else {
                      dirtyFields.add('smtp_mode');
                    }
                  }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: recipient,
            focusNode: inputFocus('test_recipient'),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => nextInput('test_recipient'),
            onChanged: (_) {
              if (mailResult != null) setState(() => mailResult = null);
            },
            enabled: !busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Testnachricht an'),
          ),
          const SizedBox(height: 16),
          if (mailResult != null)
            Semantics(liveRegion: true, child: Notice(mailResult!)),
          ActionButton(
            label: 'Speichern & Testmail senden',
            secondary: true,
            enabled: !busy,
            onPressed: () => runAction(() async {
              setState(() => mailResult = null);
              if (recipient.text.trim().isEmpty) {
                inputFocus('test_recipient').requestFocus();
                throw ApiError(
                  'Gib zuerst eine E-Mail-Adresse für die Testnachricht ein.',
                );
              }
              if (recipient.text.trim().length > 254 ||
                  !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                      .hasMatch(recipient.text.trim())) {
                inputFocus('test_recipient').requestFocus();
                throw ApiError(
                  'Gib zuerst eine gültige E-Mail-Adresse mit höchstens 254 Zeichen für die Testnachricht ein.',
                );
              }
              await save();
              final result = await widget.state.api.post('$base/mail-test', {
                'email': recipient.text.trim(),
              });
              if (own) setState(() => mailResult = '${result['message']}');
            }),
          ),
        ],
      );
    } else if (current == 2) {
      body = null;
    } else if (current == 3) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [heading('Neue Familien'), group(2)],
      );
    } else if (current == 4) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('Push-Benachrichtigungen'),
          toggle('push_approved', 'Push freigeben'),
          toggle(
            'google_login_enabled',
            'Google-Anmeldung für Eltern aktivieren',
          ),
          group(3),
        ],
      );
    } else {
      final checks = config!['checks'] as Map;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('Bereit für den Start'),
          const Text(
            'Prüfübersicht ohne Geheimnisse · vorhandene Eingaben werden erst durch ausdrückliches Speichern übernommen.',
          ),
          SurfaceInset(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.initial)
                  Text(
                    'Erstadmin: ${username.text.trim()} · wird erst beim Abschluss angelegt',
                  ),
                Text(
                  'Betreiber: ${fields['operator_name']!.text.isEmpty ? 'noch offen' : fields['operator_name']!.text}',
                ),
                Text(
                  'Support: ${fields['operator_support_email']!.text.isEmpty ? 'noch offen' : fields['operator_support_email']!.text}',
                ),
                Text(
                  'E-Mail-Absender: ${fields['smtp_from']!.text.isEmpty ? 'noch offen' : fields['smtp_from']!.text}',
                ),
                Text(
                  'Gespeicherter KI-Stand: Revision ${config!['provider']['revision'] ?? 'nicht gemeldet'}',
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => runAction(load),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Status ohne Speichern aktualisieren'),
          ),
          for (final item in {
            'database': 'Datenbank',
            'https': 'HTTPS',
            'worker_available': 'Hintergrundverarbeitung',
            'mail_configured': 'E-Mail eingerichtet',
            'operator_complete': 'Betreiberangaben',
            'data_approved': 'Datenschutzfreigabe',
            'push_available': 'Push (optional)',
          }.entries)
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  checks[item.key] == true
                      ? Icons.check_circle_rounded
                      : Icons.pending_outlined,
                  color: checks[item.key] == true ? teal : muted,
                ),
                title: Text(item.value),
                onTap:
                    checks[item.key] == true &&
                        _checkSection(item.key) != null &&
                        !busy
                    ? () => selectStep(
                        _checkSection(item.key)! + (widget.initial ? 1 : 0),
                      )
                    : null,
                trailing:
                    checks[item.key] == true || _checkSection(item.key) == null
                    ? (checks[item.key] == true &&
                              _checkSection(item.key) != null
                          ? const Icon(Icons.arrow_forward_rounded)
                          : null)
                    : TextButton(
                        onPressed: busy
                            ? null
                            : () => selectStep(
                                _checkSection(item.key)! +
                                    (widget.initial ? 1 : 0),
                              ),
                        child: const Text('Prüfen'),
                      ),
                subtitle: Text(
                  checks[item.key] == true
                      ? 'Erfüllt'
                      : checks[item.key] == false
                      ? 'Noch offen'
                      : 'Noch nicht gemeldet',
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(config!['provider']['status'] ?? ''),
          TextButton(
            onPressed: busy ? null : () => selectStep(widget.initial ? 3 : 2),
            child: const Text('Gespeicherten KI-Stand prüfen'),
          ),
          if (widget.initial) ...[
            const SizedBox(height: 16),
            if (completionUncertain) ...[
              const Notice(
                'Der Abschluss ist noch nicht sicher abgeglichen. Zuerst den gespeicherten Einrichtungsstatus lesen; kein erneuter Abschluss durch Neuladen.',
              ),
              ActionButton(
                label: 'Einrichtungsstatus zuerst prüfen',
                enabled: !busy,
                secondary: true,
                onPressed: () => runAction(reconcileCompletion),
              ),
            ],
            ActionButton(
              label: 'Einrichtung abschließen',
              icon: Icons.check_rounded,
              enabled: !busy && !completionUncertain,
              onPressed: completeInstallation,
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.initial)
          AdminContextTabs(
            selected: step,
            onSelected: selectStep,
            items: [
              for (final label in labels)
                (
                  {
                        'Betrieb': Icons.tune_rounded,
                        'E-Mail': Icons.mail_outline_rounded,
                        'KI': Icons.auto_awesome_rounded,
                        'Tarif': Icons.family_restroom_rounded,
                        'Push': Icons.notifications_outlined,
                        'Status': Icons.fact_check_outlined,
                      }[label] ??
                      Icons.circle_outlined,
                  label,
                ),
            ],
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < labels.length; i++)
                ChoiceChip(
                  label: Text(
                    widget.initial ? '${i + 1}  ${labels[i]}' : labels[i],
                  ),
                  selected: i == step,
                  showCheckmark: false,
                  onSelected: !busy && (!widget.initial || i < step)
                      ? (_) => selectStep(i)
                      : null,
                ),
            ],
          ),
        if (widget.initial) ...[
          const SizedBox(height: 12),
          Semantics(
            label: 'Einrichtungsfortschritt',
            value: 'Schritt ${step + 1} von ${labels.length}: ${labels[step]}',
            excludeSemantics: true,
            child: LinearProgressIndicator(
              value: (step + 1) / labels.length,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (body != null)
                KeyedSubtree(
                  key: ValueKey('site-section-$current'),
                  child: body,
                ),
              if (providerVisited)
                Offstage(
                  key: const ValueKey('installation-provider-section'),
                  offstage: current != 2,
                  child: ExcludeFocus(
                    excluding: current != 2,
                    child: providerSection(),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (widget.initial && step > 0)
              OutlinedButton(
                onPressed: busy ? null : () => selectStep(step - 1),
                child: const Text('Zurück'),
              ),
            if (widget.initial && step < labels.length - 1)
              ActionButton(
                label: step == 0
                    ? 'Zugang prüfen & weiter'
                    : 'Speichern & weiter',
                enabled: !busy,
                icon: Icons.arrow_forward_rounded,
                onPressed: () async {
                  final startedStep = step;
                  await runAction(() async {
                    if (widget.initial && startedStep == 0) {
                      fieldErrors.removeWhere(
                        (key, _) =>
                            ['username', 'password', 'confirm'].contains(key),
                      );
                      if (!RegExp(r'^[A-Za-z0-9._-]{3,50}$')
                          .hasMatch(username.text.trim())) {
                        fieldErrors['username'] = '3 bis 50 Zeichen: Buchstaben, Ziffern, Punkt, Unterstrich oder Bindestrich.';
                      }
                      if (password.text.runes.length < 12 ||
                          password.text.runes.length > 128) {
                        fieldErrors['password'] =
                            'Ein Passwort mit 12 bis 128 Zeichen eingeben.';
                      }
                      if (password.text != confirm.text ||
                          confirm.text.isEmpty) {
                        fieldErrors['confirm'] =
                            'Das gleiche Passwort erneut eingeben.';
                      }
                      if (fieldErrors.isNotEmpty) {
                        setState(() {});
                        inputFocus(fieldErrors.keys.first).requestFocus();
                        throw ApiError('Die markierten Zugangsfelder prüfen.');
                      }
                    } else {
                      await save();
                    }
                    if (mounted && step == startedStep) {
                      selectStep(startedStep + 1, afterSave: true);
                    }
                  });
                },
              ),
            if (!widget.initial)
              ActionButton(
                label: 'Einstellungen speichern',
                enabled: !busy,
                onPressed: () => runAction(() async {
                  final changed = await save();
                  if (mounted) {
                    toast(
                      context,
                      changed ? 'Gespeichert.' : 'Keine lokalen Änderungen.',
                    );
                  }
                }),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!own) {
      if (!widget.initial && widget.state.user == null) {
        return Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Deine Betriebssitzung ist beendet. Bitte melde dich erneut an.',
              ),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Erneut anmelden'),
              ),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    }
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null)
          Semantics(liveRegion: true, child: Notice('$error', warning: true)),
        if (secretResult != null)
          Semantics(liveRegion: true, child: Notice(secretResult!)),
        if (fieldErrors.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final section
                  in fieldErrors.keys
                      .where(
                        (key) =>
                            !['username', 'password', 'confirm'].contains(key),
                      )
                      .map(_fieldSection)
                      .toSet())
                if (!widget.initial || section + 1 <= step)
                  TextButton.icon(
                    onPressed: busy ? null : () => showFieldError(section),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(
                      'Fehler in ${const ['Betrieb', 'E-Mail', 'KI', 'Tarif', 'Push', 'Status'][section]} anzeigen',
                    ),
                  ),
            ],
          ),
        if (unlocked && siteDirty) ...[
          const Notice(
            'Ungespeicherter Betriebsentwurf. Prüfstände beziehen sich auf die zuletzt gespeicherten Einstellungen; Änderungen erst bewusst speichern.',
          ),
        ],
        KeyedSubtree(
          key: const ValueKey('installation-work-area'),
          child: content(),
        ),
        if (unlocked && siteDirty) ...[
          TextButton.icon(
            onPressed: busy ? null : resetSiteDraft,
            icon: const Icon(Icons.undo),
            label: const Text('Betriebsentwurf zurücksetzen'),
          ),
          TextButton.icon(
            onPressed: busy ? null : reviewSiteDraft,
            icon: const Icon(Icons.compare_arrows),
            label: const Text('Betriebsänderungen prüfen'),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
    if (!widget.initial) {
      return PageFrame(
        state: widget.state,
        title: 'Betriebseinstellungen',
        showTitle: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AdminWorkspaceHeader(
              title: 'Betriebseinstellungen',
              subtitle: 'Zugänge, Freigaben und Dienste bewusst konfigurieren.',
              currentPath: '/admin/settings',
              icon: Icons.tune_rounded,
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [brand(), const SizedBox(height: 20), child],
            ),
          ),
        ),
      ),
    );
  }
}

/// Existing operator job recovery is GET-only; a new reservation always requires
/// the explicit start action. An interrupted poll never becomes a second POST.
class OperatorProbePanel extends StatefulWidget {
  final AppState state;
  final String endpoint;
  final dynamic savedRevision;
  final Future<void> Function() onFinished;
  const OperatorProbePanel(
    this.state, {
    super.key,
    required this.endpoint,
    required this.savedRevision,
    required this.onFinished,
  });
  @override
  State<OperatorProbePanel> createState() => _OperatorProbePanelState();
}

class _OperatorProbePanelState extends State<OperatorProbePanel> {
  Json? probe;
  bool loading = true, starting = false;
  String? error, origin;
  int generation = 0;
  late final Object? owner = widget.state.user;
  bool get own => mounted && identical(widget.state.user, owner);
  bool get active =>
      probe != null && ['queued', 'running'].contains(probe!['status']);
  @override
  void initState() {
    super.initState();
    widget.state.addListener(accountChanged);
    restore();
  }

  void accountChanged() {
    if (!own && mounted) {
      generation++;
      setState(() {
        probe = null;
        error = null;
        loading = false;
        starting = false;
      });
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    generation++;
    super.dispose();
  }

  Future<void> restore() async {
    if (!own || starting) return;
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final metadata = await widget.state.api.get('${widget.endpoint}/probes');
      if (!own || request != generation) return;
      final found = metadata['active'] ?? metadata['latest'];
      if (found is Map) {
        setState(() {
          probe = Json.from(found);
          origin = metadata['active'] != null
              ? 'Aktive künstliche Anbieterprüfung'
              : 'Letzte eigene künstliche Anbieterprüfung';
        });
        await updateResult(request);
      } else {
        setState(() {
          probe = null;
          origin = null;
        });
      }
    } catch (failure) {
      if (own && request == generation) {
        setState(
          () => error = failure is ApiError ? failure.message : 'Der gespeicherte Prüfstatus konnte nicht geladen werden. Status erneut laden; keine neue Prüfung starten.',
        );
      }
    } finally {
      if (own && request == generation) setState(() => loading = false);
    }
  }

  Future<void> updateResult(int request) async {
    final id = probe?['id'];
    if (id is! String || id.isEmpty) return;
    final result = await widget.state.api.get('${widget.endpoint}/probes/$id');
    if (!own || request != generation) return;
    setState(() => probe = {...?probe, ...result});
  }

  Future<void> start() async {
    if (!own || starting || loading || active || error != null) return;
    final request = ++generation;
    setState(() {
      starting = true;
      error = null;
    });
    try {
      final job = await widget.state.api.post('${widget.endpoint}/probe');
      if (!own || request != generation) return;
      setState(() {
        probe = {...job, 'status': job['status'] ?? 'queued'};
        origin = 'Bewusst gestartete künstliche Anbieterprüfung';
      });
      for (var i = 0; i < 180; i++) {
        await updateResult(request);
        if (!own || request != generation) return;
        if (!active) {
          await widget.onFinished();
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!own || request != generation) return;
      }
    } catch (failure) {
      if (own && request == generation) {
        setState(
          () => error = failure is ApiError ? failure.message : 'Die Anfrage konnte nicht sicher abgeschlossen werden. Zuerst den gespeicherten Prüfstatus laden; nicht erneut starten.',
        );
      }
    } finally {
      if (own && request == generation) setState(() => starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => !own
      ? const SizedBox.shrink()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Notice(
              'Diese echte Anbieterprüfung verwendet feste künstliche Beispieldaten und reserviert reguläres Kontingent. Kosten können entstehen oder unbekannt bleiben. Öffnen und Statusladen starten keine neue Prüfung.',
            ),
            if (loading || starting) const LinearProgressIndicator(),
            if (error != null)
              Semantics(liveRegion: true, child: Notice(error!, warning: true)),
            if (probe != null) ...[
              Text(origin ?? 'Gespeicherte künstliche Anbieterprüfung'),
              SelectableText('Prüfauftrag: ${probe!['id']}'),
              Text(
                'Konfigurationsrevision: ${probe!['config_revision'] ?? 'nicht gemeldet'} · aktuell gespeichert: ${widget.savedRevision ?? 'nicht gemeldet'}',
              ),
              if (probe!['created'] is num)
                Text(
                  'Gestartet: ${DateTime.fromMillisecondsSinceEpoch((probe!['created'] as num).toInt() * 1000).toLocal()} (Gerätezeit)',
                ),
              if (probe!['config_revision'] != null &&
                  widget.savedRevision != null &&
                  probe!['config_revision'] != widget.savedRevision)
                const Notice(
                  'Dieses Prüfergebnis gehört zu einer älteren gespeicherten Konfiguration. Es bestätigt nicht den aktuellen Entwurf.',
                  warning: true,
                ),
              Semantics(
                liveRegion: true,
                child: Text(
                  probe!['status'] == 'completed'
                      ? 'Bild- und Aufgabenprüfung erfolgreich.'
                      : probe!['error'] ??
                            (probe!['status'] == 'failed'
                                ? 'Prüfung fehlgeschlagen. Anbieterstatus ansehen.'
                                : 'Prüfung läuft weiter. Status kann ohne neuen Auftrag geladen werden.'),
                ),
              ),
              for (final item in probe!['report'] as List? ?? [])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    {
                          'extract': 'Foto erkennen',
                          'unit': 'Übungen erstellen',
                          'package': 'Tagespaket erstellen',
                        }[item['function']] ??
                        'Anbieterprüfung',
                  ),
                  subtitle: Text(
                    '${item['available'] == true ? 'Verfügbar' : 'Nicht bestätigt'} · ${item['error'] ?? (item['cost_micros_usd'] == null ? 'Kosten unbekannt' : '${(item['cost_micros_usd'] / 1000000).toStringAsFixed(6)} USD')}',
                  ),
                ),
            ],
            OutlinedButton.icon(
              onPressed: loading || starting ? null : restore,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Gespeicherten Prüfstatus laden'),
            ),
            const SizedBox(height: 12),
            ActionButton(
              label: 'Bild & Aufgaben mit Beispieldaten prüfen',
              icon: Icons.science_outlined,
              enabled: !loading && !starting && !active && error == null,
              onPressed: start,
            ),
          ],
        );
}
