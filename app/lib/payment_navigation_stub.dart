import 'package:url_launcher/url_launcher.dart';

Future<bool> openDocument(Uri uri) async => false;

/// No bearer token or order/reference data is forwarded to an external browser.
Future<bool> openWithdrawal(String orderId, Uri origin) => launchUrl(
  origin.resolve('/widerrufen'),
  mode: LaunchMode.externalApplication,
);
