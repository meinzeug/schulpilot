import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Installation policy only. Opening or editing never confirms a child's page.
class AdminMaterialReviewSettings extends StatefulWidget {
  final AppState state;
  final bool enabled;
  const AdminMaterialReviewSettings(
    this.state, {
    super.key,
    this.enabled = true,
  });
  @override
  State<AdminMaterialReviewSettings> createState() =>
      _AdminMaterialReviewSettingsState();
}

class _AdminMaterialReviewSettingsState
    extends State<AdminMaterialReviewSettings> {
  static const endpoint = '/admin/installation/material-review';
  late final ownerState = widget.state;
  late final owner = ownerState.user;
  late final token = ownerState.api.token;
  String? savedMode, draft, error, notice;
  int? revision;
  int generation = 0;
  bool opened = false,
      loading = false,
      saving = false,
      conflict = false,
      invalidated = false;
  bool get own =>
      mounted &&
      !invalidated &&
      identical(widget.state, ownerState) &&
      owner != null &&
      identical(ownerState.user, owner) &&
      ownerState.api.token == token &&
      ownerState.isAdmin;
  bool get active =>
      own &&
      widget.enabled &&
      ModalRoute.of(context)?.isCurrent != false &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
  bool get dirty => draft != null && draft != savedMode;

  @override
  void initState() {
    super.initState();
    ownerState.addListener(identityChanged);
  }

  void identityChanged() {
    if (own || !mounted) return;
    generation++;
    setState(() {
      invalidated = true;
      savedMode = draft = error = notice = null;
      revision = null;
      loading = saving = conflict = false;
    });
  }

  @override
  void dispose() {
    generation++;
    ownerState.removeListener(identityChanged);
    super.dispose();
  }

  (String, int) checked(Json value) {
    final mode = value['mode'], version = value['revision'];
    if (!const {'manual', 'automatic'}.contains(mode) ||
        version is! int ||
        version < 0) {
      throw ApiError('Der gespeicherte Prüfmodus konnte nicht gelesen werden.');
    }
    return (mode as String, version);
  }

  Future<void> load() async {
    if (!active || loading || saving) return;
    final request = ++generation;
    final keepDraft = dirty;
    setState(() {
      loading = true;
      error = notice = null;
    });
    try {
      final value = checked(await ownerState.api.get(endpoint));
      if (!own || request != generation) return;
      setState(() {
        savedMode = value.$1;
        revision = value.$2;
        if (!keepDraft) draft = savedMode;
        conflict = false;
        notice = keepDraft
            ? 'Aktueller Stand geladen. Dein Entwurf bleibt erhalten.'
            : null;
      });
    } catch (failure) {
      if (own && request == generation) {
        setState(
          () => error = failure is ApiError
              ? failure.message
              : 'Der Prüfmodus konnte gerade nicht geladen werden.',
        );
      }
    } finally {
      if (own && request == generation) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (!active ||
        loading ||
        saving ||
        !dirty ||
        revision == null ||
        conflict) {
      return;
    }
    final request = ++generation, expected = revision!, selected = draft!;
    setState(() {
      saving = true;
      error = notice = null;
    });
    try {
      final value = checked(
        await ownerState.api.put(endpoint, {
          'mode': selected,
          'expected_revision': expected,
        }),
      );
      if (!own || request != generation) return;
      if (value.$1 != selected || value.$2 < expected) {
        throw ApiError(
          'Der gespeicherte Stand ist unklar. Gleiche ihn vor weiteren Änderungen ab.',
        );
      }
      setState(() {
        savedMode = draft = value.$1;
        revision = value.$2;
        notice = 'Prüfmodus gespeichert.';
      });
    } catch (failure) {
      if (own && request == generation) {
        setState(() {
          conflict = failure is ApiError && failure.status == 409;
          error = conflict
              ? 'Die Einstellung wurde inzwischen geändert. Dein Entwurf bleibt erhalten. Gleiche den aktuellen Stand ab.'
              : failure is ApiError
              ? failure.message
              : 'Speichern hat gerade nicht geklappt. Dein Entwurf bleibt erhalten.';
        });
      }
    } finally {
      if (own && request == generation) setState(() => saving = false);
    }
  }

  static String label(String? value) =>
      value == 'automatic' ? 'Automatisch prüfen' : 'Manuell prüfen';

  @override
  Widget build(BuildContext context) {
    if (!own) return const SizedBox.shrink();
    return ExpansionTile(
      key: const ValueKey('admin-material-review'),
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.fact_check_outlined),
      title: const Text('Prüfung neuer Heftseiten'),
      maintainState: true,
      onExpansionChanged: (value) {
        if (!active) return;
        setState(() => opened = value);
        if (value && revision == null) load();
      },
      children: [
        if (opened)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Lege fest, wie Fotoabschriften vor dem Lernen geprüft werden.',
                ),
                const SizedBox(height: 12),
                if (loading || saving) const LinearProgressIndicator(),
                if (savedMode != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Gespeichert: ${label(savedMode)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                if (revision != null)
                  RadioGroup<String>(
                    groupValue: draft,
                    onChanged: (value) {
                      if (active && !loading && !saving && value != null) {
                        setState(() {
                          draft = value;
                          notice = null;
                        });
                      }
                    },
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          value: 'manual',
                          title: const Text('Manuell prüfen'),
                          subtitle: const Text(
                            'Jede Abschrift ansehen und selbst bestätigen.',
                          ),
                          enabled: active && !loading && !saving,
                        ),
                        RadioListTile<String>(
                          value: 'automatic',
                          title: const Text('Automatisch prüfen'),
                          subtitle: const Text(
                            'Ein zweiter KI-Durchgang prüft Foto und Abschrift. Dafür können zusätzliche KI-Kosten entstehen.',
                          ),
                          enabled: active && !loading && !saving,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Unleserliche Stellen bleiben markiert und werden nicht als Grundlage für bewertete Aufgaben verwendet.',
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Notice(error!, warning: true),
                  ),
                if (notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(notice!),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ActionButton(
                      label: 'Prüfmodus speichern',
                      icon: Icons.save_outlined,
                      enabled:
                          active && !loading && !saving && dirty && !conflict,
                      onPressed: save,
                    ),
                    TextButton(
                      onPressed: active && !loading && !saving ? load : null,
                      child: Text(
                        conflict
                            ? 'Aktuellen Stand abgleichen'
                            : 'Gespeicherten Stand laden',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
