import 'dart:js_interop';

@JS('window.location.assign')
external void _assign(JSString value);

Future<bool> openDocument(Uri uri) async {
  _assign(uri.toString().toJS);
  return true;
}

Future<bool> openWithdrawal(String orderId, Uri origin) =>
    openDocument(Uri(path: '/api/orders/$orderId/withdrawal-form'));
