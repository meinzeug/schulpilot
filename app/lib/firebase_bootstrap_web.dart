import 'dart:js_interop';

@JS('schulpilotLoadFirebase')
external JSPromise<JSAny?> _load();

Future<void> loadFirebaseRuntime() async => await _load().toDart;
