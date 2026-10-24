import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'api.dart';
import 'parent_form_guard.dart';
import 'ui.dart';

/// Curriculum selection is an explicit parent action, never a learning result.
class CurriculumProfileButton extends StatelessWidget {
  final AppState state;
  final String childId, childName;
  final VoidCallback? onSaved;
  const CurriculumProfileButton(
    this.state, {
    super.key,
    required this.childId,
    required this.childName,
    this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    final owner = state.user, family = state.familyId, token = state.api.token;
    final actorId = owner?['id'];
    final sourceRoute = ModalRoute.of(context);
    if (!state.isParent || !state.canManage || family == null) {
      return const SizedBox.shrink();
    }
    return OutlinedButton.icon(
      key: ValueKey('curriculum-profile:$childId'),
      onPressed: () async {
        bool currentButton() =>
            context.mounted &&
            state.isParent &&
            state.canManage &&
            identical(state.user, owner) &&
            state.user?['id'] == actorId &&
            state.familyId == family &&
            state.api.token == token &&
            context.widget is CurriculumProfileButton &&
            identical(
              (context.widget as CurriculumProfileButton).state,
              state,
            ) &&
            (context.widget as CurriculumProfileButton).childId == childId &&
            sourceRoute?.isCurrent == true;
        if (!currentButton()) {
          return;
        }
        var changed = false;
        final route = DialogRoute<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => CurriculumProfileEditor(
            state,
            childId: childId,
            childName: childName,
            onSaved: () => changed = true,
          ),
        );
        await Navigator.of(context, rootNavigator: true).push(route);
        await route.completed;
        if (changed && currentButton()) {
          onSaved?.call();
        }
      },
      icon: const Icon(Icons.school_outlined),
      label: const Text('Bundesland & Lehrplan'),
    );
  }
}

class CurriculumProfileEditor extends StatefulWidget {
  final AppState state;
  final String childId, childName;
  final VoidCallback? onSaved;
  const CurriculumProfileEditor(
    this.state, {
    super.key,
    required this.childId,
    required this.childName,
    this.onSaved,
  });
  @override
  State<CurriculumProfileEditor> createState() =>
      _CurriculumProfileEditorState();
}

