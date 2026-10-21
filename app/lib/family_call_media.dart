import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  bool get remoteCameraFrameSeen => false;
  bool get remoteScreenFrameSeen => false;
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
  final RTCVideoRenderer _localRenderer;
  final RTCVideoRenderer _remoteRenderer;
  final RTCVideoRenderer _screenRenderer;
  final bool webPlatform;
  final Future<void> Function(MediaStreamTrack track) unmuteMicrophone;
  final Future<MediaStream> Function(Map<String, dynamic>) captureUserMedia;
  final Future<MediaStream> Function(Map<String, dynamic>) captureDisplayMedia;
  final Future<RTCPeerConnection> Function(Map<String, dynamic>) peerFactory;
  WebRtcFamilyCallMedia({
    this.webPlatform = kIsWeb,
    RTCVideoRenderer Function()? rendererFactory,
    Future<void> Function(MediaStreamTrack track)? unmuteMicrophone,
    Future<MediaStream> Function(Map<String, dynamic>)? captureUserMedia,
    Future<MediaStream> Function(Map<String, dynamic>)? captureDisplayMedia,
    Future<RTCPeerConnection> Function(Map<String, dynamic>)? peerFactory,
  }) : _localRenderer = (rendererFactory ?? RTCVideoRenderer.new)(),
       _remoteRenderer = (rendererFactory ?? RTCVideoRenderer.new)(),
       _screenRenderer = (rendererFactory ?? RTCVideoRenderer.new)(),
       unmuteMicrophone =
           unmuteMicrophone ??
           ((track) => Helper.setMicrophoneMute(false, track)),
       captureUserMedia =
           captureUserMedia ??
           ((constraints) => navigator.mediaDevices.getUserMedia(constraints)),
       captureDisplayMedia =
           captureDisplayMedia ??
           ((constraints) =>
               navigator.mediaDevices.getDisplayMedia(constraints)),
       peerFactory =
           peerFactory ??
           ((configuration) => createPeerConnection(configuration));
  MediaStream? _local;
  MediaStream? _screen;
  MediaStream? _pendingScreen;
  final _extraCaptures = <MediaStream>[];
  RTCPeerConnection? _peer;
  RTCRtpSender? _screenSender;
  String? _remoteCameraId;
  String? _remoteScreenId;
  String? _remoteCameraTrackId;
  String? _remoteScreenTrackId;
  bool _cameraFrameSeen = false;
  bool _screenFrameSeen = false;
  Future<void> _remoteBindings = Future.value();
  final _earlyTracks = <RTCTrackEvent>[];
  final _earlyIce = <Json>[];
  bool _remoteDescription = false;
  bool _closed = false;
  bool _initialized = false;
  bool _screenStarting = false;
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
  bool get hasRemoteCamera => _remoteCameraTrackId != null;
  @override
  bool get hasRemoteScreen => _remoteScreenTrackId != null;
  @override
  bool get remoteCameraFrameSeen => _cameraFrameSeen;
  @override
  bool get remoteScreenFrameSeen => _screenFrameSeen;
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
    _remoteRenderer.onFirstFrameRendered = () {
      if (!_closed) {
        _cameraFrameSeen = true;
        notifyListeners();
      }
    };
    _screenRenderer.onFirstFrameRendered = () {
      if (!_closed) {
        _screenFrameSeen = true;
        notifyListeners();
      }
    };
    if (_closed) {
      await Future.wait([
        _localRenderer.dispose(),
        _remoteRenderer.dispose(),
        _screenRenderer.dispose(),
      ]);
      return;
    }
    final stream = await captureUserMedia({
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
    // On native, renderer.muted changes the actual microphone track. Only the
    // browser preview has an audio element that needs local echo suppression.
    if (webPlatform) _localRenderer.muted = true;
    notifyListeners();
  }

  @override
  Future<void> connect(List<dynamic> iceServers) async {
    if (_closed || _peer != null) return;
    final peer = await peerFactory({
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
      _earlyTracks.add(event);
      _queueRemoteTracks();
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

  void _queueRemoteTracks() {
    _remoteBindings = _remoteBindings.then((_) => _attachRemoteTracks());
    // The peer can close while a native texture call is completing. Never log
    // stream IDs, SDP or a platform exception containing private transport data.
    _remoteBindings = _remoteBindings.catchError((Object _) {});
  }

  Future<void> _attachRemoteTracks() async {
    for (final event in _earlyTracks.toList()) {
      if (_closed || event.streams.isEmpty) continue;
      final stream = event.streams.first;
      if (stream.id == _remoteScreenId && event.track.kind == 'video') {
        _earlyTracks.remove(event);
        if (_remoteScreenTrackId != event.track.id) _screenFrameSeen = false;
        _remoteScreenTrackId = event.track.id;
        await _screenRenderer.setSrcObject(
          stream: stream,
          trackId: event.track.id,
        );
      } else if (stream.id == _remoteCameraId ||
          (event.track.kind == 'audio' && _remoteCameraId == null)) {
        _earlyTracks.remove(event);
        if (event.track.kind == 'video') {
          if (_remoteCameraTrackId != event.track.id) _cameraFrameSeen = false;
          _remoteCameraTrackId = event.track.id;
        }
        // Explicit track binding avoids selecting a stale Unified Plan stream
        // wrapper. An audio event must never replace the selected camera track.
        if (_remoteCameraTrackId != null) {
          await _remoteRenderer.setSrcObject(
            stream: stream,
            trackId: _remoteCameraTrackId,
          );
        } else {
          _remoteRenderer.srcObject = stream;
        }
      }
    }
    if (!_closed) notifyListeners();
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
      _remoteScreenTrackId = null;
      _screenFrameSeen = false;
      _screenRenderer.srcObject = null;
    }
    _queueRemoteTracks();
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
    if (_closed) return;
    final enable = !_microphone;
    for (final track in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      // Only this explicit microphone-on action may clear an API mute left by
      // an earlier call. Microphone-off never sets a global device mute.
      if (enable && !webPlatform) await unmuteMicrophone(track);
      if (_closed) return;
      track.enabled = enable;
    }
    _microphone = enable;
    notifyListeners();
  }

  @override
  Future<bool> toggleCamera() async {
    if (_closed || _local == null) return false;
    if (_local!.getVideoTracks().isEmpty) {
      final captured = await captureUserMedia({
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

  Future<void> _disposeScreenCapture(MediaStream stream) async {
    final stops = <Future<void>>[];
    for (final track in stream.getTracks()) {
      track.onEnded = null;
      stops.add(track.stop());
    }
    await Future.wait(stops.map((stop) => stop.catchError((Object _) {})));
    try {
      await stream.dispose();
    } catch (_) {}
  }

  @override
  Future<void> startScreen() async {
    if (_closed || _screen != null || _screenStarting) return;
    _screenStarting = true;
    MediaStream? captured;
    try {
      // No asynchronous work precedes this explicit capture request: web
      // browsers require the share button's transient user activation.
      captured = await captureDisplayMedia({'video': true, 'audio': false});
      _pendingScreen = captured;
      final peer = _peer;
      if (_closed || peer == null) return;
      final tracks = captured.getVideoTracks();
      if (tracks.isEmpty) {
        throw StateError('Screen capture has no video track.');
      }
      final sender = await peer.addTrack(tracks.first, captured);
      if (_closed || _peer != peer || _pendingScreen != captured) {
        try {
          await peer.removeTrack(sender);
        } catch (_) {}
        return;
      }
      // Capturing alone is not an active screen sender. Adopt it only after
      // addTrack succeeds; every earlier failure is rolled back below.
      _screen = captured;
      _pendingScreen = null;
      _screenSender = sender;
      final adopted = captured;
      tracks.first.onEnded = () {
        if (_screen == adopted && !_closed) {
          unawaited(stopScreen().then((_) => onScreenStopped?.call()));
        }
      };
      notifyListeners();
    } finally {
      _screenStarting = false;
      if (captured != null && _pendingScreen == captured) {
        _pendingScreen = null;
        await _disposeScreenCapture(captured);
      }
    }
  }

  @override
  Future<void> stopScreen() async {
    final stream = _screen;
    final pending = _pendingScreen;
    final sender = _screenSender;
    _screen = null;
    _pendingScreen = null;
    _screenSender = null;
    // Stop actual capture before changing the sender or its foreground type.
    if (stream != null) await _disposeScreenCapture(stream);
    if (pending != null) await _disposeScreenCapture(pending);
    if (sender != null) {
      try {
        await _peer?.removeTrack(sender);
      } catch (_) {}
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
    final pendingScreen = _pendingScreen;
    final peer = _peer;
    _local = null;
    _screen = null;
    _pendingScreen = null;
    _peer = null;
    // Stop every capture immediately, without waiting for signaling or another
    // track's platform callback. The independent authority watchdog uses this.
    final stopping = <Future<void>>[];
    final stoppingTracks = <String?>{};
    for (final stream in [local, screen, pendingScreen, ..._extraCaptures]) {
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
    for (final stream in [local, screen, pendingScreen, ..._extraCaptures]) {
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
