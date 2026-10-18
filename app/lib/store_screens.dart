import 'dart:convert';
import 'dart:math';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'ui.dart';

String euro(dynamic cents) =>
    '${((cents as num) / 100).toStringAsFixed(2).replaceAll('.', ',')} €';
String calendar(dynamic stamp) {
  if (stamp == null) return '–';
  final date = DateTime.fromMillisecondsSinceEpoch(
    (stamp as num).toInt() * 1000,
  ).toLocal();
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

String orderStatus(dynamic status) => switch (status) {
  'awaiting_payment' => 'Wartet auf Zahlungseingang',
  'paid' => 'Zahlung geprüft · freigeschaltet',
  'cancelled' => 'Storniert',
  'refunded' => 'Erstattung geprüft · Zugang beendet',
  _ => 'In Prüfung',
};

class StoreSection extends StatelessWidget {
  final AppState state;
  const StoreSection(this.state, {super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || state.isChild) return const SizedBox.shrink();
    return LoadView<Json>(
      load: () => state.api.get('/store/catalog'),
      builder: (catalog, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Tag('EIN PREIS. 30 TAGE. EURE FAMILIE.'),
          const SizedBox(height: 16),
          heading('Mehr Rückenwind für euren Alltag'),
          const Text(
            'Per Überweisung bezahlen. Nach geprüftem Zahlungseingang geht es los. Ohne automatische Verlängerung.',
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, size) {
              final count = (catalog['plans'] as List).length;
              final columns = size.maxWidth >= 920
                  ? 3
                  : size.maxWidth >= 620
                  ? 2
                  : 1;
              final width = (size.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final plan in (catalog['plans'] as List).take(count))
                    SizedBox(
                      width: width,
                      child: Panel(
                        color: plan['id'] == 'familie' ? mint : Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              plan['name'],
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              euro(plan['price_cents']),
                              style: const TextStyle(
                                fontSize: 38,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.5,
                              ),
                            ),
                            const Text(
                              'einmalig für 30 Tage',
                              style: TextStyle(color: muted),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              '${plan['children']} ${plan['children'] == 1 ? 'Kinderzugang' : 'Kinderzugänge'}',
                            ),
                            Text('${plan['calls']} KI-Schritte je Laufzeit'),
                            const SizedBox(height: 8),
                            const Text(
                              'Heftfotos · Lernpakete · Lernhilfe\nEigene Zugänge · Elternübersicht',
                              style: TextStyle(height: 1.7),
                            ),
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: catalog['enabled'] == true
                                  ? () => context.go('/bestellen/${plan['id']}')
                                  : null,
                              child: Text(
                                catalog['enabled'] == true
                                    ? 'Tarif wählen'
                                    : 'Verkauf startet bald',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            catalog['tax_notice'],
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 24),
          const ExpansionTile(
            title: Text('Was ist ein KI-Schritt?'),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Text(
                  'Ein KI-Schritt erkennt Material, erstellt Aufgaben oder gibt neue Lernhilfe. Auch ausdrücklich wiederholte Versuche zählen. Bei einem Fehler mit unbekanntem Verbrauch bleibt der Schritt angerechnet. Vorhandene Inhalte öffnen und Aufgaben beantworten verbraucht keine zusätzlichen KI-Schritte.',
                ),
              ),
            ],
          ),
          const ExpansionTile(
            title: Text('Wann kann mein Kind anfangen?'),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Text(
                  'Nach deiner Bestellung erhältst du die Bankverbindung und einen eindeutigen Verwendungszweck. Wir prüfen den Zahlungseingang und schalten manuell frei. Auf ausdrücklichen Wunsch startet ihr schon vor Ablauf der 14-tägigen Widerrufsfrist. Sonst beginnt die Laufzeit frühestens danach.',
                ),
              ),
            ],
          ),
          const ExpansionTile(
            title: Text('Braucht mein Kind eine E-Mail-Adresse?'),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Text(
                  'Nein. Du erstellst einen eigenen Kinderzugang mit Benutzername und sicherem Passwort. Dein Kind kann sich damit selbst auf seinem Gerät anmelden.',
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () => context.go('/bedingungen'),
            child: const Text('Vertragsbedingungen & Widerruf'),
          ),
        ],
      ),
    );
  }
}

