import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Operator settings only; a secret is never restored from an API response.
class PayPalSettings extends StatefulWidget {
  final AppState state;
  const PayPalSettings(this.state, {super.key});
  @override
  State<PayPalSettings> createState() => _PayPalSettingsState();
}

class _PayPalSettingsState extends State<PayPalSettings> {
  late final account = widget.state.user;
  final client = TextEditingController(),
      merchant = TextEditingController(),
      webhook = TextEditingController(),
      secret = TextEditingController(),
      approval = TextEditingController(),
      googleApproval = TextEditingController();
  Json? data;
  String environment = 'sandbox';
  bool enabled = false,
      googlePay = false,
      loading = false,
      saving = false,
      dirty = false;
  String? error, notice;
  int generation = 0;
  bool get own =>
      mounted && widget.state.isAdmin && identical(account, widget.state.user);
  bool get busy => loading || saving;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(changedAccount);
  }

  void changedAccount() {
    if (!mounted || own) return;
    generation++;
    for (final field in [
      client,
      merchant,
      webhook,
      secret,
      approval,
      googleApproval,
    ]) {
      field.clear();
    }
    setState(() {
      data = null;
      error = notice = null;
      dirty = false;
    });
  }

  @override
  void dispose() {
    generation++;
    widget.state.removeListener(changedAccount);
    for (final field in [
      client,
      merchant,
      webhook,
      secret,
      approval,
      googleApproval,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  void apply(Json value) {
    data = value;
    environment = value['environment'] == 'live' ? 'live' : 'sandbox';
    enabled = value['enabled'] == true;
    googlePay = value['google_pay_enabled'] == true;
    client.text = value['client_id'] as String? ?? '';
    merchant.text = value['merchant_id'] as String? ?? '';
    webhook.text = value['webhook_id'] as String? ?? '';
    approval.text = value['approval_evidence'] as String? ?? '';
    googleApproval.text = value['google_pay_evidence'] as String? ?? '';
    secret.clear();
    dirty = false;
  }

  Future<void> load() async {
    if (!own || busy) return;
    if (dirty &&
        !await confirmDialog(
          context,
          'Zahlungsentwurf verwerfen?',
          'Die ungespeicherten Zahlungsangaben werden durch den gespeicherten Stand ersetzt.',
        )) {
      return;
    }
    if (!own) return;
    final stamp = ++generation;
    setState(() {
      loading = true;
      error = notice = null;
    });
    try {
      final value = await widget.state.api.get('/admin/payments/paypal');
      if (!own || stamp != generation) return;
      setState(() => apply(value));
    } catch (e) {
      if (own && stamp == generation) {
        setState(
          () => error = e is ApiError
              ? e.message
              : 'Die Zahlungskonfiguration konnte nicht geladen werden.',
        );
      }
    } finally {
      if (own && stamp == generation) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (!own || busy || data == null) return;
    final body = <String, dynamic>{
      'revision': data!['revision'],
      'environment': environment,
      'enabled': enabled,
      'google_pay_enabled': googlePay,
      'client_id': client.text.trim(),
      'merchant_id': merchant.text.trim(),
      'webhook_id': webhook.text.trim(),
      'approval_evidence': approval.text.trim(),
      'google_pay_evidence': googleApproval.text.trim(),
      if (secret.text.isNotEmpty) 'client_secret': secret.text,
    };
    final stamp = ++generation;
    setState(() {
      saving = true;
      error = notice = null;
    });
    try {
      final result = Json.from(
        await widget.state.api.call('PUT', '/admin/payments/paypal', body),
      );
      if (!own || stamp != generation) return;
      setState(() {
        apply(result);
        notice = 'Zahlungsangaben gespeichert. Eine Händlerfreigabe oder erfolgreiche Zahlung wird dadurch nicht bestätigt.';
      });
    } catch (e) {
      if (own && stamp == generation) {
        setState(
          () => error = e is ApiError ? e.message : 'Speichern konnte nicht bestätigt werden. Der Entwurf bleibt hier; lade bei unklarem Ausgang zuerst den gespeicherten Stand.',
        );
      }
    } finally {
      if (own && stamp == generation) setState(() => saving = false);
    }
  }

  Widget input(
    TextEditingController controller,
    String label, {
    bool sensitive = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: controller,
      enabled: !busy,
      obscureText: sensitive,
      smartDashesType: sensitive ? SmartDashesType.disabled : null,
      smartQuotesType: sensitive ? SmartQuotesType.disabled : null,
      enableIMEPersonalizedLearning: !sensitive,
      maxLines: lines,
      maxLength: sensitive
          ? 4096
          : lines > 1
          ? 1000
          : 300,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) {
        if (own && !busy) setState(() => dirty = true);
      },
    ),
  );

  @override
  Widget build(BuildContext context) => !own
      ? const SizedBox.shrink()
      : ExpansionTile(
          title: const Text('PayPal und Google Pay einrichten'),
          subtitle: const Text('Getrennte Freigaben · standardmäßig gesperrt'),
          onExpansionChanged: (open) {
            if (open && data == null && !busy) load();
          },
          childrenPadding: const EdgeInsets.all(16),
          children: [
            const Notice(
              'Hier werden nur Zahlungsangaben verwaltet. Öffnen und Speichern führen keine Zahlung aus. Liveverkauf erst nach tatsächlicher Händler-, Vertrags- und Datenschutzprüfung freigeben.',
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) Notice(error!, warning: true),
            if (notice != null) Notice(notice!),
            if (data != null) ...[
              DropdownButtonFormField<String>(
                key: ValueKey(environment),
                initialValue: environment,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'PayPal-Umgebung'),
                selectedItemBuilder: (_) => const [
                  Text('Sandbox', maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('Live', maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                items: const [
                  DropdownMenuItem(
                    value: 'sandbox',
                    child: Text('Sandbox · nur Testzahlungen'),
                  ),
                  DropdownMenuItem(
                    value: 'live',
                    child: Text('Live · echte Zahlungen'),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (value) {
                        if (own && value != null) {
                          setState(() {
                            environment = value;
                            dirty = true;
                          });
                        }
                      },
              ),
              input(client, 'Öffentliche PayPal-Client-ID'),
              input(
                secret,
                data!['has_client_secret'] == true
                    ? 'Neues Client-Secret (leer = gespeichertes behalten)'
                    : 'PayPal-Client-Secret',
                sensitive: true,
              ),
              input(merchant, 'PayPal-Händler-ID'),
              input(webhook, 'PayPal-Webhook-ID'),
              input(
                approval,
                'Nachweis der Händler- und Livefreigabe',
                lines: 3,
              ),
              input(
                googleApproval,
                'Nachweis der Google-Pay-Freigabe',
                lines: 3,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                title: const Text('PayPal-Zahlungen freigeben'),
                onChanged: busy
                    ? null
                    : (value) {
                        if (own) {
                          setState(() {
                            enabled = value == true;
                            if (!enabled) googlePay = false;
                            dirty = true;
                          });
                        }
                      },
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: googlePay,
                title: const Text(
                  'Google Pay über PayPal zusätzlich freigeben',
                ),
                subtitle: const Text(
                  'Eine Google-Anmeldung ist keine Händler- oder Zahlungsfreigabe.',
                ),
                onChanged: busy || !enabled
                    ? null
                    : (value) {
                        if (own) {
                          setState(() {
                            googlePay = value == true;
                            dirty = true;
                          });
                        }
                      },
              ),
              if (data!['readiness'] != null)
                Text('Gespeicherter Prüfstand: ${data!['readiness']}'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: busy || !dirty ? null : save,
                    child: Text(
                      saving
                          ? 'Wird gespeichert …'
                          : 'Zahlungsangaben speichern',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : load,
                    child: const Text('Gespeicherten Zahlungsstand laden'),
                  ),
                ],
              ),
            ] else if (!loading)
              OutlinedButton(
                onPressed: load,
                child: const Text('Zahlungskonfiguration erneut laden'),
              ),
          ],
        );
}