class _CurriculumProfileEditorState extends State<CurriculumProfileEditor>
    with WidgetsBindingObserver {
  late final AppState ownerState = widget.state;
  late final Json? owner = ownerState.user;
  late final Object? actorId = owner?['id'];
  late final String? family = ownerState.familyId, token = ownerState.api.token;
  final states = <Json>[];
  Json? profile;
  late final String childId = widget.childId;
  String? stateCode,
      schoolForm,
      error,
      notice,
      baseline,
      requestKey,
      requestBody;
  int grade = 1, revision = 0, epoch = 0;
  String? profileRevision;
  bool loading = true,
      saving = false,
      closing = false,
      foreground = true,
      needsRefresh = false,
      didSave = false;
  ModalRoute<bool>? discardRoute;
  bool get owned =>
      mounted &&
      !closing &&
      identical(widget.state, ownerState) &&
      ownerState.isParent &&
      ownerState.canManage &&
      widget.childId == childId &&
      identical(ownerState.user, owner) &&
      ownerState.user?['id'] == actorId &&
      ownerState.familyId == family &&
      ownerState.api.token == token;
  bool get current => owned && foreground;
  bool get active => current && ModalRoute.of(context)?.isCurrent == true;
  bool get fieldsAvailable =>
      current &&
      !loading &&
      !saving &&
      !needsRefresh &&
      profile?['can_manage'] == true;
  bool get interactive =>
      fieldsAvailable && ModalRoute.of(context)?.isCurrent == true;
  String get path =>
      '/children/${Uri.encodeComponent(childId)}/curriculum-profile';
  Map<String, String> get headers => {
    'X-Schulpilot-Account': '${owner?['id'] ?? ''}',
  };
  Json get body => {
    'revision': revision,
    'profile_revision': profileRevision,
    'state_code': stateCode,
    'school_form_id': schoolForm,
    'grade': grade,
  };
  String get fingerprint => jsonEncode(body);
  bool get dirty => baseline != null && fingerprint != baseline;
  Json? get chosenState =>
      states.where((s) => s['code'] == stateCode).firstOrNull;
  List<Json> get forms => (chosenState?['school_forms'] as List? ?? [])
      .whereType<Map>()
      .map((s) => Json.from(s))
      .toList();

  @override
  void initState() {
    super.initState();
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    ownerState.addListener(identityChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (current) {
        load();
      }
    });
  }

  @override
  void didUpdateWidget(covariant CurriculumProfileEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId ||
        oldWidget.state != widget.state) {
      identityChanged();
    }
  }

  void identityChanged() {
    if (owned || closing) {
      return;
    }
    closing = true;
    epoch++;
    final route = ModalRoute.of(context), extra = discardRoute;
    scheduleMicrotask(() {
      if (extra?.isActive == true) {
        extra!.navigator?.removeRoute(extra);
      }
      if (route?.isActive == true) {
        route!.navigator?.removeRoute(route);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    foreground = value == AppLifecycleState.resumed;
    epoch++;
    if (!mounted || closing) {
      return;
    }
    setState(() {
      loading = saving = false;
      if (!foreground) {
        error = 'Vor dem Speichern bitte den aktuellen Stand neu laden. Dein Entwurf bleibt erhalten.';
        needsRefresh = true;
      }
    });
  }

  @override
  void dispose() {
    epoch++;
    ownerState.removeListener(identityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<bool> readyResponse(
    int request,
    ModalRoute<dynamic>? requestRoute,
  ) async {
    if (!current || request != epoch) {
      return false;
    }
    // The explicit discard confirmation belongs to this form. Wait for its
    // completed return rather than treating it as an unrelated route or
    // applying a response underneath it. No request is repeated.
    final extra = discardRoute;
    if (extra != null && extra.isCurrent) {
      await extra.completed;
    }
    return acceptResponse(request, requestRoute);
  }

  bool acceptResponse(int request, ModalRoute<dynamic>? requestRoute) {
    if (!current || request != epoch) {
      return false;
    }
    if (!identical(requestRoute, ModalRoute.of(context)) ||
        requestRoute?.isCurrent != true) {
      epoch++;
      setState(() {
        loading = saving = false;
        needsRefresh = true;
        error = 'Der Dialog war verdeckt. Bitte den aktuellen Stand neu laden. Dein Entwurf bleibt erhalten.';
      });
      return false;
    }
    return true;
  }

  Future<void> load() async {
    if (!active || saving) {
      return;
    }
    final request = ++epoch;
    final requestRoute = ModalRoute.of(context);
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final values = await Future.wait([
        ownerState.api.call('GET', '/curriculum/catalog', null, headers),
        ownerState.api.call('GET', path, null, headers),
      ]);
      if (!await readyResponse(request, requestRoute)) {
        return;
      }
      final catalog = values[0], row = values[1];
      if (row['child_id'] != childId ||
          row['revision'] is! int ||
          row['grade'] is! int ||
          (row['grade'] as int) < 1 ||
          (row['grade'] as int) > 13 ||
          row['profile_revision'] is! String ||
          catalog['states'] is! List) {
        throw ApiError('Der Lehrplanstand ist nicht vollständig verfügbar.');
      }
      final candidates = (catalog['states'] as List)
          .whereType<Map>()
          .map((s) => Json.from(s))
          .toList();
      if (candidates.any(
        (s) =>
            s['code'] is! String ||
            s['name'] is! String ||
            s['school_forms'] is! List,
      )) {
        throw ApiError('Der Länderkatalog ist nicht vollständig verfügbar.');
      }
      final code = row['state_code'] as String?;
      if (code != null && !candidates.any((s) => s['code'] == code)) {
        throw ApiError(
          'Die gespeicherte Landeszuordnung ist nicht im aktuellen Katalog.',
        );
      }
      final selected = candidates.where((s) => s['code'] == code).firstOrNull;
      final availableForms = (selected?['school_forms'] as List? ?? [])
          .whereType<Map>();
      if (row['school_form_id'] != null &&
          !availableForms.any((f) => f['id'] == row['school_form_id'])) {
        throw ApiError(
          'Die gespeicherte Schulform muss im aktuellen Katalog neu geprüft werden.',
        );
      }
      setState(() {
        needsRefresh = false;
        states
          ..clear()
          ..addAll(candidates);
        profile = row;
        revision = row['revision'];
        profileRevision = row['profile_revision'];
        grade = row['grade'];
        stateCode = code;
        schoolForm = row['school_form_id'];
        baseline = fingerprint;
        requestKey = requestBody = null;
      });
    } catch (e) {
      if (await readyResponse(request, requestRoute)) {
        setState(
          () => error = e is ApiError
              ? e.message
              : 'Der Lehrplan konnte nicht geladen werden.',
        );
      }
    } finally {
      if (current && request == epoch) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> reload() async {
    if (!active || saving) {
      return;
    }
    if (dirty) {
      final discard = await confirmParentDiscard(
        context,
        current: () => current,
        subject: 'Die Lehrplanauswahl',
        onRoute: (r) => discardRoute = r,
      );
      discardRoute = null;
      if (!discard || !current) {
        return;
      }
    }
    await load();
  }

  Future<void> save() async {
    if (!interactive || !dirty || profileRevision == null) {
      return;
    }
    if (chosenState == null ||
        (schoolForm != null && !forms.any((f) => f['id'] == schoolForm))) {
      setState(
        () =>
            error = 'Wähle ein Bundesland und eine dort angebotene Schulform.',
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final value = body, serialized = fingerprint;
    if (serialized != requestBody) {
      requestBody = serialized;
      requestKey = List.generate(
        24,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
    }
    final request = ++epoch;
    final requestRoute = ModalRoute.of(context);
    setState(() {
      saving = true;
      error = notice = null;
    });
    try {
      final row = await ownerState.api.call('PUT', path, value, {
        ...headers,
        'Idempotency-Key': requestKey!,
      });
      if (!await readyResponse(request, requestRoute)) {
        return;
      }
      if (row['child_id'] != childId ||
          row['revision'] is! int ||
          row['profile_revision'] is! String ||
          row['state_code'] != value['state_code'] ||
          row['school_form_id'] != value['school_form_id'] ||
          row['grade'] != value['grade']) {
        throw ApiError(
          'Die gespeicherte Zuordnung konnte nicht bestätigt werden. Bitte neu laden.',
        );
      }
      setState(() {
        profile = row;
        revision = row['revision'];
        profileRevision = row['profile_revision'];
        baseline = fingerprint;
        requestKey = requestBody = null;
        notice = 'Gespeichert. Die Lehrplanauswahl passt jetzt zu diesem Kind.';
        didSave = true;
      });
      widget.onSaved?.call();
    } catch (e) {
      if (await readyResponse(request, requestRoute)) {
        setState(
          () => error = e is ApiError ? e.message : 'Das Speichern hat nicht geklappt. Dein Entwurf bleibt erhalten.',
        );
      }
    } finally {
      if (current && request == epoch) {
        setState(() => saving = false);
      }
    }
  }

  Future<void> close() async {
    if (!active || saving) {
      return;
    }
    if (dirty) {
      final discard = await confirmParentDiscard(
        context,
        current: () => current,
        subject: 'Die Lehrplanauswahl',
        onRoute: (r) => discardRoute = r,
      );
      discardRoute = null;
      if (!discard || !current) {
        return;
      }
    }
    if (!mounted || !current) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context, didSave);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localEpoch = epoch;
    final localBody = fingerprint;
    final localState = stateCode;
    final enabled = interactive;
    // A DropdownButton reads its current callback after its popup returns.
    // Keep that callback installed while the popup covers this route; each
    // selection still checks interactive and the captured state/epoch below.
    final fieldsEnabled = fieldsAvailable;
    return PopScope(
      canPop: !dirty && !saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          close();
        }
      },
      child: AlertDialog(
        scrollable: true,
        title: const Text('Bundesland & Lehrplan'),
        content: SizedBox(
          width: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Für ${widget.childName}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              if (loading) const LinearProgressIndicator(),
              if (!loading && profile != null) ...[
                if (profile?['configured'] != true &&
                    ('${profile?['legacy_region'] ?? ''}${profile?['legacy_school_type'] ?? ''}')
                        .trim()
                        .isNotEmpty)
                  Notice(
                    'Bisher eingetragen: ${profile?['legacy_region'] ?? ''} · ${profile?['legacy_school_type'] ?? ''}. Bitte dem passenden Land und Schulweg zuordnen.',
                  ),
                if (profile?['needs_review'] == true ||
                    profile?['state_binding_stale'] == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Notice(
                      (profile?['notice'] as String?)?.trim().isNotEmpty == true
                          ? profile!['notice']
                          : 'Land oder Schulform wurde außerhalb des Lehrplanprofils geändert. Bitte die Zuordnung neu prüfen.',
                      warning: true,
                    ),
                  ),
                DropdownButtonFormField<String>(
                  key: ValueKey('curriculum-state:$stateCode'),
                  initialValue: stateCode,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: const InputDecoration(labelText: 'Bundesland'),
                  items: states
                      .map(
                        (s) => DropdownMenuItem<String>(
                          value: s['code'],
                          child: Text('${s['name']}'),
                        ),
                      )
                      .toList(),
                  onChanged: !fieldsEnabled
                      ? null
                      : (value) {
                          if (!interactive ||
                              localEpoch != epoch ||
                              localState != stateCode ||
                              value == null ||
                              !states.any((s) => s['code'] == value)) {
                            return;
                          }
                          setState(() {
                            stateCode = value;
                            schoolForm = null;
                            error = notice = null;
                          });
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('curriculum-school:$stateCode:$schoolForm'),
                  initialValue: schoolForm,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: const InputDecoration(labelText: 'Schulform'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Noch nicht ausgewählt'),
                    ),
                    ...forms.map(
                      (s) => DropdownMenuItem<String>(
                        value: s['id'],
                        child: Text('${s['label']}'),
                      ),
                    ),
                  ],
                  onChanged: !fieldsEnabled || stateCode == null
                      ? null
                      : (value) {
                          if (!interactive ||
                              localEpoch != epoch ||
                              localState != stateCode ||
                              (value != null &&
                                  !forms.any((f) => f['id'] == value))) {
                            return;
                          }
                          setState(() {
                            schoolForm = value;
                            error = notice = null;
                          });
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey('curriculum-grade:$grade'),
                  initialValue: grade,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: const InputDecoration(labelText: 'Klassenstufe'),
                  items: [
                    for (var i = 1; i <= 13; i++)
                      DropdownMenuItem(value: i, child: Text('Klasse $i')),
                  ],
                  onChanged: !fieldsEnabled
                      ? null
                      : (value) {
                          if (!interactive ||
                              localEpoch != epoch ||
                              localState != stateCode ||
                              value == null ||
                              value < 1 ||
                              value > 13) {
                            return;
                          }
                          setState(() {
                            grade = value;
                            error = notice = null;
                          });
                        },
                ),
                const SizedBox(height: 14),
                const Text(
                  'Lehrpläne können mehrere Klassen oder Oberstufenphasen zusammenfassen. Das zeigen wir bei den Themen an.',
                ),
                if (chosenState?['coverage'] != 'complete') ...[
                  const SizedBox(height: 10),
                  const Notice(
                    'Der geprüfte Themenbestand wird erweitert. Fehlende Zuordnungen werden nicht als vollständiger Lehrplan ausgegeben.',
                  ),
                ],
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Notice(error!, warning: true),
                ),
              if (notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Notice(notice!),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : close,
            child: const Text('Schließen'),
          ),
          TextButton(
            onPressed: saving || loading ? null : reload,
            child: const Text('Neu laden'),
          ),
          FilledButton(
            onPressed: !enabled || !dirty || profileRevision == null
                ? null
                : () {
                    if (!interactive ||
                        localEpoch != epoch ||
                        localBody != fingerprint) {
                      return;
                    }
                    save();
                  },
            child: Text(saving ? 'Wird gespeichert…' : 'Zuordnung speichern'),
          ),
        ],
      ),
    );
  }
}
