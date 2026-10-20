import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

Future<void> editSubjectLevel(
  BuildContext context,
  AppState state,
  String childId,
  String subjectId,
) async {
  final owner = state.user?['id'];
  final values = await Future.wait([
    state.api.get('/children/$childId/subjects'),
    state.api.get('/children/$childId/subjects/$subjectId/levels'),
  ]);
  if (!context.mounted || owner != state.user?['id']) return;
  if (values[0]['can_manage'] != true) {
    throw ApiError('Nur berechtigte Eltern können die Stufe ändern.');
  }
  final own = (values[0]['items'] as List)
      .where((r) => r['id'] == subjectId)
      .firstOrNull;
  if (own == null) throw ApiError('Fach nicht gefunden.');
  final levels = (values[1]['items'] as List).map((r) => Json.from(r)).toList();
  if (levels.isEmpty) {
    toast(context, 'Für dieses Fach sind keine Stufen hinterlegt.');
    return;
  }
  final previous = levels
      .where(
        (r) =>
            r['level_type'] == own['level_type'] &&
            (r['level_type'] == 'vorschule'
                ? own['level_number'] == 0
                : r['level_number'] == own['level_number']),
      )
      .firstOrNull;
  String selected = previous?['id'] ?? '';
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, rebuild) => AnimatedBuilder(
        animation: state,
        builder: (_, _) => owner != state.user?['id']
            ? SizedBox.shrink()
            : AlertDialog(
                title: Text('Stufe festlegen'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        own['title'],
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selected,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Klasse oder Lernjahr',
                        ),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text('Noch nicht festlegen'),
                          ),
                          for (final row in levels)
                            DropdownMenuItem<String>(
                              value: row['id'],
                              child: Text(row['title']),
                            ),
                        ],
                        onChanged: (value) =>
                            rebuild(() => selected = value ?? ''),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Ein Sprachlernjahr ist keine Schulklasse. Wähle es nur, wenn es bekannt ist.',
                        style: TextStyle(color: context.palette.muted),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('Abbrechen'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('Stufe übernehmen'),
                  ),
                ],
              ),
      ),
    ),
  );
  if (result != true || !context.mounted || owner != state.user?['id']) return;
  final row = levels.where((r) => r['id'] == selected).firstOrNull;
  await state.api.put('/children/$childId/subjects/$subjectId', {
    'active': own['selected'] == true,
    'revision': own['setting_revision'],
    'level_type': row?['level_type'],
    'level_number': row == null
        ? null
        : row['level_type'] == 'vorschule'
        ? 0
        : row['level_number'],
    'level_confirmed': true,
  });
  if (owner == state.user?['id']) state.refreshState();
}
