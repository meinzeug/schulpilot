import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'parent_form_guard.dart';
import 'ui.dart';

/// Personal reminders never change the child's goals or device push consent.
class ParentGoalRemindersButton extends StatelessWidget {
  final AppState state;
  final String childId, childName;
  const ParentGoalRemindersButton(
    this.state, {
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  Widget build(BuildContext context) {
    final owner = state.user, family = state.familyId, token = state.api.token;
    if (!state.isParent || family == null || owner == null) {
      return const SizedBox.shrink();
    }
    return OutlinedButton.icon(
      key: ValueKey('parent-goal-reminders:$childId'),
      onPressed: () {
        if (!context.mounted ||
            !identical(state.user, owner) ||
            state.familyId != family ||
            state.api.token != token ||
            ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        showParentGoalReminders(
          context,
          state,
          childId: childId,
          childName: childName,
        );
      },
      icon: const Icon(Icons.notifications_active_outlined),
      label: const Text('Lernhinweise einstellen'),
    );
  }
}

Future<void> showParentGoalReminders(
  BuildContext context,
  AppState state, {
  required String childId,
  required String childName,
}) async {
  if (!context.mounted ||
      !state.isParent ||
      state.familyId == null ||
      state.user?['id'] is! String ||
      ModalRoute.of(context)?.isCurrent != true) {
    return;
  }
  final owner = state.user!, family = state.familyId, token = state.api.token;
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ReminderEditor(
      state,
      childId: childId,
      childName: childName,
      owner: owner,
      family: family,
      token: token,
    ),
  );
  await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
}

class _ReminderEditor extends StatefulWidget {
  final AppState state;
  final String childId, childName;
  final Json owner;
  final String? family, token;
  const _ReminderEditor(
    this.state, {
    required this.childId,
    required this.childName,
    required this.owner,
    required this.family,
    required this.token,
  });
  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor>
    with WidgetsBindingObserver {
  final form = GlobalKey<FormState>();
  final feedback = GlobalKey();
  final time = TextEditingController(), timezone = TextEditingController();
  late final AppState state;
  late final Json? owner;
  late final String? family, token;
  late final String actor;
  Set<int> weekdays = {};
  int revision = 0, epoch = 0, reads = 0;
  bool enabled = false, daily = false, exams = false;
  bool loaded = false, loading = true, saving = false, closing = false;
  bool foreground = true, canConfigure = false, saved = false;
  String? error, baseline, requestFingerprint, requestKey;
  ModalRoute<bool>? discardRoute;

  bool get ownerCurrent =>
      mounted &&
      !closing &&
      state.isParent &&
      identical(state.user, owner) &&
      state.familyId == family &&
      state.api.token == token;
  bool get current => ownerCurrent && foreground;
  bool get interactive =>
      current &&
      !loading &&
      !saving &&
      loaded &&
      canConfigure &&
      ModalRoute.of(context)?.isCurrent == true;
  String get path =>
      '/children/${Uri.encodeComponent(widget.childId)}/parent-goal-reminders';
  Map<String, String> get headers => {'X-Schulpilot-Account': actor};
  Json get body => {
    'revision': revision,
    'enabled': enabled,
    'weekdays': weekdays.toList()..sort(),
    'time': time.text.trim(),
    'timezone': timezone.text.trim(),
    'daily_minimum': daily,
    'exam_sessions': exams,
  };
  String get fingerprint => jsonEncode(body);
  bool get dirty => baseline != null && fingerprint != baseline;

  @override
  void initState() {
    super.initState();
    state = widget.state;
    owner = widget.owner;
    actor = owner?['id']?.toString() ?? '';
    family = widget.family;
    token = widget.token;
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    state.addListener(identityChanged);
    WidgetsBinding.instance.addObserver(this);
    // The route exists before checking it and dispatching a read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (ownerCurrent) {
        load();
      } else {
        identityChanged();
      }
    });
  }

