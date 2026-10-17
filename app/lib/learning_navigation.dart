import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

bool planItemDue(Json plan, dynamic item) {
  final scheduled = item['scheduled_for'];
  final date = plan['date'];
  return scheduled == null ||
      date is! String ||
      scheduled.toString().compareTo(date) <= 0;
}

Future<void> openPlanItem(
  BuildContext context,
  AppState state,
  Json data,
  dynamic item,
) async {
  // Collections do not carry a server calendar. Their fixed start dates are
  // enforced by the API; never guess the child's timezone from this device.
  final plan = data['plan'] is Map
      ? Json.from(data['plan'] as Map)
      : <String, dynamic>{};
  if (!planItemDue(plan, item)) {
    throw ApiError('Dieser Lernauftrag ist für einen späteren Tag eingeplant.');
  }
  if (item['kind'] == 'study_path') {
    openRoute(
      context,
      '/after-school/${data['child']['id']}?day=${item['id']}',
    );
    return;
  }
  String? unitId;
  if (item['kind'] == 'unit') {
    unitId = item['id'];
  } else {
    String? materialId = item['material_id'];
    if (item['kind'] == 'material') materialId = item['id'];
    if (item['kind'] == 'assignment' && materialId == null) {
      final matches = (data['materials'] as List? ?? [])
          .where(
            (m) =>
                m['confirmed'] == true &&
                m['subject'] == item['subject'] &&
                m['topic'] == item['topic'],
          )
          .toList();
      if (matches.isNotEmpty) {
        materialId = matches.first['id'];
      } else {
        final path = Uri(
          path: '/children/${data['child']['id']}/materials',
          queryParameters: {
            'subject': item['subject'].toString(),
            'topic': item['topic'].toString(),
            'status': 'confirmed',
            'sort': 'newest',
            'page_size': '1',
          },
        );
        final found = await state.api.get(path.toString());
        final items = found['items'] as List;
        if (items.isNotEmpty) materialId = items.first['id'];
      }
    }
    final result = await state.api.job(
      '/children/${data['child']['id']}/units',
      {
        'material_id': materialId,
        'assignment_id': item['kind'] == 'assignment' ? item['id'] : null,
        'review_of': item['kind'] == 'review' ? item['id'] : null,
      },
    );
    unitId = result['unit_id'];
  }
  if (unitId != null) {
    await state.api.post('/units/$unitId/start');
    if (context.mounted) openRoute(context, '/unit/$unitId');
  }
}
