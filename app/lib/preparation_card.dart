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
      padding: EdgeInsets.only(top: 12),
      child: Panel(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: processing
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.fact_check_outlined, color: context.palette.teal),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${schoolDate(preparation['date'])} · $action'),
          trailing: Icon(Icons.chevron_right_rounded),
          onTap: open,
        ),
      ),
    );
  }
}
