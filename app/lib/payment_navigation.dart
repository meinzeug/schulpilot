import 'package:flutter/foundation.dart';

import 'payment_navigation_stub.dart'
    if (dart.library.js_interop) 'payment_navigation_web.dart'
    as platform;

/// Deliberate full-document navigation keeps payment SDKs out of the app CSP.
Future<bool> openPaymentDocument(String orderId, {String? appearance}) {
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(orderId)) return Future.value(false);
  return platform.openDocument(
    Uri(
      path: '/pay/$orderId',
      queryParameters: ['light', 'dark'].contains(appearance)
          ? {'theme': appearance!}
          : null,
    ),
  );
}

/// Web keeps authentication on the current document origin. Native uses only
/// the public HTTPS form and never forwards an order/reference to the browser.
Uri? orderWithdrawalDocumentUri(String orderId, Uri apiBase) {
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(orderId)) return null;
  final origin = kIsWeb ? Uri.base : apiBase;
  if (origin.host.isEmpty ||
      (kIsWeb && !const ['http', 'https'].contains(origin.scheme)) ||
      (!kIsWeb && origin.scheme != 'https')) {
    return null;
  }
  return Uri(
    scheme: origin.scheme,
    host: origin.host,
    port: origin.hasPort ? origin.port : null,
    path: kIsWeb ? '/api/orders/$orderId/withdrawal-form' : '/widerrufen',
  );
}

Future<bool> openOrderWithdrawal(String orderId, Uri apiBase) {
  final uri = orderWithdrawalDocumentUri(orderId, apiBase);
  if (uri == null) return Future.value(false);
  return kIsWeb
      ? platform.openDocument(uri)
      : platform.openWithdrawal(orderId, uri);
}

Future<bool> openWithdrawalDashboard() =>
    platform.openDocument(Uri(path: '/api/admin/withdrawals/dashboard'));
