import 'dart:convert';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

bool orderWithinDates(dynamic order, DateTimeRange? range) {
  if (range == null) return true;
  final stamp = order['created'];
  if (stamp is! num || !stamp.isFinite || stamp <= 0) return false;
  final date = DateTime.fromMillisecondsSinceEpoch(stamp.toInt() * 1000)
      .toLocal();
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final after = DateTime(range.end.year, range.end.month, range.end.day + 1);
  return !date.isBefore(start) && date.isBefore(after);
}

String storedOrderPeriod(dynamic order, int localNow) {
  if (order['status'] != 'paid') return 'unpaid';
  final start = order['starts'], end = order['ends'];
  if (start is! num ||
      end is! num ||
      !start.isFinite ||
      !end.isFinite ||
      start <= 0 ||
      end <= start) {
    return 'unknown';
  }
  if (start > localNow) return 'scheduled';
  return end <= localNow ? 'ended' : 'running';
}

class StoreOrderPeriodFilter extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const StoreOrderPeriodFilter({
    super.key,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey(value),
    initialValue: value,
    isExpanded: true,
    decoration: const InputDecoration(
      labelText: 'Gespeicherte Laufzeitlage',
      helperText: 'Einordnung der gespeicherten Termine nach Gerätezeit. Freigabe und aktuelle Familienrechte bleiben serverseitig.',
      helperMaxLines: 4,
    ),
    items: const [
      DropdownMenuItem(
        value: 'all',
        child: Text('Alle gespeicherten Laufzeiten'),
      ),
      DropdownMenuItem(
        value: 'scheduled',
        child: Text('Freigeschaltet · beginnt später'),
      ),
      DropdownMenuItem(
        value: 'running',
        child: Text('Freigeschaltet · Termin läuft jetzt'),
      ),
      DropdownMenuItem(
        value: 'ended',
        child: Text('Freigeschaltet · Termin beendet'),
      ),
      DropdownMenuItem(
        value: 'unknown',
        child: Text('Freigeschaltet · Termine fehlen'),
      ),
    ],
    onChanged: (v) {
      if (v != null) {
        FocusManager.instance.primaryFocus?.unfocus();
        onChanged(v);
      }
    },
  );
}

class StoreOrderDateFilter extends StatelessWidget {
  final DateTimeRange? range;
  final ValueChanged<DateTimeRange?> onChanged;
  final bool enabled;
  const StoreOrderDateFilter({
    super.key,
    required this.range,
    required this.onChanged,
    this.enabled = true,
  });
  String date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      OutlinedButton.icon(
        onPressed: !enabled
            ? null
            : () async {
                FocusManager.instance.primaryFocus?.unfocus();
                final result = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(1970),
                  lastDate: DateTime(2100, 12, 31),
                  initialDateRange: range,
                  helpText: 'Bestellt am · geladener Ausschnitt',
                );
                if (context.mounted && result != null && enabled) {
                  onChanged(result);
                }
              },
        icon: const Icon(Icons.date_range_outlined),
        label: Text(
          range == null
              ? 'Bestellzeitraum wählen'
              : '${date(range!.start)} – ${date(range!.end)}',
        ),
      ),
      if (range != null)
        TextButton(
          onPressed: enabled ? () => onChanged(null) : null,
          child: const Text('Bestellzeitraum entfernen'),
        ),
      const Text(
        'Filtert das Bestelldatum in Geräte-Ortszeit innerhalb der geladenen Bestellungen.',
      ),
    ],
  );
}

class LoadedOpenOrderAmount extends StatelessWidget {
  final List<dynamic> orders;
  final VoidCallback? onShow;
  const LoadedOpenOrderAmount({
    super.key,
    required this.orders,
    required this.onShow,
  });
  @override
  Widget build(BuildContext context) {
    final open = orders
        .where((o) => o['status'] == 'awaiting_payment')
        .toList();
    final known = open
        .where((o) => o['amount_cents'] is int && o['amount_cents'] >= 0)
        .toList();
    final cents = known.fold<int>(0, (n, o) => n + (o['amount_cents'] as int));
    return ActionPanel(
      actionLabel: 'Geladene offene Bestellungen anzeigen',
      onPressed: onShow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('OFFENE BESTELLWERTE · GELADENER AUSSCHNITT'),
          Text(
            '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')} € aus ${known.length} Bestellungen mit gemeldetem Preis',
          ),
          if (known.length != open.length)
            Text(
              '${open.length - known.length} offene Bestellungen ohne verwertbaren Preis bleiben aus der Summe ausgeschlossen.',
            ),
          const Text(
            'Bestellwerte, kein gemessener Zahlungseingang und keine vollständige Forderungsübersicht. Eine Zahlung zählt erst nach geprüftem Zahlungsbeleg.',
          ),
        ],
      ),
    );
  }
}