  void identityChanged() {
    if (ownerCurrent || closing) {
      return;
    }
    closing = true;
    epoch++;
    reads++;
    final route = ModalRoute.of(context), extra = discardRoute;
    scheduleMicrotask(() {
      if (extra?.isActive == true) {
        extra!.navigator?.removeRoute(extra);
      }
      if (route?.isActive == true) {
        route!.navigator?.removeRoute(route);
      }
    });
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    final active = value == AppLifecycleState.resumed;
    if (foreground == active || !mounted || closing) {
      return;
    }
    foreground = active;
    epoch++;
    reads++;
    final extra = discardRoute;
    discardRoute = null;
    if (extra?.isActive == true) {
      scheduleMicrotask(() {
        if (extra!.isActive) {
          extra.navigator?.removeRoute(extra);
        }
      });
    }
    setState(() {
      loading = saving = false;
      if (loaded) {
        error = 'Die Ansicht war im Hintergrund. Deine Auswahl bleibt erhalten. Prüfe sie und speichere bei Bedarf erneut.';
      }
    });
    // No write, device permission or provider request on resume. A not-yet-read
    // form may perform only its original authenticated settings GET again.
    if (active && !loaded) {
      load();
    }
  }

  bool requestCurrent(int captured, int read) =>
      current &&
      epoch == captured &&
      reads == read &&
      ModalRoute.of(context)?.isCurrent == true;

  Future<void> load() async {
    if (!current || saving || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final captured = epoch, read = ++reads;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = Json.from(await state.api.call('GET', path, null, headers));
      if (!requestCurrent(captured, read)) {
        return;
      }
      adopt(value);
    } catch (e) {
      if (requestCurrent(captured, read)) {
        setState(
          () => error = e is ApiError
              ? e.message
              : 'Die Lernhinweise konnten nicht geladen werden.',
        );
      }
    } finally {
      if (ownerCurrent && epoch == captured && reads == read) {
        setState(() {
          loading = false;
          if (!loaded && error == null) {
            error =
                'Die Ansicht wurde unterbrochen. Lade die Lernhinweise erneut.';
          }
        });
      }
    }
  }

