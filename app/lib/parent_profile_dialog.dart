import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'parent_form_guard.dart';
import 'ui.dart';

/// Only explicit parent profile editing; learning snapshots are never rewritten.
Future<void> showParentProfileDialog(
  BuildContext context,
  AppState state,
  Json child,
) async {
  if (!context.mounted || !state.isParent || !state.canManage) return;
  final account = state.user, family = state.familyId;
  final route = DialogRoute<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ParentProfileEditor(state, child: Json.from(child)),
  );
  final changed = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  if (changed == true &&
      context.mounted &&
      identical(state.user, account) &&
      state.familyId == family) {
    toast(context, 'Lernangaben gespeichert.');
  }
}

class _ParentProfileEditor extends StatefulWidget {
  final AppState state;
  final Json child;
  const _ParentProfileEditor(this.state, {required this.child});
  @override
  State<_ParentProfileEditor> createState() => _ParentProfileEditorState();
}

class _ParentProfileEditorState extends State<_ParentProfileEditor> {
  final form = GlobalKey<FormState>();
  final feedback = GlobalKey();
  late final Json? account;
  late final String? family;
  late final TextEditingController name, grade, subjects, school, region;
  late String baseline;
  String? revision, error;
  Json? comparison;
  bool busy = false, comparing = false, closing = false;
  ModalRoute<bool>? discardRoute;
  bool get current =>
      mounted &&
      !closing &&
      identical(account, widget.state.user) &&
      family == widget.state.familyId &&
      widget.state.canManage;
  List<TextEditingController> get controllers => [
    name,
    grade,
    subjects,
    school,
    region,
  ];
  String fingerprint() => jsonEncode(controllers.map((c) => c.text).toList());
  bool get dirty => fingerprint() != baseline;
  @override
  void initState() {
    super.initState();
    account = widget.state.user;
    family = widget.state.familyId;
    final child = widget.child;
    name = TextEditingController(text: child['display_name']);
    grade = TextEditingController(text: '${child['grade']}');
    subjects = TextEditingController(
      text: (child['subjects'] as List? ?? []).join(', '),
    );
    school = TextEditingController(text: child['school_type'] ?? '');
    region = TextEditingController(text: child['region'] ?? '');
    revision = child['profile_revision'] as String?;
    baseline = fingerprint();
    widget.state.addListener(identityChanged);
  }