Uint8List storeOrderReportBytes(
  List<dynamic> shown, {
  required int loadedCount,
  required String scope,
}) => Uint8List.fromList(
  utf8.encode(
    const JsonEncoder.withIndent('  ').convert({
      'format': 'schulpilot-order-metadata-v1',
      'scope': scope,
      'generated_at_local': DateTime.now().toIso8601String(),
      'loaded_count': loadedCount,
      'selected_count': shown.length,
      'notice': 'Nur aktuell geladene und ausgewählte Bestellmetadaten. Keine vollständige Historie, Bankumsätze oder privaten Lerninhalte. Gespeicherte Originalstatus und Centbeträge, keine neu bestätigte Zahlung.',
      'orders': [
        for (final order in shown)
          {
            for (final key in [
              'id',
              'payment_reference',
              'status',
              'amount_cents',
              'created',
              'starts',
              'ends',
              'checked_at',
              'mail_status',
            ])
              key: order[key],
            'offer': {
              for (final key in [
                'id',
                'name',
                'price_cents',
                'children',
                'calls',
                'duration_days',
              ])
                key: order['offer']?[key],
            },
          },
      ],
    }),
  ),
);

class StoreOrderExportButton extends StatefulWidget {
  final AppState state;
  final List<dynamic> shown;
  final int loadedCount;
  final String scope;
  final Future<void> Function(Uint8List)? save;
  const StoreOrderExportButton(
    this.state, {
    super.key,
    required this.shown,
    required this.loadedCount,
    required this.scope,
    this.save,
  });
  @override
  State<StoreOrderExportButton> createState() => _StoreOrderExportButtonState();
}

class _StoreOrderExportButtonState extends State<StoreOrderExportButton> {
  late final owner = widget.state.user, family = widget.state.familyId;
  bool busy = false;
  String? note;
  bool get own =>
      mounted &&
      identical(widget.state.user, owner) &&
      (widget.state.isAdmin ||
          widget.state.isOwner && widget.state.familyId == family);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        onPressed: busy || widget.shown.isEmpty || !own
            ? null
            : () async {
                if (!own ||
                    busy ||
                    ModalRoute.of(context)?.isCurrent == false) {
                  return;
                }
                final bytes = storeOrderReportBytes(
                  widget.shown,
                  loadedCount: widget.loadedCount,
                  scope: widget.scope,
                );
                setState(() {
                  busy = true;
                  note = null;
                });
                try {
                  final save = widget.save;
                  if (save != null) {
                    await save(bytes);
                  } else {
                    await FileSaver.instance.saveFile(
                      name: 'schulpilot-bestellausschnitt',
                      bytes: bytes,
                      fileExtension: 'json',
                      mimeType: MimeType.json,
                    );
                  }
                  if (own) {
                    setState(
                      () => note = 'Bestellmetadaten an den Speicherdialog übergeben. Prüfe die lokale Datei selbst; dies ist keine Zahlungsbestätigung.',
                    );
                  }
                } catch (_) {
                  if (own) {
                    setState(
                      () => note = 'Der Bestellausschnitt konnte nicht übergeben werden. Die gespeicherten Bestellungen bleiben unverändert.',
                    );
                  }
                } finally {
                  if (own) setState(() => busy = false);
                }
              },
        icon: const Icon(Icons.download_outlined),
        label: Text(
          busy
              ? 'Bestellausschnitt wird übergeben …'
              : 'Angezeigte Bestellmetadaten speichern',
        ),
      ),
      if (note != null) Semantics(liveRegion: true, child: Notice(note!)),
    ],
  );
}
