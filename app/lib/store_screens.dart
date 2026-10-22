import 'dart:convert';
import 'dart:math';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'admin_workspace_ui.dart';
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
  int version = 0, orderVersion = 0, section = 0;
  final storeForm = GlobalKey<_StoreAdminFormState>();
  String orderFilter = 'all', orderQuery = '', orderSort = 'newest';
  final orderSearch = TextEditingController();
  @override
  void dispose() {
    orderSearch.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (storeForm.currentState?.dirty == true &&
        !await confirmDialog(
          context,
          'Verkaufsentwurf beim Neuladen verwerfen?',
          'Bei Abbrechen bleibt der ungespeicherte Verkaufsentwurf erhalten.',
        )) {
      return;
    }
    if (mounted) {
      setState(() {
        version++;
        orderVersion++;
      });
    }
  }

  void storeSaved() => setState(() => version++);
  void orderSaved() => setState(() => orderVersion++);

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Verkauf & Zahlungseingänge',
    showTitle: false,
    actions: [
      OutlinedButton.icon(
        onPressed: refresh,
        icon: Icon(Icons.refresh_rounded),
        label: const Text('Aktualisieren'),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminWorkspaceHeader(
          title: 'Zahlungen sicher prüfen',
          subtitle: 'Bestellungen mit dem Bankkonto abgleichen und anschließend freischalten.',
          currentPath: '/admin/verkauf',
          icon: Icons.account_balance_outlined,
        ),
        const SizedBox(height: 24),
        AdminContextTabs(
          selected: section,
          items: const [
            (Icons.receipt_long_outlined, 'Bestellungen'),
            (Icons.tune_rounded, 'Verkauf einrichten'),
          ],
          onSelected: (index) {
            FocusManager.instance.primaryFocus?.unfocus();
            setState(() => section = index);
          },
        ),
        const SizedBox(height: 24),
        Offstage(
          offstage: section != 1,
          child: ExcludeFocus(
            excluding: section != 1,
            child: LoadView<Json>(
              key: ValueKey('store-$version'),
              load: () => widget.state.api.get('/admin/store'),
              builder: (data, _) => StoreAdminForm(
                widget.state,
                data,
                key: storeForm,
                onSaved: storeSaved,
              ),
            ),
          ),
        ),
        Offstage(
          offstage: section != 0,
          child: ExcludeFocus(
            excluding: section != 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AdminSectionHeading(
                  title: 'Bestellungen prüfen',
                  subtitle: 'Erst mit dem tatsächlichen Bankkonto abgleichen. Keine automatische Bankanbindung.',
                  icon: Icons.fact_check_outlined,
                ),
                LoadView<List<dynamic>>(
                  key: ValueKey('orders-$orderVersion'),
                  load: () => widget.state.api.list('/admin/orders'),
                  builder: (orders, _) {
                    bool hasStatus(dynamic order, String status) =>
                        status == 'all' ||
                        (status == 'closed'
                            ? [
                                'cancelled',
                                'refunded',
                              ].contains(order['status'])
                            : order['status'] == status);
                    bool matches(dynamic order) =>
                        hasStatus(order, orderFilter) &&
                        '${order['payment_reference'] ?? ''}'
                            .toLowerCase()
                            .contains(orderQuery);
                    final sorted = [...orders]
                      ..sort((a, b) {
                        int compare = orderSort == 'status'
                            ? '${a['status']}'.compareTo('${b['status']}')
                            : 0;
                        if (compare != 0) return compare;
                        compare = (a['created'] as num? ?? 0).compareTo(
                          b['created'] as num? ?? 0,
                        );
                        if (orderSort != 'oldest') compare = -compare;
                        return compare == 0
                            ? '${a['id']}'.compareTo('${b['id']}')
                            : compare;
                      });
                    final shown = orders.where(matches).length;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Lokale Suche in höchstens den 200 zuletzt geladenen Bestellungen · $shown von ${orders.length} angezeigt. Keine vollständige Bestellhistorie.',
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: orderSearch,
                          onChanged: (v) => setState(
                            () => orderQuery = v.trim().toLowerCase(),
                          ),
                          decoration: InputDecoration(
                            labelText: 'Bank-Verwendungszweck suchen',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: orderQuery.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Bestellsuche leeren',
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () => setState(() {
                                      orderSearch.clear();
                                      orderQuery = '';
                                    }),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final item in const [
                              ('all', 'Alle'),
                              ('awaiting_payment', 'Zahlung offen'),
                              ('paid', 'Freigeschaltet'),
                              ('closed', 'Beendet'),
                            ])
                              FilterChip(
                                label: Text(
                                  '${item.$2} (${orders.where((o) => hasStatus(o, item.$1)).length})',
                                ),
                                selected: orderFilter == item.$1,
                                showCheckmark: false,
                                onSelected: (_) {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  setState(() => orderFilter = item.$1);
                                },
                              ),
                          ],
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: orderSort,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Geladene Bestellungen sortieren',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'newest',
                              child: Text('Neueste zuerst'),
                            ),
                            DropdownMenuItem(
                              value: 'oldest',
                              child: Text('Älteste zuerst'),
                            ),
                            DropdownMenuItem(
                              value: 'status',
                              child: Text('Status, dann neueste zuerst'),
                            ),
                          ],
                          onChanged: (v) {
                            FocusManager.instance.primaryFocus?.unfocus();
                            setState(() => orderSort = v ?? 'newest');
                          },
                        ),
                        const SizedBox(height: 16),
                        if (shown == 0)
                          const Panel(
                            child: Text(
                              'Keine Bestellungen in dieser Ansicht.',
                            ),
                          ),
                        for (final order in sorted)
                          Offstage(
                            key: ValueKey(order['id']),
                            offstage: !matches(order),
                            child: ExcludeFocus(
                              excluding: !matches(order),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: AdminWorkSurface(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Wrap(
                                        alignment: WrapAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 16,
                                        runSpacing: 8,
                                        children: [
                                          SelectableText(
                                            '${order['payment_reference']}',
                                            style: TextStyle(
                                              fontSize: 19,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          Text(
                                            euro(order['amount_cents']),
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w800,
                                              color: context.palette.teal,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${order['offer']['name']} · ${calendar(order['created'])}',
                                        style: TextStyle(
                                          color: context.palette.muted,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SurfaceInset(
                                        child: Text(
                                          orderStatus(order['status']),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (order['status'] == 'awaiting_payment')
                                        PaymentCheckForm(
                                          widget.state,
                                          order,
                                          onSaved: orderSaved,
                                        ),
                                      if (order['status'] == 'paid')
                                        PaymentCheckForm(
                                          widget.state,
                                          order,
                                          refund: true,
                                          onSaved: orderSaved,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
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
  bool busy = false;
  final bankFocus = FocusNode(), taxFocus = FocusNode();
  bool get dirty =>
      recipient.text != widget.data['recipient'] ||
      iban.text != widget.data['iban'] ||
      bank.text != widget.data['bank_name'] ||
      enabled != widget.data['enabled'] ||
      tax != widget.data['tax_mode'] ||
      plans.text !=
          const JsonEncoder.withIndent('  ').convert(widget.data['plans']);
  String? error;
  late final Object? owner = widget.state.user;
  @override
  void dispose() {
    bankFocus.dispose();
    taxFocus.dispose();
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
        if ((widget.data['missing'] as List).isNotEmpty) ...[
          for (final item in widget.data['missing'] as List)
            Text('Noch erforderlich: $item'),
          if ((widget.data['missing'] as List).contains(
            'Kontoinhaber und geprüfte IBAN',
          ))
            TextButton(
              onPressed: busy ? null : () => bankFocus.requestFocus(),
              child: const Text('Bankdaten hier prüfen'),
            ),
          if ((widget.data['missing'] as List).contains(
            'Bestätigte Umsatzsteuerbehandlung',
          ))
            TextButton(
              onPressed: busy ? null : () => taxFocus.requestFocus(),
              child: const Text('Steuerangabe hier prüfen'),
            ),
        ],
        TextButton(
          onPressed: () => context.go('/admin/settings'),
          child: const Text('Betreiberangaben & E-Mail einrichten'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: recipient,
          focusNode: bankFocus,
          enabled: !busy,
          decoration: const InputDecoration(labelText: 'Kontoinhaber'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: iban,
          enabled: !busy,
          decoration: const InputDecoration(labelText: 'IBAN'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: bank,
          enabled: !busy,
          decoration: const InputDecoration(labelText: 'Bankname (optional)'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: tax,
          focusNode: taxFocus,
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
          onChanged: busy ? null : (value) => setState(() => tax = value!),
        ),
        ListenableBuilder(
          listenable: plans,
          builder: (context, _) {
            dynamic parsed;
            try {
              parsed = jsonDecode(plans.text);
            } catch (_) {
              parsed = null;
            }
            return ExpansionTile(
              title: const Text('Tarifvorschau des Entwurfs'),
              children: [
                const Text(
                  '30 Tage ab Laufzeitbeginn · keine automatische Verlängerung. Noch nicht veröffentlicht.',
                ),
                if (parsed is! List || parsed.any((e) => e is! Map))
                  const Text('Tarifliste zuerst korrigieren.'),
                if (parsed is List)
                  for (final plan in parsed.whereType<Map>())
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${plan['name'] ?? 'Name fehlt'} · ${plan['price_cents'] is int ? euro(plan['price_cents']) : 'Preis noch prüfen'}',
                      ),
                      subtitle: Text(
                        'Kennung ${plan['id'] ?? 'fehlt'} · ${plan['children'] ?? '?'} Kinder · ${plan['calls'] ?? '?'} KI-Schritte je Laufzeit',
                      ),
                    ),
              ],
            );
          },
        ),
        ExpansionTile(
          title: const Text('Tarife bearbeiten'),
          children: [
            TextField(
              controller: plans,
              enabled: !busy,
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
          onChanged: busy ? null : (v) => setState(() => enabled = v),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([recipient, iban, bank, plans]),
          builder: (context, _) => Text(
            dirty
                ? 'Ungespeicherter Verkaufsentwurf · Veröffentlichung erst mit Speichern'
                : 'Gespeicherte Verkaufseinstellungen · Revision ${widget.data['revision']}',
          ),
        ),
        Text(
          enabled
              ? 'Entwurf: Neue Bestellungen freigeben. Voraussetzungen werden beim Speichern erneut geprüft.'
              : 'Entwurf: Keine neuen Bestellungen freigeben. Bereits gespeicherte Bestellungen bleiben erhalten.',
        ),
        if (error != null)
          Semantics(liveRegion: true, child: Notice(error!, warning: true)),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  if (dirty &&
                      !await confirmDialog(
                        context,
                        'Gespeicherten Verkaufsstand laden?',
                        'Der ungespeicherte Entwurf wird verworfen. Bei Abbrechen bleibt er erhalten.',
                      )) {
                    return;
                  }
                  if (mounted && identical(widget.state.user, owner)) {
                    widget.onSaved();
                  }
                },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Gespeicherten Verkaufsstand laden'),
        ),
        ActionButton(
          label: 'Verkaufseinstellungen speichern',
          enabled: !busy,
          onPressed: () async {
            if (busy || !identical(widget.state.user, owner)) return;
            dynamic parsed;
            try {
              parsed = jsonDecode(plans.text);
            } catch (_) {
              setState(
                () => error = 'Die Tarifliste ist kein gültiges JSON. Korrigiere den Entwurf.',
              );
              return;
            }
            if (parsed is! List ||
                parsed.isEmpty ||
                parsed.length > 6 ||
                parsed.any((item) => item is! Map)) {
              setState(
                () => error =
                    'Die Tarifliste muss 1 bis 6 Tarifobjekte enthalten.',
              );
              return;
            }
            final ids = <String>{};
            for (final (index, plan) in parsed.indexed) {
              String? invalid;
              final id = plan['id'];
              if (id is! String ||
                  !RegExp(r'^[a-z][a-z0-9-]{1,29}$').hasMatch(id) ||
                  !ids.add(id)) {
                invalid = 'id (eindeutig, 2 bis 30 Kleinbuchstaben/Ziffern/Bindestriche)';
              }
              if (plan['name'] is! String ||
                  (plan['name'] as String).isEmpty ||
                  (plan['name'] as String).runes.length > 40) {
                invalid ??= 'name (1 bis 40 Zeichen)';
              }
              for (final entry in const {
                'price_cents': (100, 25000),
                'children': (1, 20),
                'calls': (10, 10000),
              }.entries) {
                final v = plan[entry.key];
                if (v is! int || v < entry.value.$1 || v > entry.value.$2) {
                  invalid ??=
                      '${entry.key} (ganze Zahl ${entry.value.$1} bis ${entry.value.$2})';
                }
              }
              if (plan.keys.any(
                (k) => !const {
                  'id',
                  'name',
                  'price_cents',
                  'children',
                  'calls',
                }.contains(k),
              )) {
                invalid ??= 'unbekanntes Tariffeld';
              }
              if (invalid != null) {
                setState(() => error = 'Tarif ${index + 1}: $invalid prüfen.');
                return;
              }
            }
            FocusManager.instance.primaryFocus?.unfocus();
            setState(() {
              busy = true;
              error = null;
            });
            try {
              await widget.state.api.put('/admin/store', {
                'revision': widget.data['revision'],
                'enabled': enabled,
                'recipient': recipient.text,
                'iban': iban.text,
                'bank_name': bank.text,
                'tax_mode': tax,
                'plans': parsed,
              });
              if (mounted && identical(widget.state.user, owner)) {
                widget.onSaved();
              }
            } catch (failure) {
              if (mounted && identical(widget.state.user, owner)) {
                setState(
                  () => error = failure is ApiError ? failure.message : 'Verkaufseinstellungen konnten nicht gespeichert werden. Dein Entwurf bleibt erhalten.',
                );
              }
            } finally {
              if (mounted && identical(widget.state.user, owner)) {
                setState(() => busy = false);
              }
            }
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
  final form = GlobalKey<FormState>();
  bool checked = false, busy = false, showCheckError = false;
  String? error, statusMessage;
  late final Object? owner = widget.state.user;
  bool get own => mounted && identical(widget.state.user, owner);
  void edited(String _) {
    if (checked || showCheckError || error != null) {
      setState(() {
        checked = false;
        showCheckError = false;
        error = null;
      });
    }
  }

  int? cents(String raw) {
    final value = raw.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d{1,4}(\.\d{1,2})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    return int.parse(parts[0]) * 100 +
        int.parse((parts.length == 2 ? parts[1] : '').padRight(2, '0'));
  }

  String? dateError(String? raw) {
    final text = (raw ?? '').trim();
    final parsed = DateTime.tryParse(text);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != text) {
      return 'Einen echten Buchungstag als JJJJ-MM-TT eingeben.';
    }
    return null;
  }

  Future<void> save() async {
    if (!own || busy) return;
    final valid = form.currentState!.validate();
    setState(() => showCheckError = !checked);
    if (!valid || !checked) return;
    final body = <String, dynamic>{
      'received_cents': cents(amount.text),
      'booking_date': bookingDate.text.trim(),
      'booking_reference': reference.text.trim(),
      'bank_entry_checked': true,
    };
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
      statusMessage = null;
    });
    final confirmed = await confirmDialog(
      context,
      widget.refund ? 'Erstattung prüfen' : 'Zahlung vor Freischaltung prüfen',
      'Bestellung: ${widget.order['payment_reference'] ?? widget.order['id']}\nBetrag: ${euro(body['received_cents'])}\nBuchungstag: ${body['booking_date']}\nBank-Buchungsnummer: ${body['booking_reference']}\n${widget.refund ? 'Nur die bereits extern gebuchte Erstattung dokumentieren; die App überweist kein Geld.' : 'Erst nach deinem bewussten Bestätigen wird der Zugang freigeschaltet.'}',
      confirmLabel: 'Buchung verbindlich speichern',
    );
    if (!own) return;
    if (!confirmed) {
      setState(() => busy = false);
      return;
    }
    try {
      await widget.state.api.post(
        '/admin/orders/${widget.order['id']}/${widget.refund ? 'refund' : 'approve'}',
        body,
      );
      if (own) widget.onSaved();
    } catch (failure) {
      if (own) {
        setState(
          () => error = failure is ApiError ? failure.message : 'Die Buchung konnte nicht bestätigt werden. Prüfe den gespeicherten Bestellstatus, bevor du erneut speicherst.',
        );
      }
    } finally {
      if (own) setState(() => busy = false);
    }
  }

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
      Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: amount,
              enabled: !busy,
              onChanged: edited,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Betrag in EUR',
                helperText: widget.refund
                    ? 'Tatsächlich extern erstatteter Betrag.'
                    : 'Tatsächlich eingegangener Betrag.',
                helperMaxLines: 3,
                errorMaxLines: 3,
              ),
              validator: (v) =>
                  (cents(v ?? '') ?? 0) < 1 ||
                      (cents(v ?? '') ?? 100001) > 100000
                  ? 'Eurobetrag von 0,01 bis 1000 mit höchstens zwei Nachkommastellen eingeben.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: bookingDate,
              enabled: !busy,
              onChanged: edited,
              decoration: InputDecoration(
                suffixIcon: IconButton(
                  tooltip: 'Buchungstag auswählen',
                  icon: const Icon(Icons.calendar_month_outlined),
                  onPressed: busy
                      ? null
                      : () async {
                          final now = DateTime.now();
                          final value =
                              DateTime.tryParse(bookingDate.text) ?? now;
                          final selected = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(now.year, now.month, now.day),
                            initialDate:
                                value.isBefore(DateTime(2000)) ||
                                    value.isAfter(now)
                                ? now
                                : value,
                          );
                          if (!own || selected == null) return;
                          bookingDate.text = selected
                              .toIso8601String()
                              .substring(0, 10);
                          edited('');
                        },
                ),
                labelText: 'Buchungstag',
                helperText: 'JJJJ-MM-TT, zum Beispiel 2026-10-22.',
                errorMaxLines: 3,
              ),
              validator: dateError,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: reference,
              enabled: !busy,
              onChanged: edited,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Bank-Buchungsnummer',
                helperText: 'Die eindeutige Banknummer, nicht nur den SCH-Verwendungszweck.',
                helperMaxLines: 3,
                errorMaxLines: 3,
              ),
              validator: (v) =>
                  (v ?? '').trim().length < 6 || (v ?? '').trim().length > 160
                  ? 'Die Bank-Buchungsnummer mit 6 bis 160 Zeichen eintragen.'
                  : null,
            ),
            CheckboxListTile(
              value: checked,
              contentPadding: EdgeInsets.zero,
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      checked = v ?? false;
                      showCheckError = false;
                    }),
              title: Text(
                widget.refund
                    ? 'Ich habe die tatsächlich gebuchte Erstattung geprüft. Die App führt keine Überweisung aus.'
                    : 'Ich habe diesen Zahlungseingang im tatsächlichen Bankkonto geprüft.',
              ),
            ),
            if (showCheckError)
              Semantics(
                liveRegion: true,
                child: Notice(
                  'Bestätige zuerst die Prüfung dieser Buchung im Bankkonto.',
                  warning: true,
                ),
              ),
            if (error != null)
              Semantics(liveRegion: true, child: Notice(error!, warning: true)),
            if (statusMessage != null)
              Semantics(liveRegion: true, child: Notice(statusMessage!)),
            if (error != null)
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        if (!own || busy) return;
                        setState(() => busy = true);
                        try {
                          final orders = await widget.state.api.list(
                            '/admin/orders',
                          );
                          if (!own) return;
                          final found = orders
                              .where((o) => o['id'] == widget.order['id'])
                              .firstOrNull;
                          setState(
                            () => statusMessage = found == null
                                ? 'Die Bestellung ist nicht im geladenen Ausschnitt. Der Buchungsstatus ist noch unklar; nicht ungeprüft erneut buchen.'
                                : 'Gespeicherter Bestellstatus: ${orderStatus(found['status'])}. Keine neue Buchung ausgelöst.',
                          );
                          if (found != null &&
                              found['status'] != widget.order['status']) {
                            widget.onSaved();
                          }
                        } catch (_) {
                          if (own) {
                            setState(
                              () => statusMessage = 'Der Bestellstatus konnte nicht geladen werden. Keine neue Buchung ausgelöst.',
                            );
                          }
                        } finally {
                          if (own) setState(() => busy = false);
                        }
                      },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Bestellstatus zuerst laden'),
              ),
            ActionButton(
              label: widget.refund
                  ? 'Erstattung dokumentieren & Laufzeit sperren'
                  : 'Geprüften Zahlungseingang freischalten',
              enabled: !busy,
              onPressed: save,
            ),
          ],
        ),
      ),
    ],
  );
}
