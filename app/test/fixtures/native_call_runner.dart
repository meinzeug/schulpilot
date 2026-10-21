import 'package:flutter/material.dart';
import 'package:schulpilot/family_call_native.dart';

/// Offline operator-owned Android presenter fixture, never a release target.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FamilyCallNative.instance.initialize();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Künstliche Android-Anrufprüfung · offline')),
      ),
    ),
  );
}
