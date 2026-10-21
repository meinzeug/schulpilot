import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'api.dart';

/// Media stays on the participants' devices. The API only relays signaling.
abstract class FamilyCallMedia extends ChangeNotifier {
  bool get microphoneEnabled;
  bool get cameraEnabled;
  bool get sharingScreen;
  bool get hasRemoteCamera;
  bool get hasRemoteScreen;
  String get connectionState;
  void Function(Json candidate)? onIce;
  void Function()? onScreenStopped;
  Future<void> prepare({required bool camera});
  Future<void> connect(List<dynamic> iceServers);
  Future<Json> offer();
  Future<Json> answer(Json offer);
  Future<void> receiveAnswer(Json answer);
  Future<void> receiveIce(Json candidate);
  Future<void> toggleMicrophone();
  Future<bool> toggleCamera();
  Future<void> startScreen();
  Future<void> stopScreen();
  Widget video({required bool remote, bool screen = false});
  Future<void> close();
}

class WebRtcFamilyCallMedia extends FamilyCallMedia {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  final _screenRenderer = RTCVideoRenderer();
  MediaStream? _local;
  MediaStream? _screen;
  final _extraCaptures = <MediaStream>[];
  MediaStream? _remoteCamera;
  MediaStream? _remoteScreen;
  RTCPeerConnection? _peer;
  RTCRtpSender? _screenSender;
  String? _remoteCameraId;
  String? _remoteScreenId;
  final _earlyTracks = <RTCTrackEvent>[];
  final _earlyIce = <Json>[];
  bool _remoteDescription = false;
  bool _closed = false;
  bool _initialized = false;
  bool _microphone = true;
  bool _camera = true;
  String _connection = 'new';

  @override
  bool get microphoneEnabled => _microphone;
  @override
  bool get cameraEnabled =>
      _camera && _local?.getVideoTracks().isNotEmpty == true;
  @override
  bool get sharingScreen => _screen != null;
  @override
  bool get hasRemoteCamera => _remoteCamera != null;
  @override
  bool get hasRemoteScreen => _remoteScreen != null;
  @override
  String get connectionState => _connection;

