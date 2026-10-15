import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

class PreparationCard extends StatelessWidget {
  final String childId;
  final Json preparation;
  final bool primary;
  const PreparationCard({
    super.key,
    required this.childId,
    required this.preparation,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final status = preparation['status'];
    final processing = status == 'processing';
    final title = processing
        ? 'Deine Fotos sind abgegeben.'
        : status == 'needs_review'
        ? 'Deine Heftseiten sind erkannt.'
        : status == 'needs_photo'
        ? 'Ein Foto braucht dich.'
        : 'Die Vorbereitung wartet.';
    final subtitle = processing
        ? 'Ich bereite deinen Stoff vor. Du kannst die App schließen.'
        : status == 'needs_review'
        ? 'Schau kurz nach, ob alles stimmt.'
        : status == 'needs_photo'
        ? 'Eine Seite ist noch nicht gut lesbar.'
        : 'Deine Fotos bleiben gespeichert. Schau kurz nach.';
    final action = status == 'needs_review'
        ? 'Heftseiten prüfen'
        : status == 'needs_photo'
        ? 'Foto prüfen'
        : 'Vorbereitung ansehen';
    void open() => openRoute(
      context,
      '/after-school/$childId?day=${preparation['day_id']}',
    );
    if (primary) {
      return FocusCard(
        eyebrow: 'Nach der Schule',
        title: title,
        subtitle: subtitle,
        icon: processing
            ? Icons.auto_awesome_outlined
            : Icons.fact_check_outlined,
        action: SizedBox(
          width: double.infinity,
          child: ActionButton(label: action, onPressed: () async => open()),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: processing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.fact_check_outlined, color: teal),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text('${preparation['date'] ?? ''} · $action'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: open,
        ),
      ),
    );
  }
}