  void adopt(Json value) {
    final days = value['weekdays'];
    if (value['child_id'] != widget.childId ||
        value['revision'] is! int ||
        value['revision'] < 0 ||
        value['enabled'] is! bool ||
        days is! List ||
        days.any((d) => d is! int || d < 0 || d > 6) ||
        days.toSet().length != days.length ||
        value['time'] is! String ||
        !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value['time']) ||
        value['timezone'] is! String ||
        value['timezone'].isEmpty ||
        value['timezone'].runes.length > 64 ||
        value['daily_minimum'] is! bool ||
        value['exam_sessions'] is! bool ||
        value['can_configure'] is! bool) {
      throw ApiError(
        'Der gespeicherte Hinweisstand ist unvollständig. Bitte erneut laden.',
      );
    }
    setState(() {
      revision = value['revision'];
      enabled = value['enabled'];
      weekdays = days.cast<int>().toSet();
      time.text = value['time'];
      timezone.text = value['timezone'];
      daily = value['daily_minimum'];
      exams = value['exam_sessions'];
      canConfigure = value['can_configure'];
      loaded = true;
      baseline = fingerprint;
      requestFingerprint = requestKey = null;
      error = null;
    });
  }

  void changed(int captured, VoidCallback change) {
    if (!interactive || epoch != captured) {
      return;
    }
    setState(() {
      change();
      saved = false;
      error = null;
    });
  }

  void revealFeedback() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final target = feedback.currentContext;
    if (current &&
        target != null &&
        target.mounted &&
        ModalRoute.of(context)?.isCurrent == true) {
      Scrollable.ensureVisible(
        target,
        alignment: .5,
        duration: const Duration(milliseconds: 160),
      );
    }
  });

  Future<void> save() async {
    if (!interactive) {
      return;
    }
    final invalid = form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await Scrollable.ensureVisible(
        invalid.first.context,
        alignment: .5,
        duration: const Duration(milliseconds: 160),
      );
      return;
    }
    if (enabled && (weekdays.isEmpty || (!daily && !exams))) {
      setState(
        () => error = weekdays.isEmpty
            ? 'Wähle mindestens einen Wochentag.'
            : 'Wähle mindestens einen Anlass für den Hinweis.',
      );
      revealFeedback();
      return;
    }
    final snapshot = body, captured = epoch, read = reads;
    final encoded = jsonEncode(snapshot);
    if (requestFingerprint != encoded) {
      requestFingerprint = encoded;
      requestKey =
          'goal-${List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    }
    final key = requestKey!;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      saving = true;
      error = null;
      saved = false;
    });
    try {
      final value = Json.from(
        await state.api.call('PUT', path, snapshot, {
          ...headers,
          'Idempotency-Key': key,
        }),
      );
      if (!requestCurrent(captured, read)) {
        return;
      }
      adopt(value);
      setState(() => saved = true);
      revealFeedback();
    } catch (e) {
      if (requestCurrent(captured, read)) {
        setState(
          () => error = e is ApiError && e.status == 409
              ? '${e.message} Deine Auswahl bleibt erhalten. Lade den gespeicherten Stand bewusst, bevor du ihn ersetzt.'
              : '${e is ApiError ? e.message : 'Speichern fehlgeschlagen.'} Deine Auswahl bleibt erhalten.',
        );
        revealFeedback();
      }
    } finally {
      if (ownerCurrent && epoch == captured && reads == read) {
        setState(() => saving = false);
      }
    }
  }

  Future<bool> discard() async {
    if (!dirty) {
      return true;
    }
    final captured = epoch;
    final accepted = await confirmParentDiscard(
      context,
      current: () => current && epoch == captured,
      subject: 'Deine Lernhinweise',
      onRoute: (r) => discardRoute = r,
    );
    discardRoute = null;
    return accepted &&
        mounted &&
        current &&
        epoch == captured &&
        ModalRoute.of(context)?.isCurrent == true;
  }

  Future<void> reload() async {
    if (!current ||
        saving ||
        loading ||
        ModalRoute.of(context)?.isCurrent != true ||
        !await discard()) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (current && ModalRoute.of(context)?.isCurrent == true) {
      epoch++;
      await load();
    }
  }

  Future<void> close() async {
    if (!current ||
        saving ||
        ModalRoute.of(context)?.isCurrent != true ||
        !await discard()) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (current && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    reads++;
    state.removeListener(identityChanged);
    WidgetsBinding.instance.removeObserver(this);
    time.dispose();
    timezone.dispose();
    final extra = discardRoute;
    scheduleMicrotask(() {
      if (extra?.isActive == true) {
        extra!.navigator?.removeRoute(extra);
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ownerCurrent) {
      return const SizedBox.shrink();
    }
    final captured = epoch;
    final edit = interactive;
    const days = [
      'Montag',
      'Dienstag',
      'Mittwoch',
      'Donnerstag',
      'Freitag',
      'Samstag',
      'Sonntag',
    ];
    return PopScope(
      canPop: !saving && !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          close();
        }
      },
      child: AlertDialog(
        key: const ValueKey('parent-goal-reminders-dialog'),
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: const Text('Meine Lernhinweise'),
        content: SizedBox(
          width: 480,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Für ${widget.childName}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Nur an dich. Die Lernziele und Pläne deines Kindes bleiben unverändert.',
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (loaded) ...[
                  SwitchListTile(
                    key: const ValueKey('goal-reminder-enabled'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Lernhinweise an mich'),
                    value: enabled,
                    onChanged: edit
                        ? (v) => changed(captured, () => enabled = v)
                        : null,
                  ),
                  const Text(
                    'An diesen Tagen',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < days.length; i++)
                        Semantics(
                          label: days[i],
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            child: FilterChip(
                              key: ValueKey('goal-reminder-day:$i'),
                              label: Text(days[i].substring(0, 2)),
                              selected: weekdays.contains(i),
                              onSelected: edit
                                  ? (v) => changed(captured, () {
                                      if (v) {
                                        weekdays.add(i);
                                      } else {
                                        weekdays.remove(i);
                                      }
                                    })
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('goal-reminder-time'),
                    controller: time,
                    enabled: edit,
                    keyboardType: TextInputType.datetime,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
                      LengthLimitingTextInputFormatter(5),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Uhrzeit',
                      helperText:
                          '24-Stunden-Format, z. B. 18:00 · ${timezone.text}',
                    ),
                    validator: (v) =>
                        RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$')
                            .hasMatch((v ?? '').trim())
                        ? null
                        : 'Nutze eine Uhrzeit von 00:00 bis 23:59.',
                    onChanged: (_) => changed(captured, () {}),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    key: const ValueKey('goal-reminder-daily'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Offenes Mindestlernziel'),
                    subtitle: const Text(
                      'Nur an einem vorgesehenen Lerntag, wenn noch Lernzeit fehlt.',
                    ),
                    value: daily,
                    onChanged: edit
                        ? (v) => changed(captured, () => daily = v)
                        : null,
                  ),
                  SwitchListTile(
                    key: const ValueKey('goal-reminder-exams'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Offene Klassenarbeitsrunden'),
                    subtitle: const Text(
                      'Nur für geplante Runden am heutigen Tag. Keine Nachholhinweise für alte Tage.',
                    ),
                    value: exams,
                    onChanged: edit
                        ? (v) => changed(captured, () => exams = v)
                        : null,
                  ),
                  ExpansionTile(
                    key: const ValueKey('goal-reminder-timezone-tools'),
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Zeitzone'),
                    children: [
                      TextFormField(
                        key: const ValueKey('goal-reminder-timezone'),
                        controller: timezone,
                        enabled: edit,
                        maxLength: 64,
                        decoration: const InputDecoration(
                          labelText: 'Zeitzone',
                          helperText: 'Zum Beispiel Europe/Berlin oder UTC',
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Gib eine Zeitzone an.'
                            : null,
                        onChanged: (_) => changed(captured, () {}),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hinweise stehen in deiner Glocke. Push benötigt zusätzlich die Freigabe auf diesem Gerät und die Kategorie „Lernhinweise zu offenen Zielen“. Ruhezeiten und Geräteeinstellungen gelten weiter. Eine Zustellung ist nicht garantiert.',
                  ),
                  if (!canConfigure)
                    const Notice(
                      'Diese Einstellung kann mit deinem aktuellen Zugang nicht geändert werden.',
                      warning: true,
                    ),
                ],
                if (error != null || saved)
                  Padding(
                    key: feedback,
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Notice(
                        error ??
                            'Deine persönlichen Lernhinweise sind gespeichert.',
                        warning: error != null,
                      ),
                    ),
                  ),
                if (!loading && (error != null || loaded))
                  TextButton(
                    key: const ValueKey('goal-reminder-reload'),
                    onPressed: current && !saving
                        ? () {
                            if (epoch == captured) {
                              reload();
                            }
                          }
                        : null,
                    child: Text(
                      loaded ? 'Gespeicherten Stand laden' : 'Erneut laden',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('goal-reminder-close'),
            onPressed: current && !saving
                ? () {
                    if (epoch == captured) {
                      close();
                    }
                  }
                : null,
            child: const Text('Schließen'),
          ),
          FilledButton(
            key: const ValueKey('goal-reminder-save'),
            onPressed: edit
                ? () {
                    if (epoch == captured) {
                      save();
                    }
                  }
                : null,
            child: Text(saving ? 'Wird gespeichert …' : 'Speichern'),
          ),
        ],
      ),
    );
  }
}