class OffersScreen extends StatelessWidget {
  final AppState state;
  final bool terms;
  const OffersScreen(this.state, {super.key, this.terms = false});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: InkWell(onTap: () => context.go('/'), child: brand()),
      actions: [
        TextButton(
          onPressed: () => context.go(state.user == null ? '/login' : '/app'),
          child: Text(state.user == null ? 'Anmelden' : 'Mein Lernraum'),
        ),
      ],
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: terms
              ? LoadView<Json>(
                  load: () => state.api.get('/store/catalog'),
                  builder: (data, _) =>
                      Panel(child: SelectionArea(child: Text(data['terms']))),
                )
              : StoreSection(state),
        ),
      ),
    ),
  );
}

class CheckoutScreen extends StatefulWidget {
  final AppState state;
  final String planId;
  const CheckoutScreen(this.state, {super.key, required this.planId});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool terms = false, early = false, busy = false;
  String? error;
  final keyId = List.generate(
    24,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Dein Familienzugang',
    child: !widget.state.isOwner
        ? const Panel(
            child: Text('Bestellungen verwaltet der Inhaber des Elternkontos.'),
          )
        : LoadView<Json>(
            load: () => widget.state.api.get('/store/catalog'),
            builder: (catalog, _) {
              final matches = (catalog['plans'] as List).where(
                (p) => p['id'] == widget.planId,
              );
              if (matches.isEmpty) {
                return const Panel(
                  child: Text('Dieser Tarif ist nicht mehr verfügbar.'),
                );
              }
              final plan = matches.first;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading(
                          '${plan['name']} · ${euro(plan['price_cents'])}',
                        ),
                        Text(
                          '${plan['children']} Kinderzugänge · ${plan['calls']} KI-Schritte',
                        ),
                        const Text(
                          '30 Tage ab Freischaltung · keine automatische Verlängerung',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Zahlung per Überweisung. Wir schalten nach manueller Prüfung des Zahlungseingangs frei.',
                        ),
                        Text(catalog['tax_notice']),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: const Text('Vertragsbedingungen & Widerruf lesen'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectionArea(child: Text(catalog['terms'])),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: terms,
                    onChanged: busy ? null : (v) => setState(() => terms = v!),
                    title: const Text(
                      'Ich akzeptiere die Vertragsbedingungen und habe die Widerrufsbelehrung gelesen.',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: early,
                    onChanged: busy ? null : (v) => setState(() => early = v!),
                    title: const Text(
                      'Ich möchte vor Ablauf der 14-tägigen Widerrufsfrist starten.',
                    ),
                    subtitle: const Text(
                      'Optional. Bei Widerruf kann für bereits auf meinen Wunsch erbrachte Leistungen anteiliger Wertersatz anfallen.',
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (catalog['enabled'] != true)
                    const Text('Bestellungen sind noch nicht freigegeben.'),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Text(
                    'Gesamtpreis: ${euro(plan['price_cents'])}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${plan['name']} · 30 Tage · ${plan['children']} Kinderzugänge · ${plan['calls']} KI-Schritte',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: !terms || busy || catalog['enabled'] != true
                        ? null
                        : () async {
                            setState(() {
                              busy = true;
                              error = null;
                            });
                            try {
                              await widget.state.api.post(
                                '/families/${widget.state.familyId}/orders',
                                {
                                  'plan_id': widget.planId,
                                  'catalog_revision': catalog['revision'],
                                  'request_key': keyId,
                                  'accept_terms': true,
                                  'early_start': early,
                                },
                              );
                              if (context.mounted) context.go('/bestellungen');
                            } catch (e) {
                              if (mounted) setState(() => error = e.toString());
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    child: Text(
                      busy
                          ? 'Bestellung wird gespeichert …'
                          : 'Zahlungspflichtig bestellen',
                    ),
                  ),
                ],
              );
            },
          ),
  );
}

class OrdersScreen extends StatefulWidget {
  final AppState state;
  const OrdersScreen(this.state, {super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  int version = 0;
  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Tarif & Bestellungen',
    actions: [
      OutlinedButton.icon(
        onPressed: () => setState(() => version++),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Status aktualisieren'),
      ),
    ],
    child: !widget.state.isOwner
        ? const Text('Nur für den Inhaber des Familienkontos.')
        : LoadView<Json>(
            key: ValueKey(version),
            load: () => widget.state.api.get(
              '/families/${widget.state.familyId}/orders',
            ),
            builder: (data, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FocusCard(
                  eyebrow: 'EUER ZUGANG',
                  title: data['access']['plan'],
                  subtitle: switch (data['access']['state']) {
                    'active' =>
                      'Freigeschaltet bis ${calendar(data['access']['ends'])}',
                    'scheduled' =>
                      'Start am ${calendar(data['access']['starts'])}',
                    'existing' => 'Euer bisheriger Zugang bleibt bestehen.',
                    _ => 'Aktuell keine bezahlte Laufzeit. Gespeicherte Inhalte bleiben erreichbar.',
                  },
                  action: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: ink,
                    ),
                    onPressed: () => context.go('/angebote'),
                    child: const Text('Tarife ansehen'),
                  ),
                ),
                const SizedBox(height: 24),
                for (final order in data['orders'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          heading(
                            '${order['offer']['name']} · ${euro(order['amount_cents'])}',
                          ),
                          Text(
                            orderStatus(order['status']),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            'Verwendungszweck: ${order['payment_reference']}',
                          ),
                          if (order['status'] == 'awaiting_payment') ...[
                            const SizedBox(height: 12),
                            SelectableText(
                              'Empfänger: ${order['bank']['recipient']}\nIBAN: ${order['bank']['iban']}\n${order['bank']['name']}',
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Bitte genau diesen Gesamtbetrag und Verwendungszweck nutzen. Die Freischaltung folgt nach Prüfung des Zahlungseingangs.',
                            ),
                          ],
                          if (order['starts'] != null)
                            Text(
                              '${calendar(order['starts'])} – ${calendar(order['ends'])}',
                            ),
                          if (order['mail_status'] == 'failed')
                            const Text(
                              'Die Bestätigungsmail konnte nicht versendet werden. Deine Bestellung ist gespeichert; lade die Bestätigung hier herunter.',
                            ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              ActionButton(
                                label: 'Bestätigung herunterladen',
                                secondary: true,
                                icon: Icons.download_outlined,
                                onPressed: () async {
                                  final bytes = await widget.state.api.bytes(
                                    '/orders/${order['id']}/confirmation',
                                  );
                                  await FileSaver.instance.saveFile(
                                    name: order['payment_reference'],
                                    bytes: bytes,
                                    fileExtension: 'txt',
                                    mimeType: MimeType.text,
                                  );
                                },
                              ),
                              if (order['mail_status'] == 'failed')
                                ActionButton(
                                  label: 'E-Mail erneut senden',
                                  secondary: true,
                                  onPressed: () async {
                                    final result = await widget.state.api.post(
                                      '/orders/${order['id']}/resend',
                                    );
                                    if (context.mounted) {
                                      toast(
                                        context,
                                        result['mail_status'] == 'accepted'
                                            ? 'Vom Mailserver angenommen. Bitte den Eingang prüfen.'
                                            : 'E-Mail-Versand fehlgeschlagen.',
                                      );
                                    }
                                    if (mounted) setState(() => version++);
                                  },
                                ),
                              if (order['status'] == 'awaiting_payment')
                                ActionButton(
                                  label: 'Bestellung stornieren',
                                  secondary: true,
                                  onPressed: () async {
                                    if (!await confirmDialog(
                                      context,
                                      'Offene Bestellung stornieren?',
                                      'Falls du bereits überwiesen hast, melde dich bitte zusätzlich beim Anbieter.',
                                    )) {
                                      return;
                                    }
                                    await widget.state.api.post(
                                      '/orders/${order['id']}/cancel',
                                    );
                                    if (mounted) setState(() => version++);
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if ((data['orders'] as List).isEmpty)
                  const Panel(
                    child: Text(
                      'Hier erscheinen deine Bestellungen und Zahlungsinformationen.',
                    ),
                  ),
              ],
            ),
          ),
  );
}

class StoreAdminScreen extends StatefulWidget {
  final AppState state;
  const StoreAdminScreen(this.state, {super.key});
  @override
  State<StoreAdminScreen> createState() => _StoreAdminScreenState();
}

class _StoreAdminScreenState extends State<StoreAdminScreen> {
  int version = 0;
  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Verkauf & Zahlungseingänge',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LoadView<Json>(
          key: ValueKey('store-$version'),
          load: () => widget.state.api.get('/admin/store'),
          builder: (data, _) => StoreAdminForm(
            widget.state,
            data,
            onSaved: () => setState(() => version++),
          ),
        ),
        const SizedBox(height: 24),
        heading('Bestellungen prüfen'),
        const Text(
          'Erst mit dem tatsächlichen Bankkonto abgleichen. Keine automatische Bankanbindung.',
        ),
        const SizedBox(height: 16),
        LoadView<List<dynamic>>(
          key: ValueKey('orders-$version'),
          load: () => widget.state.api.list('/admin/orders'),
          builder: (orders, _) => Column(
            children: [
              if (orders.isEmpty)
                const Panel(child: Text('Noch keine Bestellungen.')),
              for (final order in orders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelectableText(
                          '${order['payment_reference']} · ${euro(order['amount_cents'])}',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${order['offer']['name']} · ${calendar(order['created'])} · ${orderStatus(order['status'])}',
                        ),
                        if (order['status'] == 'awaiting_payment')
                          PaymentCheckForm(
                            widget.state,
                            order,
                            onSaved: () => setState(() => version++),
                          ),
                        if (order['status'] == 'paid')
                          PaymentCheckForm(
                            widget.state,
                            order,
                            refund: true,
                            onSaved: () => setState(() => version++),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class StoreAdminForm extends StatefulWidget {
  final AppState state;
  final Json data;
  final VoidCallback onSaved;
  const StoreAdminForm(
    this.state,
    this.data, {
    super.key,
    required this.onSaved,
  });
  @override
  State<StoreAdminForm> createState() => _StoreAdminFormState();
}

class _StoreAdminFormState extends State<StoreAdminForm> {
  late final recipient = TextEditingController(text: widget.data['recipient']);
  late final iban = TextEditingController(text: widget.data['iban']);
  late final bank = TextEditingController(text: widget.data['bank_name']);
  late final plans = TextEditingController(
    text: const JsonEncoder.withIndent('  ').convert(widget.data['plans']),
  );
  late bool enabled = widget.data['enabled'];
  late String tax = widget.data['tax_mode'];
  @override
  void dispose() {
    for (final field in [recipient, iban, bank, plans]) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('Verkauf einrichten'),
        if ((widget.data['missing'] as List).isNotEmpty)
          Text(
            'Noch erforderlich: ${(widget.data['missing'] as List).join(', ')}.',
          ),
        TextButton(
          onPressed: () => context.go('/admin/settings'),
          child: const Text('Betreiberangaben & E-Mail einrichten'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: recipient,
          decoration: const InputDecoration(labelText: 'Kontoinhaber'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: iban,
          decoration: const InputDecoration(labelText: 'IBAN'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: bank,
          decoration: const InputDecoration(labelText: 'Bankname (optional)'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: tax,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Umsatzsteuer'),
          items: const [
            DropdownMenuItem(
              value: 'unconfirmed',
              child: Text('Noch nicht bestätigt'),
            ),
            DropdownMenuItem(
              value: 'small_business',
              child: Text('Kleinunternehmer · § 19 UStG'),
            ),
            DropdownMenuItem(
              value: 'standard19',
              child: Text('19 % im Endpreis enthalten'),
            ),
          ],
          onChanged: (value) => setState(() => tax = value!),
        ),
        ExpansionTile(
          title: const Text('Tarife bearbeiten'),
          children: [
            TextField(
              controller: plans,
              maxLines: 18,
              decoration: const InputDecoration(
                labelText: 'Tarife (JSON)',
                helperText: 'price_cents = Gesamtpreis in Cent; calls = KI-Schritte pro Laufzeit.',
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Zahlungspflichtige Bestellungen freigeben'),
          value: enabled,
          onChanged: (v) => setState(() => enabled = v),
        ),
        ActionButton(
          label: 'Verkaufseinstellungen speichern',
          onPressed: () async {
            dynamic parsed;
            try {
              parsed = jsonDecode(plans.text);
            } catch (_) {
              throw ApiError('Die Tarifliste ist kein gültiges JSON.');
            }
            await widget.state.api.put('/admin/store', {
              'revision': widget.data['revision'],
              'enabled': enabled,
              'recipient': recipient.text,
              'iban': iban.text,
              'bank_name': bank.text,
              'tax_mode': tax,
              'plans': parsed,
            });
            widget.onSaved();
          },
        ),
      ],
    ),
  );
}

class PaymentCheckForm extends StatefulWidget {
  final AppState state;
  final dynamic order;
  final VoidCallback onSaved;
  final bool refund;
  const PaymentCheckForm(
    this.state,
    this.order, {
    super.key,
    required this.onSaved,
    this.refund = false,
  });
  @override
  State<PaymentCheckForm> createState() => _PaymentCheckFormState();
}

class _PaymentCheckFormState extends State<PaymentCheckForm> {
  final amount = TextEditingController(), reference = TextEditingController();
  final bookingDate = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  bool checked = false;
  @override
  void dispose() {
    amount.dispose();
    reference.dispose();
    bookingDate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(
      widget.refund
          ? 'Extern gebuchte Erstattung erfassen'
          : 'Zahlung prüfen & freischalten',
    ),
    children: [
      TextField(
        controller: amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: widget.refund
              ? 'Tatsächlich erstatteter Betrag in EUR'
              : 'Tatsächlich eingegangener Betrag in EUR',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: bookingDate,
        decoration: const InputDecoration(
          labelText: 'Buchungstag · JJJJ-MM-TT',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: reference,
        decoration: const InputDecoration(
          labelText: 'Eindeutige Bank-Buchungsnummer',
          helperText: 'Nicht nur den SCH-Verwendungszweck eintragen.',
        ),
      ),
      CheckboxListTile(
        value: checked,
        contentPadding: EdgeInsets.zero,
        title: Text(
          widget.refund
              ? 'Ich habe die tatsächlich gebuchte Erstattung geprüft. Die App führt keine Überweisung aus.'
              : 'Ich habe diesen Zahlungseingang im tatsächlichen Bankkonto geprüft.',
        ),
        onChanged: (v) => setState(() => checked = v!),
      ),
      ActionButton(
        label: widget.refund
            ? 'Erstattung dokumentieren & Laufzeit sperren'
            : 'Geprüften Zahlungseingang freischalten',
        onPressed: () async {
          if (!checked) {
            throw ApiError(
              'Bitte zuerst den Bankeintrag prüfen und bestätigen.',
            );
          }
          final normalized = amount.text.trim().replaceAll(',', '.');
          if (!RegExp(r'^\d{1,4}(\.\d{1,2})?$').hasMatch(normalized)) {
            throw ApiError(
              'Bitte den tatsächlich eingegangenen Eurobetrag eingeben.',
            );
          }
          await widget.state.api.post(
            '/admin/orders/${widget.order['id']}/${widget.refund ? 'refund' : 'approve'}',
            {
              'received_cents': (double.parse(normalized) * 100).round(),
              'booking_date': bookingDate.text,
              'booking_reference': reference.text,
              'bank_entry_checked': true,
            },
          );
          widget.onSaved();
        },
      ),
    ],
  );
}
