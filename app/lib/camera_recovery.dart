import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';

/// Android may restart the app while its external camera/gallery is open.
/// Keep only the authenticated owner and intended destination on disk.
Future<void> rememberCameraSource(
  AppState state,
  String childId, {
  String purpose = 'notebook',
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  await state.storage.write(
    key: 'camera_context',
    value: jsonEncode({
      'owner_id': state.user?['id'],
      'child_id': childId,
      'purpose': purpose,
    }),
  );
}

Future<void> clearCameraSource(AppState state) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  await state.storage.delete(key: 'camera_context');
  await state.storage.delete(key: 'camera_child');
}

/// Reads the platform's one-shot recovery once, without uploading or AI work.
Future<void> recoverCameraPhotos(
  AppState state, {
  Future<LostDataResponse> Function()? retrieve,
}) async {
  try {
    final lost = await (retrieve ?? ImagePicker().retrieveLostData)();
    final saved = await state.storage.read(key: 'camera_context');
    final legacyChild = await state.storage.read(key: 'camera_child');
    final context = saved == null ? null : jsonDecode(saved);
    final childId = state.user?['child_id'];
    final validContext =
        context is Map &&
        state.user?['id'] != null &&
        context['owner_id'] == state.user?['id'] &&
        context['child_id'] == childId &&
        ['notebook', 'homework'].contains(context['purpose']);
    // Releases before the purpose marker only captured notebook photos.
    final validLegacy =
        saved == null && legacyChild != null && legacyChild == childId;
    if (!state.isChild ||
        childId is! String ||
        childId.isEmpty ||
        (!validContext && !validLegacy) ||
        lost.files?.isNotEmpty != true) {
      return;
    }
    final owner = state.user?['id'];
    final photos = <Uint8List>[];
    var total = 0;
    for (final file in lost.files!.take(8)) {
      final length = await file.length();
      if (length > 10 * 1024 * 1024 || total + length > 20 * 1024 * 1024) {
        continue;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024 ||
          total + bytes.length > 20 * 1024 * 1024) {
        continue;
      }
      photos.add(bytes);
      total += bytes.length;
    }
    if (photos.isEmpty || owner != state.user?['id']) return;
    state.recoveredPhotoPurpose = validContext
        ? context['purpose']
        : 'notebook';
    state.recoveredPhoto = photos.removeAt(0);
    state.recoveredPhotos.addAll(photos);
  } catch (_) {
    // Camera recovery must never block opening the saved learning state.
  } finally {
    try {
      await clearCameraSource(state);
    } catch (_) {
      // An unavailable secure store must not prevent application startup.
    }
  }
}
