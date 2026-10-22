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

/// Select a saved server suggestion, never inventing a task or a due date.
Json? nextLearningItem(Json data, {String? excludeUnitId}) {
  final plan = Json.from(data['plan'] as Map? ?? {});
  final feedback = data['feedback_resume'];
  if (feedback is Map &&
      feedback['id'] is String &&
      feedback['id'] != excludeUnitId &&
      feedback['pending_feedback'] == true) {
    return Json.from(feedback);
  }
  final seen = <String>{};
  final items = <Json>[];
  for (final raw in [
    ...plan['today'] as List? ?? [],
    if (plan['can_continue_voluntarily'] != false)
      ...plan['voluntary'] as List? ?? [],
  ]) {
    if (raw is! Map) continue;
    final item = Json.from(raw);
    if (!planItemDue(plan, item) ||
        item['kind'] == 'unit' && item['id'] == excludeUnitId ||
        item['status'] == 'completed' ||
        !seen.add('${item['kind']}:${item['id']}')) {
      continue;
    }
    if (data['learning_preparation'] is Map && item['kind'] != 'unit') {
      continue;
    }
    items.add(item);
  }
  return items
          .where(
            (item) =>
                item['kind'] == 'unit' &&
                ['active', 'paused'].contains(item['status']),
          )
          .firstOrNull ??
      items.firstOrNull;
}

Future<void> openPlanItem(
  BuildContext context,
  AppState state,
  Json data,
  dynamic item,
) async {
  final owner = state.user, family = state.familyId;
  final route = ModalRoute.of(context);
  bool currentAccount() =>
      owner != null && identical(state.user, owner) && state.familyId == family;
  bool currentRoute() => context.mounted && (route?.isCurrent ?? true);
  if (!currentAccount() || !currentRoute()) return;
  if (state.isChild && state.user?['child_id'] != data['child']?['id']) return;
  if (item['kind'] == 'unit' && item['pending_feedback'] == true) {
    openRoute(context, '/unit/${item['id']}');
    return;
  }
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
  if (item['kind'] == 'vocabulary') {
    openRoute(
      context,
      '/vocabulary/${data['child']['id']}?locale=${item['target_locale'] ?? 'en-GB'}',
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
        if (!currentAccount() || !context.mounted || !currentRoute()) return;
        final items = found['items'] as List;
        if (items.isNotEmpty) materialId = items.first['id'];
      }
    }
    final queued = await state.api.post(
      '/children/${data['child']['id']}/units',
      {
        'material_id': materialId,
        'assignment_id': item['kind'] == 'assignment' ? item['id'] : null,
        'review_of': item['kind'] == 'review' ? item['id'] : null,
      },
      {
        'Idempotency-Key':
            'learn-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(Object())}',
      },
    );
    if (context.mounted && currentAccount() && currentRoute()) {
      openRoute(
        context,
        '/learning-preparation/${data['child']['id']}/${queued['id']}',
      );
    }
    return;
  }
  if (unitId != null) {
    if (!currentAccount() || !context.mounted || !currentRoute()) return;
    await state.api.post('/units/$unitId/start');
    if (context.mounted && currentAccount() && currentRoute()) {
      openRoute(context, '/unit/$unitId');
    }
  }
}