  void identityChanged() {
    if (current || closing) return;
    closing = true;
    final route = ModalRoute.of(context), extra = discardRoute;
    setState(() {});
    Future<void>.microtask(() {
      if (extra?.isActive == true) extra!.navigator?.removeRoute(extra);
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(identityChanged);
    for (final c in controllers) {
      c.dispose();
    }
    final extra = discardRoute;
    if (extra?.isActive == true) {
      Future<void>.microtask(() {
        if (extra!.isActive) extra.navigator?.removeRoute(extra);
      });
    }
    super.dispose();
  }

  void revealError() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final target = feedback.currentContext;
    if (current && target != null && target.mounted) {
      Scrollable.ensureVisible(
        target,
        alignment: .5,
        duration: const Duration(milliseconds: 180),
      );
    }
  });
  Future<void> close() async {
    if (!current ||
        busy ||
        comparing ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    if (dirty) {
      final discard = await confirmParentDiscard(
        context,
        current: () => current,
        subject: 'Diese Kinderangaben',
        onRoute: (r) => discardRoute = r,
      );
      discardRoute = null;
      if (!discard || !current || busy || comparing) return;
    }
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context, false);
    }
  }

  Json get body => {
    'display_name': name.text.trim(),
    'grade': int.parse(grade.text.trim()),
    'subjects': subjects.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(),
    'school_type': school.text.trim(),
    'region': region.text.trim(),
  };
  Future<void> save() async {
    if (!current ||
        busy ||
        comparing ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final invalid = form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await Scrollable.ensureVisible(
        invalid.first.context,
        alignment: .5,
        duration: const Duration(milliseconds: 180),
      );
      return;
    }
    final saved = body, expected = revision;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.state.api.call(
        'PUT',
        '/children/${widget.child['id']}',
        saved,
        {'If-Match': ?expected},
      );
      if (mounted && current) {
        final route = ModalRoute.of(context);
        if (route?.isCurrent == true) {
          Navigator.pop(context, true);
        } else if (route?.isActive == true) {
          route!.navigator?.removeRoute(route, true);
        }
      }
    } catch (e) {
      if (current) {
        setState(
          () => error = e is ApiError ? e.message : 'Die Kinderangaben konnten nicht gespeichert werden. Dein Entwurf bleibt erhalten.',
        );
        revealError();
      }
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  Future<void> compare() async {
    if (!current || busy || comparing) return;
    setState(() {
      comparing = true;
    });
    try {
      final value = await widget.state.api.get('/families/$family');
      if (!current) return;
      final row = (value['children'] as List? ?? [])
          .whereType<Map>()
          .where((c) => c['id'] == widget.child['id'])
          .firstOrNull;
      if (row == null || row['profile_revision'] is! String) {
        throw ApiError(
          'Der aktuelle Kinderstand ist nicht verfügbar. Schließe diesen Entwurf und lade die Familie erneut.',
        );
      }
      setState(() {
        comparison = Json.from(row);
        error = null;
      });
    } catch (e) {
      if (current) {
        setState(
          () => error = e is ApiError ? e.message : 'Der gespeicherte Vergleich konnte nicht geladen werden. Deine Eingaben bleiben erhalten.',
        );
        revealError();
      }
    } finally {
      if (current) setState(() => comparing = false);
    }
  }

  void adopt() {
    if (!current || busy || comparing || comparison == null) return;
    final fresh = comparison!;
    setState(() {
      name.text = fresh['display_name'];
      grade.text = '${fresh['grade']}';
      subjects.text = (fresh['subjects'] as List).join(', ');
      school.text = fresh['school_type'] ?? '';
      region.text = fresh['region'] ?? '';
      revision = fresh['profile_revision'];
      baseline = fingerprint();
      comparison = null;
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) => !current
      ? const SizedBox.shrink()
      : PopScope(
          canPop: !busy && !comparing && !dirty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !busy && !comparing) close();
          },
          child: AlertDialog(
            scrollable: true,
            title: const Text('Notwendige Lernangaben'),
            content: SizedBox(
              width: 460,
              child: Form(
                key: form,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: () {
                  if (mounted) setState(() {});
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Für ${widget.child['display_name']}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (widget.child['username'] is String)
                      Text('Kinderzugang: ${widget.child['username']}'),
                    const Text(
                      'Benutzername, Passwörter und gespeicherte Antworten werden hier nicht geändert.',
                    ),
                    const SizedBox(height: 16),
                    for (final item in [
                      (name, 'Anzeigename'),
                      (grade, 'Klassenstufe'),
                      (subjects, 'Fächer (mit Komma trennen)'),
                      (school, 'Schulform (optional)'),
                      (region, 'Bundesland (optional)'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: TextFormField(
                          controller: item.$1,
                          enabled: !busy && !comparing,
                          keyboardType: identical(item.$1, grade)
                              ? TextInputType.number
                              : null,
                          textInputAction: identical(item.$1, region)
                              ? TextInputAction.done
                              : TextInputAction.next,
                          decoration: InputDecoration(labelText: item.$2),
                          validator: (v) {
                            if (identical(item.$1, name) &&
                                (v ?? '').trim().isEmpty) {
                              return 'Gib einen Anzeigenamen ein.';
                            }
                            if ([name, school, region].contains(item.$1) &&
                                (v ?? '').trim().runes.length > 80) {
                              return 'Nutze für ${item.$2} höchstens 80 Zeichen.';
                            }
                            if (identical(item.$1, subjects)) {
                              final entries = (v ?? '')
                                  .split(',')
                                  .map((s) => s.trim())
                                  .where((s) => s.isNotEmpty)
                                  .toList();
                              if (entries.length > 20) {
                                return 'Du kannst höchstens 20 Fächer angeben.';
                              }
                              if (entries.any((s) => s.runes.length > 80)) {
                                return 'Ein einzelner Fachname darf höchstens 80 Zeichen haben.';
                              }
                              if (entries
                                      .map((s) => s.toLowerCase())
                                      .toSet()
                                      .length !=
                                  entries.length) {
                                return 'Nenne jedes Fach nur einmal.';
                              }
                            }
                            if (identical(item.$1, grade)) {
                              final n = int.tryParse((v ?? '').trim());
                              if (n == null || n < 1 || n > 13) {
                                return 'Nutze eine Klassenstufe von 1 bis 13.';
                              }
                            }
                            return null;
                          },
                        ),
                      ),
                    if (error != null)
                      Semantics(
                        key: feedback,
                        liveRegion: true,
                        child: Notice(error!, warning: true),
                      ),
                    OutlinedButton.icon(
                      onPressed: busy || comparing ? null : compare,
                      icon: const Icon(Icons.compare_arrows),
                      label: Text(
                        comparing
                            ? 'Vergleich wird geladen …'
                            : 'Gespeicherten Stand vergleichen',
                      ),
                    ),
                    if (comparison != null) ...[
                      const Text(
                        'Gespeicherter Stand und dein Entwurf',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      for (final item in [
                        (name, 'display_name', 'Anzeigename'),
                        (grade, 'grade', 'Klassenstufe'),
                        (subjects, 'subjects', 'Fächer'),
                        (school, 'school_type', 'Schulform'),
                        (region, 'region', 'Bundesland'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SelectableText(
                            '${item.$3}\nGespeichert: ${comparison![item.$2] is List ? (comparison![item.$2] as List).join(', ') : comparison![item.$2]}\nDein Entwurf: ${item.$1.text}',
                          ),
                        ),
                      const Notice(
                        'Vergleichen speichert nichts. Der folgende Knopf ersetzt bewusst deinen Entwurf durch den gespeicherten Stand.',
                      ),
                      OutlinedButton(
                        onPressed: busy || comparing ? null : adopt,
                        child: const Text(
                          'Gespeicherten Stand in den Entwurf übernehmen',
                        ),
                      ),
                    ],
                    if (busy) const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy || comparing ? null : close,
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: busy || comparing ? null : save,
                child: Text(busy ? 'Bitte warten …' : 'Speichern'),
              ),
            ],
          ),
        );
}