  @override
  Future<void> prepare({required bool camera}) async {
    if (_closed) return;
    await Future.wait([
      _localRenderer.initialize(),
      _remoteRenderer.initialize(),
      _screenRenderer.initialize(),
    ]);
    _initialized = true;
    if (_closed) {
      await Future.wait([
        _localRenderer.dispose(),
        _remoteRenderer.dispose(),
        _screenRenderer.dispose(),
      ]);
      return;
    }
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true},
      'video': camera
          ? {'facingMode': 'user', 'width': 640, 'height': 480, 'frameRate': 20}
          : false,
    });
    if (_closed) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
      return;
    }
    _local = stream;
    _camera = camera;
    _localRenderer.srcObject = stream;
    _localRenderer.muted = true;
    notifyListeners();
  }

  @override
  Future<void> connect(List<dynamic> iceServers) async {
    if (_closed || _peer != null) return;
    final peer = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    if (_closed) {
      await peer.close();
      return;
    }
    _peer = peer;
    peer.onIceCandidate = (candidate) {
      if (_closed) return;
      onIce?.call({
        'candidate': candidate.candidate ?? '',
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    peer.onConnectionState = (state) {
      if (_closed) return;
      _connection = state.name
          .replaceFirst('RTCPeerConnectionState', '')
          .toLowerCase();
      notifyListeners();
    };
    peer.onTrack = (event) {
      if (_closed) return;
      if (event.track.kind == 'audio') {
        // The camera renderer carries the remote audio stream too.
        _earlyTracks.add(event);
        _attachRemoteTracks();
      } else {
        _earlyTracks.add(event);
        _attachRemoteTracks();
      }
    };
    final local = _local;
    if (local != null) {
      for (final track in local.getTracks()) {
        await peer.addTrack(track, local);
      }
    }
    if (local?.getVideoTracks().isEmpty != false) {
      await peer.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
    }
  }

  void _attachRemoteTracks() {
    for (final event in _earlyTracks.toList()) {
      if (event.streams.isEmpty) continue;
      final stream = event.streams.first;
      if (stream.id == _remoteScreenId) {
        _remoteScreen = stream;
        _screenRenderer.srcObject = stream;
        _screenRenderer.muted = true;
        _earlyTracks.remove(event);
      } else if (stream.id == _remoteCameraId ||
          (event.track.kind == 'audio' && _remoteCameraId == null)) {
        _remoteCamera = stream;
        _remoteRenderer.srcObject = stream;
        _earlyTracks.remove(event);
      }
    }
    notifyListeners();
  }

  Json _description(String? sdp) => {
    'sdp': sdp,
    'camera_stream_id': _local?.id,
    'screen_stream_id': _screen?.id,
  };

  void _remoteStreams(Json description) {
    _remoteCameraId = description['camera_stream_id'] as String?;
    _remoteScreenId = description['screen_stream_id'] as String?;
    if (_remoteScreenId == null) {
      _remoteScreen = null;
      _screenRenderer.srcObject = null;
    }
    _attachRemoteTracks();
  }

  @override
  Future<Json> offer() async {
    final peer = _peer!;
    final description = await peer.createOffer();
    await peer.setLocalDescription(description);
    return _description(description.sdp);
  }

  @override
  Future<Json> answer(Json offer) async {
    _remoteStreams(offer);
    await _peer!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], 'offer'),
    );
    _remoteDescription = true;
    await _flushIce();
    final description = await _peer!.createAnswer();
    await _peer!.setLocalDescription(description);
    return _description(description.sdp);
  }

  @override
  Future<void> receiveAnswer(Json answer) async {
    _remoteStreams(answer);
    await _peer!.setRemoteDescription(
      RTCSessionDescription(answer['sdp'], 'answer'),
    );
    _remoteDescription = true;
    await _flushIce();
  }

  @override
  Future<void> receiveIce(Json candidate) async {
    if (!_remoteDescription) {
      _earlyIce.add(candidate);
      return;
    }
    await _peer!.addCandidate(
      RTCIceCandidate(
        candidate['candidate'],
        candidate['sdpMid'],
        candidate['sdpMLineIndex'],
      ),
    );
  }

  Future<void> _flushIce() async {
    for (final candidate in _earlyIce.toList()) {
      await receiveIce(candidate);
      _earlyIce.remove(candidate);
    }
  }

  @override
  Future<void> toggleMicrophone() async {
    _microphone = !_microphone;
    for (final track in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = _microphone;
    }
    notifyListeners();
  }

  @override
  Future<bool> toggleCamera() async {
    if (_closed || _local == null) return false;
    if (_local!.getVideoTracks().isEmpty) {
      final captured = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
          'width': 640,
          'height': 480,
          'frameRate': 20,
        },
      });
      if (_closed) {
        for (final track in captured.getTracks()) {
          await track.stop();
        }
        await captured.dispose();
        return false;
      }
      _extraCaptures.add(captured);
      for (final track in captured.getVideoTracks()) {
        await _local!.addTrack(track);
        await _peer?.addTrack(track, _local!);
      }
      _localRenderer.srcObject = _local;
      _camera = true;
      notifyListeners();
      return true;
    }
    _camera = !_camera;
    for (final track in _local!.getVideoTracks()) {
      track.enabled = _camera;
    }
    notifyListeners();
    return false;
  }

  @override
  Future<void> startScreen() async {
    // This must be the first asynchronous operation on the explicit share tap:
    // browsers require transient user activation for getDisplayMedia.
    final capture = navigator.mediaDevices.getDisplayMedia({
      'video': true,
      'audio': false,
    });
    final stream = await capture;
    if (_closed || _peer == null) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
      return;
    }
    _screen = stream;
    final tracks = stream.getVideoTracks();
    if (tracks.isNotEmpty) {
      tracks.first.onEnded = () {
        if (_screen == stream && !_closed) {
          unawaited(stopScreen().then((_) => onScreenStopped?.call()));
        }
      };
      _screenSender = await _peer!.addTrack(tracks.first, stream);
    }
    notifyListeners();
  }

  @override
  Future<void> stopScreen() async {
    final stream = _screen;
    _screen = null;
    if (_screenSender != null) {
      await _peer?.removeTrack(_screenSender!);
      _screenSender = null;
    }
    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.onEnded = null;
        await track.stop();
      }
      await stream.dispose();
    }
    if (!_closed) notifyListeners();
  }

  @override
  Widget video({required bool remote, bool screen = false}) {
    if (!_initialized) return const SizedBox.shrink();
    return RTCVideoView(
      remote ? (screen ? _screenRenderer : _remoteRenderer) : _localRenderer,
      mirror: !remote,
      objectFit: screen
          ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
          : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    onIce = null;
    onScreenStopped = null;
    final local = _local;
    final screen = _screen;
    final peer = _peer;
    _local = null;
    _screen = null;
    _peer = null;
    // Stop every capture immediately, without waiting for signaling or another
    // track's platform callback. The independent authority watchdog uses this.
    final stopping = <Future<void>>[];
    final stoppingTracks = <String?>{};
    for (final stream in [local, screen, ..._extraCaptures]) {
      for (final track in stream?.getTracks() ?? <MediaStreamTrack>[]) {
        if (stoppingTracks.add(track.id)) {
          track.onEnded = null;
          stopping.add(track.stop());
        }
      }
    }
    if (peer != null) stopping.add(peer.close());
    await Future.wait(
      stopping.map((future) => future.catchError((Object _) {})),
    );
    for (final stream in [local, screen, ..._extraCaptures]) {
      await stream?.dispose();
    }
    _extraCaptures.clear();
    if (_initialized) {
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
      _screenRenderer.srcObject = null;
      await Future.wait([
        _localRenderer.dispose(),
        _remoteRenderer.dispose(),
        _screenRenderer.dispose(),
      ]);
    }
    _earlyTracks.clear();
    _earlyIce.clear();
  }
}
