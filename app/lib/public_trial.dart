import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Public catalogue metadata is an offer, never an account entitlement.
/// Older or incomplete responses must not promise a free trial.
class PublicTrialOffer {
  final bool available;
  final int children;
  final int calls;
  const PublicTrialOffer({
    required this.available,
    this.children = 0,
    this.calls = 0,
  });

  factory PublicTrialOffer.fromCatalog(Json catalog) {
    final value = catalog['trial'];
    if (value is! Map) return const PublicTrialOffer(available: false);
    final children = value['children'];
    final calls = value['calls'];
    final valid =
        value['enabled'] == true &&
        value['duration_days'] == 30 &&
        value['starts_on'] == 'verified_email' &&
        value['payment_required'] == false &&
        value['auto_renew'] == false &&
        children is int &&
        children > 0 &&
        children <= 20 &&
        calls is int &&
        calls >= 0 &&
        calls <= 10000;
    return valid
        ? PublicTrialOffer(available: true, children: children, calls: calls)
        : const PublicTrialOffer(available: false);
  }
}

class TrialTermsSummary extends StatelessWidget {
  final PublicTrialOffer offer;
  final bool compact;
  const TrialTermsSummary(this.offer, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (!offer.available) {
      return const Notice(
        'Der kostenlose Testzugang ist zurzeit noch nicht freigegeben.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '30 Tage kostenlos · für neue Familien',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: context.palette.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Start nach E-Mail-Bestätigung. Die Testphase endet nach 30 Tagen.',
          style: TextStyle(color: context.palette.muted),
        ),
        const SizedBox(height: 8),
        Text(
          '${offer.children} ${offer.children == 1 ? 'Kinderzugang' : 'Kinderzugänge'} · bis zu ${offer.calls} KI-Schritte für die gesamte Testphase',
          style: TextStyle(color: context.palette.ink),
        ),
        const SizedBox(height: 8),
        Text(
          'Keine Zahlungsdaten. Keine automatische Bestellung oder Verlängerung.',
          style: TextStyle(color: context.palette.muted),
        ),
        if (!compact) ...[
          const SizedBox(height: 8),
          const Text(
            'Für KI-Aufträge gelten zusätzlich die verfügbaren Anbieter-, Kosten- und Systemgrenzen. Gespeicherte Inhalte öffnen und Aufgaben beantworten sind keine zusätzlichen KI-Schritte.',
          ),
        ],
      ],
    );
  }
}

class TrialOfferCard extends StatelessWidget {
  final PublicTrialOffer offer;
  final VoidCallback onStart;
  final String actionLabel;
  const TrialOfferCard({
    super.key,
    required this.offer,
    required this.onStart,
    this.actionLabel = '30 Tage kostenlos testen',
  });

  @override
  Widget build(BuildContext context) => Panel(
    color: context.palette.mint,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Tag('EURE ZEIT ZUM AUSPROBIEREN'),
        const SizedBox(height: 16),
        if (offer.available) ...[
          heading('Erst kennenlernen. Dann entscheiden.'),
          const SizedBox(height: 8),
          TrialTermsSummary(offer),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(actionLabel),
          ),
        ] else ...[
          heading('Euer Einstieg wird vorbereitet'),
          const SizedBox(height: 8),
          TrialTermsSummary(offer),
        ],
      ],
    ),
  );
}

/// Uses only the existing parent usage response; never computes an entitlement
/// from the device clock, monthly resets, or a public marketing offer.
class FamilyTrialUsageNotice extends StatelessWidget {
  final Json usage;
  final VoidCallback onRefresh;
  const FamilyTrialUsageNotice(
    this.usage, {
    super.key,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final access = usage['access'];
    if (access is! Map ||
        !['trial', 'trial_expired'].contains(access['state'])) {
      return const SizedBox.shrink();
    }
    final trial = access['trial'];
    final ends = access['state'] == 'trial'
        ? access['ends']
        : trial is Map
        ? trial['ends']
        : null;
    if (trial is! Map ||
        ends is! num ||
        trial['duration_days'] != 30 ||
        trial['payment_required'] != false ||
        trial['auto_renew'] != false) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Notice(
            'Der Teststatus ist unvollständig. Ein gültiges Testende ist gerade nicht bestätigt.',
            warning: true,
          ),
          TextButton(
            onPressed: onRefresh,
            child: const Text('Gespeicherten Teststatus aktualisieren'),
          ),
        ],
      );
    }
    final date = DateTime.fromMillisecondsSinceEpoch(ends.toInt() * 1000)
        .toLocal();
    final deadline =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} um ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} Uhr';
    final expired = access['state'] == 'trial_expired';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          expired
              ? 'Kostenlose Testphase beendet'
              : 'Deine kostenlose Testphase',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text('${expired ? 'Beendet am' : 'Endet am'} $deadline (Ortszeit)'),
        const SizedBox(height: 8),
        if (expired)
          const Text(
            'Neue KI-Schritte sind durch diese Testphase nicht mehr freigeschaltet. Gespeicherte Inhalte bleiben erreichbar.',
          )
        else ...[
          if (usage['calls_used'] is num &&
              usage['calls_remaining'] is num &&
              trial['calls'] is num)
            Text(
              'Angerechnet: ${usage['calls_used']} von ${trial['calls']} KI-Schritten. Noch ${usage['calls_remaining']} Schritte im Testkontingent.',
            ),
          const Text(
            'Das Kontingent gilt für alle 30 Tage zusammen. Ein Monatswechsel setzt es nicht zurück.',
          ),
          const Text(
            'Zusätzliche Kosten- und Systemgrenzen können neue KI-Schritte früher stoppen.',
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          'Keine automatische Bestellung, Abbuchung oder Verlängerung.',
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}
