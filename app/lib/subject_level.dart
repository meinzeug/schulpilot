import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

Future<void> editSubjectLevel(
  BuildContext context,
  AppState state,
  String childId,
  String subjectId,
) async {
  final account = state.user, family = state.familyId;
  bool current() =>
      account != null &&
      identical(account, state.user) &&
      family == state.familyId &&
      state.isParent;
  if (!current()) return;
  Future<List<Json>> read() => Future.wait([
    state.api.get('/children/$childId/subjects'),
    state.api.get('/children/$childId/subjects/$subjectId/levels'),
  ]);
  final values = await read();
  if (!context.mounted || !current()) return;
  if (values[0]['can_manage'] != true) {
    throw ApiError('Nur berechtigte Eltern können die Stufe ändern.');
  }
  Json? own = (values[0]['items'] as List)
      .map((r) => Json.from(r))
      .where((r) => r['id'] == subjectId)
      .firstOrNull;
  if (own == null) throw ApiError('Fach nicht gefunden.');
  var levels = (values[1]['items'] as List).map((r) => Json.from(r)).toList();
  if (levels.isEmpty) {
    toast(context, 'Für dieses Fach sind keine Stufen hinterlegt.');
    return;
  }
  final previous = levels
      .where(
        (r) =>
            r['level_type'] == own!['level_type'] &&
            (r['level_type'] == 'vorschule'
                ? own!['level_number'] == 0
                : r['level_number'] == own!['level_number']),
      )
      .firstOrNull;
  String selected = previous?['id'] ?? '';
  String? error;
  bool busy = false, canManage = true;
  ModalRoute<dynamic>? route;
  void changed() {
    if (current()) return;
    final old = route;
    if (old == null) return;
    Future<void>.microtask(() {
      if (!current() && old.isActive) old.navigator?.removeRoute(old);
    });
  }

  state.addListener(changed);
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        route ??= ModalRoute.of(ctx);
        changed();
        return StatefulBuilder(
          builder: (ctx, rebuild) => PopScope(
            canPop: !busy,
            child: AlertDialog(
              title: const Text('Stufe festlegen'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      own!['title'],
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: ValueKey('${own!['setting_revision']}:$selected'),
                      initialValue: selected,
                      isExpanded: true,
                      itemHeight: null,
                      decoration: const InputDecoration(
                        labelText: 'Klasse oder Lernjahr',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Noch nicht festlegen'),
                        ),
                        for (final row in levels)
                          DropdownMenuItem<String>(
                            value: row['id'],
                            child: Text(row['title']),
                          ),
                      ],
                      onChanged: busy || !canManage
                          ? null
                          : (value) => rebuild(() => selected = value ?? ''),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Ein Sprachlernjahr ist keine Schulklasse. Wähle es nur, wenn es bekannt ist.',
                      style: TextStyle(color: context.palette.muted),
                    ),
                    if (busy)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: const Text('Stufe wird abgeglichen …'),
                        ),
                      ),
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Notice(error!, warning: true),
                      ),
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                if (!current() || route?.isCurrent != true) {
                                  return;
                                }
                                rebuild(() => busy = true);
                                try {
                                  final latest = await read();
                                  if (!ctx.mounted || !current()) return;
                                  final next = (latest[0]['items'] as List)
                                      .map((r) => Json.from(r))
                                      .where((r) => r['id'] == subjectId)
                                      .firstOrNull;
                                  if (next == null) {
                                    throw ApiError(
                                      'Dieses Fach ist nicht mehr verfügbar.',
                                    );
                                  }
                                  rebuild(() {
                                    own = next;
                                    levels = (latest[1]['items'] as List)
                                        .map((r) => Json.from(r))
                                        .toList();
                                    canManage = latest[0]['can_manage'] == true;
                                    if (!levels.any(
                                      (r) => r['id'] == selected,
                                    )) {
                                      selected = '';
                                    }
                                    error = canManage ? null : 'Du kannst diese Stufe ansehen, aber nicht mehr ändern.';
                                  });
                                } catch (e) {
                                  if (ctx.mounted && current()) {
                                    rebuild(
                                      () => error = e is ApiError ? e.message : 'Die gespeicherte Stufe konnte gerade nicht geladen werden.',
                                    );
                                  }
                                } finally {
                                  if (ctx.mounted && current()) {
                                    rebuild(() => busy = false);
                                  }
                                }
                              },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Gespeicherte Stufe neu laden'),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          if (ctx.mounted && route?.isCurrent == true) {
                            Navigator.pop(ctx);
                          }
                        },
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: busy || !canManage
                      ? null
                      : () async {
                          if (!current() || route?.isCurrent != true) return;
                          final row = levels
                              .where((r) => r['id'] == selected)
                              .firstOrNull;
                          final body = {
                            'active': own!['selected'] == true,
                            'revision': own!['setting_revision'],
                            'level_type': row?['level_type'],
                            'level_number': row == null
                                ? null
                                : row['level_type'] == 'vorschule'
                                ? 0
                                : row['level_number'],
                            'level_confirmed': true,
                          };
                          rebuild(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            await state.api.put(
                              '/children/$childId/subjects/$subjectId',
                              body,
                            );
                            if (!current()) return;
                            state.refreshState();
                            if (route?.isActive == true) {
                              if (route!.isCurrent) {
                                route!.navigator?.pop();
                              } else {
                                route!.navigator?.removeRoute(route!);
                              }
                            }
                          } catch (e) {
                            if (ctx.mounted && current()) {
                              rebuild(
                                () => error = e is ApiError ? e.message : 'Die Stufe konnte gerade nicht gespeichert werden. Deine Auswahl bleibt erhalten.',
                              );
                            }
                          } finally {
                            if (ctx.mounted && current()) {
                              rebuild(() => busy = false);
                            }
                          }
                        },
                  child: const Text('Stufe übernehmen'),
                ),
              ],
            ),
          ),
        );
      },
    );
  } finally {
    state.removeListener(changed);
  }
}
