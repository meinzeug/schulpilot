import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'payment_navigation.dart';
import 'ui.dart';

String orderPaymentMethod(Json order) => order['payment_method'] is String
    ? order['payment_method']
    : 'bank_transfer';

String paymentMethodLabel(String method) => switch (method) {
  'bank_transfer' => 'Überweisung',
  'paypal' => 'PayPal',
  'google_pay' => 'Google Pay über PayPal',
  _ => 'Zahlungsart nicht gemeldet',
};

/// No SDK or payment API is loaded here. The dedicated document authenticates
/// the current HttpOnly session and reads the exact owned order again.
class OrderPaymentAccess extends StatelessWidget {
  final AppState state;
  final Json order;
  final Future<bool> Function(String id, {String? appearance})? openDocument;
  const OrderPaymentAccess(
    this.state, {
    super.key,
    required this.order,
    this.openDocument,
  });

  @override
  Widget build(BuildContext context) {
    final method = orderPaymentMethod(order);
    if (!kIsWeb ||
        !state.isOwner ||
        state.isChild ||
        state.isDemo ||
        !['paypal', 'google_pay'].contains(method)) {
      return const SizedBox.shrink();
    }
    final account = state.user, family = state.familyId;
    final route = ModalRoute.of(context);
    final id = order['id'].toString();
    bool current() =>
        context.mounted &&
        identical(account, state.user) &&
        family == state.familyId &&
        state.isOwner &&
        !state.isDemo &&
        (route?.isCurrent ?? true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Gespeicherte Zahlungsart: ${paymentMethodLabel(method)}'),
        const SizedBox(height: 8),
        const Text(
          'Die sichere Zahlungsseite liest zuerst den gespeicherten Status. Öffnen startet keine neue Zahlung.',
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: RegExp(r'^[a-f0-9]{32}$').hasMatch(id)
              ? () async {
                  if (!current()) return;
                  final accepted = await (openDocument ?? openPaymentDocument)(
                    id,
                    appearance: Theme.of(context).brightness == Brightness.dark
                        ? 'dark'
                        : 'light',
                  );
                  if (context.mounted && current() && !accepted) {
                    showError(
                      context,
                      ApiError(
                        'Die Zahlungsseite konnte nicht geöffnet werden. Bitte den Webbrowser verwenden.',
                      ),
                    );
                  }
                }
              : null,
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(
            order['status'] == 'awaiting_payment'
                ? '${paymentMethodLabel(method)}-Zahlung öffnen'
                : 'Gespeicherten Zahlungsstatus öffnen',
          ),
        ),
      ],
    );
  }
}

class OrderWithdrawalAccess extends StatelessWidget {
  final AppState state;
  final Json order;
  final Future<bool> Function(String id, Uri origin)? openDocument;
  const OrderWithdrawalAccess(
    this.state, {
    super.key,
    required this.order,
    this.openDocument,
  });

  @override
  Widget build(BuildContext context) {
    if (!state.isOwner || state.isChild || state.isDemo) {
      return const SizedBox.shrink();
    }
    final account = state.user,
        family = state.familyId,
        route = ModalRoute.of(context);
    final id = order['id'].toString();
    bool current() =>
        context.mounted &&
        identical(account, state.user) &&
        family == state.familyId &&
        state.isOwner &&
        !state.isDemo &&
        (route?.isCurrent ?? true);
    return TextButton.icon(
      onPressed: RegExp(r'^[a-f0-9]{32}$').hasMatch(id)
          ? () async {
              if (!current()) return;
              final opened = await (openDocument ?? openOrderWithdrawal)(
                id,
                Uri.parse(state.api.base),
              );
              if (context.mounted && current() && !opened) {
                showError(
                  context,
                  ApiError(
                    'Das Widerrufsformular konnte nicht geöffnet werden. Bitte den Anbieter über die gespeicherten Kontaktdaten erreichen.',
                  ),
                );
              }
            }
          : null,
      icon: const Icon(Icons.assignment_return_outlined),
      label: const Text('Vertrag widerrufen'),
    );
  }
}
