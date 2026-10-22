import 'package:flutter/material.dart';

/// Discarding a private form is explicit, without writing a draft or a request.
Future<bool> confirmParentDiscard(
  BuildContext context, {
  required bool Function() current,
  required String subject,
  required ValueChanged<ModalRoute<bool>> onRoute,
}) async {
  if (!context.mounted ||
      !current() ||
      ModalRoute.of(context)?.isCurrent != true) {
    return false;
  }
  late final DialogRoute<bool> route;
  route = DialogRoute<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: const Text('Änderungen verwerfen?'),
      content: Text(
        '$subject enthält noch nicht gespeicherte Änderungen. Du kannst weiterbearbeiten oder sie bewusst verwerfen.',
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (ctx.mounted && current() && route.isCurrent) {
              Navigator.pop(ctx, false);
            }
          },
          child: const Text('Weiterbearbeiten'),
        ),
        FilledButton(
          onPressed: () {
            if (ctx.mounted && current() && route.isCurrent) {
              Navigator.pop(ctx, true);
            }
          },
          child: const Text('Änderungen verwerfen'),
        ),
      ],
    ),
  );
  onRoute(route);
  if (!current()) return false;
  final accepted = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  return context.mounted && current() && accepted == true;
}
